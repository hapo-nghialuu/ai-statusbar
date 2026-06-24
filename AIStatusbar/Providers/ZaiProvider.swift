import Foundation

/// Z.ai / GLM API host region. Global is `api.z.ai`; mainland China is
/// `open.bigmodel.cn`. Persisted in UserDefaults; the picker in ProvidersPane
/// binds the same key.
enum ZaiRegion: String, CaseIterable, Identifiable {
    case global
    case cn

    static let defaultsKey = "zaiRegion"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .global: "Global (api.z.ai)"
        case .cn:     "BigModel CN (open.bigmodel.cn)"
        }
    }
    var baseHost: String {
        switch self {
        case .global: "api.z.ai"
        case .cn:     "open.bigmodel.cn"
        }
    }
    static var current: ZaiRegion {
        ZaiRegion(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "global") ?? .global
    }
}

/// Z.ai / GLM coding-plan quota provider.
///
/// Endpoint: `GET https://<host>/api/monitor/usage/quota/limit`
/// Auth: `Authorization: Bearer <key>`.
///
/// Response: `{ code, success, data: { limits: [ { type, unit, number,
/// percentage, remaining, next_reset_time } ], plan_name } }`. Each limit
/// entry maps to one `QuotaWindow` (percentage is the % already used).
final class ZaiProvider: QuotaProvider {
    let id = "zai"
    let displayName = "Z.ai / GLM"

    static func endpoint(region: ZaiRegion = .current) -> URL {
        URL(string: "https://\(region.baseHost)/api/monitor/usage/quota/limit")!
    }

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

        var req = URLRequest(url: Self.endpoint(region: .current))
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
        guard let root = try? JSONDecoder().decode(QuotaResponse.self, from: data) else {
            return failure("Response thiếu trường")
        }
        // Z.ai returns HTTP 200 even on logical errors; check the envelope.
        guard root.success, root.code == 200, let limits = root.data?.limits, !limits.isEmpty else {
            return failure(root.msg.isEmpty ? "Không có dữ liệu quota" : root.msg)
        }
        let windows: [QuotaWindow] = limits.map { e in
            let used = max(0, min(100, e.percentage))
            return QuotaWindow(
                label: Self.label(type: e.type, unit: e.unit, number: e.number),
                usedPct: used,
                remainingPct: 100 - used,
                resetDate: e.nextResetTime.map { Date(timeIntervalSince1970: TimeInterval($0) / 1000) })
        }
        return ProviderStatus(
            id: id,
            displayName: displayName,
            windows: windows,
            lastUpdated: Date(),
            error: nil,
            accountLabel: accountLabel,
            planName: root.data?.planName)
    }

    /// Human label from the raw limit type/unit/number.
    /// unit codes (z.ai): 1=days, 3=hours, 5=minutes, 6=weeks.
    static func label(type: String, unit: Int, number: Int) -> String {
        if type == "TOKENS_LIMIT" { return "Tokens" }
        switch unit {
        case 3: return "\(number) giờ"
        case 1: return "\(number) ngày"
        case 5: return "\(number) phút"
        case 6: return number == 1 ? "Tuần" : "\(number) tuần"
        default: return "Giới hạn"
        }
    }

    private func failure(_ message: String) -> ProviderStatus {
        ProviderStatus(id: id, displayName: displayName, windows: [], lastUpdated: Date(), error: message)
    }

    private struct QuotaResponse: Decodable {
        let code: Int
        let msg: String
        let success: Bool
        let data: QuotaData?

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.code = (try? c.decode(Int.self, forKey: .code)) ?? 0
            self.msg = (try? c.decode(String.self, forKey: .msg)) ?? ""
            self.success = (try? c.decode(Bool.self, forKey: .success)) ?? false
            self.data = try? c.decodeIfPresent(QuotaData.self, forKey: .data)
        }
        enum CodingKeys: String, CodingKey { case code, msg, success, data }
    }
    private struct QuotaData: Decodable {
        let limits: [LimitRaw]
        let planName: String?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.limits = (try? c.decodeIfPresent([LimitRaw].self, forKey: .limits)) ?? []
            let candidates = [
                try? c.decodeIfPresent(String.self, forKey: .planName),
                try? c.decodeIfPresent(String.self, forKey: .plan),
                try? c.decodeIfPresent(String.self, forKey: .planType),
            ].compactMap { $0 }.compactMap { $0 }
            let trimmed = candidates.first?.trimmingCharacters(in: .whitespacesAndNewlines)
            self.planName = (trimmed?.isEmpty ?? true) ? nil : trimmed
        }
        enum CodingKeys: String, CodingKey {
            case limits
            case planName = "plan_name"
            case plan
            case planType = "plan_type"
        }
    }
    private struct LimitRaw: Decodable {
        let type: String
        let unit: Int
        let number: Int
        let percentage: Int
        let nextResetTime: Int?
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.type = (try? c.decode(String.self, forKey: .type)) ?? ""
            self.unit = (try? c.decode(Int.self, forKey: .unit)) ?? 0
            self.number = (try? c.decode(Int.self, forKey: .number)) ?? 0
            self.percentage = (try? c.decode(Int.self, forKey: .percentage)) ?? 0
            self.nextResetTime = try? c.decodeIfPresent(Int.self, forKey: .nextResetTime)
        }
        enum CodingKeys: String, CodingKey {
            case type, unit, number, percentage
            case nextResetTime = "next_reset_time"
        }
    }
}
