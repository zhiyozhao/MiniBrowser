import Foundation
import Testing
import WebKit
@testable import MiniBrowser

@MainActor
private final class DialogStub: JavaScriptDialogHandling {
    var messages: [String] = []
    var receivedDefaultText: String?
    var confirmResult = true
    var promptResult: String? = "local-input"

    func showAlert(_ message: String, in webView: WKWebView, completion: @escaping () -> Void) {
        messages.append(message)
        completion()
    }

    func showConfirm(_ message: String, in webView: WKWebView, completion: @escaping (Bool) -> Void) {
        messages.append(message)
        completion(confirmResult)
    }

    func showPrompt(_ prompt: String, defaultText: String?, in webView: WKWebView,
                    completion: @escaping (String?) -> Void) {
        messages.append(prompt)
        receivedDefaultText = defaultText
        completion(promptResult)
    }
}

@Suite("P3 JavaScript 原生对话框", .serialized)
@MainActor
struct JavaScriptDialogTests {
    @Test("alert、confirm、prompt 将原生结果交还页面")
    func dialogsReturnResults() async throws {
        let server = try LocalHTTPServer { _ in
            .init("""
            <html><head><title>page-ready</title></head><body><script>
            function runDialogs() {
                alert('local-alert');
                window.confirmResult = confirm('local-confirm');
                window.promptResult = prompt('local-prompt', 'default-local');
                document.title = 'dialogs-done';
            }
            </script></body></html>
            """)
        }
        try await server.start()
        defer { server.stop() }
        let tab = BrowserTab(url: server.baseURL)
        let fixture = WebViewFixture(webView: tab.webView)
        let dialogs = DialogStub()
        let coordinator = WebViewRepresentable.Coordinator(
            tab: tab,
            onCreateWebView: { _, _, _ in nil },
            dialogs: dialogs
        )
        tab.webView.navigationDelegate = coordinator
        tab.webView.uiDelegate = coordinator
        defer { fixture.close() }

        try await fixture.waitForTitle("page-ready")
        _ = try await fixture.evaluate("runDialogs()")
        try await fixture.waitForTitle("dialogs-done")
        #expect(dialogs.messages == ["local-alert", "local-confirm", "local-prompt"])
        #expect(dialogs.receivedDefaultText == "default-local")
        #expect(try await fixture.evaluate("window.confirmResult") as? Bool == true)
        #expect(try await fixture.evaluate("window.promptResult") as? String == "local-input")
    }

    @Test("取消 confirm 和 prompt 返回 false 与 null")
    func cancelledDialogs() async throws {
        let server = try LocalHTTPServer { _ in
            .init("""
            <html><head><title>cancel-ready</title></head><body><script>
            function cancelDialogs() {
                window.confirmResult = confirm('cancel-confirm');
                window.promptResult = prompt('cancel-prompt');
                document.title = 'cancel-done';
            }
            </script></body></html>
            """)
        }
        try await server.start()
        defer { server.stop() }
        let tab = BrowserTab(url: server.baseURL)
        let fixture = WebViewFixture(webView: tab.webView)
        let dialogs = DialogStub()
        dialogs.confirmResult = false
        dialogs.promptResult = nil
        let coordinator = WebViewRepresentable.Coordinator(
            tab: tab,
            onCreateWebView: { _, _, _ in nil },
            dialogs: dialogs
        )
        tab.webView.navigationDelegate = coordinator
        tab.webView.uiDelegate = coordinator
        defer { fixture.close() }

        try await fixture.waitForTitle("cancel-ready")
        _ = try await fixture.evaluate("cancelDialogs()")
        try await fixture.waitForTitle("cancel-done")
        #expect(try await fixture.evaluate("window.confirmResult") as? Bool == false)
        #expect(try await fixture.evaluate("window.promptResult === null") as? Bool == true)
    }

    @Test("隐藏标签的 alert、confirm、prompt 静默取消")
    func hiddenTabDialogsAreCancelled() {
        let tab = BrowserTab(loadsInitialContent: false)
        let dialogs = DialogStub()
        let coordinator = WebViewRepresentable.Coordinator(
            tab: tab,
            onCreateWebView: { _, _, _ in nil },
            dialogs: dialogs,
            isTabSelected: { false }
        )
        var alertCompleted = false
        var confirmResult: Bool?
        var promptResult: String??
        coordinator.webView(tab.webView, runJavaScriptAlertPanelWithMessage: "hidden-alert",
                            initiatedByFrame: WKFrameInfo()) { alertCompleted = true }
        coordinator.webView(tab.webView, runJavaScriptConfirmPanelWithMessage: "hidden-confirm",
                            initiatedByFrame: WKFrameInfo()) { confirmResult = $0 }
        coordinator.webView(tab.webView, runJavaScriptTextInputPanelWithPrompt: "hidden-prompt",
                            defaultText: "default", initiatedByFrame: WKFrameInfo()) { promptResult = $0 }
        #expect(alertCompleted)
        #expect(confirmResult == false)
        #expect(promptResult == .some(nil))
        #expect(dialogs.messages.isEmpty)
    }
}
