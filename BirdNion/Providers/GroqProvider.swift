import Foundation

/// Groq usage provider. Bearer API key → Prometheus metrics endpoint reports
/// rolling 5-minute rates (no hard quota), so we surface req/min + tokens/min
/// as an informational window. Native port of CodexBar's GroqUsageFetcher.
final class GroqProvider: QuotaProvider {
    let id = "groq"
    let displayName = "Groq"

    static let queryURL = URL(string: "https://api.groq.com/v1/metrics/prometheus/api/v1/query")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func override() -> String? { BirdNionConfigStore.accountLabel(provider: id) }

    func fetch() async throws -> ProviderStatus {
        guard let token = BirdNionConfigStore.apiKey(provider: id), !token.isEmpty else {
            return failure("Chưa cấu hình API key Groq")
        }
        let accountLabel = override() ?? String(token.prefix(8))

        async let requests = scalar("sum(model_project_id_status_code:requests:rate5m)", token: token)
        async let tokensIn = scalar("sum(model_project_id:tokens_in:rate5m)", token: token)
        async let tokensOut = scalar("sum(model_project_id:tokens_out:rate5m)", token: token)
        async let cacheHits = scalar("sum(model_project_id:prompt_cache_hits:rate5m)", token: token)

        do {
            let (req, tin, tout, hits) = try await (requests, tokensIn, tokensOut, cacheHits)
            let reqPerMin = req * 60
            let tokPerMin = (tin + tout) * 60
            let cachePerMin = hits * 60

            // Primary: Requests/min (rate metric → usedPct=0, value in subtitle)
            let reqWindow = QuotaWindow(
                label: "Yêu cầu/phút",
                usedPct: 0, remainingPct: 100,
                subtitle: "\(dec(reqPerMin)) req/phút",
                windowSeconds: 300)

            // Secondary: Tokens/min
            let tokWindow = QuotaWindow(
                label: "Tokens/phút",
                usedPct: 0, remainingPct: 100,
                subtitle: "\(dec(tokPerMin)) tok/phút",
                windowSeconds: 300)

            // Tertiary: Cache hits/min — only shown when > 0
            var windows: [QuotaWindow] = [reqWindow, tokWindow]
            if cachePerMin > 0 {
                let cacheWindow = QuotaWindow(
                    label: "Cache hit/phút",
                    usedPct: 0, remainingPct: 100,
                    subtitle: "\(dec(cachePerMin)) cache/phút",
                    windowSeconds: 300)
                windows.append(cacheWindow)
            }

            return ProviderStatus(
                id: id, displayName: displayName, windows: windows, lastUpdated: Date(),
                error: nil, accountLabel: accountLabel, planName: "Prometheus metrics")
        } catch {
            return failure("Groq: \(error.localizedDescription)")
        }
    }

    private func scalar(_ query: String, token: String) async throws -> Double {
        var comp = URLComponents(url: Self.queryURL, resolvingAgainstBaseURL: false)!
        comp.queryItems = [URLQueryItem(name: "query", value: query)]
        var req = URLRequest(url: comp.url!)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15
        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ProviderError.http((response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return Self.parseScalar(data)
    }

    static func parseScalar(_ data: Data) -> Double {
        guard let r = try? JSONDecoder().decode(PromResponse.self, from: data), r.status == "success" else {
            return 0
        }
        return r.data?.result.compactMap { $0.value?.last?.doubleValue }.reduce(0, +) ?? 0
    }

    private func dec(_ v: Double) -> String {
        if v >= 100 { return String(format: "%.0f", v) }
        if v >= 10 { return String(format: "%.1f", v) }
        return String(format: "%.2f", v)
    }

    private func failure(_ message: String) -> ProviderStatus {
        ProviderStatus(id: id, displayName: displayName, windows: [], lastUpdated: Date(), error: message)
    }

    private enum ProviderError: LocalizedError {
        case http(Int)
        var errorDescription: String? { switch self { case let .http(c): "HTTP \(c)" } }
    }

    struct PromResponse: Decodable {
        let status: String
        let data: Payload?
        struct Payload: Decodable { let result: [Series] }
        struct Series: Decodable { let value: [PromValue]? }
        enum PromValue: Decodable {
            case number(Double), string(String)
            init(from decoder: Decoder) throws {
                let c = try decoder.singleValueContainer()
                if let n = try? c.decode(Double.self) { self = .number(n); return }
                self = .string(try c.decode(String.self))
            }
            var doubleValue: Double? {
                switch self { case let .number(n): n; case let .string(s): Double(s) }
            }
        }
    }
}
