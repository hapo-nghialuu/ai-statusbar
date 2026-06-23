import Foundation

/// Stand-in for HapoHubProvider when real endpoint is unknown (config.baseURL == "TODO_BOSS").
final class MockHapoHubProvider: QuotaProvider {
    let id = "hapo"
    let displayName = "Hapo AI Hub (mock)"

    func fetch() async throws -> ProviderStatus {
        let now = Date()
        return ProviderStatus(
            id: id,
            displayName: displayName,
            windows: [
                QuotaWindow(label: "5 giờ", usedPct: 20, remainingPct: 80),
                QuotaWindow(label: "Tuần", usedPct: 40, remainingPct: 60)
            ],
            lastUpdated: now,
            error: nil
        )
    }
}
