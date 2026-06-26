import CodexBarCore
import Foundation

/// Token cost rolled up from the local Codex logs.
///
/// Token counts are exact; the dollar amount is an estimate (tokens × a model
/// price table), so it is surfaced as "≈" in the UI.
struct CodexCostSummary: Equatable {
    let todayUSD: Double
    let todayTokens: Int
    /// Totals over the configured history window (default 30 days). The field
    /// name is kept for compatibility; the window length is `historyDays`.
    let last30USD: Double
    let last30Tokens: Int

    var isEmpty: Bool { todayTokens == 0 && last30Tokens == 0 }
}

/// Rolls up Codex token cost for "today" and the configured history window.
///
/// Delegates to CodexBarCore's `CostUsageFetcher`, which scans the full set of
/// local Codex log sources (native `~/.codex/sessions` + `archived_sessions`,
/// plus supported pi sessions), uses `turn_context` model markers as the
/// authoritative model bucket, and prices each model. Scoped to the active
/// account's `CODEX_HOME`. Results are cached briefly so toggling the Settings
/// pane doesn't rescan on every open.
enum CodexCostScanner {
    private static let cacheTTL: TimeInterval = 300
    static let historyDaysKey = "codexCostHistoryDays"

    /// Rolling history window in days (1...365). Defaults to 30 when unset.
    /// `SettingsStore` writes the same key.
    static var historyDays: Int {
        let raw = UserDefaults.standard.integer(forKey: historyDaysKey)
        return raw == 0 ? 30 : max(1, min(365, raw))
    }

    /// Actor-isolated cache so the brief memoization is safe across tasks.
    private actor Cache {
        static let shared = Cache()
        private var entry: (at: Date, value: CodexCostSummary)?
        func valid(now: Date, ttl: TimeInterval) -> CodexCostSummary? {
            guard let entry, now.timeIntervalSince(entry.at) < ttl else { return nil }
            return entry.value
        }
        func store(_ value: CodexCostSummary, at: Date) { entry = (at, value) }
    }

    /// Cached, off-main scan. Returns nil only when the scan throws (e.g. no
    /// readable log sources).
    static func summary(now: Date = Date()) async -> CodexCostSummary? {
        if let cached = await Cache.shared.valid(now: now, ttl: cacheTTL) { return cached }
        let codexHome = CodexAccountStore.activeAuthURL().deletingLastPathComponent().path
        guard let snapshot = try? await CostUsageFetcher().loadTokenSnapshot(
            provider: .codex,
            now: now,
            codexHomePath: codexHome,
            historyDays: historyDays)
        else { return nil }
        let value = map(snapshot)
        await Cache.shared.store(value, at: now)
        return value
    }

    /// Pure mapping (snapshot → BirdNion model), unit-testable. "session" totals
    /// are today's; "last30Days" totals span the configured window.
    static func map(_ snapshot: CostUsageTokenSnapshot) -> CodexCostSummary {
        CodexCostSummary(
            todayUSD: snapshot.sessionCostUSD ?? 0,
            todayTokens: snapshot.sessionTokens ?? 0,
            last30USD: snapshot.last30DaysCostUSD ?? 0,
            last30Tokens: snapshot.last30DaysTokens ?? 0)
    }
}
