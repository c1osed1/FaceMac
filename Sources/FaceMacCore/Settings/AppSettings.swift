import Foundation

public final class AppSettings {
    public static let shared = AppSettings()

    private enum Key: String {
        case enabled
        case matchThreshold
        case thresholdOverridden
        case maxAttempts
        case autoUnlock
        case unlockCooldown
        case requiredFrames
        case scanTimeout
        case retryButtonOffsetX
        case retryButtonVerticalFraction
        case retryButtonSize
        case notchExpandedWidth
        case language
        case showMatchText
        case rejectionThreshold
        case keepDisplayAwake
        case livenessMode
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.enabled.rawValue: true,
            Key.matchThreshold.rawValue: 0.45,
            Key.maxAttempts.rawValue: 5,
            Key.autoUnlock.rawValue: true,
            Key.unlockCooldown.rawValue: 3.0,
            Key.requiredFrames.rawValue: 3,
            Key.scanTimeout.rawValue: 5.0,
            Key.retryButtonOffsetX.rawValue: 0.0,
            Key.retryButtonVerticalFraction.rawValue: 0.852,
            Key.retryButtonSize.rawValue: 54.0,
            Key.notchExpandedWidth.rawValue: 232.0,
            Key.language.rawValue: AppLanguage.system.rawValue,
            Key.showMatchText.rawValue: true,
            Key.rejectionThreshold.rawValue: 0.20,
            Key.keepDisplayAwake.rawValue: true,
            Key.livenessMode.rawValue: LivenessMode.blinkOrMotion.rawValue,
        ])
    }

    public var isEnabled: Bool {
        get { defaults.bool(forKey: Key.enabled.rawValue) }
        set { defaults.set(newValue, forKey: Key.enabled.rawValue) }
    }

    public var matchThreshold: Float {
        get { defaults.float(forKey: Key.matchThreshold.rawValue) }
        set { defaults.set(newValue, forKey: Key.matchThreshold.rawValue) }
    }

    /// False until the user sets a threshold themselves; lets the app apply the
    /// active embedder's recommended default on first run.
    public var thresholdOverridden: Bool {
        get { defaults.bool(forKey: Key.thresholdOverridden.rawValue) }
        set { defaults.set(newValue, forKey: Key.thresholdOverridden.rawValue) }
    }

    public var maxAttempts: Int {
        get { defaults.integer(forKey: Key.maxAttempts.rawValue) }
        set { defaults.set(newValue, forKey: Key.maxAttempts.rawValue) }
    }

    public var autoUnlock: Bool {
        get { defaults.bool(forKey: Key.autoUnlock.rawValue) }
        set { defaults.set(newValue, forKey: Key.autoUnlock.rawValue) }
    }

    public var unlockCooldown: TimeInterval {
        get { defaults.double(forKey: Key.unlockCooldown.rawValue) }
        set { defaults.set(newValue, forKey: Key.unlockCooldown.rawValue) }
    }

    /// How many consecutive camera frames must match before the password is
    /// typed. A single lucky frame is how a stranger gets in.
    public var requiredFrames: Int {
        get { max(defaults.integer(forKey: Key.requiredFrames.rawValue), 1) }
        set { defaults.set(newValue, forKey: Key.requiredFrames.rawValue) }
    }

    /// How long the camera stays on for a single recognition attempt.
    public var scanTimeout: TimeInterval {
        get { defaults.double(forKey: Key.scanTimeout.rawValue) }
        set { defaults.set(newValue, forKey: Key.scanTimeout.rawValue) }
    }

    /// Where the lock-screen retry button sits: horizontal offset from the
    /// screen centre, and vertical position as a fraction of screen height.
    public var retryButtonOffsetX: Double {
        get { defaults.double(forKey: Key.retryButtonOffsetX.rawValue) }
        set { defaults.set(newValue, forKey: Key.retryButtonOffsetX.rawValue) }
    }

    public var retryButtonVerticalFraction: Double {
        get { defaults.double(forKey: Key.retryButtonVerticalFraction.rawValue) }
        set { defaults.set(newValue, forKey: Key.retryButtonVerticalFraction.rawValue) }
    }

    /// UI language: "system", "en", "ru" or "zh".
    public var language: AppLanguage {
        get { AppLanguage(rawValue: defaults.string(forKey: Key.language.rawValue) ?? "") ?? .system }
        set { defaults.set(newValue.rawValue, forKey: Key.language.rawValue) }
    }

    /// Width of the notch overlay when it is open.
    public var notchExpandedWidth: Double {
        get { defaults.double(forKey: Key.notchExpandedWidth.rawValue) }
        set { defaults.set(newValue, forKey: Key.notchExpandedWidth.rawValue) }
    }

    /// Below this cosine similarity the face is treated as a different person
    /// and recognition is rejected immediately instead of waiting for the timeout.
    public var rejectionThreshold: Float {
        get { defaults.float(forKey: Key.rejectionThreshold.rawValue) }
        set { defaults.set(newValue, forKey: Key.rejectionThreshold.rawValue) }
    }

    /// Proof-of-life required before the password is typed.
    public var livenessMode: LivenessMode {
        get { LivenessMode(storedValue: defaults.string(forKey: Key.livenessMode.rawValue)) }
        set { defaults.set(newValue.rawValue, forKey: Key.livenessMode.rawValue) }
    }

    /// Keeps the display from dimming while a scan is running.
    public var keepDisplayAwake: Bool {
        get { defaults.bool(forKey: Key.keepDisplayAwake.rawValue) }
        set { defaults.set(newValue, forKey: Key.keepDisplayAwake.rawValue) }
    }

    /// Shows "It's you / NN% match" next to the success animation.
    public var showMatchText: Bool {
        get { defaults.bool(forKey: Key.showMatchText.rawValue) }
        set { defaults.set(newValue, forKey: Key.showMatchText.rawValue) }
    }

    /// Diameter of the lock-screen retry button.
    public var retryButtonSize: Double {
        get { defaults.double(forKey: Key.retryButtonSize.rawValue) }
        set { defaults.set(newValue, forKey: Key.retryButtonSize.rawValue) }
    }

    /// Adopts the active embedder's recommended cosine threshold unless the user
    /// has set one themselves.
    public func applyRecommendedThreshold(from embedder: FaceEmbedder) {
        guard !thresholdOverridden else { return }
        matchThreshold = embedder.recommendedThreshold
    }
}
