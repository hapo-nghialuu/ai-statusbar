import Foundation

/// Returns MockHapoHubProvider when config.baseURL == "TODO_BOSS", else the real adapter.
enum HapoHubFactory {
    static func make(session: URLSession = .shared,
                     config: HapoHubConfig,
                     keychain: KeychainService) -> QuotaProvider {
        if config.baseURL == "TODO_BOSS" {
            return MockHapoHubProvider()
        }
        return HapoHubProvider(session: session, config: config, keychain: keychain)
    }
}
