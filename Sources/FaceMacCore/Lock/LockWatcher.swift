import AppKit
import CoreGraphics
import Foundation

public protocol LockWatcherDelegate: AnyObject {
    func lockWatcherDidLock(_ watcher: LockWatcher)
    func lockWatcherDidUnlock(_ watcher: LockWatcher)
    /// The display woke while the session was still locked — e.g. the lid was
    /// opened. This is the natural moment to start recognising the user.
    func lockWatcherDidWakeLocked(_ watcher: LockWatcher)
}

/// Observes screen lock / unlock for the current user session.
///
/// This covers the in-session lock screen (Ctrl+Cmd+Q, screen saver), which is
/// where Accessibility-based key injection works. The pre-login `loginwindow`
/// runs in a different security context and is out of scope for v1.
public final class LockWatcher {
    private static let lockNames: Set<Notification.Name> = [
        Notification.Name("com.apple.screenIsLocked"),
        Notification.Name("com.apple.screensaver.didstart"),
    ]

    public weak var delegate: LockWatcherDelegate?

    private let center = DistributedNotificationCenter.default()
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []

    public init() {}

    public func start() {
        stop()

        let names: [Notification.Name] = [
            Notification.Name("com.apple.screenIsLocked"),
            Notification.Name("com.apple.screenIsUnlocked"),
            Notification.Name("com.apple.screensaver.didstart"),
            Notification.Name("com.apple.screensaver.didstop"),
        ]

        for name in names {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                guard let self else { return }
                if Self.lockNames.contains(notification.name) {
                    Log.lock.info("screen locked")
                    self.delegate?.lockWatcherDidLock(self)
                } else {
                    Log.lock.info("screen unlocked")
                    self.delegate?.lockWatcherDidUnlock(self)
                }
            }
            observers.append((center, token))
        }

        // The lid (or any display wake) while the session is locked is the one
        // moment where scanning should start on its own.
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.didWakeNotification] {
            let token = workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                guard let self, Self.isScreenLocked else { return }
                Log.lock.info("display woke while locked")
                self.delegate?.lockWatcherDidWakeLocked(self)
            }
            observers.append((workspaceCenter, token))
        }
    }

    public func stop() {
        observers.forEach { $0.center.removeObserver($0.token) }
        observers.removeAll()
    }

    public static var isScreenLocked: Bool {
        guard let raw = CGSessionCopyCurrentDictionary() else { return false }
        let dictionary = raw as NSDictionary
        return (dictionary["CGSSessionScreenIsLocked"] as? Bool) ?? false
    }
}
