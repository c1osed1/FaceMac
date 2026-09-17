import AppKit
import FaceMacCore
import SwiftUI

enum WindowID {
    static let enroll = "enroll"
    static let test = "test"
    static let settings = "settings"
}

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.statusText)

        Divider()

        Toggle(L10n.t("menu.enabled"), isOn: Binding(
            get: { model.isEnabled },
            set: { model.setEnabled($0) }
        ))

        Button(L10n.t("menu.enroll")) { open(WindowID.enroll) }
        Button(L10n.t("menu.test")) { open(WindowID.test) }
            .disabled(!model.hasEnrollment)
        Button(L10n.t("menu.previewNotch")) { model.previewNotch() }
        Button(L10n.t("menu.scanNow")) { model.scanNow() }
            .disabled(!model.isEnabled || !model.hasEnrollment)
        Button(L10n.t("menu.forgetFace")) { model.forgetFace() }
            .disabled(!model.hasEnrollment)

        Divider()

        Button(model.hasPassword ? L10n.t("menu.changePassword") : L10n.t("menu.setPassword")) { model.setPassword() }
        Button(L10n.t("menu.typePassword")) { model.tryUnlockNow() }
            .disabled(!model.hasPassword)

        if !model.accessibilityTrusted {
            Button(L10n.t("menu.grantAccessibility")) { model.requestAccessibility() }
        }

        Divider()

        Button(L10n.t("menu.settings")) { open(WindowID.settings) }
        Button(L10n.t("menu.quit")) { model.quit() }
    }

    private func open(_ id: String) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: id)
    }
}
