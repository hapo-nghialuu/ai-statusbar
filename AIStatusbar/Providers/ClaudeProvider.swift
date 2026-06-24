import Foundation
import Security

/// Claude (Anthropic) subscription usage provider.
///
/// Auth: reads the OAuth token Claude Code stores in the macOS Keychain under
/// service `Claude Code-credentials` (JSON: `{ "claudeAiOauth": { "accessToken",
/// "expiresAt", ... } }`). Because that item belongs to the Claude Code app,
/// the first read triggers a macOS Keychain access prompt — the user must
/// click "Always Allow" once.
///
/// Endpoint: `GET https://api.anthropic.com/api/oauth/usage`
/// Headers: `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`.
/// Response: `{ "five_hour": { utilization, resets_at }, "seven_day": {...} }`
/// where `utilization` is a percent already used (0..100), mapped to the
/// 5h session + weekly windows (same shape as Codex).
final class ClaudeProvider: QuotaProvider {
    let id = "claude"
    let displayName = "Claude"

    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    static let keychainService = "Claude Code-credentials"
    static let betaHeader = "oauth-2025-04-20"

    private let session: URLSession
    /// Token reader, injectable so tests don't touch the real Keychain.
    private let tokenProvider: () -> String?

    init(session: URLSession = .shared,
         tokenProvider: @escaping () -> String? = { ClaudeProvider.readKeychainToken() }) {
        self.session = session
        self.tokenProvider = tokenProvider
    }

    private func override() -> String? {
        ProvidersStore.load().providers.first(where: { $0.id == self.id })?.accountLabel
    }

    func fetch() async throws -> ProviderStatus {
        guard let token = tokenProvider(), !token.isEmpty else {
            return failure("Chưa đăng nhập Claude — đăng nhập bằng Claude Code")
        }

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.betaHeader, forHTTPHeaderField: "anthropic-beta")
        req.setValue("claude-code/1.0.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            return failure("Network: \(error.localizedDescription)")
        }
        guard let http = response as? HTTPURLResponse else { return failure("Response không phải HTTP") }
        switch http.statusCode {
        case 200..<300:
            return parse(data, accountLabel: override())
        case 401, 403:
            return failure("Token Claude hết hạn — đăng nhập lại bằng Claude Code")
        default:
            return failure("HTTP \(http.statusCode)")
        }
    }

    func parse(_ data: Data, accountLabel: String?) -> ProviderStatus {
        guard let root = try? JSONDecoder().decode(UsageResponse.self, from: data) else {
            return failure("Response thiếu trường")
        }
        var windows: [QuotaWindow] = []
        if let five = root.fiveHour, let pct = five.utilization {
            windows.append(Self.window(label: "5 giờ", utilization: pct,
                                       resetsAt: five.resetsAt, seconds: 5 * 3600))
        }
        if let week = root.sevenDay, let pct = week.utilization {
            windows.append(Self.window(label: "Tuần", utilization: pct,
                                       resetsAt: week.resetsAt, seconds: 7 * 24 * 3600))
        }
        guard !windows.isEmpty else { return failure("Claude chưa có dữ liệu quota") }
        return ProviderStatus(
            id: id,
            displayName: displayName,
            windows: windows,
            lastUpdated: Date(),
            error: nil,
            accountLabel: accountLabel)
    }

    /// `utilization` is a percent already used (0..100).
    private static func window(label: String, utilization: Double,
                               resetsAt: String?, seconds: Int) -> QuotaWindow {
        let used = max(0, min(100, Int(utilization.rounded())))
        return QuotaWindow(
            label: label,
            usedPct: used,
            remainingPct: 100 - used,
            resetDate: parseISO8601(resetsAt),
            windowSeconds: seconds)
    }

    static func parseISO8601(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }

    private func failure(_ message: String) -> ProviderStatus {
        ProviderStatus(id: id, displayName: displayName, windows: [], lastUpdated: Date(), error: message)
    }

    // MARK: - Keychain

    /// Reads `claudeAiOauth.accessToken` from the Claude Code keychain item.
    /// Returns nil if absent or access is denied. May trigger a macOS prompt.
    static func readKeychainToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return tokenFromKeychainJSON(data)
    }

    /// Parses the keychain JSON blob → access token. Exposed for tests.
    static func tokenFromKeychainJSON(_ data: Data) -> String? {
        guard let root = try? JSONDecoder().decode(KeychainRoot.self, from: data) else { return nil }
        let token = root.claudeAiOauth?.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (token?.isEmpty ?? true) ? nil : token
    }

    // MARK: - Models

    private struct KeychainRoot: Decodable {
        let claudeAiOauth: OAuth?
        struct OAuth: Decodable { let accessToken: String? }
    }

    private struct UsageResponse: Decodable {
        let fiveHour: Window?
        let sevenDay: Window?
        enum CodingKeys: String, CodingKey {
            case fiveHour = "five_hour"
            case sevenDay = "seven_day"
        }
    }
    private struct Window: Decodable {
        let utilization: Double?
        let resetsAt: String?
        enum CodingKeys: String, CodingKey {
            case utilization
            case resetsAt = "resets_at"
        }
    }
}
