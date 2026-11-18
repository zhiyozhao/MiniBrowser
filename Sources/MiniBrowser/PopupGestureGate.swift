import WebKit

/// WebKit enforces whether a popup has user activation. This adds a single-use
/// permit for each trusted activation, in a content world the page cannot access.
@MainActor
final class PopupGestureGate: NSObject, WKScriptMessageHandler {
    private final class Permit: NSObject {
        let activationToken: String
        var available = true

        init(activationToken: String) { self.activationToken = activationToken }
    }

    static let shared = PopupGestureGate()
    static let messageName = "minibrowserPopupGesture"
    private let permits = NSMapTable<WKWebView, Permit>.weakToStrongObjects()
    private static let script = """
    let minibrowserPointerActivation = { token: null, serial: 0 };
    function grantPopup(event, token) {
        if (!event.isTrusted) return;
        webkit.messageHandlers.minibrowserPopupGesture.postMessage(token || 'input');
    }
    // Down and up share one activation token. This permits mousedown handlers,
    // while preventing the matching mouseup from granting a second popup.
    addEventListener('mousedown', event => {
        if (!event.isTrusted) return;
        minibrowserPointerActivation.serial++;
        minibrowserPointerActivation.token = 'pointer:' + minibrowserPointerActivation.serial;
        grantPopup(event, minibrowserPointerActivation.token);
    }, true);
    addEventListener('mouseup', event => {
        if (!event.isTrusted) return;
        const token = minibrowserPointerActivation.token ||
            ('pointer:' + (++minibrowserPointerActivation.serial));
        grantPopup(event, token);
    }, true);
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
        let token = message.body as? String ?? UUID().uuidString
        if token.hasPrefix("pointer:"),
           let existing = permits.object(forKey: webView), existing.activationToken == token {
            return
        }
        permits.setObject(Permit(activationToken: token), forKey: webView)
    }

    func consume(for webView: WKWebView) -> Bool {
        guard let permit = permits.object(forKey: webView), permit.available else {
            permits.removeObject(forKey: webView)
            return false
        }
        permit.available = false
        return true
    }
}
