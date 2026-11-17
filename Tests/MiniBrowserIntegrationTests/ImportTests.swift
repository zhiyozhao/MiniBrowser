import Foundation
import Testing
import WebKit
@testable import MiniBrowser

@Suite("本地 WebView 测试基座", .serialized)
@MainActor
struct LocalWebViewSmokeTests {
    @Test("真实 WebView 加载本地测试页")
    func loadLocalPage() async throws {
        let server = try LocalHTTPServer { _ in
            .init("<html><head><title>local-ready</title></head><body>ok</body></html>")
        }
        try await server.start()
        defer { server.stop() }
        let fixture = WebViewFixture()
        defer { fixture.close() }

        fixture.load(server.baseURL.appendingPathComponent("smoke"))
        try await fixture.waitForTitle("local-ready")
        #expect(server.requests.map(\.path) == ["/smoke"])
    }
}
