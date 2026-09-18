import AppKit
import Combine
import FaceMacCore
import Foundation

@MainActor
final class AppModel: ObservableObject {
    // MARK: Status

    @Published private(set) var isEnabled: Bool
    @Published private(set) var statusText: String = "Idle"
    @Published private(set) var hasEnrollment: Bool
    @Published private(set) var hasPassword: Bool
    @Published private(set) var accessibilityTrusted: Bool

    // MARK: Settings

    @Published private(set) var notchWidth: Double
    @Published private(set) var showMatchText: Bool
    @Published private(set) var keepDisplayAwake: Bool
    @Published private(set) var uiLanguage: AppLanguage
    @Published private(set) var threshold: Float
    @Published private(set) var maxAttempts: Int
    @Published private(set) var unlockCooldown: Double
    @Published private(set) var requiredFrames: Int
    @Published private(set) var livenessMode: LivenessMode
    @Published private(set) var scanTimeout: Double
    @Published private(set) var retryOffsetX: Double
    @Published private(set) var retryVerticalFraction: Double
    @Published private(set) var retryPreview = false
    @Published private(set) var retryButtonSize: Double
    @Published private(set) var embedderName: String

    // MARK: Enrollment

    @Published private(set) var isEnrolling = false
    @Published private(set) var enrollMessage = "Press Start, then follow the prompts."
    @Published private(set) var enrollStepIndex = 0
    @Published private(set) var enrollStepCount = GuidedEnroller.stepCount
    @Published private(set) var enrollStepProgress: Float = 0
    @Published private(set) var enrollStepTitle = "Look straight at the camera"
    @Published private(set) var enrollStepSymbol = "face.smiling"
    @Published private(set) var enrollSampleCount = 0
    @Published private(set) var enrollJustFinished = false

    // MARK: Recognition test

    @Published private(set) var isTesting = false
    @Published private(set) var testSimilarity: Float = -1
    @Published private(set) var testCentroid: Float = -1
    @Published private(set) var testMatched = false
    @Published private(set) var testFaceCount = 0

    let coordinator: UnlockCoordinator
    let notch = NotchPresenter()
    let retryButton = RetryButtonPresenter()

    private let settings: AppSettings
    private let store: EnrollmentStore
    private let keychain: KeychainStore
    private let embedder: FaceEmbedder
    private var guidedEnroller: GuidedEnroller?
    private var tester: RecognitionTester?

    init(
        settings: AppSettings = .shared,
        store: EnrollmentStore = .shared,
        keychain: KeychainStore = .shared
    ) {
        let embedder = EmbedderFactory.make()
        settings.applyRecommendedThreshold(from: embedder)

        self.settings = settings
        self.store = store
        self.keychain = keychain
        self.embedder = embedder
        self.isEnabled = settings.isEnabled
        self.notchWidth = settings.notchExpandedWidth
        self.showMatchText = settings.showMatchText
        self.keepDisplayAwake = settings.keepDisplayAwake
        self.uiLanguage = settings.language
        L10n.language = settings.language
        self.threshold = settings.matchThreshold
        self.maxAttempts = settings.maxAttempts
        self.unlockCooldown = settings.unlockCooldown
        self.requiredFrames = settings.requiredFrames
        self.livenessMode = settings.livenessMode
        self.scanTimeout = settings.scanTimeout
        self.retryOffsetX = settings.retryButtonOffsetX
        self.retryVerticalFraction = settings.retryButtonVerticalFraction
        self.retryButtonSize = settings.retryButtonSize
        self.embedderName = String(describing: type(of: embedder))
        self.accessibilityTrusted = KeyboardInjector.isAccessibilityTrusted
        self.hasEnrollment = AppModel.validEnrollment(store: store, embedder: embedder)?
            .embeddings.isEmpty == false
        self.hasPassword = ((try? keychain.password()) ?? nil) != nil
        self.coordinator = UnlockCoordinator(
            settings: settings,
            store: store,
            keychain: keychain,
            embedder: embedder
        )

        coordinator.stateHandler = { [weak self] state in
            self?.apply(state)
        }

        notch.onRetry = { [weak self] in
            self?.coordinator.retryScan()
        }
        notch.start()

        retryButton.onRetry = { [weak self] in
            self?.coordinator.retryScan()
        }
        retryButton.onPositionChanged = { [weak self] in
            guard let self else { return }
            self.retryOffsetX = self.settings.retryButtonOffsetX
            self.retryVerticalFraction = self.settings.retryButtonVerticalFraction
        }
        retryButton.start()

        NotificationCenter.default.addObserver(
            forName: .faceMacWillTerminate,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.coordinator.stop()
        }

        if isEnabled {
            coordinator.start()
        } else {
            statusText = "Disabled"
        }
    }

    private func apply(_ state: UnlockCoordinator.State) {
        statusText = AppModel.describe(state)

        var showScanButton = false
        switch state {
        case .scanning:
            notch.handle(.scanning)
        case .unlocking(let similarity):
            notch.handle(.matched(similarity: similarity))
        case .prompted:
            // Locked on purpose: keep the camera off, just offer the scan button.
            notch.handle(.hidden)
            showScanButton = true
        case .timedOut:
            showScanButton = true
            notch.handle(.failed(reason: L10n.t("notch.notRecognised")))
        case .rejected:
            showScanButton = true
            notch.handle(.rejected(reason: L10n.t("notch.notYou")))
        case .spoof:
            showScanButton = true
            notch.handle(.rejected(reason: L10n.t("notch.notLive")))
        case .idle, .disabled, .armed:
            notch.handle(.hidden)
        case .failed(let reason):
            if notch.isVisible {
                notch.handle(.failed(reason: reason))
            }
        }

        // The lock-screen button is offered while locked and idle, and after a
        // failed attempt so the user can try again.
        retryButton.setPrompted(showScanButton)
    }

    func previewNotch() {
        notch.preview()
    }

    func scanNow() {
        coordinator.retryScan()
    }

    private static func validEnrollment(store: EnrollmentStore, embedder: FaceEmbedder) -> Enrollment? {
        guard let enrollment = try? store.load() else { return nil }
        return enrollment.modelTag == embedder.modelTag ? enrollment : nil
    }

    private static func describe(_ state: UnlockCoordinator.State) -> String {
        switch state {
        case .idle: return L10n.t("status.idle")
        case .disabled: return L10n.t("status.disabled")
        case .armed: return L10n.t("status.armed")
        case .prompted: return L10n.t("status.prompted")
        case .scanning: return L10n.t("status.scanning")
        case .unlocking(let similarity): return String(format: L10n.t("status.unlocking"), similarity)
        case .failed(let reason): return reason
        case .timedOut: return L10n.t("status.timedOut")
        case .rejected: return L10n.t("notch.notYou")
        case .spoof: return L10n.t("status.notLive")
        }
    }

    // MARK: Enable / permissions

    func setLanguage(_ value: AppLanguage) {
        uiLanguage = value
        settings.language = value
        L10n.language = value
        coordinator.refreshLocalizedState()
    }

    func setEnabled(_ value: Bool) {
        isEnabled = value
        settings.isEnabled = value
        if value {
            coordinator.start()
        } else {
            coordinator.stop()
            statusText = "Disabled"
        }
    }

    func requestAccessibility() {
        KeyboardInjector.requestAccessibility()
        refreshPermissions()
    }

    func refreshPermissions() {
        accessibilityTrusted = KeyboardInjector.isAccessibilityTrusted
        hasPassword = ((try? keychain.password()) ?? nil) != nil
        hasEnrollment = AppModel.validEnrollment(store: store, embedder: embedder)?
            .embeddings.isEmpty == false
    }

    // MARK: Password

    func setPassword() {
        let alert = NSAlert()
        alert.messageText = L10n.t("alert.passwordTitle")
        alert.informativeText = L10n.t("alert.passwordInfo")
        alert.addButton(withTitle: L10n.t("alert.save"))
        alert.addButton(withTitle: L10n.t("alert.cancel"))

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.placeholderString = "Login password"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            try keychain.setPassword(field.stringValue)
            hasPassword = true
            statusText = "Password saved"
        } catch {
            statusText = "Could not save password: \(error)"
        }
    }

    func forgetPassword() {
        try? keychain.deletePassword()
        hasPassword = false
        statusText = "Password removed"
    }

    // MARK: Face data

    func forgetFace() {
        try? store.delete()
        hasEnrollment = false
        coordinator.handleEnrollmentChanged()
        statusText = "Face data deleted"
    }

    // MARK: Camera preview

    func previewAcquire() {
        do {
            try CameraCapture.shared.acquire()
        } catch {
            enrollMessage = "Camera unavailable: \(error)"
        }
    }

    func previewRelease() {
        CameraCapture.shared.relinquish()
    }

    // MARK: Enrollment

    func beginEnrollment() {
        guard !isEnrolling else { return }
        isEnrolling = true
        enrollStepIndex = 0
        enrollStepCount = GuidedEnroller.stepCount
        enrollStepProgress = 0
        enrollStepTitle = GuidedEnroller.Step.center.title
        enrollStepSymbol = GuidedEnroller.Step.center.symbol
        enrollSampleCount = 0
        enrollJustFinished = false
        enrollMessage = GuidedEnroller.Step.center.title

        let enroller = GuidedEnroller(embedder: embedder)
        self.guidedEnroller = enroller

        enroller.onProgress = { [weak self] progress in
            guard let self else { return }
            self.enrollStepIndex = progress.stepIndex
            self.enrollStepCount = progress.stepCount
            self.enrollStepProgress = progress.stepProgress
            self.enrollStepTitle = progress.step.title
            self.enrollStepSymbol = progress.step.symbol
            self.enrollSampleCount = progress.samples
            self.enrollMessage = progress.step.title
        }

        enroller.completion = { [weak self] result in
            guard let self else { return }
            self.guidedEnroller = nil
            self.isEnrolling = false
            switch result {
            case .success(let embeddings):
                do {
                    let enrollment = Enrollment(
                        name: NSUserName(),
                        embeddings: embeddings,
                        modelTag: self.embedder.modelTag
                    )
                    try self.store.save(enrollment)

                    // Calibrate the accept threshold against how consistent this
                    // user's own samples are on this camera and in this light.
                    let calibration = ThresholdCalibration.calibrate(from: enrollment)
                    self.threshold = calibration.threshold
                    self.settings.matchThreshold = calibration.threshold
                    self.settings.thresholdOverridden = true

                    self.hasEnrollment = true
                    self.coordinator.handleEnrollmentChanged()
                    self.enrollMessage = String(
                        format: L10n.t("enroll.done"),
                        embeddings.count, calibration.threshold
                    )
                    self.statusText = "Face enrolled"
                    self.enrollSampleCount = embeddings.count
                    self.enrollJustFinished = true
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(1.6))
                        self.enrollJustFinished = false
                    }
                } catch {
                    self.enrollMessage = "Could not save: \(error)"
                }
            case .failure(GuidedEnroller.EnrollError.cancelled):
                self.enrollMessage = L10n.t("enroll.cancelled")
            case .failure(GuidedEnroller.EnrollError.notEnoughAngles):
                self.enrollMessage = L10n.t("enroll.notEnoughAngles")
            case .failure(let error):
                self.enrollMessage = String(format: L10n.t("enroll.failed"), "\(error)")
            }
        }

        enroller.start()
    }

    func cancelEnrollment() {
        guidedEnroller?.cancel()
    }

    // MARK: Recognition test

    func beginTest() {
        guard !isTesting else { return }
        isTesting = true
        testSimilarity = -1
        testCentroid = -1
        testMatched = false
        testFaceCount = 0

        let tester = RecognitionTester(embedder: embedder, store: store)
        self.tester = tester
        tester.onReading = { [weak self] reading in
            guard let self else { return }
            self.testFaceCount = reading.faceCount
            self.testSimilarity = reading.similarity
            self.testCentroid = reading.centroidSimilarity
            self.testMatched = reading.isMatch
        }
        tester.onError = { [weak self] error in
            self?.statusText = "Test: \(error)"
            self?.isTesting = false
        }
        tester.start()
    }

    func endTest() {
        tester?.stop()
        tester = nil
        isTesting = false
    }

    // MARK: Unlock now (manual)

    func tryUnlockNow() {
        guard let password = try? keychain.password() else {
            statusText = "Set the saved password first"
            return
        }

        let alert = NSAlert()
        alert.messageText = L10n.t("alert.typeTitle")
        alert.informativeText = L10n.t("alert.typeInfo")
        alert.addButton(withTitle: L10n.t("alert.typeIt"))
        alert.addButton(withTitle: L10n.t("alert.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        do {
            let injector = KeyboardInjector()
            try injector.type(password)
            try injector.pressReturn()
            statusText = "Typed the password"
        } catch {
            statusText = "Could not type: \(error)"
        }
    }

    // MARK: Settings

    func setKeepDisplayAwake(_ value: Bool) {
        keepDisplayAwake = value
        settings.keepDisplayAwake = value
    }

    func setShowMatchText(_ value: Bool) {
        showMatchText = value
        settings.showMatchText = value
        notch.showsMatchText = value
    }

    func updateNotchWidth(_ value: Double) {
        notchWidth = value
        settings.notchExpandedWidth = value
        notch.refreshMetrics()
    }

    func updateThreshold(_ value: Float) {
        threshold = value
        settings.matchThreshold = value
        settings.thresholdOverridden = true
    }

    func updateMaxAttempts(_ value: Int) {
        maxAttempts = value
        settings.maxAttempts = value
    }

    func updateCooldown(_ value: Double) {
        unlockCooldown = value
        settings.unlockCooldown = value
    }

    func updateRequiredFrames(_ value: Int) {
        requiredFrames = value
        settings.requiredFrames = value
    }

    func setLivenessMode(_ value: LivenessMode) {
        livenessMode = value
        settings.livenessMode = value
    }

    func updateScanTimeout(_ value: Double) {
        scanTimeout = value
        settings.scanTimeout = value
    }

    func setRetryPreview(_ on: Bool) {
        retryPreview = on
        retryButton.setPreviewing(on)
    }

    func updateRetryOffsetX(_ value: Double) {
        retryOffsetX = value
        settings.retryButtonOffsetX = value
        retryButton.refresh()
    }

    func updateRetryVerticalFraction(_ value: Double) {
        retryVerticalFraction = value
        settings.retryButtonVerticalFraction = value
        retryButton.refresh()
    }

    func updateRetryButtonSize(_ value: Double) {
        retryButtonSize = value
        settings.retryButtonSize = value
        retryButton.refresh()
    }

    func quit() {
        coordinator.stop()
        NSApp.terminate(nil)
    }
}
