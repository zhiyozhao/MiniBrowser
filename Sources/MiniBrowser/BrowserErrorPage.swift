import Foundation
import WebKit

/// WebKit 强持有 message handler，此代理避免 configuration 与 BrowserTab 形成循环。
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var delegate: WKScriptMessageHandler?

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        delegate?.userContentController(userContentController, didReceive: message)
    }
}

enum BrowserErrorPage {
    static func certificate(host: String) -> String {
        page(
            title: "证书无效",
            heading: "无法安全连接",
            message: "\(host) 的证书无效。继续后仅在本次会话中对此站点放行。",
            button: """
            <button id="continue">仍然继续</button>
            <script>
            document.getElementById('continue').addEventListener('click', () => {
                window.webkit.messageHandlers.miniBrowser.postMessage('continueCertificate');
            });
            </script>
            """
        )
    }

    private static func page(title: String, heading: String, message: String, button: String = "") -> String {
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="color-scheme" content="light dark"><title>\(escaped(title))</title>
        <style>body{font:14px -apple-system;margin:32px;line-height:1.5}button{font:inherit;padding:6px 14px}</style>
        </head><body><h1>\(escaped(heading))</h1><p>\(escaped(message))</p>\(button)</body></html>
        """
    }

    private static func escaped(_ value: String) -> String {
        value.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
