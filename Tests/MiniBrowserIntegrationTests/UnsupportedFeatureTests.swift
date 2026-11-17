import Foundation
import Testing
import WebKit
@testable import MiniBrowser

@Suite("有意不支持的网页能力", .serialized)
@MainActor
struct UnsupportedFeatureTests {
    @Test("附件和外部协议取消导航并保留当前页面")
    func unsupportedNavigationStaysOnPage() async throws {
        let server = try LocalHTTPServer { request in
            switch request.path {
            case "/":
                return .init("""
                <html><head><title>current-page</title></head><body>
                <a id="download" href="/attachment">download</a>
                <script>
                function openExternal() {
                    window.location.href = 'weixin://local-only';
                    document.title = 'external-stayed';
                }
                </script></body></html>
                """)
            case "/attachment":
                return .init(
                    data: Data("not a webpage".utf8),
                    headers: ["Content-Disposition": "attachment; filename=local.txt"]
                )
            default:
                return .init("not found", status: "404 Not Found", contentType: "text/plain")
            }
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
        try await fixture.waitForTitle("current-page")

        _ = try await fixture.evaluate("document.getElementById('download').click()")
        try await waitUntil("attachment request was cancelled") {
            server.requests.contains { $0.path == "/attachment" }
        }
        try await waitUntil("current URL restored after attachment") {
            fixture.webView.url?.path == "/"
        }
        #expect(fixture.webView.title == "current-page")

        _ = try await fixture.evaluate("openExternal()")
        try await fixture.waitForTitle("external-stayed")
        #expect(fixture.webView.url?.path == "/")
    }

}
