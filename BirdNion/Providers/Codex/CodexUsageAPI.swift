import Foundation

/// Codex usage payload from `chatgpt.com/backend-api/wham/usage`.
///
/// Trimmed port of CodexBar's `CodexUsageResponse`: we keep `plan_type`, the
/// `rate_limit` windows, `credits`, and `additional_rate_limits` (model-specific
/// limits such as GPT-5.3-Codex-Spark — surfaced as extra `QuotaWindow`s
/// alongside primary/weekly).
struct CodexUsageResponse: Decodable, Equatable {
    let planType: String?
    let rateLimit: RateLimit?
    let credits: Credits?
    /// Model-specific limits (e.g. GPT-5.3-Codex-Spark). Decoded lossy so one
    /// malformed entry doesn't drop its siblings. `additionalRateLimitsHadValue`
    /// is true when the field was present-but-malformed — downstream code can
    /// surface that as a data-confidence flag.
    let additionalRateLimits: [AdditionalRateLimit]?
    let additionalRateLimitsDecodeFailed: Bool

    enum CodingKeys: String, CodingKey {
        case planType = "plan_type"
        case rateLimit = "rate_limit"
        case credits
        case additionalRateLimits = "additional_rate_limits"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.planType = try? c.decodeIfPresent(String.self, forKey: .planType)
        self.rateLimit = try? c.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
        self.credits = try? c.decodeIfPresent(Credits.self, forKey: .credits)

        // Lossy per-element array decode so one bad entry never rejects the
        // whole response. Mirrors CodexBar's `LossyAdditionalRateLimit` pattern.
        let hadValue = Self.hasNonNilValue(container: c, key: .additionalRateLimits)
        if let lossy = try? c.decodeIfPresent([LossyAdditionalRateLimit].self,
                                               forKey: .additionalRateLimits)
        {
            self.additionalRateLimits = lossy.compactMap(\.value)
            self.additionalRateLimitsDecodeFailed =
                lossy.contains(where: \.decodeFailed)
                || (self.additionalRateLimits?.contains(where: \.hasWindowDecodeFailure) ?? false)
        } else {
            self.additionalRateLimits = nil
            self.additionalRateLimitsDecodeFailed = hadValue
        }
    }

    init(planType: String?, rateLimit: RateLimit?, credits: Credits? = nil,
         additionalRateLimits: [AdditionalRateLimit]? = nil,
         additionalRateLimitsDecodeFailed: Bool = false) {
        self.planType = planType
        self.rateLimit = rateLimit
        self.credits = credits
        self.additionalRateLimits = additionalRateLimits
        self.additionalRateLimitsDecodeFailed = additionalRateLimitsDecodeFailed
    }

    private static func hasNonNilValue(
        container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys) -> Bool
    {
        guard container.contains(key) else { return false }
        return (try? container.decodeNil(forKey: key)) == false
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

    /// Model-specific limit (e.g. GPT-5.3-Codex-Spark). Decoded per-element
    /// lossily so one malformed entry doesn't drop its siblings.
    struct AdditionalRateLimit: Decodable, Equatable {
        let limitName: String?
        let meteredFeature: String?
        let rateLimit: RateLimit?
        let rateLimitDecodeFailed: Bool

        enum CodingKeys: String, CodingKey {
            case limitName = "limit_name"
            case meteredFeature = "metered_feature"
            case rateLimit = "rate_limit"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.limitName = try? c.decodeIfPresent(String.self, forKey: .limitName)
            self.meteredFeature = try? c.decodeIfPresent(String.self, forKey: .meteredFeature)
            let rateLimitHadValue = Self.hasNonNilValue(container: c, key: .rateLimit)
            do {
                self.rateLimit = try c.decodeIfPresent(RateLimit.self, forKey: .rateLimit)
                self.rateLimitDecodeFailed = false
            } catch {
                self.rateLimit = nil
                self.rateLimitDecodeFailed = rateLimitHadValue
            }
        }

        init(limitName: String?, meteredFeature: String?, rateLimit: RateLimit?,
             rateLimitDecodeFailed: Bool = false) {
            self.limitName = limitName
            self.meteredFeature = meteredFeature
            self.rateLimit = rateLimit
            self.rateLimitDecodeFailed = rateLimitDecodeFailed
        }

        private static func hasNonNilValue(
            container: KeyedDecodingContainer<CodingKeys>,
            key: CodingKeys) -> Bool
        {
            guard container.contains(key) else { return false }
            return (try? container.decodeNil(forKey: key)) == false
        }

        /// True if any nested window failed to decode — drives the UI's
        /// data-confidence flag.
        var hasWindowDecodeFailure: Bool {
            rateLimitDecodeFailed
                || (rateLimit?.primaryWindow == nil && rateLimit?.secondaryWindow == nil
                    && rateLimitDecodeFailed)
        }
    }

    /// Decodes one `additional_rate_limits` element without throwing, so a
    /// single malformed entry can't discard its valid siblings.
    private struct LossyAdditionalRateLimit: Decodable {
        let value: AdditionalRateLimit?
        let decodeFailed: Bool

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            self.value = try? c.decode(AdditionalRateLimit.self)
            self.decodeFailed = self.value == nil
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
