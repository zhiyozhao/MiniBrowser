import WebKit

/// WebKit enforces whether a popup has user activation. This adds a single-use
/// permit for each trusted activation, in a content world the page cannot access.
@MainActor
final class PopupGestureGate: NSObject, WKScriptMessageHandler {
    static let shared = PopupGestureGate()
    static let messageName = "minibrowserPopupGesture"
    private let permits = NSMapTable<WKWebView, NSNumber>.weakToStrongObjects()
    private static let script = """
    function grantPopup(event) {
        if (!event.isTrusted) return;
        webkit.messageHandlers.minibrowserPopupGesture.postMessage('input');
    }
    // mouseup represents the completed activation. Keeping this independent of
    // a wall-clock timer allows slow clicks and context-menu actions to finish.
    addEventListener('mouseup', grantPopup, true);
    addEventListener('keydown', event => {
        if (!event.repeat) grantPopup(event);
    }, true);
    // The native context menu's “open in new tab” action occurs after this
    // event, so it receives the same single activation permit.
    addEventListener('contextmenu', grantPopup, true);
    // Accessibility activation can dispatch a click without pointer/key input.
    addEventListener('click', event => {
        if (event.detail === 0) grantPopup(event);
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
        // A permit is deliberately not time limited. WebKit still applies its
        // own transient-user-activation rules; this map only ensures that our
        // delegate can create at most one tab for one activation.
        permits.setObject(NSNumber(value: true), forKey: webView)
    }

    func consume(for webView: WKWebView) -> Bool {
        guard permits.object(forKey: webView) != nil else {
            permits.removeObject(forKey: webView)
            return false
        }
        permits.removeObject(forKey: webView)
        return true
    }
}
