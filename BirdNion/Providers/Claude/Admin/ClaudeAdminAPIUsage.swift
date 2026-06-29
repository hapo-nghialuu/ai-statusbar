import Foundation

// Native port of CodexBarCore's Claude Admin API usage stack. Hits Anthropic's
// org-level Usage & Cost API with an Admin key and rolls the daily buckets up
// into a 30-day org dashboard (cost + tokens + per-model + per-cost-item).
// Pure Foundation HTTP/JSON. The orchestrator (source `.api`) maps the snapshot
// into a ClaudeUsageSnapshot; the popover renders the daily breakdown.

// MARK: - Settings

enum ClaudeAdminAPISettingsReader {
    static let adminAPIKeyEnvironmentKey = "ANTHROPIC_ADMIN_KEY"
    static let alternateAdminAPIKeyEnvironmentKey = "ANTHROPIC_ADMIN_API_KEY"
    static let apiKeyEnvironmentKeys = [adminAPIKeyEnvironmentKey, alternateAdminAPIKeyEnvironmentKey]

    /// Resolves the Admin key from the environment. The Settings UI (Keychain)
    /// is layered on top by the orchestrator; env is the zero-config fallback.
    static func apiKey(environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        for key in apiKeyEnvironmentKeys {
            if let token = cleaned(environment[key]) { return token }
        }
        return nil
    }

    static func cleaned(_ raw: String?) -> String? {
        guard var value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
            (value.hasPrefix("'") && value.hasSuffix("'")) {
            value = String(value.dropFirst().dropLast())
        }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}

// MARK: - Snapshot

struct ClaudeAdminAPIUsageSnapshot: Codable, Equatable, Sendable {
    struct DailyBucket: Codable, Equatable, Sendable, Identifiable {
        let day: String
        let startTime: Date
        let endTime: Date
        let costUSD: Double
        let inputTokens: Int
        let cacheCreationInputTokens: Int
        let cacheReadInputTokens: Int
        let outputTokens: Int
        let totalTokens: Int
        let costItems: [CostBreakdown]
        let models: [ModelBreakdown]
        var id: String { day }
    }

    struct CostBreakdown: Codable, Equatable, Sendable, Identifiable {
        let name: String
        let costUSD: Double
        var id: String { name }
    }

    struct ModelBreakdown: Codable, Equatable, Sendable, Identifiable {
        let name: String
        let inputTokens: Int
        let cacheCreationInputTokens: Int
        let cacheReadInputTokens: Int
        let outputTokens: Int
        let totalTokens: Int
        var id: String { name }
    }

    struct Summary: Equatable, Sendable {
        let costUSD: Double
        let inputTokens: Int
        let cacheCreationInputTokens: Int
        let cacheReadInputTokens: Int
        let outputTokens: Int
        let totalTokens: Int
    }

    let daily: [DailyBucket]
    let updatedAt: Date

    init(daily: [DailyBucket], updatedAt: Date) {
        self.daily = daily.sorted { $0.startTime < $1.startTime }
        self.updatedAt = updatedAt
    }

    var last30Days: Summary { summary(days: 30) }
    var last7Days: Summary { summary(days: 7) }
    var latestDay: Summary { summary(days: 1) }

    func summary(days: Int) -> Summary {
        let selected = daily.suffix(max(1, days))
        return Summary(
            costUSD: selected.reduce(0) { $0 + $1.costUSD },
            inputTokens: selected.reduce(0) { $0 + $1.inputTokens },
            cacheCreationInputTokens: selected.reduce(0) { $0 + $1.cacheCreationInputTokens },
            cacheReadInputTokens: selected.reduce(0) { $0 + $1.cacheReadInputTokens },
            outputTokens: selected.reduce(0) { $0 + $1.outputTokens },
            totalTokens: selected.reduce(0) { $0 + $1.totalTokens })
    }

    var topModels: [ModelBreakdown] {
        var totals: [String: ModelAccumulator] = [:]
        for day in daily {
            for model in day.models { totals[model.name, default: ModelAccumulator()].add(model) }
        }
        return totals.map { name, total in total.makeModel(name: name) }
            .sorted { $0.totalTokens == $1.totalTokens ? $0.name < $1.name : $0.totalTokens > $1.totalTokens }
    }

    var topCostItems: [CostBreakdown] {
        var totals: [String: Double] = [:]
        for day in daily {
            for item in day.costItems { totals[item.name, default: 0] += item.costUSD }
        }
        return totals.map { CostBreakdown(name: $0.key, costUSD: $0.value) }
            .sorted { $0.costUSD == $1.costUSD ? $0.name < $1.name : $0.costUSD > $1.costUSD }
    }

    /// 30-day org spend as a native cost snapshot (limit unknown via Admin API).
    var last30ProviderCost: ProviderCostSnapshot {
        ProviderCostSnapshot(
            used: last30Days.costUSD,
            limit: 0,
            currencyCode: "USD",
            period: "Last 30 days",
            updatedAt: updatedAt)
    }

    private struct ModelAccumulator {
        var inputTokens = 0
        var cacheCreationInputTokens = 0
        var cacheReadInputTokens = 0
        var outputTokens = 0
        var totalTokens = 0

        mutating func add(_ model: ModelBreakdown) {
            inputTokens += model.inputTokens
            cacheCreationInputTokens += model.cacheCreationInputTokens
            cacheReadInputTokens += model.cacheReadInputTokens
            outputTokens += model.outputTokens
            totalTokens += model.totalTokens
        }

        func makeModel(name: String) -> ModelBreakdown {
            ModelBreakdown(
                name: name,
                inputTokens: inputTokens,
                cacheCreationInputTokens: cacheCreationInputTokens,
                cacheReadInputTokens: cacheReadInputTokens,
                outputTokens: outputTokens,
                totalTokens: totalTokens)
        }
    }
}

// MARK: - Errors

enum ClaudeAdminAPIUsageError: LocalizedError, Sendable, Equatable {
    case missingCredentials
    case networkError(String)
    case apiError(endpoint: String, statusCode: Int)
    case parseFailed(endpoint: String, message: String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials: "Cần Anthropic Admin API key cho nguồn Claude API."
        case let .networkError(message): "Claude API usage network error: \(message)"
        case let .apiError(endpoint, statusCode): "Claude API usage \(endpoint) lỗi: HTTP \(statusCode)"
        case let .parseFailed(endpoint, message): "Không phân tích được Claude API usage \(endpoint): \(message)"
        }
    }
}

// MARK: - Fetcher

enum ClaudeAdminAPIUsageFetcher {
    static let costReportURL = URL(string: "https://api.anthropic.com/v1/organizations/cost_report")!
    static let messagesUsageURL = URL(string: "https://api.anthropic.com/v1/organizations/usage_report/messages")!

    private static let anthropicVersion = "2023-06-01"
    private static let timeoutSeconds: TimeInterval = 20
    private static let maxDailyBuckets = 31

    static func fetchUsage(
        apiKey: String,
        costURL: URL = costReportURL,
        messagesURL: URL = messagesUsageURL,
        session: URLSession = .shared,
        now: Date = Date()) async throws -> ClaudeAdminAPIUsageSnapshot {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ClaudeAdminAPIUsageError.missingCredentials }

        let calendar = utcCalendar
        let range = dailyRange(now: now, calendar: calendar)
        let costsData = try await fetchData(
            url: url(baseURL: costURL, range: range,
                     queryItems: [URLQueryItem(name: "group_by[]", value: "description")]),
            apiKey: trimmed, endpoint: "cost_report", session: session)
        let messagesData = try await fetchData(
            url: url(baseURL: messagesURL, range: range,
                     queryItems: [URLQueryItem(name: "group_by[]", value: "model")]),
            apiKey: trimmed, endpoint: "messages", session: session)

        let costs = try decodeCosts(costsData)
        let messages = try decodeMessages(messagesData)
        return makeSnapshot(costs: costs, messages: messages, now: now, calendar: calendar)
    }

    /// Builds a snapshot straight from canned JSON — used by unit tests.
    static func parseSnapshotForTesting(
        costs: Data, messages: Data, now: Date,
        calendar: Calendar = utcCalendar) throws -> ClaudeAdminAPIUsageSnapshot {
        makeSnapshot(costs: try decodeCosts(costs), messages: try decodeMessages(messages),
                     now: now, calendar: calendar)
    }

    private static func fetchData(url: URL, apiKey: String, endpoint: String,
                                  session: URLSession) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeoutSeconds
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("BirdNion/1.0", forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ClaudeAdminAPIUsageError.networkError(error.localizedDescription)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw ClaudeAdminAPIUsageError.apiError(endpoint: endpoint, statusCode: code) }
        return data
    }

    private static func decodeCosts(_ data: Data) throws -> CostReportResponse {
        do { return try JSONDecoder().decode(CostReportResponse.self, from: data) }
        catch { throw ClaudeAdminAPIUsageError.parseFailed(endpoint: "cost_report", message: error.localizedDescription) }
    }

    private static func decodeMessages(_ data: Data) throws -> MessagesUsageResponse {
        do { return try JSONDecoder().decode(MessagesUsageResponse.self, from: data) }
        catch { throw ClaudeAdminAPIUsageError.parseFailed(endpoint: "messages", message: error.localizedDescription) }
    }

    private static func makeSnapshot(costs: CostReportResponse, messages: MessagesUsageResponse,
                                     now: Date, calendar: Calendar) -> ClaudeAdminAPIUsageSnapshot {
        var accumulators: [String: DailyAccumulator] = [:]

        for bucket in costs.data {
            var acc = accumulators[bucket.startingAt]
                ?? DailyAccumulator(startingAt: bucket.startingAt, endingAt: bucket.endingAt)
            for result in bucket.results {
                let value = (Double(result.amount) ?? 0) / 100
                acc.costUSD += value
                let item = displayName(result.description ?? result.costType, fallback: "Claude API")
                acc.costItems[item, default: 0] += value
            }
            accumulators[bucket.startingAt] = acc
        }

        for bucket in messages.data {
            var acc = accumulators[bucket.startingAt]
                ?? DailyAccumulator(startingAt: bucket.startingAt, endingAt: bucket.endingAt)
            for result in bucket.results {
                let input = result.uncachedInputTokens ?? 0
                let cacheCreation = result.cacheCreation?.totalInputTokens ?? 0
                let cacheRead = result.cacheReadInputTokens ?? 0
                let output = result.outputTokens ?? 0
                let total = input + cacheCreation + cacheRead + output
                acc.inputTokens += input
                acc.cacheCreationInputTokens += cacheCreation
                acc.cacheReadInputTokens += cacheRead
                acc.outputTokens += output
                acc.totalTokens += total
                let modelName = displayName(result.model, fallback: "Claude API")
                acc.models[modelName, default: ModelAccumulator()].add(
                    input: input, cacheCreation: cacheCreation, cacheRead: cacheRead,
                    output: output, total: total)
            }
            accumulators[bucket.startingAt] = acc
        }

        let daily = accumulators.values
            .compactMap { $0.makeBucket(calendar: calendar) }
            .filter { $0.startTime <= now }
            .sorted { $0.startTime < $1.startTime }
        return ClaudeAdminAPIUsageSnapshot(daily: daily, updatedAt: now)
    }

    private static func displayName(_ raw: String?, fallback: String) -> String {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty
        else { return fallback }
        return trimmed
    }

    private static func url(baseURL: URL, range: DateRange, queryItems extraItems: [URLQueryItem]) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "starting_at", value: rfc3339String(from: range.start)),
            URLQueryItem(name: "ending_at", value: rfc3339String(from: range.end)),
            URLQueryItem(name: "bucket_width", value: "1d"),
            URLQueryItem(name: "limit", value: String(maxDailyBuckets)),
        ] + extraItems
        return components.url!
    }

    private static func dailyRange(now: Date, calendar: Calendar) -> DateRange {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(maxDailyBuckets - 1), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        return DateRange(start: start, end: end)
    }

    static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private static func rfc3339Formatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func rfc3339String(from date: Date) -> String { rfc3339Formatter().string(from: date) }

    fileprivate static func dayKey(from date: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    fileprivate static func parseDate(_ raw: String) -> Date? { rfc3339Formatter().date(from: raw) }
}

// MARK: - Wire response models

private struct DateRange { let start: Date; let end: Date }

private struct DailyAccumulator {
    let startingAt: String
    let endingAt: String
    var costUSD: Double = 0
    var inputTokens = 0
    var cacheCreationInputTokens = 0
    var cacheReadInputTokens = 0
    var outputTokens = 0
    var totalTokens = 0
    var costItems: [String: Double] = [:]
    var models: [String: ModelAccumulator] = [:]

    func makeBucket(calendar: Calendar) -> ClaudeAdminAPIUsageSnapshot.DailyBucket? {
        guard let start = ClaudeAdminAPIUsageFetcher.parseDate(startingAt),
              let end = ClaudeAdminAPIUsageFetcher.parseDate(endingAt) else { return nil }
        return ClaudeAdminAPIUsageSnapshot.DailyBucket(
            day: ClaudeAdminAPIUsageFetcher.dayKey(from: start, calendar: calendar),
            startTime: start, endTime: end,
            costUSD: costUSD,
            inputTokens: inputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens,
            cacheReadInputTokens: cacheReadInputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            costItems: costItems
                .map { ClaudeAdminAPIUsageSnapshot.CostBreakdown(name: $0.key, costUSD: $0.value) }
                .sorted { $0.costUSD == $1.costUSD ? $0.name < $1.name : $0.costUSD > $1.costUSD },
            models: models.map { name, total in total.makeModel(name: name) }
                .sorted { $0.totalTokens == $1.totalTokens ? $0.name < $1.name : $0.totalTokens > $1.totalTokens })
    }
}

private struct ModelAccumulator {
    var inputTokens = 0
    var cacheCreationInputTokens = 0
    var cacheReadInputTokens = 0
    var outputTokens = 0
    var totalTokens = 0

    mutating func add(input: Int, cacheCreation: Int, cacheRead: Int, output: Int, total: Int) {
        inputTokens += input
        cacheCreationInputTokens += cacheCreation
        cacheReadInputTokens += cacheRead
        outputTokens += output
        totalTokens += total
    }

    func makeModel(name: String) -> ClaudeAdminAPIUsageSnapshot.ModelBreakdown {
        ClaudeAdminAPIUsageSnapshot.ModelBreakdown(
            name: name,
            inputTokens: inputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens,
            cacheReadInputTokens: cacheReadInputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens)
    }
}

private struct CostReportResponse: Decodable {
    let data: [CostBucket]
}

private struct CostBucket: Decodable {
    let startingAt: String
    let endingAt: String
    let results: [CostResult]

    private enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

private struct CostResult: Decodable {
    let amount: String
    let description: String?
    let costType: String?

    private enum CodingKeys: String, CodingKey {
        case amount
        case description
        case costType = "cost_type"
    }
}

private struct MessagesUsageResponse: Decodable {
    let data: [MessagesBucket]
}

private struct MessagesBucket: Decodable {
    let startingAt: String
    let endingAt: String
    let results: [MessagesResult]

    private enum CodingKeys: String, CodingKey {
        case startingAt = "starting_at"
        case endingAt = "ending_at"
        case results
    }
}

private struct MessagesResult: Decodable {
    let uncachedInputTokens: Int?
    let cacheCreation: CacheCreation?
    let cacheReadInputTokens: Int?
    let outputTokens: Int?
    let model: String?

    private enum CodingKeys: String, CodingKey {
        case uncachedInputTokens = "uncached_input_tokens"
        case cacheCreation = "cache_creation"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens = "output_tokens"
        case model
    }
}

private struct CacheCreation: Decodable {
    let ephemeral1HInputTokens: Int?
    let ephemeral5MInputTokens: Int?

    var totalInputTokens: Int { (ephemeral1HInputTokens ?? 0) + (ephemeral5MInputTokens ?? 0) }

    private enum CodingKeys: String, CodingKey {
        case ephemeral1HInputTokens = "ephemeral_1h_input_tokens"
        case ephemeral5MInputTokens = "ephemeral_5m_input_tokens"
    }
}
