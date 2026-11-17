import Foundation
import Testing
import WebKit
@testable import MiniBrowser

@Suite("P8 会话内证书例外", .serialized)
@MainActor
struct CertificateTests {
    @Test("错误页继续后放行当前证书和源，其他端口仍需确认")
    func continueOnlyForCurrentSessionAndSite() async throws {
        let trustedServer = try await LocalHTTPSServer(title: "trusted-local")
        defer { trustedServer.stop() }
        let otherServer = try await LocalHTTPSServer(title: "other-local")
        defer { otherServer.stop() }
        let session = ServerTrustSession()
        let tab = BrowserTab(url: trustedServer.baseURL)
        let fixture = WebViewFixture(webView: tab.webView)
        let coordinator = WebViewRepresentable.Coordinator(
            tab: tab,
            onCreateWebView: { _, _, _ in nil },
            serverTrustSession: session
        )
        tab.webView.navigationDelegate = coordinator
        tab.webView.uiDelegate = coordinator
        defer { fixture.close() }

        try await fixture.waitForTitle("证书无效")
        #expect(try await fixture.evaluate("document.body.innerText.includes('仍然继续')") as? Bool == true)
        _ = try await fixture.evaluate("document.getElementById('continue').click()")
        try await fixture.waitForTitle("trusted-local")

        // 同一源在会话内保留例外，无需再次点击。
        fixture.load(trustedServer.baseURL)
        try await fixture.waitForTitle("trusted-local")

        // 端口是源的一部分，另一个本地 HTTPS 服务不会被顺便放行。
        fixture.load(otherServer.baseURL)
        try await fixture.waitForTitle("证书无效")
        #expect(try await fixture.evaluate("document.body.innerText.includes('other-local')") as? Bool == false)
    }
}
