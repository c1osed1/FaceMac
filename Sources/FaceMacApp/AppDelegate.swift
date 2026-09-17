import AppKit
import FaceMacCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Log.app.info("FaceMac launched")
    }

    func applicationWillTerminate(_ notification: Notification) {
        NotificationCenter.default.post(name: .faceMacWillTerminate, object: nil)
    }
}

extension Notification.Name {
    static let faceMacWillTerminate = Notification.Name("com.facemac.app.willTerminate")
}
