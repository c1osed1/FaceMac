import AppKit
import Combine
import FaceMacCore
import SkyLightWindow
import SwiftUI

/// Drives the notch overlay: owns the panel, the phase and the animated metrics.
///
/// The panel is created once at launch and stays on screen (transparent while
/// `phase == .hidden`). A window that already exists before the screen locks is
/// composited above the lock screen far more reliably than one created while
/// locked.
@MainActor
final class NotchPresenter: ObservableObject {
    enum Phase: Equatable {
        case hidden
        case scanning
        case matched(similarity: Float)
        case failed(reason: String)
        case rejected(reason: String)
    }

    @Published private(set) var phase: Phase = .hidden
    @Published private(set) var message: String = ""
    /// Mirrors `AppSettings.showMatchText` so the notch can react live.
    @Published var showsMatchText: Bool = true

    /// Called when the user taps "Try Again" on the failed notch.
    var onRetry: (() -> Void)?

    let spring = Animation.spring(response: 0.42, dampingFraction: 0.86, blendDuration: 0)
    let hoverSpring = Animation.bouncy.speed(1.2)

    private var panel: NotchPanel?
    private var geometry: NotchGeometry?
    private var hideTask: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    /// Keeps a phase on screen for a minimum time so a fast unlock is still seen.
    private var holdUntil: Date?

    // MARK: Metrics (animated via `phase`)
    //
    // On a notched display the hidden state *is* the closed notch, so the open
    // state looks like the notch itself growing. Non-notched displays stay
    // invisible when hidden.

    var width: CGFloat {
        guard let geometry else { return 0 }
        switch phase {
        case .hidden:
            return geometry.hasPhysicalNotch ? geometry.closedWidth : 0
        case .scanning, .matched, .failed, .rejected:
            return max(geometry.closedWidth, CGFloat(AppSettings.shared.notchExpandedWidth))
        }
    }

    var height: CGFloat {
        guard let geometry else { return 0 }
        switch phase {
        case .hidden:
            return geometry.hasPhysicalNotch ? geometry.closedHeight : 0
        case .scanning, .matched, .failed, .rejected:
            return geometry.closedHeight + 88
        }
    }

    var topRadius: CGFloat {
        guard let geometry else { return 8 }
        guard geometry.hasPhysicalNotch else { return min(max(height, 1) / 2, 26) }
        return phase == .hidden ? 6 : 10
    }

    var bottomRadius: CGFloat {
        guard let geometry else { return 28 }
        guard geometry.hasPhysicalNotch else { return min(max(height, 1) / 2, 26) }
        return phase == .hidden ? 14 : 30
    }

    var isExpanded: Bool {
        switch phase {
        case .matched, .failed, .rejected: return true
        case .hidden, .scanning: return false
        }
    }

    var topInset: CGFloat { 0 }

    /// Content starts below the notch housing so it is never swallowed by it.
    var contentTopInset: CGFloat {
        guard let geometry, geometry.hasPhysicalNotch else { return 0 }
        return geometry.closedHeight
    }

    var isVisible: Bool { phase != .hidden }

    /// Always black — only the glyph is tinted, never the plate.
    var shapeFill: Color { .black }

    var isRejected: Bool {
        if case .rejected = phase { return true }
        return false
    }

    /// Re-reads settings-driven metrics (e.g. notch width).
    func refreshMetrics() {
        objectWillChange.send()
    }

    // MARK: Lifecycle

    func start() {
        showsMatchText = AppSettings.shared.showMatchText
        geometry = NotchGeometry.preferred()
        preparePanel()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.refreshGeometry() }
        }
        NotchLog.write("start closed=\(Int(width))x\(Int(height)) screen=\(geometry?.screen.localizedName ?? "?")")
    }

    private func refreshGeometry() {
        geometry = NotchGeometry.preferred()
        guard let geometry else { return }
        panel?.setFrame(geometry.panelFrame, display: true)
        NotchLog.write("geometry changed -> \(Int(geometry.closedWidth))x\(Int(geometry.closedHeight))")
    }

    // MARK: Phase control

    func handle(_ newPhase: Phase) {
        NotchLog.write("handle \(label(newPhase))")
        switch newPhase {
        case .hidden:
            requestHide()
        case .scanning:
            holdUntil = nil
            hideTask?.cancel()
            show(newPhase)
        case .matched:
            show(newPhase)
            // Keep the notch up long enough for the success animation to finish.
            let hold = FaceIDLottieView.duration + 0.2
            holdUntil = Date().addingTimeInterval(hold)
            scheduleHide(after: hold + 0.3)
        case .failed:
            show(newPhase)
            holdUntil = Date().addingTimeInterval(1.2)
            scheduleHide(after: 2.0)
        case .rejected:
            show(newPhase)
            holdUntil = Date().addingTimeInterval(1.2)
            scheduleHide(after: 2.2)
        }
    }

    private func show(_ newPhase: Phase) {
        phase = newPhase
        switch newPhase {
        case .scanning: message = L10n.t("notch.looking")
        case .matched: message = L10n.t("notch.itsYou")
        case .failed(let reason): message = reason.isEmpty ? L10n.t("notch.notRecognised") : reason
        case .rejected(let reason): message = reason.isEmpty ? L10n.t("notch.notYou") : reason
        case .hidden: break
        }
        ensurePanelVisible()
        updateInteractivity()
        logPanelState("shown \(label(newPhase))")
    }

    private func requestHide() {
        if let until = holdUntil, Date() < until {
            let delay = until.timeIntervalSinceNow
            hideTask?.cancel()
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await MainActor.run { self?.hide() }
            }
            return
        }
        holdUntil = nil
        hide()
    }

    private func scheduleHide(after seconds: TimeInterval) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.hide() }
        }
    }

    private func hide() {
        hideTask?.cancel()
        holdUntil = nil
        phase = .hidden
        updateInteractivity()
        logPanelState("hidden")
    }

    /// The notch only accepts clicks while it is offering a retry; the rest of
    /// the time it must let events through to whatever is underneath.
    ///
    /// The window frame is never changed here: resizing it on a phase change made
    /// the notch slide sideways on the lock screen.
    private func updateInteractivity() {
        guard let panel else { return }
        let interactive: Bool
        if case .failed = phase { interactive = true } else { interactive = false }
        panel.ignoresMouseEvents = !interactive
    }

    /// Cycles the animation for manual inspection without locking the Mac:
    /// scan → success → rejected → timed out.
    func preview() {
        previewTask?.cancel()
        previewTask = Task { [weak self] in
            guard let self else { return }
            await MainActor.run { self.handle(.scanning) }
            try? await Task.sleep(for: .seconds(1.8))

            guard !Task.isCancelled else { return }
            await MainActor.run { self.handle(.matched(similarity: 0.72)) }
            try? await Task.sleep(for: .seconds(FaceIDLottieView.duration + 0.6))

            guard !Task.isCancelled else { return }
            await MainActor.run { self.handle(.rejected(reason: L10n.t("notch.notYou"))) }
            try? await Task.sleep(for: .seconds(2.0))

            guard !Task.isCancelled else { return }
            await MainActor.run { self.handle(.failed(reason: L10n.t("notch.notRecognised"))) }
            try? await Task.sleep(for: .seconds(2.0))

            guard !Task.isCancelled else { return }
            await MainActor.run { self.handle(.hidden) }
        }
    }

    // MARK: Panel

    private func preparePanel() {
        guard panel == nil else { return }
        guard let geometry = geometry ?? NotchGeometry.preferred() else { return }
        self.geometry = geometry

        let panel = NotchPanel(contentRect: geometry.panelFrame)
        let hosting = FirstMouseHostingView(rootView: NotchView(presenter: self))
        hosting.frame = CGRect(origin: .zero, size: geometry.panelSize)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        panel.setFrame(geometry.panelFrame, display: true)
        panel.orderFrontRegardless()
        // Put the panel in a SkyLight space above the lock screen (level 400 vs
        // the lock screen's 300). Without this it only shows up after unlock.
        SkyLightOperator.shared.delegateWindow(panel)
        self.panel = panel
        logPanelState("prepared")
    }

    private func ensurePanelVisible() {
        preparePanel()
        panel?.orderFrontRegardless()
        if let panel {
            SkyLightOperator.shared.delegateWindow(panel)
        }
    }

    private func logPanelState(_ note: String) {
        guard let panel else {
            NotchLog.write("\(note): no panel")
            return
        }
        let occluded = panel.occlusionState.contains(.visible) ? "visible" : "occluded"
        let onScreen = panel.isOnActiveSpace ? "activeSpace" : "otherSpace"
        NotchLog.write(
            "\(note): level=\(panel.level.rawValue) frame=\(Int(panel.frame.origin.x)),\(Int(panel.frame.origin.y)),\(Int(panel.frame.width))x\(Int(panel.frame.height)) "
                + "isVisible=\(panel.isVisible) \(occluded) \(onScreen) alpha=\(panel.alphaValue)"
        )
    }

    private func label(_ phase: Phase) -> String {
        switch phase {
        case .hidden: return "hidden"
        case .scanning: return "scanning"
        case .matched: return "matched"
        case .failed: return "failed"
        case .rejected: return "rejected"
        }
    }
}
