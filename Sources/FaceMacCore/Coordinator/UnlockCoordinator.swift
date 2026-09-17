import CoreMedia
import CoreVideo
import Foundation

/// Ties camera, recognition, the Keychain password and key injection together.
///
/// Flow: screen locks -> camera on -> face detected + matched -> password typed ->
/// camera off. Every step falls back to the normal manual login on failure.
public final class UnlockCoordinator {
    public enum State: Equatable {
        case idle
        case disabled
        case armed
        case scanning
        case unlocking(similarity: Float)
        case failed(reason: String)
        /// The camera gave up without a match; the lock screen may offer a retry.
        case timedOut
        /// Confidently a different person.
        case rejected
    }

    public private(set) var state: State = .idle {
        didSet {
            guard state != oldValue else { return }
            let state = self.state
            DispatchQueue.main.async { [weak self] in
                self?.stateHandler?(state)
            }
        }
    }

    /// Called on the main queue whenever `state` changes.
    public var stateHandler: ((State) -> Void)?

    private let settings: AppSettings
    private let store: EnrollmentStore
    private let keychain: KeychainStore
    private let detector = FaceDetector()
    private let embedder: FaceEmbedder
    private let capture: CameraCapture
    private let injector = KeyboardInjector()
    private let lockWatcher = LockWatcher()

    private var cachedEnrollment: Enrollment?
    private var cachedCentroid: FaceEmbedding?
    private var attempts = 0
    private var frameCounter = 0
    private var lastAttemptAt = Date.distantPast
    private var isScanning = false

    /// Consecutive matching frames seen so far, and when the streak began.
    private var matchStreak = 0
    private var streakStartedAt: Date?
    private var lowScoreStreak = 0
    private var scanTimeoutWork: DispatchWorkItem?

    public init(
        settings: AppSettings = .shared,
        store: EnrollmentStore = .shared,
        keychain: KeychainStore = .shared,
        embedder: FaceEmbedder? = nil,
        capture: CameraCapture = .shared
    ) {
        self.settings = settings
        self.store = store
        self.keychain = keychain
        self.embedder = embedder ?? EmbedderFactory.make()
        self.capture = capture
        self.capture.addDelegate(self)
        self.lockWatcher.delegate = self

        settings.applyRecommendedThreshold(from: self.embedder)
    }

    public func start() {
        lockWatcher.start()
        reloadEnrollment()
        state = settings.isEnabled ? .armed : .disabled
        Log.app.info("coordinator started, enabled=\(self.settings.isEnabled, privacy: .public)")
    }

    public func stop() {
        lockWatcher.stop()
        stopScanning()
        state = .idle
    }

    /// Re-emits the current state so localized text updates after a language change.
    public func refreshLocalizedState() {
        reloadEnrollment()
        let current = state
        DispatchQueue.main.async { [weak self] in
            self?.stateHandler?(current)
        }
    }

    public func reloadEnrollment() {
        var enrollment = try? store.load()
        if let loaded = enrollment, loaded.modelTag != embedder.modelTag {
            Log.app.info("enrollment was made with a different model, ignoring it")
            enrollment = nil
        }
        cachedEnrollment = enrollment
        cachedCentroid = enrollment?.centroid
    }

    public func handleEnrollmentChanged() {
        reloadEnrollment()
        let hasFace = cachedEnrollment?.embeddings.isEmpty == false
        Log.app.info("enrollment reloaded, hasFace=\(hasFace, privacy: .public)")
    }

    private func startScanning() {
        guard !isScanning else { return }
        guard settings.isEnabled else {
            state = .disabled
            return
        }
        guard let enrollment = cachedEnrollment, !enrollment.embeddings.isEmpty else {
            state = .failed(reason: L10n.t("failure.noEnrollment"))
            return
        }
        guard injectorReady() else {
            state = .failed(reason: L10n.t("failure.accessibility"))
            return
        }
        guard keychainHasPassword() else {
            state = .failed(reason: L10n.t("failure.noPassword"))
            return
        }

        attempts = 0
        frameCounter = 0
        lowScoreStreak = 0
        resetMatchStreak()
        do {
            try capture.acquire()
            if settings.keepDisplayAwake {
                DisplaySleepGuard.shared.hold()
            }
            isScanning = true
            state = .scanning
            scheduleScanTimeout()
        } catch {
            state = .failed(reason: String(format: L10n.t("failure.camera"), "\(error)"))
        }
    }

    /// Re-arms recognition after a failed attempt (the notch "Try Again" button).
    public func retryScan() {
        startScanning()
    }

    /// Gives up after `scanTimeout` seconds so the camera light does not stay on.
    private func scheduleScanTimeout() {
        scanTimeoutWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isScanning else { return }
            self.stopScanning()
            self.state = .timedOut
            Log.app.info("scan timed out")
        }
        scanTimeoutWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + settings.scanTimeout, execute: work)
    }

    private func cancelScanTimeout() {
        scanTimeoutWork?.cancel()
        scanTimeoutWork = nil
    }

    private func stopScanning() {
        cancelScanTimeout()
        DisplaySleepGuard.shared.release()
        guard isScanning else { return }
        capture.relinquish()
        isScanning = false
        resetMatchStreak()
    }

    private func injectorReady() -> Bool {
        KeyboardInjector.isAccessibilityTrusted
    }

    private func keychainHasPassword() -> Bool {
        (try? keychain.password()) ?? nil != nil
    }

    private func process(_ pixelBuffer: CVPixelBuffer) {
        guard isScanning, let enrollment = cachedEnrollment else { return }

        frameCounter += 1
        guard frameCounter % 2 == 0 else { return }

        guard
            let faces = try? detector.detect(in: pixelBuffer),
            let face = faces.max(by: { $0.area < $1.area })
        else {
            resetMatchStreak()
            return
        }

        // Tiny or heavily turned faces produce noisy embeddings — the main
        // source of false accepts. Ignore those frames entirely.
        guard face.area >= 0.02, abs(face.yaw) <= 0.6, abs(face.pitch) <= 0.6 else {
            resetMatchStreak()
            return
        }

        guard let embedding = try? embedder.embed(FaceInput(pixelBuffer: pixelBuffer, face: face)) else {
            resetMatchStreak()
            return
        }

        let best = FaceMatcher.match(
            embedding,
            against: enrollment.embeddings,
            threshold: settings.matchThreshold
        )
        let centroid = FaceMatcher.similarity(
            embedding,
            toCentroid: cachedCentroid ?? enrollment.centroid
        )

        // Confidently someone else: fail fast instead of scanning for the full
        // timeout.
        if best.similarity < settings.rejectionThreshold {
            lowScoreStreak += 1
            if lowScoreStreak >= 3 {
                stopScanning()
                state = .rejected
                Log.app.info("rejected: best=\(best.similarity, privacy: .public)")
                return
            }
        } else {
            lowScoreStreak = 0
        }

        // Both the closest reference and the centroid must agree.
        guard best.isMatch, centroid >= settings.matchThreshold - 0.06 else {
            Log.vision.debug("no match best=\(best.similarity, privacy: .public) centroid=\(centroid, privacy: .public)")
            resetMatchStreak()
            return
        }

        let now = Date()
        if let started = streakStartedAt, now.timeIntervalSince(started) > 2.5 {
            matchStreak = 0
            streakStartedAt = nil
        }
        matchStreak += 1
        if streakStartedAt == nil { streakStartedAt = now }

        Log.vision.debug(
            "streak \(self.matchStreak, privacy: .public)/\(self.settings.requiredFrames, privacy: .public) best=\(best.similarity, privacy: .public) centroid=\(centroid, privacy: .public)"
        )

        guard matchStreak >= settings.requiredFrames else { return }

        guard settings.autoUnlock, now.timeIntervalSince(lastAttemptAt) >= settings.unlockCooldown else { return }
        lastAttemptAt = now
        attempts += 1
        resetMatchStreak()
        unlock(similarity: best.similarity)
    }

    private func resetMatchStreak() {
        matchStreak = 0
        streakStartedAt = nil
    }

    private func unlock(similarity: Float) {
        state = .unlocking(similarity: similarity)
        Log.app.info("match, similarity=\(similarity, privacy: .public)")

        do {
            guard let password = try keychain.password() else {
                state = .failed(reason: L10n.t("failure.noPassword"))
                stopScanning()
                return
            }
            try injector.type(password)
            try injector.pressReturn()
            stopScanning()
            state = .armed
        } catch {
            stopScanning()
            if attempts >= settings.maxAttempts {
                state = .failed(reason: String(format: L10n.t("failure.giveUp"), attempts))
            } else {
                state = .failed(reason: String(format: L10n.t("failure.couldNotType"), "\(error)"))
            }
        }
    }
}

extension UnlockCoordinator: CameraCaptureDelegate {
    public func cameraCapture(_ capture: CameraCapture, didOutput pixelBuffer: CVPixelBuffer, at time: CMTime) {
        DispatchQueue.main.async { [weak self] in
            self?.process(pixelBuffer)
        }
    }
}

extension UnlockCoordinator: LockWatcherDelegate {
    public func lockWatcherDidLock(_ watcher: LockWatcher) {
        startScanning()
    }

    public func lockWatcherDidUnlock(_ watcher: LockWatcher) {
        stopScanning()
        state = settings.isEnabled ? .armed : .disabled
    }
}
