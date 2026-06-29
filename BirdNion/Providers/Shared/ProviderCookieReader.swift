import Foundation
import SweetCookieKit

// MARK: - ProviderCookieReader

/// Generic browser-cookie reader for providers that authenticate via session cookies.
///
/// Mirrors ClaudeWebCookieReader's cooldown-gate pattern but is parameterised by
/// domain so any provider can reuse it without duplicating the SweetCookieKit wiring.
///
/// Usage:
/// ```swift
/// let header = ProviderCookieReader.cookieHeader(domain: "commandcode.ai")
/// ```
enum ProviderCookieReader {

    // MARK: - Cooldown gate

    /// UserDefaults key prefix; append the domain to avoid key collisions.
    private static let deniedUntilKeyPrefix = "providerCookieDeniedUntil_"

    /// Lock serialises browser reads so parallel provider fetches don't race.
    private static let gateLock = NSLock()

    // MARK: - Public API

    /// Returns a `Cookie:` header value for `domain`, built from all cookie records
    /// in the first browser store that has cookies for that domain.
    ///
    /// Returns `nil` when:
    /// - No browser has cookies for this domain.
    /// - The cooldown gate is active (a previous read was denied by Full Disk Access / Keychain).
    ///
    /// Tries Safari first (no Keychain prompt), then `Browser.defaultImportOrder`.
    ///
    /// No pre-emptive cooldown block: every call attempts the read so the macOS
    /// Keychain "<Browser> Safe Storage" prompt can appear (and the user can pick
    /// "Always Allow"). Once granted, SweetCookieKit caches the key so there's no
    /// repeat prompt; the cooldown is only recorded for telemetry/back-off hints.
    static func cookieHeader(domain: String) -> String? {
        gateLock.lock()
        defer { gateLock.unlock() }
        return extractFromBrowsers(domain: domain)
    }

    /// Resolves the cookie header honoring the provider's "cookie source"
    /// preference (UserDefaults `<providerID>CookieSource`: auto/manual/off).
    /// `manual` reads a user-pasted Cookie header from `<providerID>ManualCookie`.
    static func resolvedCookieHeader(providerID: String, domain: String) -> String? {
        let source = UserDefaults.standard.string(forKey: "\(providerID)CookieSource") ?? "auto"
        switch source {
        case "off":
            return nil
        case "manual":
            let raw = UserDefaults.standard.string(forKey: "\(providerID)ManualCookie")?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (raw?.isEmpty ?? true) ? nil : raw
        default:
            return cookieHeader(domain: domain)
        }
    }

    // MARK: - Browser iteration

    private static func extractFromBrowsers(domain: String) -> String? {
        let client = BrowserCookieClient()
        let query = BrowserCookieQuery(domains: [domain])

        // Safari first — no Keychain prompt needed.
        if let header = tryBrowser(.safari, client: client, query: query, domain: domain) {
            return header
        }

        let remaining = Browser.defaultImportOrder.filter { $0 != .safari }
        for browser in remaining {
            if let header = tryBrowser(browser, client: client, query: query, domain: domain) {
                return header
            }
        }
        return nil
    }

    private static func tryBrowser(
        _ browser: Browser,
        client: BrowserCookieClient,
        query: BrowserCookieQuery,
        domain: String
    ) -> String? {
        do {
            let storeRecords = try client.records(matching: query, in: browser)
            // Use the first store that has at least one cookie.
            if let first = storeRecords.first, !first.records.isEmpty {
                return buildCookieHeader(from: first.records)
            }
        } catch let error as BrowserCookieError {
            recordCooldownIfNeeded(error, domain: domain)
        } catch {
            // notFound / loadFailed — browser not installed or store unreadable; skip silently.
        }
        return nil
    }

    // MARK: - Cookie header builder

    private static func buildCookieHeader(from records: [BrowserCookieRecord]) -> String {
        records
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    // MARK: - 6-hour cooldown gate

    private static func deniedUntilKey(domain: String) -> String {
        deniedUntilKeyPrefix + domain
    }

    private static func cooldownDate(domain: String) -> Date? {
        UserDefaults.standard.object(forKey: deniedUntilKey(domain: domain)) as? Date
    }

    /// Cooldown after an access-denied so we don't re-trigger the macOS Keychain
    /// prompt on every background poll. Kept SHORT (5 min) so a user who clicks
    /// Refresh — or grants "Always Allow" — gets a fresh attempt quickly rather
    /// than being locked out for hours.
    private static let cooldownSeconds: TimeInterval = 5 * 60

    private static func recordCooldownIfNeeded(_ error: BrowserCookieError, domain: String) {
        if case .accessDenied = error {
            let suppressUntil = Date().addingTimeInterval(cooldownSeconds)
            UserDefaults.standard.set(suppressUntil, forKey: deniedUntilKey(domain: domain))
        }
    }
}
