import ApplicationServices
import Carbon.HIToolbox
import Foundation

/// Synthesises keystrokes via CGEvent. Requires Accessibility permission.
public final class KeyboardInjector {
    public enum InjectError: Error {
        case accessibilityNotTrusted
        case eventCreationFailed
    }

    public init() {}

    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    public static func requestAccessibility(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func type(_ text: String) throws {
        guard Self.isAccessibilityTrusted else {
            throw InjectError.accessibilityNotTrusted
        }

        let source = CGEventSource(stateID: .hidSystemState)
        for scalar in text.unicodeScalars {
            var utf16 = Array(String(scalar).utf16)
            guard
                let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false)
            else {
                throw InjectError.eventCreationFailed
            }
            keyDown.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyUp.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: &utf16)
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)
        }
    }

    public func pressReturn() throws {
        try press(virtualKey: CGKeyCode(kVK_Return))
    }

    public func press(virtualKey: CGKeyCode) throws {
        guard Self.isAccessibilityTrusted else {
            throw InjectError.accessibilityNotTrusted
        }
        let source = CGEventSource(stateID: .hidSystemState)
        CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)?
            .post(tap: .cghidEventTap)
        CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)?
            .post(tap: .cghidEventTap)
    }
}
