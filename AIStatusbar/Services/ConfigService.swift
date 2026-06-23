import Foundation

enum ConfigError: Error, Equatable {
    case fileMissing
    case invalidJSON(String)
    case ioError(String)
    case bakUnparseable(String)

    var message: String {
        switch self {
        case .fileMissing: return "File không tồn tại"
        case .invalidJSON(let s): return "JSON không hợp lệ: \(s)"
        case .ioError(let s): return "I/O error: \(s)"
        case .bakUnparseable(let s): return ".bak không parse được: \(s)"
        }
    }
}

/// Read/write Claude Code global settings.json with 3-deep ring .bak rotation,
/// atomic write, symlink resolution. Global-only in v1 (per-project deferred).
@MainActor
final class ConfigService: ObservableObject {
    @Published var activePath: URL
    @Published var lastError: String?

    init(homeOverride: URL? = nil) {
        let resolved = Self.resolveGlobalPath(home: homeOverride)
        self.activePath = resolved
    }

    static func resolveGlobalPath(home: URL? = nil) -> URL {
        let h: URL
        if let home = home {
            h = home
        } else {
            h = URL(fileURLWithPath: NSString(string: "~").expandingTildeInPath)
        }
        return h.appendingPathComponent(".claude/settings.json")
    }

    func loadGlobal() throws -> [String: Any] {
        let url = activePath
        let resolved = url.resolvingSymlinksInPath()
        guard FileManager.default.fileExists(atPath: resolved.path) else {
            // Treat missing as empty; first save will create the file.
            return [:]
        }
        let data: Data
        do {
            data = try Data(contentsOf: resolved)
        } catch {
            throw ConfigError.ioError("\(error)")
        }
        do {
            let any = try JSONSerialization.jsonObject(with: data, options: [.mutableContainers])
            return (any as? [String: Any]) ?? [:]
        } catch {
            throw ConfigError.invalidJSON("\(error)")
        }
    }

    func saveGlobal(_ settings: [String: Any]) throws {
        let url = activePath.resolvingSymlinksInPath()
        let parent = url.deletingLastPathComponent()
        // Validate .bak parses before rotation
        let bak = parent.appendingPathComponent("settings.json.bak")
        if FileManager.default.fileExists(atPath: bak.path) {
            if let data = try? Data(contentsOf: bak) {
                let parsed: Any? = try? JSONSerialization.jsonObject(with: data, options: [])
                if parsed == nil {
                    // Don't rotate forward an unparseable .bak; warn and proceed
                    lastError = "Warning: .bak hiện tại không parse được, sẽ bị ghi đè."
                } else {
                // .bak → .bak.1
                let bak1 = parent.appendingPathComponent("settings.json.bak.1")
                let bak2 = parent.appendingPathComponent("settings.json.bak.2")
                if FileManager.default.fileExists(atPath: bak1.path) {
                    if FileManager.default.fileExists(atPath: bak2.path) {
                        try? FileManager.default.removeItem(at: bak2)
                    }
                    try? FileManager.default.moveItem(at: bak1, to: bak2)
                }
                try? FileManager.default.moveItem(at: bak, to: bak1)
                }
            }
        }
        // Copy current → .bak (only if current exists)
        if FileManager.default.fileExists(atPath: url.path) {
            if FileManager.default.fileExists(atPath: bak.path) {
                try? FileManager.default.removeItem(at: bak)
            }
            try? FileManager.default.copyItem(at: url, to: bak)
        }
        // Write new content
        let data: Data
        do {
            data = try JSONSerialization.data(withJSONObject: settings,
                                              options: [.prettyPrinted, .sortedKeys])
        } catch {
            throw ConfigError.invalidJSON("\(error)")
        }
        let tmp = parent.appendingPathComponent(".settings.json.tmp")
        do {
            try data.write(to: tmp, options: .atomic)
        } catch {
            throw ConfigError.ioError("write tmp: \(error)")
        }
        // Atomic replace
        do {
            if FileManager.default.fileExists(atPath: url.path) {
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tmp)
            } else {
                try FileManager.default.moveItem(at: tmp, to: url)
            }
        } catch {
            // Try to restore from .bak
            if FileManager.default.fileExists(atPath: bak.path) {
                try? FileManager.default.copyItem(at: bak, to: url)
            }
            throw ConfigError.ioError("replace: \(error)")
        }
        lastError = nil
    }
}
