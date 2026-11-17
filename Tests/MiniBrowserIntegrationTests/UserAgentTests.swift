import Foundation
import Testing
import WebKit
@testable import MiniBrowser

@Suite("P9 统一 Safari User-Agent", .serialized)
@MainActor
struct UserAgentTests {
    @Test("不同本地站点收到相同且与引擎一致的 UA")
    func uniformSafariUserAgent() async throws {
        let handler: @Sendable (LocalHTTPServer.Request) -> LocalHTTPServer.Response = { _ in
            .init("<html><head><title>ua-ready</title></head><body>ok</body></html>")
        }
        let firstServer = try LocalHTTPServer(handler: handler)
        let secondServer = try LocalHTTPServer(handler: handler)
        try await firstServer.start()
        try await secondServer.start()
        defer { firstServer.stop(); secondServer.stop() }
        let first = WebViewFixture(configuration: WebViewConfigurationFactory.make())
        let second = WebViewFixture(configuration: WebViewConfigurationFactory.make())
        defer { first.close(); second.close() }

        first.load(firstServer.baseURL.appendingPathComponent("first"))
        second.load(secondServer.baseURL.appendingPathComponent("second"))
        try await first.waitForTitle("ua-ready")
        try await second.waitForTitle("ua-ready")
        let firstUA = try #require(try await first.evaluate("navigator.userAgent") as? String)
        let secondUA = try #require(try await second.evaluate("navigator.userAgent") as? String)
        #expect(firstUA == secondUA)
        #expect(firstUA == firstServer.requests.first?.headers["user-agent"])
        #expect(secondUA == secondServer.requests.first?.headers["user-agent"])
        #expect(firstUA.contains("AppleWebKit/605.1.15"))
        #expect(firstUA.contains("Version/18.0 Safari/605.1.15"))
        #expect(!firstUA.contains("Chrome/"))
    }
}
