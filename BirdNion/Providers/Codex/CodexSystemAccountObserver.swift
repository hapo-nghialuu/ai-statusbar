import Foundation

/// Watches the system Codex home (`~/.codex`) and posts `.birdnionRefresh` when
/// its contents change — e.g. the user runs `codex login` in a terminal, which
/// rewrites `auth.json`. Mirrors CodexBar's `CodexSystemAccountObserver` so the
/// menu updates without a manual refresh.
///
/// Best-effort: silently no-ops if the directory can't be opened. Changes are
/// debounced (codex login writes several files in quick succession) and the
/// watch re-arms itself if the directory is replaced (atomic rename/delete).
@MainActor
final class CodexSystemAccountObserver {
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1
    private var debounce: Task<Void, Never>?

    private var watchedDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex", isDirectory: true)
    }

    func start() {
        stop()
        let dir = watchedDir
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        let descriptor = open(dir.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        fd = descriptor
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .extend],
            queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            let replaced = src.data.contains(.delete) || src.data.contains(.rename)
            self.handleChange(rearm: replaced)
        }
        src.setCancelHandler { [weak self] in
            if let fd = self?.fd, fd >= 0 { close(fd) }
            self?.fd = -1
        }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil
        debounce?.cancel()
        debounce = nil
    }

    private func handleChange(rearm: Bool) {
        debounce?.cancel()
        debounce = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled else { return }
            NotificationCenter.default.post(name: .birdnionRefresh, object: nil)
            // The directory was swapped out from under us → re-open the watch.
            if rearm { self?.start() }
        }
    }
}
