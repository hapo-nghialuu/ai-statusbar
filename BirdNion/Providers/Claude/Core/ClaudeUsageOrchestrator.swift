import Foundation

// Native replacement for CodexBarCore's ClaudeUsageFetcher. Resolves the user's
// selected source (or the auto plan), runs the matching native fetcher, and
// maps the result into a unified ClaudeUsageSnapshot. For `.auto` it walks the
// planner's ordered steps and returns the first that succeeds. When web extras
// are enabled (cookie source != off) and the primary source lacks cost/extra
// windows, it best-effort merges the claude.ai cookie scrape — this restores
// the OAuth-mode cost overlay that was removed in the 2026-06-25 refactor.
enum ClaudeUsageOrchestrator {
    struct Result {
        let snapshot: ClaudeUsageSnapshot
        let sourceLabel: String
    }

    static func loadLatestUsage(session: URLSession = .shared,
                                allowKeychainPrompt: Bool) async throws -> Result {
        let selected = readDataSource()
        let cookieSource = readCookieSource()
        let manualCookie = readManualCookieHeader()
        let webEnabled = cookieSource != .off

        let input = ClaudeSourcePlanningInput(
            selectedDataSource: selected,
            webExtrasEnabled: webEnabled,
            hasWebSession: cookieSource == .manual ? (manualCookie != nil) : (cookieSource == .auto),
            hasCLI: ClaudeCLIResolver.isAvailable(),
            hasOAuthCredentials: true)   // OAuth is the default; the fetch reports real availability
        let plan = ClaudeSourcePlanner.resolve(input: input)

        var lastError: Error?
        for step in plan.executionSteps {
            do {
                var snapshot = try await fetch(
                    step.dataSource, session: session, cookieSource: cookieSource,
                    manualCookie: manualCookie, allowKeychainPrompt: allowKeychainPrompt)
                if webEnabled, step.dataSource != .web {
                    snapshot = await applyWebExtras(
                        to: snapshot, cookieSource: cookieSource, manualCookie: manualCookie, session: session)
                }
                return Result(snapshot: snapshot, sourceLabel: step.dataSource.sourceLabel)
            } catch {
                lastError = error
            }
        }
        throw lastError ?? ClaudeUsageError.oauthFailed("Không có nguồn Claude khả dụng")
    }

    // MARK: - Per-source fetch

    private static func fetch(_ source: ClaudeUsageDataSource,
                             session: URLSession,
                             cookieSource: ClaudeCookieSource,
                             manualCookie: String?,
                             allowKeychainPrompt: Bool) async throws -> ClaudeUsageSnapshot {
        switch source {
        case .oauth:
            return try await ClaudeOAuthUsageAPI.loadSnapshot(
                session: session, allowKeychainPrompt: allowKeychainPrompt)
        case .web:
            return try await fetchWeb(cookieSource: cookieSource, manualCookie: manualCookie, session: session)
        case .cli:
            return mapCLI(try await ClaudeCLISession.loadSnapshot())
        case .api:
            return try await fetchAdmin(session: session)
        case .auto:
            throw ClaudeUsageError.parseFailed("auto không phải nguồn cụ thể")
        }
    }

    private static func fetchWeb(cookieSource: ClaudeCookieSource,
                                manualCookie: String?,
                                session: URLSession) async throws -> ClaudeUsageSnapshot {
        let data: ClaudeWebUsageData
        if cookieSource == .manual, let header = manualCookie {
            data = try await ClaudeWebAPIFetcher.fetchUsage(cookieHeader: header, session: session)
        } else {
            data = try await ClaudeWebAPIFetcher.fetchUsage(session: session)
        }
        return mapWeb(data)
    }

    private static func fetchAdmin(session: URLSession) async throws -> ClaudeUsageSnapshot {
        guard let key = adminAPIKey() else { throw ClaudeAdminAPIUsageError.missingCredentials }
        let snap = try await ClaudeAdminAPIUsageFetcher.fetchUsage(apiKey: key, session: session)
        return ClaudeUsageSnapshot(
            primary: nil,
            secondary: nil,
            opus: nil,
            providerCost: snap.last30ProviderCost,
            updatedAt: snap.updatedAt,
            loginMethod: "Admin API",
            adminUsage: snap)
    }

    // MARK: - Web-extras merge (restores cookie cost scrape)

    /// Best-effort: pull claude.ai cookie data and fill any missing cost / extra
    /// windows on `snapshot`. Never throws — wrapped in a 5s race so a hanging
    /// Keychain cookie prompt can't stall the refresh. Returns the original
    /// snapshot unchanged on any failure.
    private static func applyWebExtras(to snapshot: ClaudeUsageSnapshot,
                                       cookieSource: ClaudeCookieSource,
                                       manualCookie: String?,
                                       session: URLSession) async -> ClaudeUsageSnapshot {
        if snapshot.providerCost != nil, !snapshot.extraRateWindows.isEmpty { return snapshot }
        let web: ClaudeWebUsageData? = await withTaskGroup(of: ClaudeWebUsageData?.self) { group in
            group.addTask {
                do {
                    if cookieSource == .manual, let header = manualCookie {
                        return try await ClaudeWebAPIFetcher.fetchUsage(cookieHeader: header, session: session)
                    }
                    return try await ClaudeWebAPIFetcher.fetchUsage(session: session)
                } catch { return nil }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
        guard let web else { return snapshot }
        let mergedExtra = snapshot.extraRateWindows.isEmpty ? web.extraRateWindows : snapshot.extraRateWindows
        return ClaudeUsageSnapshot(
            primary: snapshot.primary,
            primaryWindowKind: snapshot.primaryWindowKind,
            secondary: snapshot.secondary,
            opus: snapshot.opus,
            extraRateWindows: mergedExtra,
            providerCost: snapshot.providerCost ?? web.extraUsageCost,
            updatedAt: snapshot.updatedAt,
            accountEmail: snapshot.accountEmail ?? web.accountEmail,
            accountOrganization: snapshot.accountOrganization ?? web.accountOrganization,
            loginMethod: snapshot.loginMethod ?? web.loginMethod,
            rawText: snapshot.rawText,
            adminUsage: snapshot.adminUsage)
    }

    // MARK: - Mappers

    private static func mapWeb(_ d: ClaudeWebUsageData) -> ClaudeUsageSnapshot {
        ClaudeUsageSnapshot(
            primary: RateWindow(usedPercent: d.sessionPercentUsed, windowMinutes: 5 * 60,
                                resetsAt: d.sessionResetsAt, resetDescription: nil),
            secondary: d.weeklyPercentUsed.map {
                RateWindow(usedPercent: $0, windowMinutes: 7 * 24 * 60,
                           resetsAt: d.weeklyResetsAt, resetDescription: nil)
            },
            opus: d.opusPercentUsed.map {
                RateWindow(usedPercent: $0, windowMinutes: 7 * 24 * 60, resetsAt: nil, resetDescription: nil)
            },
            extraRateWindows: d.extraRateWindows,
            providerCost: d.extraUsageCost,
            accountEmail: d.accountEmail,
            accountOrganization: d.accountOrganization,
            loginMethod: d.loginMethod)
    }

    private static func mapCLI(_ s: ClaudeStatusSnapshot) -> ClaudeUsageSnapshot {
        func window(left: Int?, minutes: Int, reset: String?) -> RateWindow? {
            guard let left else { return nil }
            let used = Double(max(0, min(100, 100 - left)))
            return RateWindow(usedPercent: used, windowMinutes: minutes,
                              resetsAt: ClaudeStatusProbe.parseResetDate(from: reset), resetDescription: reset)
        }
        let primary = window(left: s.sessionPercentLeft, minutes: 5 * 60, reset: s.primaryResetDescription)
            ?? RateWindow(usedPercent: 0, windowMinutes: 5 * 60, resetsAt: nil, resetDescription: nil)
        return ClaudeUsageSnapshot(
            primary: primary,
            secondary: window(left: s.weeklyPercentLeft, minutes: 7 * 24 * 60, reset: s.secondaryResetDescription),
            opus: window(left: s.opusPercentLeft, minutes: 7 * 24 * 60, reset: s.opusResetDescription),
            accountEmail: s.accountEmail,
            accountOrganization: s.accountOrganization,
            loginMethod: s.loginMethod,
            rawText: s.rawText)
    }

    // MARK: - Settings + credentials

    private static func readDataSource() -> ClaudeUsageDataSource {
        let raw = UserDefaults.standard.string(forKey: "claudeUsageDataSource") ?? ClaudeUsageDataSource.oauth.rawValue
        return ClaudeUsageDataSource(rawValue: raw) ?? .oauth
    }

    private static func readCookieSource() -> ClaudeCookieSource {
        let raw = UserDefaults.standard.string(forKey: "claudeCookieSource") ?? ClaudeCookieSource.auto.rawValue
        return ClaudeCookieSource(rawValue: raw) ?? .auto
    }

    private static func readManualCookieHeader() -> String? {
        let raw = UserDefaults.standard.string(forKey: "claudeManualCookieHeader")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (raw?.isEmpty ?? true) ? nil : raw
    }

    /// Admin key from the active admin account, else the environment.
    private static func adminAPIKey() -> String? {
        if let active = ClaudeTokenAccountStore.active(), active.kind == .admin {
            let token = active.token.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { return token }
        }
        return ClaudeAdminAPISettingsReader.apiKey()
    }
}
