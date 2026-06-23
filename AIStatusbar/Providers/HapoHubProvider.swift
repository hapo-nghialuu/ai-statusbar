import Foundation

/// Hapo Hub quota provider. Token must match `^[A-Za-z0-9._\-]+$` to prevent
/// header injection (CR/LF in a pasted token would break URLRequest or split
/// additional HTTP headers — Finding F1).
final class HapoHubProvider: QuotaProvider {
    var id: String { config.id }
    var displayName: String { config.displayName }

    private let config: HapoHubConfig
    private let session: URLSession
    private let keychain: KeychainService

    init(session: URLSession = .shared, config: HapoHubConfig, keychain: KeychainService) {
        self.session = session
        self.config = config
        self.keychain = keychain
    }

    static let tokenCharacterSet: CharacterSet = {
        var s = CharacterSet.alphanumerics
        s.insert(charactersIn: "._-")
        return s
    }()

    func fetch() async throws -> ProviderStatus {
        let token: String
        do {
            token = try keychain.read(account: config.id)
        } catch KeychainError.itemNotFound {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Chưa cấu hình token")
        } catch let e as KeychainError {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Keychain error: \(e)")
        } catch {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "\(error)")
        }

        if token.unicodeScalars.contains(where: { !Self.tokenCharacterSet.contains($0) }) {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Token chứa ký tự không hợp lệ")
        }

        guard let url = URL(string: config.baseURL) else {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "baseURL không hợp lệ")
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(config.authHeaderTemplate.replacingOccurrences(of: "{token}", with: token),
                     forHTTPHeaderField: "Authorization")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Network: \(error.localizedDescription)")
        }

        guard let http = response as? HTTPURLResponse else {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Response không phải HTTP")
        }
        let ct = http.value(forHTTPHeaderField: "Content-Type") ?? ""
        if !(200..<300).contains(http.statusCode) {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "HTTP \(http.statusCode)")
        }
        if !ct.hasPrefix("application/json") {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Endpoint trả về non-JSON (Content-Type: \(ct))")
        }
        return parse(data)
    }

    func parse(_ data: Data) -> ProviderStatus {
        guard let any = try? JSONSerialization.jsonObject(with: data) else {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Response không phải JSON")
        }
        guard let value = resolve(path: config.jsonPath, in: any) as? Int else {
            return ProviderStatus(id: id, displayName: displayName, windows: [],
                                  lastUpdated: Date(),
                                  error: "Response thiếu trường \(config.jsonPath)")
        }
        let remaining = max(0, min(100, value))
        let win = QuotaWindow(label: "Quota",
                              usedPct: 100 - remaining,
                              remainingPct: remaining)
        return ProviderStatus(id: id, displayName: displayName,
                              windows: [win],
                              lastUpdated: Date(),
                              error: nil)
    }

    private func resolve(path: String, in root: Any) -> Any? {
        var cur: Any? = root
        for seg in path.split(separator: ".") {
            if let d = cur as? [String: Any] {
                cur = d[String(seg)]
            } else if let a = cur as? [Any] {
                if let i = Int(seg), i >= 0, i < a.count {
                    cur = a[i]
                } else { return nil }
            } else { return nil }
        }
        return cur
    }
}
