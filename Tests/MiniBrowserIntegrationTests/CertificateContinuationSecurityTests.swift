import Foundation
import Testing
import WebKit
@testable import MiniBrowser

@Suite("P8 证书继续防滥用", .serialized)
@MainActor
struct CertificateContinuationSecurityTests {
    @Test("恶意页面不能复用上一次错误页的继续入口")
    func maliciousPageCannotContinuePendingCertificate() async throws {
        let badTLS = try await LocalHTTPSServer(title: "unexpectedly-trusted")
        defer { badTLS.stop() }
        let tab = BrowserTab(url: badTLS.baseURL)
        let fixture = WebViewFixture(webView: tab.webView)
        let session = ServerTrustSession()
        let coordinator = WebViewRepresentable.Coordinator(
            tab: tab,
            onCreateWebView: { _, _, _ in nil },
            serverTrustSession: session
        )
        tab.webView.navigationDelegate = coordinator
        tab.webView.uiDelegate = coordinator
        defer { fixture.close() }

        try await fixture.waitForTitle("证书无效")
        let continueURL = (try await fixture.evaluate(
            "document.getElementById('continue').getAttribute('data-continue-url')"
        ) as? String) ?? "minibrowser://continue-certificate"
        let encodedURL = String(data: try JSONSerialization.data(withJSONObject: [continueURL]), encoding: .utf8)!
        let server = try LocalHTTPServer { request in
            if request.path == "/settled" {
                return .init("ok", contentType: "text/plain")
            }
            return .init("""
            <html><head><title>malicious-ready</title></head><body>malicious
            <script>
            function attack() {
                window.location.href = \(encodedURL.dropFirst().dropLast());
                fetch('/settled').then(() => { document.title = 'malicious-settled'; });
            }
            </script></body></html>
            """)
        }
        try await server.start()
        defer { server.stop() }

        fixture.load(server.baseURL)
        try await fixture.waitForTitle("malicious-ready")
        _ = try await fixture.evaluate("attack()")
        try await fixture.waitForTitle("malicious-settled")
        #expect(fixture.webView.url?.host == server.baseURL.host)

        // 旧证书没有被恶意页面放行，重新访问仍应出现确认页。
        fixture.load(badTLS.baseURL)
        try await fixture.waitForTitle("证书无效")
        let newContinueURL = try await fixture.evaluate(
            "document.getElementById('continue').getAttribute('data-continue-url')"
        ) as? String
        #expect(newContinueURL != continueURL)
    }
}
