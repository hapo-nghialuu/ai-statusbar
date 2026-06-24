import XCTest
@testable import AIStatusbar

final class CodexProviderTests: XCTestCase {
    private func tempURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-test-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("auth.json")
    }

    private func makeStubConfig() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self] + (c.protocolClasses ?? [])
        return c
    }

    // MARK: - CodexAuthStore.parse

    func testParseOAuthTokens() throws {
        let json = """
        {"tokens":{"access_token":"at","refresh_token":"rt","id_token":"it","account_id":"acc"},
         "last_refresh":"2026-06-01T00:00:00Z"}
        """.data(using: .utf8)!
        let creds = try CodexAuthStore.parse(json)
        XCTAssertEqual(creds.accessToken, "at")
        XCTAssertEqual(creds.refreshToken, "rt")
        XCTAssertEqual(creds.accountId, "acc")
        XCTAssertNotNil(creds.lastRefresh)
    }

    func testParseAPIKeyFallback() throws {
        let json = #"{"OPENAI_API_KEY":"sk-test"}"#.data(using: .utf8)!
        let creds = try CodexAuthStore.parse(json)
        XCTAssertEqual(creds.accessToken, "sk-test")
        XCTAssertTrue(creds.refreshToken.isEmpty)
    }

    func testParseMissingTokens() {
        let json = #"{"other":1}"#.data(using: .utf8)!
        XCTAssertThrowsError(try CodexAuthStore.parse(json)) { error in
            XCTAssertEqual(error as? CodexAuthError, .missingTokens)
        }
    }

    func testLoadNotFound() {
        XCTAssertThrowsError(try CodexAuthStore.load(url: tempURL())) { error in
            XCTAssertEqual(error as? CodexAuthError, .notFound)
        }
    }

    func testSaveRoundTripPrivatePermissions() throws {
        let url = tempURL()
        let creds = CodexCredentials(
            accessToken: "new-at", refreshToken: "new-rt",
            idToken: nil, accountId: "acc", lastRefresh: Date())
        try CodexAuthStore.save(creds, url: url)
        let reloaded = try CodexAuthStore.load(url: url)
        XCTAssertEqual(reloaded.accessToken, "new-at")
        XCTAssertEqual(reloaded.refreshToken, "new-rt")

        let perms = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o600)
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }

    // MARK: - needsRefresh

    func testNeedsRefreshBoundary() {
        let stale = CodexCredentials(accessToken: "a", refreshToken: "r", idToken: nil,
                                     accountId: nil, lastRefresh: Date().addingTimeInterval(-9 * 86400))
        let fresh = CodexCredentials(accessToken: "a", refreshToken: "r", idToken: nil,
                                     accountId: nil, lastRefresh: Date())
        let never = CodexCredentials(accessToken: "a", refreshToken: "r", idToken: nil,
                                     accountId: nil, lastRefresh: nil)
        XCTAssertTrue(stale.needsRefresh)
        XCTAssertFalse(fresh.needsRefresh)
        XCTAssertTrue(never.needsRefresh)
    }

    // MARK: - Usage decode + map

    private let usageJSON = """
    {"plan_type":"plus","rate_limit":{
      "primary_window":{"used_percent":42,"reset_at":1750000000,"limit_window_seconds":18000},
      "secondary_window":{"used_percent":8,"reset_at":1750500000,"limit_window_seconds":604800}}}
    """.data(using: .utf8)!

    func testDecodeAndMapWindows() throws {
        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: usageJSON)
        XCTAssertEqual(usage.planType, "plus")
        let windows = CodexProvider.map(usage)
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows[0].label, "5 giờ")
        XCTAssertEqual(windows[0].usedPct, 42)
        XCTAssertEqual(windows[0].remainingPct, 58)
        XCTAssertEqual(windows[0].resetDate, Date(timeIntervalSince1970: 1_750_000_000))
        XCTAssertEqual(windows[1].label, "Tuần")
        XCTAssertEqual(windows[1].remainingPct, 92)
    }

    func testDecodeCreditsNumber() throws {
        let json = #"{"plan_type":"plus","credits":{"balance":12.5}}"#.data(using: .utf8)!
        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: json)
        XCTAssertEqual(usage.credits?.balance, 12.5)
    }

    func testDecodeCreditsString() throws {
        // Balance may arrive as a string; decode leniently.
        let json = #"{"credits":{"balance":"0"}}"#.data(using: .utf8)!
        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: json)
        XCTAssertEqual(usage.credits?.balance, 0)
    }

    func testDecodeNoCredits() throws {
        // Absent credits block stays nil (backward-compatible with old payloads).
        let usage = try JSONDecoder().decode(CodexUsageResponse.self, from: usageJSON)
        XCTAssertNil(usage.credits)
    }

    func testMenuBarMetricFilter() {
        let session = QuotaWindow(label: "5 giờ", usedPct: 1, remainingPct: 99)
        let weekly = QuotaWindow(label: "Tuần", usedPct: 7, remainingPct: 93)
        let all = [session, weekly]
        XCTAssertEqual(CodexMenuBarMetric.automatic.filter(all).count, 2)
        XCTAssertEqual(CodexMenuBarMetric.session.filter(all).map(\.label), ["5 giờ"])
        XCTAssertEqual(CodexMenuBarMetric.weekly.filter(all).map(\.label), ["Tuần"])
        // Fallback: chosen window absent → keep all rather than show nothing.
        XCTAssertEqual(CodexMenuBarMetric.weekly.filter([session]).map(\.label), ["5 giờ"])
    }

    // MARK: - fetch()

    func testFetchHappyPath() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let auth = #"{"tokens":{"access_token":"at","refresh_token":"rt"},"last_refresh":"\#(nowISO)"}"#
        try auth.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let session = URLSession(configuration: makeStubConfig())
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://chatgpt.com/backend-api/wham/usage")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, self.usageJSON)
        }
        defer { StubURLProtocol.reset() }

        let p = CodexProvider(session: session, authURL: url,
                              statusProbe: { nil }, versionProbe: { nil })
        let exp = expectation(description: "fetch")
        var status: ProviderStatus?
        Task { status = try? await p.fetch(); exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertNil(status?.error)
        XCTAssertEqual(status?.windows.count, 2)
        XCTAssertEqual(status?.windows[0].label, "5 giờ")
    }

    func testFetchUnauthorizedNoRefreshToken() throws {
        let url = tempURL()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let nowISO = ISO8601DateFormatter().string(from: Date())
        let auth = #"{"tokens":{"access_token":"at","refresh_token":""},"last_refresh":"\#(nowISO)"}"#
        try auth.data(using: .utf8)!.write(to: url)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

        let session = URLSession(configuration: makeStubConfig())
        StubURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!, Data())
        }
        defer { StubURLProtocol.reset() }

        let p = CodexProvider(session: session, authURL: url,
                              statusProbe: { nil }, versionProbe: { nil })
        let exp = expectation(description: "fetch")
        var status: ProviderStatus?
        Task { status = try? await p.fetch(); exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(status?.windows.count, 0)
        XCTAssertEqual(status?.error, "Token Codex hết hạn — chạy `codex` để đăng nhập lại")
    }

    func testFetchNotLoggedIn() throws {
        let session = URLSession(configuration: makeStubConfig())
        defer { StubURLProtocol.reset() }
        let p = CodexProvider(session: session, authURL: tempURL())
        let exp = expectation(description: "fetch")
        var status: ProviderStatus?
        Task { status = try? await p.fetch(); exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(status?.error, "Chưa đăng nhập Codex — chạy `codex` để đăng nhập")
    }
}
