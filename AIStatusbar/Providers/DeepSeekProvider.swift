import Foundation

/// DeepSeek balance provider.
///
/// Endpoint: `GET https://api.deepseek.com/user/balance`
/// Auth: `Authorization: Bearer <key>` (key prefix `sk-...`).
///
/// Response envelope:
/// ```json
/// { "is_available": true,
///   "balance_infos": [ { "currency": "USD", "total_balance": "12.34", ... } ] }
/// ```
/// DeepSeek is a prepaid balance, not a rate-limited quota — there is no
/// percentage to show. We surface the balance as `creditsRemaining` and a
/// subtitle window; the menu-bar chip stays blank (no %).
final class DeepSeekProvider: QuotaProvider {
    let id = "deepseek"
    let displayName = "DeepSeek"

    static let endpoint = URL(string: "https://api.deepseek.com/user/balance")!

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
        guard let root = try? JSONDecoder().decode(BalanceResponse.self, from: data) else {
            return failure("Response thiếu trường")
        }
        guard let info = root.balanceInfos.first else {
            return failure("Không có thông tin số dư")
        }
        let amount = Double(info.totalBalance) ?? 0
        let symbol = info.currency == "CNY" ? "¥" : "$"
        // Balance-only provider: a single full-width window carries the figure
        // as a subtitle so the row isn't blank, but there is no real %.
        let window = QuotaWindow(
            label: "Số dư",
            usedPct: 0,
            remainingPct: 100,
            subtitle: "\(symbol)\(info.totalBalance)")
        return ProviderStatus(
            id: id,
            displayName: displayName,
            windows: [window],
            lastUpdated: Date(),
            error: nil,
            accountLabel: accountLabel,
            creditsRemaining: amount)
    }

    private func failure(_ message: String) -> ProviderStatus {
        ProviderStatus(id: id, displayName: displayName, windows: [], lastUpdated: Date(), error: message)
    }

    private struct BalanceResponse: Decodable {
        let isAvailable: Bool
        let balanceInfos: [BalanceInfo]
        enum CodingKeys: String, CodingKey {
            case isAvailable = "is_available"
            case balanceInfos = "balance_infos"
        }
    }
    private struct BalanceInfo: Decodable {
        let currency: String
        let totalBalance: String
        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
        }
    }
}
