import AppKit
import WebKit

@MainActor
protocol JavaScriptDialogHandling {
    func showAlert(_ message: String, in webView: WKWebView, completion: @escaping () -> Void)
    func showConfirm(_ message: String, in webView: WKWebView, completion: @escaping (Bool) -> Void)
    func showPrompt(_ prompt: String, defaultText: String?, in webView: WKWebView,
                    completion: @escaping (String?) -> Void)
}

/// 最简单的 AppKit sheet；所有路径都必须结束 WebKit 的 completion。
final class AppKitJavaScriptDialogs: JavaScriptDialogHandling {
    func showAlert(_ message: String, in webView: WKWebView, completion: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "好")
        present(alert, in: webView) { _ in completion() }
    }

    func showConfirm(_ message: String, in webView: WKWebView, completion: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        present(alert, in: webView) { response in
            completion(response == .alertFirstButtonReturn)
        }
    }

    func showPrompt(_ prompt: String, defaultText: String?, in webView: WKWebView,
                    completion: @escaping (String?) -> Void) {
        let alert = NSAlert()
        alert.messageText = prompt
        let input = NSTextField(string: defaultText ?? "")
        input.frame.size.width = 240
        alert.accessoryView = input
        alert.addButton(withTitle: "好")
        alert.addButton(withTitle: "取消")
        present(alert, in: webView) { response in
            completion(response == .alertFirstButtonReturn ? input.stringValue : nil)
        }
    }

    private func present(_ alert: NSAlert, in webView: WKWebView,
                         completion: @escaping (NSApplication.ModalResponse) -> Void) {
        guard let window = webView.window else {
            completion(.cancel)
            return
        }
        alert.beginSheetModal(for: window, completionHandler: completion)
    }
}
