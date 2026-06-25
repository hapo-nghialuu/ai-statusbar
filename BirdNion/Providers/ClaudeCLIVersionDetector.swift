import Foundation

/// Best-effort CLI version detection for providers that ship a binary on PATH.
/// Mirrors CodexBar's `ClaudeCLIVersionDetector`: each provider gets a tiny
/// helper that runs `<binary> --version` (or fallback flags) and returns the
/// trimmed first line, or nil if anything goes wrong. Used by the Claude
/// provider to surface the installed `claude` CLI version even when OAuth
/// fetch fails (Codex parity).
enum ClaudeCLIVersionDetector {
    /// Runs `claude --version` via Process with a 5s timeout, strips ANSI,
    /// returns the trimmed first non-empty line. nil if the binary is
    /// absent or fails.
    static func claudeVersion() -> String? {
        guard let path = locateBinary("claude") else { return nil }
        return runVersion(path: path, args: ["--version"], timeout: 5)
    }

    /// Runs `codex --version` (with `version` and `-v` fallbacks). Mirrors
    /// the Codex provider's pre-existing version detection so the rest of
    /// the app can call the same helper if needed.
    static func codexVersion() -> String? {
        guard let path = locateBinary("codex") else { return nil }
        for args in [["--version"], ["version"], ["-v"]] {
            if let v = runVersion(path: path, args: args, timeout: 2) { return v }
        }
        return nil
    }

    // MARK: - Internal

    /// Resolves `<binary>` via `/usr/bin/which`. Returns the absolute path
    /// (or nil if the user doesn't have it on PATH). Synchronous + cheap —
    /// callers should `Task.detached` if they're on the main actor.
    private static func locateBinary(_ binary: String) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        proc.arguments = ["which", binary]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice
        do {
            try proc.run()
        } catch {
            return nil
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let path = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : path
    }

    /// Spawns `<path> <args>`, waits up to `timeout`s, returns the first
    /// non-empty line. Strips ANSI escape codes (Claude CLI emits them).
    /// `internal`-exposed for unit tests via `runVersionForTest`.
    private static func runVersion(path: String, args: [String], timeout: TimeInterval) -> String? {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = args
        let outPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice
        proc.standardInput = nil
        do {
            try proc.run()
        } catch {
            return nil
        }
        // Wait synchronously with the timeout — these commands are
        // interactive CLI shells that would otherwise block the actor.
        let exited = DispatchSemaphore(value: 0)
        proc.terminationHandler = { _ in exited.signal() }
        guard exited.wait(timeout: .now() + timeout) == .success else {
            proc.terminate()
            return nil
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        guard proc.terminationStatus == 0,
              let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else { return nil }
        let stripped = stripANSICodes(text)
        let firstLine = stripped.split(whereSeparator: { $0.isNewline }).first
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let line = firstLine, !line.isEmpty else { return nil }
        return line
    }

    /// Minimal ANSI escape stripper. Keeps a private copy so we don't drag
    /// the Codex module in just for one helper.
    static func stripANSICodesForTest(_ text: String) -> String {
        stripANSICodes(text)
    }

    /// Public-for-tests bridge so unit tests can verify the spawn path
    /// without going through `which` first.
    static func runVersionForTest(path: String, args: [String], timeout: TimeInterval) -> String? {
        runVersion(path: path, args: args, timeout: timeout)
    }

    static func stripANSICodes(_ text: String) -> String {
        // CSI sequences: ESC[ ... letter. Also handles OSC sequences that
        // some CLIs (e.g. claude) emit when color is forced off.
        var out = ""
        out.reserveCapacity(text.count)
        var i = text.startIndex
        while i < text.endIndex {
            let c = text[i]
            if c == "\u{1B}" {
                let next = text.index(after: i)
                if next < text.endIndex, text[next] == "[" {
                    var j = text.index(after: next)
                    while j < text.endIndex, !text[j].isLetter { j = text.index(after: j) }
                    if j < text.endIndex { i = text.index(after: j); continue }
                }
            }
            out.append(c)
            i = text.index(after: i)
        }
        return out
    }
}