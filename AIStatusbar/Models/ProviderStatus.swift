import Foundation

/// One quota window (e.g. "5 giờ" or "Tuần") reported by a provider.
/// Matches the `<!-- contract:QuotaWindow -->` block in `specs/ai-statusbar/design.md`.
struct QuotaWindow: Identifiable, Codable, Equatable {
    let id: UUID
    let label: String
    let usedPct: Int
    let remainingPct: Int

    init(id: UUID = UUID(), label: String, usedPct: Int, remainingPct: Int) {
        self.id = id
        self.label = label
        self.usedPct = usedPct
        self.remainingPct = remainingPct
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

    init(id: String, displayName: String, windows: [QuotaWindow], lastUpdated: Date, error: String? = nil) {
        self.id = id
        self.displayName = displayName
        self.windows = windows
        self.lastUpdated = lastUpdated
        self.error = error
    }
}
