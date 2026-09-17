import Foundation
import IOKit.pwr_mgt

/// Prevents the display from dimming/sleeping while recognition is running.
///
/// Without this the lock screen can dim or turn the panel off during the scan,
/// because from the system's point of view nobody is interacting.
public final class DisplaySleepGuard {
    public static let shared = DisplaySleepGuard()

    private var assertionID: IOPMAssertionID = 0
    private var holding = false

    public init() {}

    public var isHolding: Bool { holding }

    public func hold(reason: String = "FaceMac is recognising you") {
        guard !holding else { return }
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoDisplaySleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard result == kIOReturnSuccess else {
            Log.app.error("could not create display sleep assertion: \(result)")
            return
        }
        assertionID = id
        holding = true
        Log.app.info("display sleep assertion acquired")
    }

    public func release() {
        guard holding else { return }
        IOPMAssertionRelease(assertionID)
        assertionID = 0
        holding = false
        Log.app.info("display sleep assertion released")
    }
}
