import Foundation

/// OpenRouter credits provider.
///
/// Endpoint: `GET https://openrouter.ai/api/v1/credits`
/// Auth: `Authorization: Bearer <key>` (key prefix `sk-or-...`).
///
/// Response envelope:
/// ```json
/// { "data": { "total_credits": 10.0, "total_usage": 3.2 } }
/// ```
/// OpenRouter sells prepaid credits; `total_usage` accumulates against
/// `total_credits`. We surface a single window showing the % consumed plus a
/// dollar "remaining" figure. No reset (credits don't refill on a cadence).
final class OpenRouterProvider: QuotaProvider {
    let id = "openrouter"
    let displayName = "OpenRouter"

    static let endpoint = URL(string: "https://openrouter.ai/api/v1/credits")!

    private let session: URLSession
    private let keychain: KeychainService

    init(session: URLSession = .shared, keychain: KeychainService) {
        self.session = session
        self.keychain = keychain
    }

    private func override() -> String? {
        ProvidersStore.load().providers.first(where: { $0.id == self.id })?.accountLabel
    }

    func fetch() async throws -> ProviderStatus {
        // Token resolution mirrors the other providers: shared CodexBar config
        // file first, then the legacy Keychain entry.
        let token = CodexBarConfigStore.apiKey(provider: id) ?? (try? keychain.read(account: id))
        guard let token, !token.isEmpty else {
            return failure("Chưa cấu hình token")
        }
        let accountLabel = override() ?? String(token.prefix(8))

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            return failure("Network: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else { return failure("Response không phải HTTP") }
        guard (200..<300).contains(http.statusCode) else { return failure("HTTP \(http.statusCode)") }
        return parse(data, accountLabel: accountLabel)
    }

    func parse(_ data: Data, accountLabel: String) -> ProviderStatus {
        guard let root = try? JSONDecoder().decode(CreditsResponse.self, from: data) else {
            return failure("Response thiếu trường")
        }
        let total = root.data.totalCredits
        let used = root.data.totalUsage
        let remaining = max(0, total - used)
        let usedPct = total > 0 ? max(0, min(100, Int((used / total * 100).rounded()))) : 0
        let window = QuotaWindow(
            label: "Tín dụng",
            usedPct: usedPct,
            remainingPct: 100 - usedPct,
            subtitle: String(format: "$%.2f / $%.2f", remaining, total))
        return ProviderStatus(
            id: id,
            displayName: displayName,
            windows: [window],
            lastUpdated: Date(),
            error: nil,
            accountLabel: accountLabel,
            creditsRemaining: remaining)
    }

    private func failure(_ message: String) -> ProviderStatus {
        ProviderStatus(id: id, displayName: displayName, windows: [], lastUpdated: Date(), error: message)
    }

    private struct CreditsResponse: Decodable {
        let data: CreditsData
        struct CreditsData: Decodable {
            let totalCredits: Double
            let totalUsage: Double
            enum CodingKeys: String, CodingKey {
                case totalCredits = "total_credits"
                case totalUsage = "total_usage"
            }
        }
    }
}
