import Foundation
@testable import AIStatusbar

/// Registers canned (URLResponse, Data) tuples for tests. URLSession
/// instances must be configured with `protocolClasses: [StubURLProtocol.self]`
/// to consult this stub. URLSession.shared is not intercepted.
final class StubURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) -> (HTTPURLResponse, Data)

    static var handler: Handler?
    static var lastRequest: URLRequest?
    private static let lock = NSLock()
    private static var _requestCount = 0

    static var requestCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _requestCount
    }

    private static func bump() {
        lock.lock(); _requestCount += 1; lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.bump()
        Self.lastRequest = request
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        handler = nil
        lastRequest = nil
        _requestCount = 0
    }
}
