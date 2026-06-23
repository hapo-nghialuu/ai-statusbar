import Foundation

/// Codex usage payload from `chatgpt.com/backend-api/wham/usage`.
///
/// Trimmed port of CodexBar's `CodexUsageResponse`: we keep only `plan_type`
/// and the `rate_limit` windows (the data this app surfaces). Credits and
/// `additional_rate_limits` are intentionally dropped (YAGNI).
struct CodexUsageResponse: Decodable, Equatable {
    let planType: String?
    let rateLimit: RateLimit?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.planType = try? c.decodeIfPresent(String.self, forKey: .planType)
        self.rateLimit = try? c.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
    }

    init(planType: String?, rateLimit: RateLimit?) {
        self.planType = planType
        self.rateLimit = rateLimit
    }

    struct RateLimit: Decodable, Equatable {
        let primaryWindow: Window?
        let secondaryWindow: Window?

        enum CodingKeys: String, CodingKey {
            case primaryWindow = "primary_window"
            case secondaryWindow = "secondary_window"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Lossy per-window: a malformed window must not discard its sibling.
            self.primaryWindow = try? c.decodeIfPresent(Window.self, forKey: .primaryWindow)
            self.secondaryWindow = try? c.decodeIfPresent(Window.self, forKey: .secondaryWindow)
        }

        init(primaryWindow: Window?, secondaryWindow: Window?) {
            self.primaryWindow = primaryWindow
            self.secondaryWindow = secondaryWindow
        }
    }

    struct Window: Decodable, Equatable {
        let usedPercent: Int
        let resetAt: Int
        let limitWindowSeconds: Int

        enum CodingKeys: String, CodingKey {
            case usedPercent = "used_percent"
            case resetAt = "reset_at"
            case limitWindowSeconds = "limit_window_seconds"
        }
    }
}

enum CodexUsageError: Error, Equatable {
    case unauthorized
    case invalidResponse
    case serverError(Int)
}

/// Fetches Codex usage over the ChatGPT backend API using an OAuth access token.
/// Mirrors CodexBar's `CodexOAuthUsageFetcher.fetchUsage` but over `URLSession`.
enum CodexUsageAPI {
    static let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!

    static func fetchUsage(
        accessToken: String,
        accountId: String?,
        session: URLSession = .shared) async throws -> CodexUsageResponse
    {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 30
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("AIStatusbar", forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountId, !accountId.isEmpty {
            request.setValue(accountId, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw CodexUsageError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            guard let decoded = try? JSONDecoder().decode(CodexUsageResponse.self, from: data) else {
                throw CodexUsageError.invalidResponse
            }
            return decoded
        case 401, 403:
            throw CodexUsageError.unauthorized
        default:
            throw CodexUsageError.serverError(http.statusCode)
        }
    }
}
