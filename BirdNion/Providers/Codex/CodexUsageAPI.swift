import Foundation

/// Codex usage payload from `chatgpt.com/backend-api/wham/usage`.
///
/// Trimmed port of CodexBar's `CodexUsageResponse`: we keep `plan_type`, the
/// `rate_limit` windows, and `credits` (all surfaced in the providers panel).
/// `additional_rate_limits` is still dropped (YAGNI).
struct CodexUsageResponse: Decodable, Equatable {
    let planType: String?
    let rateLimit: RateLimit?
    let credits: Credits?

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.planType = try? c.decodeIfPresent(String.self, forKey: .planType)
        self.rateLimit = try? c.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
        self.credits = try? c.decodeIfPresent(Credits.self, forKey: .credits)
    }

    init(planType: String?, rateLimit: RateLimit?, credits: Credits? = nil) {
        self.planType = planType
        self.rateLimit = rateLimit
        self.credits = credits
    }

    /// Credit balance block. `balance` may arrive as a JSON number or a string,
    /// so decode leniently (matches CodexBar's `CreditDetails`).
    struct Credits: Decodable, Equatable {
        let balance: Double?

        enum CodingKeys: String, CodingKey { case balance }

        init(balance: Double?) { self.balance = balance }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            if let d = try? c.decode(Double.self, forKey: .balance) {
                self.balance = d
            } else if let s = try? c.decode(String.self, forKey: .balance) {
                self.balance = Double(s)
            } else {
                self.balance = nil
            }
        }
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
        request.setValue("BirdNion", forHTTPHeaderField: "User-Agent")
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
