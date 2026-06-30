import Foundation
import os

/// FreeModel quota provider.
///
/// Authenticates via the `bm_session` browser cookie set by freemodel.dev —
/// scraped automatically through `ProviderCookieReader`, the same path the
/// other cookie providers (CommandCode / MiMo / Cursor …) use. No API token.
///
/// Endpoints:
///   GET https://freemodel.dev/api/usage      → 5h + weekly dollar budgets
///   GET https://freemodel.dev/api/auth/me    → account email (label only)
///
/// Usage response shape:
/// ```json
/// { "window5h":   { "usedCents": 2250, "limitCents": 20000,  "resetsAt": 1782724407 },
///   "windowWeek": { "usedCents": 8,    "limitCents": 132000, "resetsAt": 1783321795 } }
/// ```
/// (the endpoint also returns request/token totals we don't surface.)
///
/// `me` response shape: `{ "user": { "email": "…", … } }`.
final class FreemodelProvider: QuotaProvider {
    let id = "freemodel"
    let displayName = "FreeModel"

    /// Cookie domain freemodel.dev sets the session cookie for.
    static let cookieDomain = "freemodel.dev"
    /// Session cookie name (Akamai bot-manager session). The dollar budgets are
    /// gated on this being present.
    private static let sessionCookieName = "bm_session"

    private static let usageURL = URL(string: "https://freemodel.dev/api/usage")!
    private static let meURL = URL(string: "https://freemodel.dev/api/auth/me")!
    private static let webOrigin = "https://freemodel.dev"
    private static let referer = "https://freemodel.dev/dashboard/usage"
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.0.0 Safari/537.36"
    private static let requestTimeout: TimeInterval = 15

    private let session: URLSession
    private static let log = Logger(subsystem: "com.local.birdnion", category: "provider.freemodel")

    init(session: URLSession = .shared) {
        self.session = session
    }

    // MARK: - QuotaProvider

    func fetch() async throws -> ProviderStatus {
        // `bm_session` is the login cookie. Passing it as the required cookie
        // makes the reader skip browsers that only hold stale freemodel.dev
        // analytics/Stripe cookies (e.g. Chrome) and keep scanning until it
        // finds the browser the user actually logged in with (e.g. Brave).
        let rawHeader = ProviderCookieReader.resolvedCookieHeader(
            providerID: id, domain: Self.cookieDomain, requiredCookie: Self.sessionCookieName)
        let cookieHeader = rawHeader.flatMap { Self.filteredCookieHeader(from: $0) }
        guard let cookieHeader else {
            return failure("Chưa đăng nhập FreeModel trên trình duyệt")
        }

        let usageData: Data
        do {
            usageData = try await fetchEndpoint(url: Self.usageURL, cookieHeader: cookieHeader)
        } catch {
            Self.log.error("fetch: usage network error: \(error.localizedDescription, privacy: .public)")
            return failure("Network: \(error.localizedDescription)")
        }

        // Account email is best-effort enrichment — never block the budget on it.
        let accountLabel = await resolveAccountLabel(cookieHeader: cookieHeader)

        return parse(usageData: usageData, accountLabel: accountLabel)
    }

    // MARK: - Parsing (static entry point for unit tests — no network I/O)

    static func _parseForTesting(usageData: Data, accountLabel: String?) -> ProviderStatus {
        FreemodelProvider().parse(usageData: usageData, accountLabel: accountLabel)
    }

    private func parse(usageData: Data, accountLabel: String?) -> ProviderStatus {
        guard let usage = try? JSONDecoder().decode(UsageResponse.self, from: usageData) else {
            let snippet = String(data: usageData.prefix(120), encoding: .utf8) ?? "<non-utf8 \(usageData.count)B>"
            Self.log.error("parse: decode failed — body: \(snippet, privacy: .public)")
            return failure("Response /api/usage không hợp lệ")
        }

        let windows = [
            Self.window(label: "5 giờ", from: usage.window5h, windowSeconds: 5 * 3600),
            Self.window(label: "Tuần", from: usage.windowWeek, windowSeconds: 7 * 24 * 3600),
        ]

        return ProviderStatus(
            id: id,
            displayName: displayName,
            windows: windows,
            lastUpdated: Date(),
            error: nil,
            accountLabel: accountLabel)
    }

    /// Map one freemodel dollar window into a QuotaWindow with a "$used / $limit"
    /// subtitle and reset countdown.
    private static func window(label: String, from w: UsageResponse.Window, windowSeconds: Int) -> QuotaWindow {
        let used = Double(w.usedCents) / 100.0
        let limit = Double(w.limitCents) / 100.0
        let usedPct = limit > 0 ? Int((used / limit * 100).rounded()) : 0
        let clamped = max(0, min(100, usedPct))
        return QuotaWindow(
            label: label,
            usedPct: clamped,
            remainingPct: 100 - clamped,
            subtitle: "\(UsageFormatter.usdString(used)) / \(UsageFormatter.usdString(limit))",
            resetDate: w.resetsAt > 0 ? Date(timeIntervalSince1970: TimeInterval(w.resetsAt)) : nil,
            windowSeconds: windowSeconds)
    }

    // MARK: - Account label

    private func resolveAccountLabel(cookieHeader: String) async -> String? {
        if let explicit = BirdNionConfigStore.accountLabel(provider: id), !explicit.isEmpty {
            return explicit
        }
        guard let data = try? await fetchEndpoint(url: Self.meURL, cookieHeader: cookieHeader),
              let me = try? JSONDecoder().decode(MeResponse.self, from: data),
              !me.user.email.isEmpty
        else {
            return nil
        }
        return me.user.email
    }

    // MARK: - Cookie filtering

    /// Forward every cookie from the browser header (freemodel validates the
    /// whole set, including the `__stripe_*` cookies) but only proceed when
    /// `bm_session` is present. A bare token (no `=`) is wrapped under the
    /// session name.
    static func filteredCookieHeader(from raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if !trimmed.contains("=") {
            return "\(sessionCookieName)=\(trimmed)"
        }

        var pairs: [String] = []
        var hasSession = false
        for chunk in trimmed.split(separator: ";") {
            let t = chunk.trimmingCharacters(in: .whitespaces)
            guard let eq = t.firstIndex(of: "=") else { continue }
            let name = String(t[..<eq]).trimmingCharacters(in: .whitespaces)
            let value = String(t[t.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !value.isEmpty else { continue }
            pairs.append("\(name)=\(value)")
            if name == sessionCookieName { hasSession = true }
        }
        guard hasSession, !pairs.isEmpty else { return nil }
        return pairs.joined(separator: "; ")
    }

    // MARK: - Networking

    private func fetchEndpoint(url: URL, cookieHeader: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.timeoutInterval = Self.requestTimeout
        req.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        req.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        req.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        req.setValue(Self.webOrigin, forHTTPHeaderField: "Origin")
        req.setValue(Self.referer, forHTTPHeaderField: "Referer")

        let (data, response) = try await session.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard (200..<300).contains(status) else {
            throw NSError(domain: "Freemodel", code: status,
                          userInfo: [NSLocalizedDescriptionKey: "HTTP \(status)"])
        }
        return data
    }

    private func failure(_ message: String) -> ProviderStatus {
        ProviderStatus(id: id, displayName: displayName, windows: [], lastUpdated: Date(), error: message)
    }
}

// MARK: - Wire types

private struct UsageResponse: Decodable {
    let window5h: Window
    let windowWeek: Window
    struct Window: Decodable {
        let usedCents: Int
        let limitCents: Int
        let resetsAt: Int
    }
}

private struct MeResponse: Decodable {
    let user: User
    struct User: Decodable { let email: String }
}
