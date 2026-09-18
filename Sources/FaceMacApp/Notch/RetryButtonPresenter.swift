import AppKit
import Combine
import FaceMacCore
import SkyLightWindow
import SwiftUI

/// A small circular "scan again" button shown on the lock screen, next to the
/// user avatar.
///
/// It appears when the lock screen is waiting for a tap (a deliberate lock) or
/// after a scan actually failed, and never while scanning. It fades/scales in
/// and out.
@MainActor
final class RetryButtonPresenter: ObservableObject {
    @Published private(set) var presented = false
    @Published private(set) var previewing = false

    /// Called when the button is tapped.
    var onRetry: (() -> Void)?
    /// Called after a drag so the settings UI can refresh.
    var onPositionChanged: (() -> Void)?

    private var panel: NSPanel?
    private var locked = false
    private var prompted = false
    private var observers: [NSObjectProtocol] = []
    private var dragStartOrigin: CGPoint?
    private var hideTask: Task<Void, Never>?

    static var buttonSize: CGFloat { CGFloat(AppSettings.shared.retryButtonSize) }

    func start() {
        let center = DistributedNotificationCenter.default()
        observers.append(center.addObserver(
            forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.locked = true
                self?.refresh()
            }
        })
        observers.append(center.addObserver(
            forName: .init("com.apple.screenIsUnlocked"), object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.locked = false
                self?.prompted = false
                self?.refresh()
            }
        })
    }

    func setPreviewing(_ value: Bool) {
        previewing = value
        refresh()
    }

    /// True while the button should be offered on the lock screen: idle and
    /// waiting for a tap, or after a failed scan. Driven by coordinator state.
    func setPrompted(_ value: Bool) {
        guard prompted != value else { return }
        prompted = value
        refresh()
    }

    func refresh() {
        let shouldShow = previewing || (locked && prompted)
        if shouldShow {
            show()
        } else {
            hide()
        }
    }

    // MARK: Actions

    func retryTapped() {
        guard !previewing else { return }
        onRetry?()
    }

    func beginDrag() {
        dragStartOrigin = panel?.frame.origin
    }

    func drag(by translation: CGSize) {
        guard previewing, let panel, let start = dragStartOrigin else { return }
        var frame = panel.frame
        frame.origin = CGPoint(x: start.x + translation.width, y: start.y - translation.height)
        panel.setFrame(frame, display: true)
    }

    func endDrag() {
        defer { dragStartOrigin = nil }
        guard previewing, let panel, let screen = screen() else { return }
        let frame = panel.frame
        AppSettings.shared.retryButtonOffsetX = Double(frame.midX - screen.frame.midX)
        AppSettings.shared.retryButtonVerticalFraction =
            Double((screen.frame.maxY - frame.midY) / screen.frame.height)
        onPositionChanged?()
    }

    // MARK: Panel

    private func screen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func ensurePanel() -> NSPanel? {
        if let panel { return panel }
        guard let screen = screen() else { return nil }
        let size = Self.buttonSize
        let frame = CGRect(
            x: screen.frame.midX - size / 2,
            y: screen.frame.midY - size / 2,
            width: size,
            height: size
        )

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = true
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.collectionBehavior = [.fullScreenAuxiliary, .canJoinAllSpaces, .ignoresCycle, .stationary]

        let hosting = FirstMouseHostingView(rootView: RetryButtonView(presenter: self))
        hosting.frame = CGRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting

        self.panel = panel
        SkyLightOperator.shared.delegateWindow(panel)
        return panel
    }

    private func show() {
        hideTask?.cancel()
        guard let screen = screen(), let panel = ensurePanel() else { return }

        let settings = AppSettings.shared
        let size = Self.buttonSize
        let x = screen.frame.midX + CGFloat(settings.retryButtonOffsetX) - size / 2
        let centerFromTop = screen.frame.height * CGFloat(settings.retryButtonVerticalFraction)
        let y = screen.frame.maxY - centerFromTop - size / 2
        panel.setFrame(CGRect(x: x.rounded(), y: y.rounded(), width: size, height: size), display: true)

        guard !presented else { return }
        panel.alphaValue = 0
        panel.ignoresMouseEvents = false
        panel.orderFrontRegardless()
        SkyLightOperator.shared.delegateWindow(panel)
        presented = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.16
            panel.animator().alphaValue = 1
        }, completionHandler: nil)
    }

    private func hide() {
        guard presented, let panel else { return }
        presented = false
        panel.ignoresMouseEvents = true
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            guard let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.16
                panel.animator().alphaValue = 0
            }, completionHandler: nil)
            try? await Task.sleep(for: .seconds(0.18))
            guard !self.presented else { return }
            panel.orderOut(nil)
        }
    }
}

struct RetryButtonView: View {
    @ObservedObject var presenter: RetryButtonPresenter
    @State private var hovering = false
    @State private var dragging = false

    private var size: CGFloat { RetryButtonPresenter.buttonSize }

    var body: some View {
        content
            .frame(width: size, height: size)
            .clipShape(Circle())
            .scaleEffect(presenter.presented ? 1 : 0.55)
            .opacity(presenter.presented ? 1 : 0)
            .animation(.spring(response: 0.34, dampingFraction: 0.72), value: presenter.presented)
            .contentShape(Circle())
            .onHover { hovering = $0 }
            .help(presenter.previewing ? "Drag to place the button" : "Scan with FaceMac")
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        MainActor.assumeIsolated {
                            guard presenter.previewing else { return }
                            if !dragging {
                                dragging = true
                                presenter.beginDrag()
                            }
                            presenter.drag(by: value.translation)
                        }
                    }
                    .onEnded { value in
                        MainActor.assumeIsolated {
                            if dragging {
                                dragging = false
                                presenter.endDrag()
                            } else if value.translation == .zero {
                                presenter.retryTapped()
                            }
                        }
                    }
            )
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            #if compiler(>=6.2)
            if #available(macOS 26.0, *) {
                Circle()
                    .fill(.clear)
                    .glassEffect(.regular.interactive(), in: .circle)
            } else {
                Circle().fill(.regularMaterial)
            }
            #else
            Circle().fill(.regularMaterial)
            #endif

            Circle()
                .fill(.black.opacity(hovering ? 0.28 : 0.38))

            Circle()
                .stroke(.white.opacity(hovering ? 0.6 : 0.35), lineWidth: 1)

            Image(systemName: "faceid")
                .font(.system(size: max(16, size * 0.44), weight: .semibold))
                .foregroundStyle(NotchPalette.green)
        }
    }
}
