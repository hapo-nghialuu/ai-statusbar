import Foundation

/// One quota window (e.g. "5 giờ" or "Tuần") reported by a provider.
/// Matches the `<!-- contract:QuotaWindow -->` block in `specs/ai-statusbar/design.md`.
///
/// `subtitle` and `resetDate` are optional overlays used by providers that
/// carry richer context (e.g. Hapo Hub's "$16.19 / $20.00" dollar amount and
/// ISO-8601 weekly reset timestamp). MiniMax leaves them nil and the UI
/// falls back to the plain "Còn X%" + "Resets in 5h"/"Resets weekly" text.
struct QuotaWindow: Identifiable, Codable, Equatable {
    let id: UUID
    let label: String
    let usedPct: Int
    let remainingPct: Int
    let subtitle: String?
    let resetDate: Date?

    init(id: UUID = UUID(),
         label: String,
         usedPct: Int,
         remainingPct: Int,
         subtitle: String? = nil,
         resetDate: Date? = nil) {
        self.id = id
        self.label = label
        self.usedPct = usedPct
        self.remainingPct = remainingPct
        self.subtitle = subtitle
        self.resetDate = resetDate
    }
}

/// Snapshot of one provider's quota state at a point in time.
/// Matches the `<!-- contract:ProviderStatus -->` block in `specs/ai-statusbar/design.md`.
///
/// Invariant: if `error != nil`, then `windows.isEmpty` MUST be true.
///            if `windows` is non-empty, `error` MUST be nil.
struct ProviderStatus: Identifiable, Codable, Equatable {
    let id: String
    let displayName: String
    let windows: [QuotaWindow]
    let lastUpdated: Date
    let error: String?
    /// User-facing identifier for this account. Strategy:
    /// 1. If user explicitly set one in Settings (ProviderConfig.accountLabel),
    ///    use that.
    /// 2. Otherwise derive from the keychain token's first 8 chars
    ///    (e.g. "sk-cp-dEwaSdME") so the chip has *something* identifying.
    /// nil only if no token is configured.
    let accountLabel: String?

    // MARK: - Optional provider detail overlays
    //
    // Enrichments surfaced in the providers detail panel. Codex populates them;
    // other providers leave them nil. All optional + defaulted so old cached
    // snapshots (without these keys) still decode.

    /// Subscription plan, e.g. "plus" / "pro" (Codex `plan_type`).
    let planType: String?
    /// Remaining credit balance (Codex `credits.balance`). nil when absent.
    let creditsRemaining: Double?
    /// Detected CLI version string, e.g. "codex-cli 0.140.0-alpha.19".
    let version: String?
    /// Provider service-status text, e.g. "All Systems Operational".
    let serviceStatus: String?
    /// Status severity: "none" / "minor" / "major" / "critical" (drives color).
    let serviceStatusLevel: String?

    init(id: String,
         displayName: String,
         windows: [QuotaWindow],
         lastUpdated: Date,
         error: String? = nil,
         accountLabel: String? = nil,
         planType: String? = nil,
         creditsRemaining: Double? = nil,
         version: String? = nil,
         serviceStatus: String? = nil,
         serviceStatusLevel: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.windows = windows
        self.lastUpdated = lastUpdated
        self.error = error
        self.accountLabel = accountLabel
        self.planType = planType
        self.creditsRemaining = creditsRemaining
        self.version = version
        self.serviceStatus = serviceStatus
        self.serviceStatusLevel = serviceStatusLevel
    }
}
