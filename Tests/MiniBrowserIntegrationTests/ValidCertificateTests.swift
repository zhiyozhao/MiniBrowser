import Foundation
import Security
import Testing
import WebKit
@testable import MiniBrowser

@Suite("P8 有效证书直接加载", .serialized)
@MainActor
struct ValidCertificateTests {
    @Test("本地 CA 签发的受信证书不显示错误页")
    func trustedCertificateLoadsNormally() async throws {
        let server = try await LocalHTTPSServer(title: "valid-https", trustedCA: true)
        defer { server.stop() }
        let ca = try #require(server.caCertificate())
        let session = ServerTrustSession(trustEvaluator: { trust in
            guard SecTrustSetAnchorCertificates(trust, [ca] as CFArray) == errSecSuccess,
                  SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess else { return false }
            return SecTrustEvaluateWithError(trust, nil)
        })
        let tab = BrowserTab(url: server.baseURL)
        let fixture = WebViewFixture(webView: tab.webView)
        let coordinator = WebViewRepresentable.Coordinator(
            tab: tab,
            onCreateWebView: { _, _, _ in nil },
            serverTrustSession: session,
            validTrustHandler: { trust, completion in
                // 不把测试 CA 写入系统信任；生产默认仍是 performDefaultHandling。
                completion(.useCredential, URLCredential(trust: trust))
            }
        )
        tab.webView.navigationDelegate = coordinator
        tab.webView.uiDelegate = coordinator
        defer { fixture.close() }

        fixture.load(server.baseURL)
        try await fixture.waitForTitle("valid-https")
        #expect(try await fixture.evaluate("document.body.innerText.includes('无法安全连接')") as? Bool == false)
    }
}
