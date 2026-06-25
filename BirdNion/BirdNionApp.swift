import SwiftUI

/// Notification name the AppDelegate uses to ask SwiftUI to open the
/// settings window. We can't call `openWindow` directly from AppDelegate
/// (it's an environment value), so we go through NotificationCenter.
extension Notification.Name {
    static let openSettingsWindow = Notification.Name("birdnion.openSettingsWindow")
}

@main
struct BirdNionApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var settings: SettingsStore
    @State private var config: ConfigService
    @State private var quota: QuotaService

    init() {
        let services = ServicesContainer()
        ServicesContainer.register(services: services)
        _settings = State(initialValue: services.settings)
        _config = State(initialValue: services.configService)
        _quota = State(initialValue: services.quotaService)
    }

    var body: some Scene {
        // 1×1 keep-alive so the AppKit shell stays alive while the Settings
        // window is closed.
        WindowGroup("BirdNionLifecycleKeepalive") {
            HiddenWindowView()
        }
        .defaultSize(width: 20, height: 20)
        .windowStyle(.hiddenTitleBar)

        // Native SwiftUI Settings scene. SwiftUI owns this window, so there's
        // no hand-built NSWindow + NSHostingView to drive NSISEngine into
        // recursion. AppDelegate brings the app forward and HiddenWindowView
        // calls the `openSettings` environment action to present it.
        Settings {
            SettingsSceneRoot()
                .environmentObject(settings)
                .environmentObject(config)
                .environmentObject(quota)
        }
    }
}
