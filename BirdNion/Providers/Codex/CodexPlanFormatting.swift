import Foundation

/// Formats Codex `plan_type` raw values into display strings.
///
/// CodexBar maintains a richer enum + formatter. BirdNion only needs a tiny
/// mapping for the values we see in the wild today:
/// - `"pro"`       → "Pro 20x"   (matches CodexBar's exact-name table)
/// - `"prolite"` / `"pro_lite"` / `"pro-lite"` / `"pro lite"` → "Pro 5x"
/// - everything else: clean `plan_name` (snake-case / kebab-case → "Title Case")
///
/// Keeping this isolated (no other provider types) makes it trivial to grow
/// later by copying `CodexPlanFormatting.swift` from CodexBar.
enum CodexPlanFormatting {
    private static let exactDisplayNames: [String: String] = [
        "pro": "Pro 20x",
        "prolite": "Pro 5x",
        "pro_lite": "Pro 5x",
        "pro-lite": "Pro 5x",
        "pro lite": "Pro 5x",
    ]

    /// Special tokens that stay uppercase when title-cased
    /// (mirrors CodexBar's `uppercaseWords`).
    private static let uppercaseWords: Set<String> = ["cbp", "k12"]

    /// Returns the display name for a raw `plan_type`, or nil if the input is
    /// empty / whitespace. Unknown values fall back to a cleaned title-cased
    /// version of the raw string.
    static func displayName(_ raw: String?) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty
        else { return nil }

        let lower = raw.lowercased()
        if let exact = exactDisplayNames[lower] { return exact }

        let candidate = cleanSnakeOrKebab(raw)
        if candidate.isEmpty { return raw }
        if let exact = exactDisplayNames[candidate.lowercased()] { return exact }

        let components = candidate
            .split(whereSeparator: { $0 == "_" || $0 == "-" || $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !components.isEmpty else { return candidate }

        let formatted = components.map(wordDisplayName).joined(separator: " ")
        return formatted.isEmpty ? candidate : formatted
    }

    /// Strip surrounding whitespace and collapse internal whitespace runs.
    private static func cleanSnakeOrKebab(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// "gpt" → "GPT", "k12" → "K12", "pro" → "Pro".
    private static func wordDisplayName(_ raw: String) -> String {
        let lower = raw.lowercased()
        if uppercaseWords.contains(lower) { return lower.uppercased() }
        guard let first = lower.first else { return raw }
        return first.uppercased() + lower.dropFirst()
    }
}
