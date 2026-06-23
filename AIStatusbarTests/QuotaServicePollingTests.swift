import XCTest
@testable import AIStatusbar

final class QuotaServicePollingTests: XCTestCase {
    @MainActor
    func testRefreshHandlesThrowingProvider() async {
        let happy = StubProvider(id: "h", displayName: "H",
                                 status: ProviderStatus(id: "h", displayName: "H",
                                                       windows: [
                                                         QuotaWindow(label: "5 giờ", usedPct: 10, remainingPct: 90),
                                                         QuotaWindow(label: "Tuần", usedPct: 20, remainingPct: 80)
                                                       ], lastUpdated: Date(), error: nil))
        let bad = ThrowingProvider(id: "b", displayName: "B")
        let svc = QuotaService(providers: [happy, bad], interval: 0.1)
        await svc.refresh()
        await svc.refresh()
        XCTAssertEqual(svc.statuses.count, 2)
        let happyStatus = svc.statuses.first { $0.id == "h" }
        XCTAssertEqual(happyStatus?.windows.count, 2)
        let badStatus = svc.statuses.first { $0.id == "b" }
        XCTAssertNotNil(badStatus?.error)
    }
}

private final class StubProvider: QuotaProvider {
    let id: String
    let displayName: String
    let status: ProviderStatus
    init(id: String, displayName: String, status: ProviderStatus) {
        self.id = id; self.displayName = displayName; self.status = status
    }
    func fetch() async throws -> ProviderStatus { status }
}

private final class ThrowingProvider: QuotaProvider {
    let id: String
    let displayName: String
    init(id: String, displayName: String) { self.id = id; self.displayName = displayName }
    func fetch() async throws -> ProviderStatus {
        throw NSError(domain: "test", code: 1)
    }
}
