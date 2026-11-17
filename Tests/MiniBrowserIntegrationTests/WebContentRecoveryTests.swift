import Foundation
import Testing
import WebKit
@testable import MiniBrowser

@Suite("P11 WebContent 崩溃恢复", .serialized)
@MainActor
struct WebContentRecoveryIntegrationTests {
    @Test("第一次自动重载，连续第二次显示无按钮错误页")
    func reloadOnceThenShowError() async throws {
        let server = try LocalHTTPServer { _ in
            .init("<html><head><title>recovery-ready</title></head><body>ok</body></html>")
        }
        try await server.start()
        defer { server.stop() }
        let tab = BrowserTab(url: server.baseURL)
        let fixture = WebViewFixture(webView: tab.webView)
        let coordinator = WebViewRepresentable.Coordinator(
            tab: tab,
            onCreateWebView: { _, _, _ in nil }
        )
        tab.webView.navigationDelegate = coordinator
        tab.webView.uiDelegate = coordinator
        defer { fixture.close() }
        try await fixture.waitForTitle("recovery-ready")

        coordinator.webViewWebContentProcessDidTerminate(tab.webView)
        try await waitUntil("automatic reload reached local server") {
            server.requests.filter { $0.path == "/" }.count == 2
        }
        coordinator.webViewWebContentProcessDidTerminate(tab.webView)

        try await fixture.waitForTitle("页面加载失败")
        #expect(server.requests.filter { $0.path == "/" }.count == 2)
        #expect(try await fixture.evaluate("document.querySelector('button') === null") as? Bool == true)
    }
}
