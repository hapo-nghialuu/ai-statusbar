import SwiftUI

@main
struct AIStatusbarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // We hold our own services here so the `Settings` scene can access them
    // before the AppDelegate has a chance to run. AppDelegate reuses the
    // same instances (see ServicesContainer.shared reference below).
    @State private var settings: SettingsStore
    @State private var keychain: KeychainService
    @State private var config: ConfigService
    @State private var quota: QuotaService

    init() {
        let services = ServicesContainer()
        ServicesContainer.register(services: services)
        _settings = State(initialValue: services.settings)
        _keychain = State(initialValue: services.keychain)
        _config = State(initialValue: services.configService)
        _quota = State(initialValue: services.quotaService)
    }

    var body: some Scene {
        // 1×1 keep-alive window so SwiftUI's lifecycle keeps the AppKit shell
        // alive while the only visible scene is `Settings` (otherwise the
        // native toolbar can fail to render). Same trick CodexBar uses.
        WindowGroup("AIStatusbarLifecycleKeepalive") {
            HiddenWindowView()
        }
        .defaultSize(width: 20, height: 20)
        .windowStyle(.hiddenTitleBar)

        // Native macOS Settings scene — system routes Cmd+, here, AppKit
        // centers it on the active screen.
        Settings {
            SettingsSceneRoot()
                .environmentObject(settings)
                .environmentObject(keychain)
                .environmentObject(config)
                .environmentObject(quota)
        }
    }
}
