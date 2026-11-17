import Foundation
import Testing
import WebKit
@testable import MiniBrowser

@Suite("P1 弹窗与 opener", .serialized)
@MainActor
struct PopupTests {
    @Test("window.open 返回真实窗口，opener 回传后 window.close 关闭弹窗")
    func windowOpenOpenerAndClose() async throws {
        let server = try LocalHTTPServer { request in
            switch request.path {
            case "/":
                return .init("""
                <html><head><title>main-ready</title></head><body><script>
                window.addEventListener('message', event => { document.title = event.data; });
                function openPopup() {
                    const popup = window.open('/popup', 'oauth', 'width=420,height=500');
                    window.popupReturned = popup !== null;
                }
                </script></body></html>
                """)
            case "/popup":
                return .init("""
                <html><head><title>popup-ready</title></head><body><script>
                if (!window.opener) { document.title = 'opener-missing'; }
                else {
                    window.opener.postMessage('oauth-done', '*');
                    window.close();
                }
                </script></body></html>
                """)
            default:
                return .init("not found", status: "404 Not Found", contentType: "text/plain")
            }
        }
        try await server.start()
        defer { server.stop() }

        let mainTab = BrowserTab(url: server.baseURL)
        let mainFixture = WebViewFixture(webView: mainTab.webView)
        var popupFixture: WebViewFixture?
        var popupCoordinator: WebViewRepresentable.Coordinator?
        var sharedDataStore = false
        let mainCoordinator = WebViewRepresentable.Coordinator(
            tab: mainTab,
            onCreateWebView: { configuration, _, _ in
                sharedDataStore = configuration.websiteDataStore === mainTab.webView.configuration.websiteDataStore
                let popupTab = BrowserTab(configuration: configuration, loadsInitialContent: false)
                let fixture = WebViewFixture(webView: popupTab.webView)
                let coordinator = WebViewRepresentable.Coordinator(
                    tab: popupTab,
                    onCreateWebView: { _, _, _ in nil }
                )
                popupTab.webView.navigationDelegate = coordinator
                popupTab.webView.uiDelegate = coordinator
                popupFixture = fixture
                popupCoordinator = coordinator
                return popupTab.webView
            }
        )
        mainTab.webView.navigationDelegate = mainCoordinator
        mainTab.webView.uiDelegate = mainCoordinator
        defer {
            _ = popupCoordinator
            popupCoordinator = nil
            popupFixture?.close()
            mainFixture.close()
        }

        try await mainFixture.waitForTitle("main-ready")
        _ = try await mainFixture.evaluate("openPopup()")
        try await waitUntil("window.open returned a window") {
            try await mainFixture.evaluate("window.popupReturned") as? Bool == true
        }
        try await mainFixture.waitForTitle("oauth-done")
        try await waitUntil("popup closed") { popupFixture?.window.isVisible == false }
        #expect(sharedDataStore)
    }

    @Test("target=_blank 保留 POST 请求体并在小窗口渲染")
    func targetBlankPreservesPOST() async throws {
        let server = try LocalHTTPServer { request in
            switch request.path {
            case "/":
                return .init("""
                <html><head><title>form-ready</title></head><body>
                <form id="payment" method="post" action="/target" target="_blank">
                <input name="token" value="local-only"></form></body></html>
                """)
            case "/target":
                return .init("<html><head><title>target-ready</title></head><body>target</body></html>")
            default:
                return .init("not found", status: "404 Not Found", contentType: "text/plain")
            }
        }
        try await server.start()
        defer { server.stop() }

        let mainTab = BrowserTab(url: server.baseURL)
        let mainFixture = WebViewFixture(webView: mainTab.webView)
        var popupFixture: WebViewFixture?
        var popupCoordinator: WebViewRepresentable.Coordinator?
        let mainCoordinator = WebViewRepresentable.Coordinator(
            tab: mainTab,
            onCreateWebView: { configuration, _, _ in
                let popupTab = BrowserTab(configuration: configuration, loadsInitialContent: false)
                let fixture = WebViewFixture(webView: popupTab.webView)
                let coordinator = WebViewRepresentable.Coordinator(
                    tab: popupTab,
                    onCreateWebView: { _, _, _ in nil }
                )
                popupTab.webView.navigationDelegate = coordinator
                popupTab.webView.uiDelegate = coordinator
                popupFixture = fixture
                popupCoordinator = coordinator
                return popupTab.webView
            }
        )
        mainTab.webView.navigationDelegate = mainCoordinator
        mainTab.webView.uiDelegate = mainCoordinator
        defer {
            _ = popupCoordinator
            popupCoordinator = nil
            popupFixture?.close()
            mainFixture.close()
        }

        try await mainFixture.waitForTitle("form-ready")
        _ = try await mainFixture.evaluate("document.getElementById('payment').submit()")
        try await waitUntil("target popup loaded") { popupFixture?.webView.title == "target-ready" }
        let post = try #require(server.requests.first { $0.path == "/target" })
        #expect(post.method == "POST")
        #expect(String(decoding: post.body, as: UTF8.self) == "token=local-only")
        #expect(popupFixture?.window.frame.width == 520)
    }
}
