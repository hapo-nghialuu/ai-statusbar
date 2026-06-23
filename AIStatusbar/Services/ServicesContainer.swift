import Foundation
import SwiftUI

/// Owns the 3 app-wide services so AppDelegate (non-SwiftUI) and Views
/// (SwiftUI) can share the same instances.
@MainActor
final class ServicesContainer: ObservableObject {
    let keychain: KeychainService
    let configService: ConfigService
    let quotaService: QuotaService

    init() {
        let ks = KeychainService()
        self.keychain = ks
        self.configService = ConfigService()
        let minimax = MiniMaxProvider(keychain: ks)
        let hapo = HapoHubFactory.make(config: HapoHubConfig.mock, keychain: ks)
        self.quotaService = QuotaService(providers: [minimax, hapo], interval: 120)
    }

    func start() {
        quotaService.start()
    }

    func stop() {
        quotaService.stop()
    }
}
