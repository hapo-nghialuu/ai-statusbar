import XCTest
@testable import AIStatusbar

final class HapoHubProviderTests: XCTestCase {
    func testMockReturnsFixedWindows() async throws {
        let p = MockHapoHubProvider()
        let s = try await p.fetch()
        XCTAssertEqual(s.windows.count, 2)
        XCTAssertEqual(s.windows[0].remainingPct, 80)
        XCTAssertEqual(s.windows[1].remainingPct, 60)
        XCTAssertNil(s.error)
    }

    func testRealReturns2xxParsed() async throws {
        let keychain = KeychainService()
        let account = "test-hapo-\(UUID().uuidString)"
        defer { try? keychain.delete(account: account) }
        try keychain.save(account: account, secret: "abc123")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self] + (cfg.protocolClasses ?? [])
        let session = URLSession(configuration: cfg)
        let config = HapoHubConfig(id: "hapo", displayName: "Hapo",
                                   baseURL: "https://hapo.example/api",
                                   authHeaderTemplate: "Bearer {token}",
                                   jsonPath: "data.quota.remaining")
        StubURLProtocol.handler = { req in
            let body = #"{"data":{"quota":{"remaining":73}}}"#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
            return (resp, body)
        }
        defer { StubURLProtocol.reset() }
        let p = HapoHubProvider(session: session, config: config, keychain: keychain)
        let s = try await p.fetch()
        XCTAssertNil(s.error)
        XCTAssertEqual(s.windows.count, 1)
        XCTAssertEqual(s.windows[0].remainingPct, 73)
    }

    func testRealNon2xx() async throws {
        let keychain = KeychainService()
        let account = "test-hapo-\(UUID().uuidString)"
        defer { try? keychain.delete(account: account) }
        try keychain.save(account: account, secret: "abc123")
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self] + (cfg.protocolClasses ?? [])
        let session = URLSession(configuration: cfg)
        let config = HapoHubConfig(id: "hapo", displayName: "Hapo",
                                   baseURL: "https://hapo.example/api",
                                   authHeaderTemplate: "Bearer {token}",
                                   jsonPath: "data.quota.remaining")
        StubURLProtocol.handler = { req in
            let body = Data()
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }
        defer { StubURLProtocol.reset() }
        let p = HapoHubProvider(session: session, config: config, keychain: keychain)
        let s = try await p.fetch()
        XCTAssertTrue(s.error?.contains("HTTP 500") ?? false)
    }
}
