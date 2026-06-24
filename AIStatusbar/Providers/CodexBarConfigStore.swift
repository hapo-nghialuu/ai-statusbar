import Foundation

/// Reads/writes the shared CodexBar config file so provider API tokens interop
/// with CodexBar (set a token in either app and both see it).
///
/// Mirrors CodexBar's resolution and schema:
///   {"version":1,"providers":[{"id":"minimax","apiKey":"sk-…","enabled":true,"region":"global"}]}
/// Path priority: `CODEXBAR_CONFIG` → `XDG_CONFIG_HOME/codexbar/config.json` →
/// `~/.config/codexbar/config.json` → legacy `~/.codexbar/config.json`.
enum CodexBarConfigStore {
    static let pathEnvKey = "CODEXBAR_CONFIG"

    static func configURL(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                          env: [String: String] = ProcessInfo.processInfo.environment,
                          fileManager: FileManager = .default) -> URL {
        if let override = env[pathEnvKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: (override as NSString).expandingTildeInPath)
        }
        if let xdg = env["XDG_CONFIG_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !xdg.isEmpty, (xdg as NSString).isAbsolutePath {
            return URL(fileURLWithPath: xdg).appendingPathComponent("codexbar/config.json")
        }
        let xdgDefault = home.appendingPathComponent(".config/codexbar/config.json")
        let legacy = home.appendingPathComponent(".codexbar/config.json")
        if fileManager.fileExists(atPath: xdgDefault.path) { return xdgDefault }
        if fileManager.fileExists(atPath: legacy.path) { return legacy }
        return xdgDefault
    }

    // MARK: - Schema (subset of CodexBar's config)

    struct Config: Codable {
        var version: Int?
        var providers: [Provider]?
    }

    struct Provider: Codable {
        var id: String
        var apiKey: String?
        var enabled: Bool?
        var region: String?
        var cookieHeader: String?
    }

    // MARK: - Read

    static func read(url: URL = configURL()) -> Config? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    /// API token for a provider id (e.g. "minimax"), trimmed; nil if unset.
    static func apiKey(provider: String, url: URL = configURL()) -> String? {
        let value = read(url: url)?.providers?.first { $0.id == provider }?.apiKey
        return cleaned(value)
    }

    /// MiniMax token with CodexBar's env-var precedence, then the config file.
    static func minimaxToken() -> String? {
        let env = ProcessInfo.processInfo.environment
        for key in ["MINIMAX_CODING_API_KEY", "MINIMAX_API_KEY"] {
            if let token = cleaned(env[key]) { return token }
        }
        return apiKey(provider: "minimax")
    }

    // MARK: - Write

    /// Upserts the API token for a provider id and writes the file atomically
    /// with 0o600 permissions, matching CodexBar.
    static func setAPIKey(_ key: String?, provider: String, url: URL = configURL()) throws {
        var config = read(url: url) ?? Config(version: 1, providers: [])
        var providers = config.providers ?? []
        let trimmed = cleaned(key)
        if let index = providers.firstIndex(where: { $0.id == provider }) {
            providers[index].apiKey = trimmed
        } else {
            providers.append(Provider(id: provider, apiKey: trimmed, enabled: true,
                                      region: nil, cookieHeader: nil))
        }
        config.providers = providers
        config.version = config.version ?? 1

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
