import Foundation

/// Codex (OpenAI/ChatGPT) usage quota provider.
///
/// Unlike MiniMax/Hapo this is **zero-config**: the OAuth token lives in
/// `~/.codex/auth.json` (written by `codex login`), not in our Keychain. We read
/// it, fetch usage from the ChatGPT backend API, and map the primary/secondary
/// rate-limit windows onto our `QuotaWindow` model.
///
/// Token handling mirrors CodexBar: refresh proactively when stale (>8 days)
/// and write the rotated token back to auth.json. Because we have no Codex CLI
/// fallback, we additionally retry once with a fresh token on a 401.
final class CodexProvider: QuotaProvider {
    let id = "codex"
    let displayName = "Codex"

    private let session: URLSession
    /// Explicit auth file (tests). When nil, resolved per fetch from the active
    /// account so switching accounts takes effect without rebuilding the provider.
    private let authURLOverride: URL?
    private var authURL: URL { authURLOverride ?? CodexAccountStore.activeAuthURL() }
    /// Best-effort side data, injectable so tests stay pure (no network/process).
    /// The status probe deliberately uses its own session (a public endpoint,
    /// unrelated to the authenticated usage session).
    private let statusProbe: () async -> OpenAIServiceStatus?
    private let versionProbe: () async -> String?
    /// CLI `/status` probe used as a fallback when the OAuth usage call fails
    /// (token expired, server error). Injected so tests stay pure.
    private let cliStatusProbe: () async -> CodexStatusSnapshot?

    init(session: URLSession = .shared,
         authURL: URL? = nil,
         statusProbe: @escaping () async -> OpenAIServiceStatus? = { await OpenAIStatusProbe.fetch() },
         versionProbe: @escaping () async -> String? = { await CodexCLI.shared.version() },
         cliStatusProbe: @escaping () async -> CodexStatusSnapshot? = {
             try? await CodexStatusProbe.fetch()
         }) {
        self.session = session
        self.authURLOverride = authURL
        self.statusProbe = statusProbe
        self.versionProbe = versionProbe
        self.cliStatusProbe = cliStatusProbe
    }

    func fetch() async throws -> ProviderStatus {
        var credentials: CodexCredentials
        do {
            credentials = try CodexAuthStore.load(url: authURL)
        } catch CodexAuthError.notFound, CodexAuthError.missingTokens {
            return failure("Chưa đăng nhập Codex — chạy `codex` để đăng nhập")
        } catch {
            return failure("Không đọc được auth.json")
        }

        // Proactive refresh (like CodexBar): rotate a stale token before it 401s.
        if credentials.needsRefresh, !credentials.refreshToken.isEmpty,
           let refreshed = try? await CodexTokenRefresher.refresh(credentials, session: session)
        {
            credentials = refreshed
            try? CodexAuthStore.save(refreshed, url: authURL)
        }

        do {
            let usage = try await CodexUsageAPI.fetchUsage(
                accessToken: credentials.accessToken,
                accountId: credentials.accountId,
                session: session)
            return await success(usage, credentials: credentials)
        } catch CodexUsageError.unauthorized {
            // Reactive refresh + single retry. If still unauthorized, try the
            // CLI `/status` probe (CodexBar's "auto" fallback chain) before
            // giving up.
            if !credentials.refreshToken.isEmpty,
               let refreshed = try? await CodexTokenRefresher.refresh(credentials, session: session)
            {
                try? CodexAuthStore.save(refreshed, url: authURL)
                if let usage = try? await CodexUsageAPI.fetchUsage(
                    accessToken: refreshed.accessToken,
                    accountId: refreshed.accountId,
                    session: session)
                {
                    return await success(usage, credentials: refreshed)
                }
            }
            if let snap = await cliStatusProbe(), let status = await cliStatusSuccess(snap, credentials: credentials) {
                return status
            }
            return failure("Token Codex hết hạn — chạy `codex` để đăng nhập lại")
        } catch CodexUsageError.serverError(let code) {
            // Server down/5xx — try the CLI probe so the user still sees
            // something rather than a hard failure.
            if let snap = await cliStatusProbe(), let status = await cliStatusSuccess(snap, credentials: credentials) {
                return status
            }
            return failure("HTTP \(code)")
        } catch CodexUsageError.invalidResponse {
            return failure("Response không hợp lệ")
        } catch {
            return failure("Network: \(error.localizedDescription)")
        }
    }

    /// Map a parsed `CodexStatusSnapshot` to a `ProviderStatus` (CLI fallback).
    /// Returns nil when the snapshot has no usable window data.
    private func cliStatusSuccess(_ snap: CodexStatusSnapshot,
                                  credentials: CodexCredentials) async -> ProviderStatus? {
        var windows: [QuotaWindow] = []
        if let five = snap.fiveHourPercentLeft {
            windows.append(QuotaWindow(label: "5 giờ",
                                       usedPct: 100 - five,
                                       remainingPct: five,
                                       resetDate: snap.fiveHourResetsAt,
                                       windowSeconds: 5 * 3600))
        }
        if let week = snap.weeklyPercentLeft {
            windows.append(QuotaWindow(label: "Tuần",
                                       usedPct: 100 - week,
                                       remainingPct: week,
                                       resetDate: snap.weeklyResetsAt,
                                       windowSeconds: 7 * 24 * 3600))
        }
        guard !windows.isEmpty else { return nil }
        async let versionTask = versionProbe()
        let service: OpenAIServiceStatus? = Self.statusChecksEnabled ? await statusProbe() : nil
        let version = await versionTask
        return ProviderStatus(
            id: id,
            displayName: displayName,
            windows: windows,
            lastUpdated: Date(),
            error: nil,
            accountLabel: accountLabel(credentials),
            planType: nil,
            creditsRemaining: snap.credits,
            version: version,
            serviceStatus: service?.description,
            serviceStatusLevel: service?.indicator,
            accountID: credentials.accountId)
    }

    // MARK: - Mapping

    /// Pure mapping (unit-testable): primary window → session (~5h), secondary → weekly,
    /// plus any model-specific `additional_rate_limits` (GPT-5.3-Codex-Spark etc.).
    /// Applies `CodexRateWindowNormalizer` so the API's slot-swap quirk doesn't
    /// reorder our popover, and adds a data-confidence flag if any window
    /// failed to decode.
    static func map(_ usage: CodexUsageResponse) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        let normalized = CodexRateWindowNormalizer.normalize(
            primary: usage.rateLimit?.primaryWindow,
            secondary: usage.rateLimit?.secondaryWindow)
        if let session = normalized.session {
            windows.append(window(session, label: "5 giờ"))
        }
        if let weekly = normalized.weekly {
            windows.append(window(weekly, label: "Tuần"))
        }
        // Model-specific (Spark 5h, Spark Weekly, …). Mapped last so primary
        // and weekly always show first in the popover.
        windows.append(contentsOf: additionalWindows(from: usage.additionalRateLimits))
        return windows
    }

    /// Maps the `additional_rate_limits` array onto named `QuotaWindow`s.
    /// Two cases are handled (1:1 with CodexBar's `CodexAdditionalRateLimitMapper`):
    /// 1. **Spark** entries: surfaces BOTH primary (5h) and secondary (weekly)
    ///    if present, labeled "Codex Spark 5-hour" / "Codex Spark Weekly".
    /// 2. **Other model-specific entries**: surfaces a single window using the
    ///    primary window if present, else secondary. Labeled from
    ///    `limit_name` / `metered_feature` with title-case cleanup.
    static func additionalWindows(
        from entries: [CodexUsageResponse.AdditionalRateLimit]?
    ) -> [QuotaWindow] {
        guard let entries, !entries.isEmpty else { return [] }
        var usedLabels = Set<String>()
        var out: [QuotaWindow] = []
        for entry in entries {
            if isSparkEntry(entry) {
                if let primary = entry.rateLimit?.primaryWindow,
                   usedLabels.insert(sparkPrimaryLabel).inserted
                {
                    out.append(window(primary, label: sparkPrimaryLabel))
                }
                if let secondary = entry.rateLimit?.secondaryWindow,
                   usedLabels.insert(sparkWeeklyLabel).inserted
                {
                    out.append(window(secondary, label: sparkWeeklyLabel))
                }
                continue
            }
            // Generic model-specific limit: prefer primary, fall back to secondary.
            let snap = entry.rateLimit?.primaryWindow ?? entry.rateLimit?.secondaryWindow
            guard let snap else { continue }
            let label = genericLabel(for: entry)
            guard usedLabels.insert(label).inserted else { continue }
            out.append(window(snap, label: label))
        }
        return out
    }

    private static let sparkPrimaryLabel = "Codex Spark 5 giờ"
    private static let sparkWeeklyLabel = "Codex Spark Tuần"

    /// Heuristic: a Spark entry is identified by `metered_feature` or `limit_name`
    /// containing "spark" (case-insensitive). Mirrors CodexBar's `isSpark`.
    private static func isSparkEntry(_ e: CodexUsageResponse.AdditionalRateLimit) -> Bool {
        let m = e.meteredFeature?.lowercased() ?? ""
        let n = e.limitName?.lowercased() ?? ""
        return m.contains("spark") || n.contains("spark")
    }

    /// Build a display label for a non-Spark additional limit. Falls back to
    /// `metered_feature` or `limit_name`, title-cased.
    private static func genericLabel(for e: CodexUsageResponse.AdditionalRateLimit) -> String {
        let raw = e.meteredFeature ?? e.limitName ?? "Codex"
        return CodexPlanFormatting.displayName(raw) ?? raw
    }

    private static func window(_ w: CodexUsageResponse.Window, label: String) -> QuotaWindow {
        return QuotaWindow(
            label: label,
            usedPct: w.usedPercent,
            remainingPct: 100 - w.usedPercent,
            resetDate: Date(timeIntervalSince1970: TimeInterval(w.resetAt)),
            windowSeconds: w.limitWindowSeconds)
    }

    private func success(_ usage: CodexUsageResponse, credentials: CodexCredentials) async -> ProviderStatus {
        let windows = Self.map(usage)
        guard !windows.isEmpty else {
            return failure("Codex chưa có dữ liệu quota")
        }
        // Best-effort side data — never fail the status if these don't resolve.
        // Run probes concurrently: status page, codex CLI version, and the
        // manual-reset credits endpoint.
        async let versionTask = versionProbe()
        async let resetTask = Self.fetchResetCredits(
            accessToken: credentials.accessToken,
            accountId: credentials.accountId,
            session: session)
        let service: OpenAIServiceStatus? = Self.statusChecksEnabled ? await statusProbe() : nil
        let version = await versionTask
        let reset = await resetTask

        return ProviderStatus(
            id: id,
            displayName: displayName,
            windows: windows,
            lastUpdated: Date(),
            error: nil,
            accountLabel: accountLabel(credentials),
            planType: CodexPlanFormatting.displayName(usage.planType),
            creditsRemaining: usage.credits?.balance,
            version: version,
            serviceStatus: service?.description,
            serviceStatusLevel: service?.indicator,
            accountID: credentials.accountId,
            resetCreditsAvailable: reset)
    }

    /// Thin wrapper so the async-let call site stays tidy. Never throws —
    /// the reset-credits count is best-effort, like `statusProbe`/`versionProbe`.
    private static func fetchResetCredits(
        accessToken: String,
        accountId: String?,
        session: URLSession) async -> Int?
    {
        do {
            let snap = try await CodexResetCreditsAPI.fetch(
                accessToken: accessToken, accountId: accountId, session: session)
            return snap.availableCount
        } catch {
            return nil
        }
    }

    /// Reads the same `statusChecksEnabled` preference that SettingsStore binds.
    /// UserDefaults has no entry until the user toggles it, so an absent key
    /// means the default (on).
    private static var statusChecksEnabled: Bool {
        (UserDefaults.standard.object(forKey: "statusChecksEnabled") as? Bool) ?? true
    }

    private func failure(_ message: String) -> ProviderStatus {
        ProviderStatus(id: id, displayName: displayName, windows: [], lastUpdated: Date(), error: message)
    }

    /// User override (providers.json) wins; otherwise the account email from the
    /// id_token; otherwise a static fallback.
    private func accountLabel(_ credentials: CodexCredentials) -> String {
        if let override = BirdNionConfigStore.accountLabel(provider: id),
           !override.isEmpty
        {
            return override
        }
        return CodexAuthStore.emailFromIDToken(credentials.idToken) ?? "Codex"
    }
}

// MARK: - OpenAI service status (status.openai.com)

/// One reading from OpenAI's public Statuspage feed.
struct OpenAIServiceStatus: Equatable {
    /// "none" | "minor" | "major" | "critical" — drives the status dot color.
    let indicator: String
    /// Human description, e.g. "All Systems Operational".
    let description: String
}

/// Fetches the OpenAI status summary. Public endpoint, no auth. Best-effort:
/// any failure returns nil so it never blocks the usage status.
enum OpenAIStatusProbe {
    static let url = URL(string: "https://status.openai.com/api/v2/status.json")!

    static func fetch(session: URLSession = .shared) async -> OpenAIServiceStatus? {
        var req = URLRequest(url: url)
        req.timeoutInterval = 10
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await session.data(for: req),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let decoded = try? JSONDecoder().decode(Payload.self, from: data)
        else { return nil }
        return OpenAIServiceStatus(indicator: decoded.status.indicator,
                                   description: decoded.status.description)
    }

    private struct Payload: Decodable {
        struct Status: Decodable { let indicator: String; let description: String }
        let status: Status
    }
}

// MARK: - codex-cli version probe

/// Resolves the installed `codex` CLI version once per launch. Shells out to
/// `codex --version` on a background thread and caches the result (the version
/// won't change while the app runs). Returns nil if the CLI isn't installed.
actor CodexCLI {
    static let shared = CodexCLI()

    /// Outer optional = "have we probed yet?"; inner = the version (nil if none).
    private var cached: String??

    func version() async -> String? {
        if let cached { return cached }
        let value = await Task.detached(priority: .utility) { Self.probe() }.value
        cached = .some(value)
        return value
    }

    private static func probe() -> String? {
        let fm = FileManager.default
        let candidates = [
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            NSHomeDirectory() + "/.codex/bin/codex",
            "/usr/bin/codex",
        ]
        guard let path = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) else {
            return nil
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let out = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let out, !out.isEmpty else { return nil }
        // Normalize to "codex-cli <version>" for display (raw output may be just
        // the version number, or already prefixed).
        return out.lowercased().contains("codex") ? out : "codex-cli \(out)"
    }
}

// MARK: - Menu bar metric

/// Which Codex window drives the percentage shown in the menu bar.
enum CodexMenuBarMetric: String, CaseIterable, Identifiable {
    case automatic   // every window (current behavior)
    case session     // the ~5h window only
    case weekly      // the 7-day window only

    static let defaultsKey = "codexMenuBarMetric"

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .automatic: "Tự động"
        case .session: "Phiên (5 giờ)"
        case .weekly: "Tuần"
        }
    }

    static var current: CodexMenuBarMetric {
        CodexMenuBarMetric(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .automatic
    }

    /// Filters a Codex provider's windows to those this metric surfaces.
    /// Falls back to all windows if the chosen one isn't present.
    func filter(_ windows: [QuotaWindow]) -> [QuotaWindow] {
        switch self {
        case .automatic:
            return windows
        case .session:
            let m = windows.filter { !$0.label.contains("Tuần") }
            return m.isEmpty ? windows : m
        case .weekly:
            let m = windows.filter { $0.label.contains("Tuần") }
            return m.isEmpty ? windows : m
        }
    }
}
