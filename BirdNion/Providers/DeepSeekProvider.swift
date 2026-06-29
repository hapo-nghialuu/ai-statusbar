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

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func override() -> String? {
        BirdNionConfigStore.accountLabel(provider: id)
    }

    func fetch() async throws -> ProviderStatus {
        // Env override first (DEEPSEEK_API_KEY), then config storage.
        let envToken = ProcessInfo.processInfo.environment["DEEPSEEK_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let token = (envToken?.isEmpty == false ? envToken : nil) ?? BirdNionConfigStore.apiKey(provider: id)
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
        // Prefer the USD-funded entry when multiple currencies are present.
        guard let info = root.balanceInfos.first(where: { $0.currency == "USD" }) ?? root.balanceInfos.first else {
            return failure("Không có thông tin số dư")
        }
        let amount = Double(info.totalBalance) ?? 0
        let symbol = info.currency == "CNY" ? "¥" : "$"
        // Balance-only provider: a single full-width window carries the figure
        // as a subtitle. When the balance runs out we flag it red (usedPct=100).
        let lowBalance = amount <= 0
        let subtitle: String
        if lowBalance {
            subtitle = "Hết số dư — cần nạp thêm"
        } else if let toppedUp = info.toppedUpBalance, let granted = info.grantedBalance {
            subtitle = "\(symbol)\(info.totalBalance) · Trả: \(symbol)\(toppedUp) · Tặng: \(symbol)\(granted)"
        } else {
            subtitle = "\(symbol)\(info.totalBalance)"
        }
        let window = QuotaWindow(
            label: "Số dư",
            usedPct: lowBalance ? 100 : 0,
            remainingPct: lowBalance ? 0 : 100,
            subtitle: subtitle)
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
        let grantedBalance: String?
        let toppedUpBalance: String?
        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case grantedBalance = "granted_balance"
            case toppedUpBalance = "topped_up_balance"
        }
    }
}
