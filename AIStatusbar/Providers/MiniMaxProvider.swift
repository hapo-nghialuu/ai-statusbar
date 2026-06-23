import Foundation

/// MiniMax Token Plan quota provider.
/// Endpoint is a compile-time constant (not overridable from providers.json — Finding F2).
final class MiniMaxProvider: QuotaProvider {
    static let endpoint = URL(string: "https://api.minimax.io/v1/token_plan/remains")!

    let id = "minimax"
    let displayName = "MiniMax"
    private let session: URLSession
    private let keychain: KeychainService

    init(session: URLSession = .shared, keychain: KeychainService) {
        self.session = session
        self.keychain = keychain
    }

    func fetch() async throws -> ProviderStatus {
        let token: String
        do {
            token = try keychain.read(account: "minimax")
        } catch KeychainError.itemNotFound {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Chưa cấu hình token")
        } catch let e as KeychainError {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Keychain error: \(e)")
        } catch {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "\(error)")
        }

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Network: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Response không phải HTTP")
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Token bị từ chối — kiểm tra loại key (inference key, không phải Subscription Key)")
        }
        guard (200..<300).contains(http.statusCode) else {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "HTTP \(http.statusCode)")
        }
        return parse(data)
    }

    func parse(_ data: Data) -> ProviderStatus {
        let decoder = JSONDecoder()
        guard let root = try? decoder.decode(RemainsResponse.self, from: data),
              let m = root.model_remains.first else {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Response thiếu trường")
        }
        let interval = QuotaWindow(label: "5 giờ",
                                   usedPct: 100 - m.current_interval_remaining_percent,
                                   remainingPct: m.current_interval_remaining_percent)
        let weekly = QuotaWindow(label: "Tuần",
                                 usedPct: 100 - m.current_weekly_remaining_percent,
                                 remainingPct: m.current_weekly_remaining_percent)
        return ProviderStatus(id: id, displayName: displayName,
                              windows: [interval, weekly],
                              lastUpdated: Date(),
                              error: nil)
    }

    private struct RemainsResponse: Decodable {
        let model_remains: [ModelRemain]
    }
    private struct ModelRemain: Decodable {
        let model_name: String
        let current_interval_total_count: Int
        let current_interval_usage_count: Int
        let current_interval_remaining_percent: Int
        let current_weekly_total_count: Int
        let current_weekly_usage_count: Int
        let current_weekly_remaining_percent: Int
    }
}
