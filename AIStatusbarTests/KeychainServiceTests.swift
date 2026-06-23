import XCTest
@testable import AIStatusbar

final class KeychainServiceTests: XCTestCase {
    func testRoundTrip() throws {
        let svc = KeychainService()
        let account = "test-\(UUID().uuidString)"
        defer { try? svc.delete(account: account) }
        try svc.save(account: account, secret: "fake-secret-value")
        let read = try svc.read(account: account)
        XCTAssertEqual(read, "fake-secret-value")
    }

    func testMissingItemThrows() {
        let svc = KeychainService()
        let account = "test-nonexistent-\(UUID().uuidString)"
        XCTAssertThrowsError(try svc.read(account: account)) { err in
            XCTAssertEqual(err as? KeychainError, .itemNotFound)
        }
    }
}
