import WebKit

/// WebKit enforces whether a popup has user activation. This adds a single-use
/// permit for each trusted click, in a content world the page cannot access.
@MainActor
final class PopupGestureGate: NSObject, WKScriptMessageHandler {
    static let shared = PopupGestureGate()
    static let messageName = "minibrowserPopupGesture"
    private let permits = NSMapTable<WKWebView, NSNumber>.weakToStrongObjects()
    private static let script = """
    let lastInput = -Infinity;
    function grantPopup(event) {
        if (!event.isTrusted) return;
        lastInput = event.timeStamp;
        webkit.messageHandlers.minibrowserPopupGesture.postMessage('input');
    }
    addEventListener('pointerdown', grantPopup, true);
    addEventListener('keydown', event => {
        if (!event.repeat) grantPopup(event);
    }, true);
    // Accessibility activation can dispatch a click without pointer/key input.
    // Do not issue a second permit for the click following a physical input.
    addEventListener('click', event => {
        if (event.detail === 0 && event.timeStamp - lastInput > 1000) grantPopup(event);
    }, true);
    """

    static func install(in configuration: WKWebViewConfiguration) {
        let controller = configuration.userContentController
        guard !controller.userScripts.contains(where: { $0.source == script }) else { return }
        controller.add(shared, contentWorld: .defaultClient, name: messageName)
        controller.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart,
                                              forMainFrameOnly: false, in: .defaultClient))
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard let webView = message.webView else { return }
        permits.setObject(NSNumber(value: ProcessInfo.processInfo.systemUptime), forKey: webView)
    }

    func consume(for webView: WKWebView) -> Bool {
        guard let timestamp = permits.object(forKey: webView)?.doubleValue,
              ProcessInfo.processInfo.systemUptime - timestamp < 0.25 else {
            permits.removeObject(forKey: webView)
            return false
        }
        permits.removeObject(forKey: webView)
        return true
    }
}
