import Foundation
import Testing
import WebKit
@testable import MiniBrowser

@Suite("P8 子资源证书失败隔离", .serialized)
@MainActor
struct SubresourceCertificateTests {
    @Test("坏证书子资源请求被拒绝，不替换主页面")
    func badSubresourceDoesNotReplaceMainPage() async throws {
        let badTLS = try await LocalHTTPSServer(title: "bad-resource")
        defer { badTLS.stop() }
        let server = try LocalHTTPServer { _ in
            .init("""
            <html><head><title>main-intact</title></head><body>main-content
            <script>
            function loadBadResource() {
                fetch('\(badTLS.baseURL.absoluteString)')
                    .then(() => { document.title = 'subresource-unexpected'; })
                    .catch(() => { document.title = 'subresource-blocked'; });
            }
            </script></body></html>
            """)
        }
        try await server.start()
        defer { server.stop() }
        let tab = BrowserTab(url: server.baseURL)
        let fixture = WebViewFixture(webView: tab.webView)
        let coordinator = WebViewRepresentable.Coordinator(
            tab: tab,
            onCreateWebView: { _, _, _ in nil },
            serverTrustSession: ServerTrustSession()
        )
        tab.webView.navigationDelegate = coordinator
        tab.webView.uiDelegate = coordinator
        defer { fixture.close() }

        try await fixture.waitForTitle("main-intact")
        _ = try await fixture.evaluate("loadBadResource()")
        try await fixture.waitForTitle("subresource-blocked")
        #expect(fixture.webView.url?.host == server.baseURL.host)
        #expect(try await fixture.evaluate("document.body.innerText.includes('main-content')") as? Bool == true)
        #expect(try await fixture.evaluate("document.body.innerText.includes('仍然继续')") as? Bool == false)
    }
}
