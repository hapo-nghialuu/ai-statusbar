import Foundation

/// Where Kilo quota data is fetched from. Mirrors CodexBar's
/// `KiloUsageDataSource`. Persisted in UserDefaults under `defaultsKey`
/// (same pattern as `CodexUsageSource` / `AntigravityUsageSource`), so the
/// Settings picker and `KiloProvider` share one source of truth.
enum KiloUsageSource: String, CaseIterable, Identifiable {
    case auto   // API key first, then the local CLI session (default)
    case api    // explicit API key / KILO_API_KEY env only
    case cli    // local `~/.local/share/kilo/auth.json` session only

    static let defaultsKey = "kiloUsageSource"

    var id: String { rawValue }

    /// Current source from UserDefaults, defaulting to `.auto`.
    static var current: KiloUsageSource {
        KiloUsageSource(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .auto
    }
}
