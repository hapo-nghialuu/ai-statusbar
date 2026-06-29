import Foundation

/// ElevenLabs (TTS) usage provider. API key (header `xi-api-key`) → the
/// subscription endpoint reports character credits used/limit + voice slots.
/// Native port of CodexBar's ElevenLabsUsageFetcher.
final class ElevenLabsProvider: QuotaProvider {
    let id = "elevenlabs"
    let displayName = "ElevenLabs"

    static let endpoint = URL(string: "https://api.elevenlabs.io/v1/user/subscription")!
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    private func override() -> String? { BirdNionConfigStore.accountLabel(provider: id) }

    func fetch() async throws -> ProviderStatus {
        // Env override first (ELEVENLABS_API_KEY), then config storage.
        let envToken = ProcessInfo.processInfo.environment["ELEVENLABS_API_KEY"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let token = (envToken?.isEmpty == false ? envToken : nil) ?? BirdNionConfigStore.apiKey(provider: id)
        guard let token, !token.isEmpty else {
            return failure("Chưa cấu hình API key ElevenLabs")
        }
        let accountLabel = override() ?? String(token.prefix(8))

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "GET"
        req.setValue(token, forHTTPHeaderField: "xi-api-key")
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
        switch http.statusCode {
        case 200..<300: return parse(data, accountLabel: accountLabel)
        case 401, 403: return failure("API key ElevenLabs không hợp lệ")
        default: return failure("HTTP \(http.statusCode)")
        }
    }

    func parse(_ data: Data, accountLabel: String?) -> ProviderStatus {
        guard let r = try? JSONDecoder().decode(Subscription.self, from: data) else {
            return failure("Response thiếu trường")
        }
        var windows: [QuotaWindow] = []
        let used = max(0, min(100, r.characterLimit > 0
                              ? Int((Double(r.characterCount) / Double(r.characterLimit) * 100).rounded()) : 0))
        windows.append(QuotaWindow(
            label: "Credits",
            usedPct: used,
            remainingPct: 100 - used,
            subtitle: "\(fmt(r.characterCount)) / \(fmt(r.characterLimit))",
            resetDate: r.nextCharacterCountResetUnix.map { Date(timeIntervalSince1970: TimeInterval($0)) },
            windowSeconds: 30 * 24 * 3600))
        if let u = r.voiceSlotsUsed, let lim = r.voiceLimit, lim > 0 {
            let p = max(0, min(100, Int((Double(u) / Double(lim) * 100).rounded())))
            windows.append(QuotaWindow(label: "Voice slots", usedPct: p, remainingPct: 100 - p,
                                       subtitle: "\(u) / \(lim)"))
        }
        if let u = r.professionalVoiceSlotsUsed, let lim = r.professionalVoiceLimit, lim > 0 {
            let p = max(0, min(100, Int((Double(u) / Double(lim) * 100).rounded())))
            windows.append(QuotaWindow(label: "Professional voices", usedPct: p, remainingPct: 100 - p,
                                       subtitle: "\(u) / \(lim)"))
        }
        let plan = displayTier(tier: r.tier, status: r.status)
        return ProviderStatus(
            id: id, displayName: displayName, windows: windows, lastUpdated: Date(),
            error: nil, accountLabel: accountLabel, planName: plan)
    }

    // Internal — exposed for unit testing without importing CodexBarCore.
    func _parseForTesting(_ data: Data, accountLabel: String?) -> ProviderStatus {
        parse(data, accountLabel: accountLabel)
    }

    /// Mirrors CodexBar's ElevenLabsUsageSnapshot.displayTier logic.
    /// Returns "Tier · status" when status != "active", otherwise just the tier name.
    private func displayTier(tier: String?, status: String?) -> String? {
        guard let tier = tier?.trimmingCharacters(in: .whitespacesAndNewlines), !tier.isEmpty else {
            return status
        }
        let statusSuffix: String
        if let s = status, !s.isEmpty, s.lowercased() != "active" {
            statusSuffix = " · \(s)"
        } else {
            statusSuffix = ""
        }
        return "\(tier.replacingOccurrences(of: "_", with: " ").capitalized)\(statusSuffix)"
    }

    private func fmt(_ n: Int) -> String {
        let f = NumberFormatter(); f.numberStyle = .decimal; f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func failure(_ message: String) -> ProviderStatus {
        ProviderStatus(id: id, displayName: displayName, windows: [], lastUpdated: Date(), error: message)
    }

    private struct Subscription: Decodable {
        let tier: String?
        let status: String?
        let characterCount: Int
        let characterLimit: Int
        let voiceSlotsUsed: Int?
        let voiceLimit: Int?
        let professionalVoiceSlotsUsed: Int?
        let professionalVoiceLimit: Int?
        let nextCharacterCountResetUnix: Int?
        enum CodingKeys: String, CodingKey {
            case tier
            case status
            case characterCount = "character_count"
            case characterLimit = "character_limit"
            case voiceSlotsUsed = "voice_slots_used"
            case voiceLimit = "voice_limit"
            case professionalVoiceSlotsUsed = "professional_voice_slots_used"
            case professionalVoiceLimit = "professional_voice_limit"
            case nextCharacterCountResetUnix = "next_character_count_reset_unix"
        }
    }
}
