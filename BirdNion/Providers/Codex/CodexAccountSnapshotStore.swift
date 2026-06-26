import Foundation

/// Persists the last successful Codex `ProviderStatus` per account so switching
/// accounts shows the previous numbers immediately (instead of a blank card)
/// and survives across relaunches. Mirrors CodexBar's per-account usage
/// snapshot store.
///
/// Keyed by `CodexAccountStore` account id ("system" or a managed UUID).
/// Best-effort: any read/write failure is swallowed — this is a UX nicety, not
/// a source of truth.
final class CodexAccountSnapshotStore: @unchecked Sendable {
    static let shared = CodexAccountSnapshotStore()

    private let lock = NSLock()
    private var loaded = false
    private var cache: [String: ProviderStatus] = [:]
    private let fileURL: URL

    /// `fileURL` is injectable for tests; production uses the App Support path.
    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            return base
                .appendingPathComponent("BirdNion", isDirectory: true)
                .appendingPathComponent("codex-account-snapshots.json")
        }()
    }

    /// Last snapshot for `id`, or nil when none has been stored.
    func snapshot(forAccount id: String) -> ProviderStatus? {
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        return cache[id]
    }

    /// Snapshot for the currently active account.
    func currentSnapshot() -> ProviderStatus? {
        snapshot(forAccount: CodexAccountStore.activeID())
    }

    /// Store a successful status for `id` and persist to disk. Error statuses
    /// are ignored so a transient failure never overwrites good cached data.
    func save(_ status: ProviderStatus, forAccount id: String) {
        guard status.error == nil, !status.windows.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }
        loadIfNeeded()
        cache[id] = status
        persist()
    }

    // MARK: - Disk

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([String: ProviderStatus].self, from: data)
        else { return }
        cache = decoded
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: fileURL)
    }
}
