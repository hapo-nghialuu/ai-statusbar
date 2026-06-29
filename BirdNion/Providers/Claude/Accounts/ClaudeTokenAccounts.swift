import Foundation

// Native multi-account store for Claude, mirroring the Claude slice of
// CodexBarCore's TokenAccounts. Stores a list of accounts (each carries a token
// — a web sessionKey or an Admin API key — plus a label and the linked
// organization) and which one is active. Persisted as JSON at
// ~/Library/Application Support/BirdNion/claude-accounts.json with 0600 perms.
// OAuth stays single-account (driven by the system Keychain), so this store
// only governs the web/admin sources + the account switcher UI.

/// One stored Claude account.
struct ClaudeTokenAccount: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let label: String
    /// Web sessionKey (`sk-ant-…`) or Admin API key, depending on `kind`.
    let token: String
    let kind: Kind
    let addedAt: Date
    var lastUsed: Date?
    /// Account email / login the token resolves to (filled after first fetch).
    var externalIdentifier: String?
    /// Anthropic organization UUID this token belongs to.
    var organizationID: String?

    enum Kind: String, Codable, Sendable {
        case web      // claude.ai sessionKey cookie
        case admin    // Anthropic Admin API key
    }

    init(id: UUID = UUID(),
         label: String,
         token: String,
         kind: Kind,
         addedAt: Date = Date(),
         lastUsed: Date? = nil,
         externalIdentifier: String? = nil,
         organizationID: String? = nil) {
        self.id = id
        self.label = label
        self.token = token
        self.kind = kind
        self.addedAt = addedAt
        self.lastUsed = lastUsed
        self.externalIdentifier = externalIdentifier
        self.organizationID = organizationID
    }

    /// Best display name: explicit label → external identifier → kind.
    var displayName: String {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if let ext = externalIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines), !ext.isEmpty {
            return ext
        }
        return kind == .admin ? "Admin key" : "Web session"
    }
}

/// The persisted account list + which one is active.
struct ClaudeTokenAccountData: Codable, Equatable, Sendable {
    var version: Int
    var accounts: [ClaudeTokenAccount]
    var activeIndex: Int

    init(version: Int = 1, accounts: [ClaudeTokenAccount] = [], activeIndex: Int = 0) {
        self.version = version
        self.accounts = accounts
        self.activeIndex = activeIndex
    }

    /// Active index clamped to a valid range (0 when empty).
    func clampedActiveIndex() -> Int {
        guard !accounts.isEmpty else { return 0 }
        return min(max(activeIndex, 0), accounts.count - 1)
    }

    var active: ClaudeTokenAccount? {
        guard !accounts.isEmpty else { return nil }
        return accounts[clampedActiveIndex()]
    }
}

/// File-backed CRUD for the Claude account list.
enum ClaudeTokenAccountStore {
    static func defaultURL() -> URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("BirdNion/claude-accounts.json")
    }

    static func load(url: URL = defaultURL()) -> ClaudeTokenAccountData {
        guard let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ClaudeTokenAccountData.self, from: data)
        else { return ClaudeTokenAccountData() }
        return decoded
    }

    @discardableResult
    static func save(_ data: ClaudeTokenAccountData, url: URL = defaultURL()) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let blob = try encoder.encode(data)
            try blob.write(to: url, options: .atomic)
            // Tokens are sensitive — restrict to the owner.
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Mutations

    @discardableResult
    static func add(_ account: ClaudeTokenAccount, url: URL = defaultURL()) -> ClaudeTokenAccountData {
        var data = load(url: url)
        data.accounts.append(account)
        data.activeIndex = data.accounts.count - 1   // newly added becomes active
        save(data, url: url)
        return data
    }

    @discardableResult
    static func remove(id: UUID, url: URL = defaultURL()) -> ClaudeTokenAccountData {
        var data = load(url: url)
        guard let idx = data.accounts.firstIndex(where: { $0.id == id }) else { return data }
        data.accounts.remove(at: idx)
        if data.activeIndex >= data.accounts.count { data.activeIndex = max(0, data.accounts.count - 1) }
        save(data, url: url)
        return data
    }

    @discardableResult
    static func setActive(id: UUID, url: URL = defaultURL()) -> ClaudeTokenAccountData {
        var data = load(url: url)
        guard let idx = data.accounts.firstIndex(where: { $0.id == id }) else { return data }
        data.activeIndex = idx
        data.accounts[idx].lastUsed = Date()
        save(data, url: url)
        return data
    }

    static func active(url: URL = defaultURL()) -> ClaudeTokenAccount? {
        load(url: url).active
    }
}
