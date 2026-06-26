import Foundation

/// Normalizes Codex primary/secondary windows into a consistent (session, weekly) order.
///
/// CodexBar's API returns a "primary_window" (~5h, "session") and a
/// "secondary_window" (~weekly) but the API occasionally swaps them — older
/// `codex` accounts or backend reshuffles report the weekly as primary. This
/// normalizer uses the window length (in minutes) to re-sort them so the
/// popover always shows session-first.
///
/// Also clamps `used_percent` into 0...100 since some accounts emit values
/// slightly outside the range (and the CodexBar backend occasionally returns
/// 101 / -1 on boundary transitions).
///
/// 1:1 port of `CodexRateWindowNormalizer` from CodexBarCore (logic + enum
/// cases are intentionally identical so behavior matches upstream).
enum CodexRateWindowNormalizer {
    /// Returns `(sessionWindow, weeklyWindow)` regardless of which slot the
    /// API originally populated. `nil` slots stay `nil`.
    static func normalize(
        primary: CodexUsageResponse.Window?,
        secondary: CodexUsageResponse.Window?)
        -> (session: CodexUsageResponse.Window?, weekly: CodexUsageResponse.Window?)
    {
        switch (primary, secondary) {
        case let (.some(p), .some(s)):
            switch (role(for: p), role(for: s)) {
            case (.session, .weekly), (.session, .unknown), (.unknown, .weekly):
                (clamp(p), clamp(s))
            case (.weekly, .session), (.weekly, .unknown):
                (clamp(s), clamp(p))
            default:
                (clamp(p), clamp(s))
            }
        case let (.some(p), .none):
            switch role(for: p) {
            case .weekly:    (nil, clamp(p))
            case .session, .unknown: (clamp(p), nil)
            }
        case let (.none, .some(s)):
            switch role(for: s) {
            case .session, .unknown: (clamp(s), nil)
            case .weekly:    (nil, clamp(s))
            }
        case (.none, .none):
            (nil, nil)
        }
    }

    private enum WindowRole { case session, weekly, unknown }

    private static func role(for window: CodexUsageResponse.Window) -> WindowRole {
        let minutes = window.limitWindowSeconds / 60
        switch minutes {
        case 300:    return .session
        case 10080:  return .weekly
        default:     return .unknown
        }
    }

    /// Clamp `used_percent` into 0...100. The API occasionally returns values
    /// outside this range at boundary transitions (e.g. 101 right when the
    /// quota resets, or -1 transiently).
    private static func clamp(_ w: CodexUsageResponse.Window) -> CodexUsageResponse.Window {
        let used = max(0, min(100, w.usedPercent))
        return used == w.usedPercent
            ? w
            : .init(usedPercent: used, resetAt: w.resetAt, limitWindowSeconds: w.limitWindowSeconds)
    }
}
