import AppKit
import MiniBrowserCore
import WebKit

enum PopupTabPolicy {
    static func selectsNewTab(for modifiers: NSEvent.ModifierFlags) -> Bool {
        !modifiers.contains(.command)
    }
}

/// Owns tabs and delegates for the whole lifetime of the window, including
/// background navigations and popups that close before SwiftUI updates.
@MainActor
final class BrowserWindowModel: ObservableObject {
    @Published private var state: BrowserWindowState
    private var tabsByID: [BrowserTab.ID: BrowserTab]
    private var coordinators: [BrowserTab.ID: WebViewRepresentable.Coordinator] = [:]
    weak var webViewHost: WebViewStackRepresentable.HostView?

    var tabs: [BrowserTab] { state.tabIDs.compactMap { tabsByID[$0] } }
    var selectedID: BrowserTab.ID? {
        get { state.selectedID }
        set {
            guard newValue != state.selectedID else { return }
            if let newValue, tabsByID[newValue] == nil { return }
            // Present synchronously in the tab action; SwiftUI updates only chrome.
            webViewHost?.select(newValue)
            state.selectedID = newValue
        }
    }
    var selectedTab: BrowserTab? { selectedID.flatMap { tabsByID[$0] } }

    init(initialTab: BrowserTab? = nil) {
        let tab = initialTab ?? BrowserTab()
        tabsByID = [tab.id: tab]
        state = BrowserWindowState(initialTabID: tab.id)
        attachDelegate(to: tab)
    }

    @discardableResult
    func newTab(url: URL? = nil) -> BrowserTab {
        let tab = BrowserTab(url: url)
        tabsByID[tab.id] = tab
        attachDelegate(to: tab)
        state.newTab(id: tab.id)
        return tab
    }

    private func attachDelegate(to tab: BrowserTab) {
        let coordinator = WebViewRepresentable.Coordinator(
            tab: tab,
            onCreateWebView: { [weak self, weak tab] configuration, action, _ in
                guard let self, let tab else { return nil }
                guard PopupGestureGate.shared.consume(for: tab.webView) else { return nil }
                return self.newPopupTab(configuration: configuration, openerID: tab.id,
                    select: PopupTabPolicy.selectsNewTab(for: action.modifierFlags))?.webView
            },
            isTabSelected: { [weak self, weak tab] in
                guard let self, let tab else { return false }
                return self.selectedID == tab.id
            },
            onPopupClosed: { [weak self] id, openerID in
                guard openerID != nil else { return }
                self?.closeTab(id)
            }
        )
        coordinators[tab.id] = coordinator
        tab.webView.navigationDelegate = coordinator
        tab.webView.uiDelegate = coordinator
        tab.applySiteZoom()
    }

    @discardableResult
    func newPopupTab(configuration: WKWebViewConfiguration, openerID: BrowserTab.ID,
                     select: Bool) -> BrowserTab? {
        guard tabsByID[openerID] != nil else { return nil }
        let tab = BrowserTab(configuration: configuration, loadsInitialContent: false)
        tab.openerTabID = openerID
        tabsByID[tab.id] = tab
        // Install before returning to WebKit, even for immediate window.close().
        attachDelegate(to: tab)
        state.insertTab(id: tab.id, after: openerID, select: select)
        webViewHost?.sync(model: self)
        return tab
    }

    func closeTab(_ id: BrowserTab.ID) {
        guard let tab = tabsByID[id] else { return }
        if selectedID == id, let openerID = tab.openerTabID, tabsByID[openerID] != nil {
            selectedID = openerID
        }
        tab.webView.stopLoading()
        tab.webView.navigationDelegate = nil
        tab.webView.uiDelegate = nil
        tab.webView.removeFromSuperview()
        state.closeTab(id: id)
        tabsByID[id] = nil
        coordinators[id] = nil
        webViewHost?.sync(model: self)
    }
}
