import SwiftUI

@main
struct AIStatusbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            // Provide an empty placeholder; the real Settings window is
            // created by AppDelegate.openSettings (so it can be opened via
            // a hot key from the popover without a second Settings instance).
            EmptyView()
        }
    }
}
