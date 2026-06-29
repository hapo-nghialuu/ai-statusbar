import Foundation

/// One Kilo organization the signed-in account belongs to. Mirrors
/// CodexBar's `KiloOrganization`.
struct KiloOrganization: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let role: String?

    init(id: String, name: String, role: String? = nil) {
        self.id = id
        self.name = name
        self.role = role
    }
}

/// Quota scope: the personal account or one selected organization. Mirrors
/// CodexBar's `KiloUsageScope`. The selected scope is persisted in
/// UserDefaults (id + name) so it survives relaunch without re-fetching.
enum KiloUsageScope: Equatable {
    case personal
    case organization(id: String, name: String)

    static let orgIDKey = "kiloOrgID"
    static let orgNameKey = "kiloOrgName"

    var organizationID: String? {
        switch self {
        case .personal: return nil
        case .organization(let id, _): return id
        }
    }

    var displayName: String {
        switch self {
        case .personal: return "Personal"
        case .organization(_, let name): return name
        }
    }

    /// Current scope from UserDefaults: org id (+ cached name) → personal.
    static func current() -> KiloUsageScope {
        let id = (UserDefaults.standard.string(forKey: orgIDKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return .personal }
        let name = (UserDefaults.standard.string(forKey: orgNameKey) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return .organization(id: id, name: name.isEmpty ? id : name)
    }
}

extension KiloOrganization {
    /// Fetches the organizations the account belongs to via the Kilo tRPC API.
    /// Endpoint: GET `…/api/trpc/user.getOrganizations?batch=1&input={"0":{"json":null}}`
    /// Returns an empty array when the account has no orgs (not an error).
    static func fetchOrganizations(token: String) async throws -> [KiloOrganization] {
        let baseURL = URL(string: "https://app.kilo.ai/api/trpc")!
        var comp = URLComponents(url: baseURL.appendingPathComponent("user.getOrganizations"),
                                 resolvingAgainstBaseURL: false)!
        comp.queryItems = [
            URLQueryItem(name: "batch", value: "1"),
            URLQueryItem(name: "input", value: #"{"0":{"json":null}}"#),
        ]
        guard let url = comp.url else { throw FetchError.invalidURL }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw FetchError.notHTTP }
        guard (200..<300).contains(http.statusCode) else { throw FetchError.httpError(http.statusCode) }
        return parse(data: data)
    }

    /// Parses both shapes Kilo returns: the tRPC batch envelope whose
    /// `json` is a **direct array** of orgs, and the REST profile shape
    /// `{ organizations: [...] }`. Unknown shapes yield an empty array.
    static func parse(data: Data) -> [KiloOrganization] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }

        // tRPC batch: [ { result: { data: { json: [orgs] | { organizations: [orgs] } } } } ]
        if let entries = root as? [[String: Any]],
           let first = entries.first,
           let result = first["result"] as? [String: Any] {
            if let dataObj = result["data"] as? [String: Any] {
                if let arr = dataObj["json"] as? [[String: Any]] { return decode(arr) }
                if let nested = dataObj["json"] as? [String: Any],
                   let arr = nested["organizations"] as? [[String: Any]] { return decode(arr) }
            }
            if let arr = result["data"] as? [[String: Any]] { return decode(arr) }
        }

        // REST profile: { organizations: [orgs] }
        if let dict = root as? [String: Any],
           let arr = dict["organizations"] as? [[String: Any]] {
            return decode(arr)
        }
        return []
    }

    private static func decode(_ raw: [[String: Any]]) -> [KiloOrganization] {
        raw.compactMap { item in
            guard let id = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty else { return nil }
            let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let role = (item["role"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return KiloOrganization(
                id: id,
                name: (name?.isEmpty ?? true) ? id : name!,
                role: (role?.isEmpty ?? true) ? nil : role)
        }
    }

    enum FetchError: Error, LocalizedError {
        case invalidURL
        case notHTTP
        case httpError(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "URL không hợp lệ"
            case .notHTTP: return "Response không phải HTTP"
            case .httpError(let code): return "HTTP \(code)"
            }
        }
    }
}
