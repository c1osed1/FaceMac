import SwiftUI

@main
struct FaceMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.isEnabled ? "faceid" : "person.crop.circle")
                .help("FaceMac")
        }
        .menuBarExtraStyle(.menu)

        Window("Enroll Face", id: WindowID.enroll) {
            EnrollView(model: model)
        }
        .windowResizability(.contentSize)

        Window("Test Recognition", id: WindowID.test) {
            TestRecognitionView(model: model)
        }
        .windowResizability(.contentSize)

        Window("FaceMac Settings", id: WindowID.settings) {
            SettingsWindowView(model: model)
        }
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentMinSize)
    }
}
