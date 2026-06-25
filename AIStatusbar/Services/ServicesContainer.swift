import Foundation
import SwiftUI

/// Owns the 3 app-wide services so AppDelegate (non-SwiftUI) and Views
/// (SwiftUI) can share the same instances.
@MainActor
final class ServicesContainer: ObservableObject {
    let keychain: KeychainService
    let configService: ConfigService
    let quotaService: QuotaService
    let settings: SettingsStore

    /// Process-wide instance. Set by `AppDelegate.register(services:)` from
    /// the App's `init` so the Settings scene can use the same services as
    /// AppDelegate. Reading before registration is a programmer error.
    static private(set) var shared: ServicesContainer?

    static func register(services: ServicesContainer) {
        shared = services
    }

    init() {
        let ks = KeychainService()
        self.keychain = ks
        self.configService = ConfigService()
        let store = SettingsStore()
        self.settings = store
        self.quotaService = QuotaService(providers: Self.makeProviders(keychain: ks),
                                         interval: store.refreshIntervalSeconds)
        // Bind so settings.pushRefreshInterval() can push changes into the loop.
        store.bind(quotaService: quotaService)
    }

    /// Build the ordered list of `QuotaProvider` instances from the latest
    /// providers.json on disk. Order matches the file (the order the user
    /// arranged in the Settings sidebar); disabled entries are skipped.
    /// Falls back to the hard-coded default triplet when the file is empty.
    /// Shared between `init()` and `rebuildProviders()` so reorder / toggle
    /// flows use the same factory.
    static func makeProviders(keychain: KeychainService) -> [QuotaProvider] {
        let doc = ProvidersStore.load()
        var providers: [QuotaProvider] = []
        for cfg in doc.providers where cfg.enabled {
            switch cfg.id {
            case "minimax":
                providers.append(MiniMaxProvider(keychain: keychain))
            case "codex":
                // Zero-config: reads ~/.codex/auth.json, no keychain token needed.
                providers.append(CodexProvider())
            case "hapo":
                let hapoConfig = HapoHubConfig(
                    id: cfg.id,
                    displayName: cfg.displayName ?? "AIHub",
                    baseURL: cfg.baseURL ?? HapoHubConfig.real.baseURL,
                    authHeaderTemplate: HapoHubConfig.real.authHeaderTemplate,
                    jsonPath: HapoHubConfig.real.jsonPath)
                providers.append(HapoHubFactory.make(
                    session: .shared,
                    config: hapoConfig,
                    keychain: keychain))
            case "openrouter":
                providers.append(OpenRouterProvider(keychain: keychain))
            case "deepseek":
                providers.append(DeepSeekProvider(keychain: keychain))
            case "zai":
                providers.append(ZaiProvider(keychain: keychain))
            case "claude":
                // Zero-config: reads the Claude Code OAuth token from the Keychain.
                providers.append(ClaudeProvider())
            default:
                break
            }
        }
        // If providers.json is missing/empty (first launch before any UI save),
        // fall back to the hard-coded defaults so the popover is never blank.
        if providers.isEmpty {
            providers = [
                MiniMaxProvider(keychain: keychain),
                CodexProvider(),
                HapoHubFactory.make(
                    session: .shared,
                    config: HapoHubConfig.real,
                    keychain: keychain)
            ]
        }
        return providers
    }

    /// Rebuild the QuotaService provider list from the current providers.json
    /// on disk. Called by AppDelegate after the user reorders / toggles in
    /// the Settings sidebar so the popover tabs + menu-bar rotation pick up
    /// the new order immediately (no app restart needed).
    func rebuildProviders() {
        quotaService.setProviders(Self.makeProviders(keychain: keychain))
    }

    func start() {
        quotaService.start()
    }

    func stop() {
        quotaService.stop()
    }
}