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

        // Build providers from providers.json so each entry uses its real
        // baseURL / authHeaderTemplate. Falls back to the default document
        // (which already points at <HAPO_HOST>) on first launch when
        // no providers.json exists on disk.
        let doc = ProvidersStore.load()
        var providers: [QuotaProvider] = []
        for cfg in doc.providers where cfg.enabled {
            if cfg.id == "minimax" {
                providers.append(MiniMaxProvider(keychain: ks))
            } else if cfg.id == "codex" {
                // Zero-config: reads ~/.codex/auth.json, no keychain token needed.
                providers.append(CodexProvider())
            } else if cfg.id == "hapo" {
                let hapoConfig = HapoHubConfig(
                    id: cfg.id,
                    displayName: cfg.displayName ?? "AIHub",
                    baseURL: cfg.baseURL ?? HapoHubConfig.real.baseURL,
                    authHeaderTemplate: HapoHubConfig.real.authHeaderTemplate,
                    jsonPath: HapoHubConfig.real.jsonPath
                )
                providers.append(HapoHubFactory.make(
                    session: .shared,
                    config: hapoConfig,
                    keychain: ks
                ))
            } else if cfg.id == "openrouter" {
                providers.append(OpenRouterProvider(keychain: ks))
            } else if cfg.id == "deepseek" {
                providers.append(DeepSeekProvider(keychain: ks))
            } else if cfg.id == "zai" {
                providers.append(ZaiProvider(keychain: ks))
            } else if cfg.id == "claude" {
                // Zero-config: reads the Claude Code OAuth token from the Keychain.
                providers.append(ClaudeProvider())
            }
        }
        // If providers.json is missing/empty (first launch before any UI save),
        // fall back to the hard-coded defaults so the popover is never blank.
        if providers.isEmpty {
            providers = [
                MiniMaxProvider(keychain: ks),
                CodexProvider(),
                HapoHubFactory.make(
                    session: .shared,
                    config: HapoHubConfig.real,
                    keychain: ks
                )
            ]
        }
        self.quotaService = QuotaService(providers: providers, interval: store.refreshIntervalSeconds)
        // Bind so settings.pushRefreshInterval() can push changes into the loop.
        store.bind(quotaService: quotaService)
    }

    func start() {
        quotaService.start()
    }

    func stop() {
        quotaService.stop()
    }
}