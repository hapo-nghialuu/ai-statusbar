import XCTest
@testable import AIStatusbar

final class MiniMaxProviderParserTests: XCTestCase {
    private let happyJSON = """
    {"model_remains":[{"model_name":"general",
    "current_interval_total_count":100,"current_interval_usage_count":13,
    "current_interval_remaining_percent":87,
    "current_weekly_total_count":700,"current_weekly_usage_count":80,
    "current_weekly_remaining_percent":89}]}
    """.data(using: .utf8)!

    private let missingModelJSON = """
    {"other":[]}
    """.data(using: .utf8)!

    private let missingPctJSON = """
    {"model_remains":[{"model_name":"general"}]}
    """.data(using: .utf8)!

    private let malformedJSON = "not json".data(using: .utf8)!

    func testHappyPath() throws {
        let keychain = KeychainService()
        let account = "test-minimax-\(UUID().uuidString)"
        defer { try? keychain.delete(account: account) }
        try keychain.save(account: account, secret: "test-token")
        let session = URLSession(configuration: makeStubConfig())
        let p = MiniMaxProvider(session: session, keychain: keychain)
        StubURLProtocol.handler = { req in
            XCTAssertEqual(req.url?.absoluteString, "https://api.minimax.io/v1/token_plan/remains")
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, self.happyJSON)
        }
        defer { StubURLProtocol.reset() }
        let exp = expectation(description: "fetch")
        var status: ProviderStatus?
        Task {
            status = try? await p.fetch()
            exp.fulfill()
        }
        wait(for: [exp], timeout: 2)
        XCTAssertNil(status?.error)
        XCTAssertEqual(status?.windows.count, 2)
        XCTAssertEqual(status?.windows[0].label, "5 giờ")
        XCTAssertEqual(status?.windows[0].remainingPct, 87)
        XCTAssertEqual(status?.windows[1].label, "Tuần")
        XCTAssertEqual(status?.windows[1].remainingPct, 89)
    }

    func testMissingModel() throws {
        let keychain = KeychainService()
        let account = "test-minimax-\(UUID().uuidString)"
        defer { try? keychain.delete(account: account) }
        try keychain.save(account: account, secret: "test-token")
        let session = URLSession(configuration: makeStubConfig())
        let p = MiniMaxProvider(session: session, keychain: keychain)
        StubURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, self.missingModelJSON)
        }
        defer { StubURLProtocol.reset() }
        let exp = expectation(description: "fetch")
        var status: ProviderStatus?
        Task { status = try? await p.fetch(); exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(status?.error, "Response thiếu trường")
    }

    func testMissingPercent() throws {
        let keychain = KeychainService()
        let account = "test-minimax-\(UUID().uuidString)"
        defer { try? keychain.delete(account: account) }
        try keychain.save(account: account, secret: "test-token")
        let session = URLSession(configuration: makeStubConfig())
        let p = MiniMaxProvider(session: session, keychain: keychain)
        StubURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, self.missingPctJSON)
        }
        defer { StubURLProtocol.reset() }
        let exp = expectation(description: "fetch")
        var status: ProviderStatus?
        Task { status = try? await p.fetch(); exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertEqual(status?.error, "Response thiếu trường")
    }

    func testMalformedJSON() throws {
        let keychain = KeychainService()
        let account = "test-minimax-\(UUID().uuidString)"
        defer { try? keychain.delete(account: account) }
        try keychain.save(account: account, secret: "test-token")
        let session = URLSession(configuration: makeStubConfig())
        let p = MiniMaxProvider(session: session, keychain: keychain)
        StubURLProtocol.handler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, self.malformedJSON)
        }
        defer { StubURLProtocol.reset() }
        let exp = expectation(description: "fetch")
        var status: ProviderStatus?
        Task { status = try? await p.fetch(); exp.fulfill() }
        wait(for: [exp], timeout: 2)
        XCTAssertNotNil(status?.error)
    }

    private func makeStubConfig() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [StubURLProtocol.self] + (c.protocolClasses ?? [])
        return c
    }
}
