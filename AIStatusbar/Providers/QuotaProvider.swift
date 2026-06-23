// No `import Foundation` here — the protocol only references types defined in our own model layer.
// Keeping this file free of Foundation makes the contract trivially testable in isolation.

protocol QuotaProvider: AnyObject {
    var id: String { get }
    var displayName: String { get }
    func fetch() async throws -> ProviderStatus
}
