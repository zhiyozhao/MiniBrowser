import AppKit
import SwiftUI
import Testing
import WebKit
@testable import MiniBrowser

@Suite("弹窗统一为标签", .serialized)
@MainActor
struct PopupTests {
    @Test("加载中切走标签，后台导航和浏览状态仍能完成")
    func backgroundNavigationKeepsDelegate() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        let delegate = fixture.main.webView.navigationDelegate
        let parent = fixture.main.webView.superview
        fixture.main.webView.load(URLRequest(url: fixture.server.baseURL.appendingPathComponent("child")))
        fixture.model.selectedID = fixture.other.id
        try await waitUntil("background navigation finished") {
            fixture.main.title == "child-ready" && !fixture.main.isLoading
        }
        #expect(fixture.main.webView.navigationDelegate === delegate)
        #expect(fixture.main.webView.superview === parent)
        fixture.model.selectedID = fixture.main.id
        #expect(!fixture.main.webView.isHiddenOrHasHiddenAncestor)
        fixture.assertOneWindow()
    }

    @Test("关闭窗口后弹窗工厂不循环持有窗口模型")
    func popupFactoryDoesNotRetainModel() {
        var model: BrowserWindowModel? = BrowserWindowModel()
        let models = NSHashTable<BrowserWindowModel>.weakObjects()
        models.add(model!)
        let opener = model!.tabs[0]
        _ = model!.newPopupTab(configuration: WebViewConfigurationFactory.make(), openerID: opener.id, select: true)
        for tab in model!.tabs { model!.closeTab(tab.id) }
        model = nil
        #expect(models.allObjects.isEmpty)
    }

    @Test("window.open 与带尺寸弹窗均插在 opener 右侧")
    func windowOpenAndSizedPopupBecomeAdjacentTabs() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        for features in ["", "width=140,height=180,left=0,top=0,popup=yes"] {
            let popup = try await fixture.open("window.child = window.open('/child', '_blank', '\(features)')")
            #expect(fixture.model.tabs.map(\.id) == [fixture.main.id, popup.id, fixture.other.id])
            #expect(fixture.model.selectedID == popup.id)
            #expect(popup.webView.configuration.websiteDataStore === fixture.main.webView.configuration.websiteDataStore)
            #expect(try await fixture.main.webView.evaluateJavaScript("child !== null") as? Bool == true)
            #expect(try await popup.webView.evaluateJavaScript("window.opener !== null") as? Bool == true)
            fixture.assertOneWindow()
            fixture.model.closeTab(popup.id)
            #expect(fixture.model.selectedID == fixture.main.id)
        }
    }

    @Test("target=_blank 链接在新标签加载且不额外发请求")
    func targetBlankLinkBecomesTab() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        let popup = try await fixture.open("document.getElementById('link').click()")
        #expect(fixture.model.tabs[1] === popup)
        #expect(fixture.server.requests.filter { $0.path == "/child" }.count == 1)
        fixture.assertOneWindow()
    }

    @Test("target=_blank POST 表单完整保留请求体")
    func targetBlankPreservesPOST() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        _ = try await fixture.open("document.getElementById('form').submit()")
        let posts = fixture.server.requests.filter { $0.path == "/child" }
        #expect(posts.count == 1)
        #expect(posts.first?.method == "POST")
        #expect(posts.first.map { String(decoding: $0.body, as: UTF8.self) } == "token=local%2Bonly&payload=hello+world")
        fixture.assertOneWindow()
    }

    @Test("OAuth 跨源重定向回传 postMessage 后关闭并返回 opener")
    func windowOpenOpenerAndClose() async throws {
        let callback = try LocalHTTPServer { _ in .init("""
        <html><title>OAuth callback</title><script>
        window.opener.postMessage('oauth-done', '*'); window.close();
        </script></html>
        """) }
        try await callback.start()
        defer { callback.stop() }
        let fixture = try await PopupFixture.make(redirect: callback.baseURL)
        defer { fixture.close() }
        _ = try await fixture.main.webView.evaluateJavaScript("window.child = window.open('/oauth', '_blank'); void(0)")
        try await waitUntil("OAuth result and popup removal") {
            fixture.main.title == "oauth-done" && fixture.model.tabs.count == 2
        }
        #expect(fixture.model.selectedID == fixture.main.id)
        #expect(try await fixture.main.webView.evaluateJavaScript("child.closed") as? Bool == true)
        fixture.assertOneWindow()
    }

    @Test("about:blank document.write 和立即 window.close 均有效")
    func blankWriteAndImmediateClose() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        _ = try await fixture.main.webView.evaluateJavaScript("""
        window.child=window.open('about:blank','_blank');
        child.document.write('<title>written</title><body>body preserved</body>'); child.document.close();
        """)
        try await waitUntil("document.write popup") { fixture.model.tabs.count == 3 }
        let popup = try #require(fixture.model.tabs.first { $0.openerTabID == fixture.main.id })
        #expect(try await popup.webView.evaluateJavaScript("document.body.textContent") as? String == "body preserved")
        _ = try await fixture.main.webView.evaluateJavaScript("child.close()")
        try await waitUntil("popup removed") { fixture.model.tabs.count == 2 }
        _ = try await fixture.main.webView.evaluateJavaScript("window.open('about:blank','_blank').close()")
        try await waitUntil("immediate popup removed") { fixture.model.tabs.count == 2 }
        #expect(fixture.model.selectedID == fixture.main.id)
        fixture.assertOneWindow()
    }

    @Test("嵌套弹窗关闭返回直接 opener，opener 已关时安全回退")
    func nestedPopupAndMissingOpener() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        let first = try await fixture.open("window.open('/child','_blank')")
        _ = try await first.webView.evaluateJavaScript("window.open('/child','_blank'); void(0)")
        try await waitUntil("nested tab") { fixture.model.tabs.count == 4 }
        let nested = try #require(fixture.model.tabs.first { $0.openerTabID == first.id })
        #expect(fixture.model.tabs[2] === nested)
        _ = try await nested.webView.evaluateJavaScript("window.close()")
        try await waitUntil("nested close") { fixture.model.tabs.count == 3 }
        #expect(fixture.model.selectedID == first.id)
        fixture.model.closeTab(fixture.main.id)
        _ = try await first.webView.evaluateJavaScript("window.close()")
        try await waitUntil("close with missing opener") { fixture.model.tabs.count == 1 }
        #expect(fixture.model.selectedID == fixture.other.id)
        fixture.assertOneWindow()
    }

    @Test("⌘普通链接走后台标签路径，保留原页；⌘空白目标策略一致")
    func commandClickOpensBackgroundTab() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        let action = CommandLinkAction(url: fixture.server.baseURL.appendingPathComponent("child"))
        let delegate = try #require(fixture.main.webView.navigationDelegate as? WebViewRepresentable.Coordinator)
        var policy: WKNavigationActionPolicy?
        delegate.webView(fixture.main.webView, decidePolicyFor: action) { policy = $0 }
        #expect(policy == .cancel)
        try await waitUntil("command link loaded") { fixture.model.tabs.count == 3 && fixture.model.tabs[1].title == "child-ready" }
        #expect(fixture.model.selectedID == fixture.main.id)
        #expect(fixture.main.webView.url?.absoluteString == fixture.server.baseURL.absoluteString + "/")
        #expect(PopupTabPolicy.selectsNewTab(for: [.command]) == false)
        #expect(PopupTabPolicy.selectsNewTab(for: []) == true)
        fixture.assertOneWindow()
    }

    @Test("自动弹窗保持 WebKit 默认策略，网页始终只有一个浏览器窗口")
    func automaticPopupMatchesWebKitDefaultAndOneWindow() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        let rawTab = BrowserTab(loadsInitialContent: false)
        let control = DefaultPopupDelegate()
        rawTab.webView.uiDelegate = control
        // Reuse this one test window for the unmodified WebKit control.
        let content = fixture.window.contentViewController
        fixture.window.contentViewController = nil
        fixture.window.contentView = rawTab.webView
        rawTab.webView.loadHTMLString(Self.automaticPopupHTML, baseURL: fixture.server.baseURL)
        try await waitUntil("control evaluated automatic popup") { rawTab.webView.title == "auto-done" }
        let expected = try await rawTab.webView.evaluateJavaScript("window.autoOpened") as? Bool
        rawTab.webView.stopLoading()
        fixture.window.contentViewController = content
        fixture.main.webView.loadHTMLString(Self.automaticPopupHTML, baseURL: fixture.server.baseURL)
        try await waitUntil("product evaluated automatic popup") { fixture.main.title == "auto-done" }
        let actual = try await fixture.main.webView.evaluateJavaScript("window.autoOpened") as? Bool
        #expect(actual == expected)
        #expect(fixture.main.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically == rawTab.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically)
        fixture.assertOneWindow()
    }

    @Test("全部弹窗场景完成后仍只有一个浏览器窗口")
    func popupScenariosDoNotCreateWindows() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }

        _ = try await fixture.open("window.open('/child', '_blank', 'width=420,height=500')")
        fixture.model.closeTab(fixture.model.tabs[1].id)
        _ = try await fixture.open("document.getElementById('link').click()")
        fixture.model.closeTab(fixture.model.tabs[1].id)
        _ = try await fixture.open("document.getElementById('form').submit()")
        fixture.model.closeTab(fixture.model.tabs[1].id)
        fixture.assertOneWindow()
    }

    private static let automaticPopupHTML = """
    <html><title>auto-start</title><script>
    setTimeout(() => { window.autoOpened=window.open('about:blank','_blank')!==null; document.title='auto-done'; }, 0);
    </script></html>
    """
}

@MainActor
private final class PopupFixture {
    let server: LocalHTTPServer
    let main: BrowserTab
    let other: BrowserTab
    let model: BrowserWindowModel
    let window: NSWindow

    static func make(redirect: URL? = nil) async throws -> PopupFixture {
        let server = try LocalHTTPServer { request in
            if request.path == "/oauth", let redirect {
                return .init("", status: "302 Found", headers: ["Location": redirect.absoluteString])
            }
            if request.path == "/child" { return .init("<html><title>child-ready</title><body>child</body></html>") }
            return .init("""
            <html><title>main-ready</title><body>
            <a id="link" href="/child" target="_blank">open</a>
            <form id="form" method="post" action="/child" target="_blank">
            <input name="token" value="local+only"><input name="payload" value="hello world"></form>
            <script>addEventListener('message', e => document.title=e.data);</script></body></html>
            """)
        }
        try await server.start()
        let fixture = PopupFixture(server: server)
        do {
            try await waitUntil("main ready") { fixture.main.title == "main-ready" }
        } catch { fixture.close(); throw error }
        return fixture
    }

    init(server: LocalHTTPServer) {
        self.server = server
        main = BrowserTab(url: server.baseURL)
        model = BrowserWindowModel(initialTab: main)
        other = model.newTab()
        model.selectedID = main.id
        window = NSWindow(contentRect: NSRect(x: -5000, y: -5000, width: 1000, height: 700),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if let screen = NSScreen.screens.first(where: { $0.localizedName == "Mi Monitor" }) {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 80, y: screen.visibleFrame.minY + 80))
        }
        let hosting = NSHostingController(rootView: BrowserView(model: model))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.orderFront(nil)
        window.setContentSize(NSSize(width: 1000, height: 700))
    }

    func open(_ script: String) async throws -> BrowserTab {
        model.selectedID = main.id
        _ = try await main.webView.evaluateJavaScript(script + "; void(0)")
        try await waitUntil("popup ready") { model.tabs.contains { $0.openerTabID == main.id && $0.title == "child-ready" } }
        return try #require(model.tabs.first { $0.openerTabID == main.id })
    }

    func assertOneWindow(sourceLocation: SourceLocation = #_sourceLocation) {
        let windows = NSApp.windows.filter { $0.isVisible && $0.styleMask.contains(.titled) }
        let browserWindows = windows.filter { candidate in
            model.tabs.contains { $0.webView.window === candidate }
        }
        #expect(browserWindows.count == 1, sourceLocation: sourceLocation)
        #expect(browserWindows.first === self.window, sourceLocation: sourceLocation)
        #expect(model.tabs.allSatisfy { $0.webView.window === self.window }, sourceLocation: sourceLocation)
    }

    func close() {
        for tab in model.tabs { model.closeTab(tab.id) }
        window.contentViewController = nil
        window.close()
        server.stop()
    }
}

/// Exercise the public navigation-delegate path without global input synthesis.
private final class CommandLinkAction: WKNavigationAction {
    let url: URL
    init(url: URL) { self.url = url; super.init() }
    override var request: URLRequest { URLRequest(url: url) }
    override var navigationType: WKNavigationType { .linkActivated }
    override var modifierFlags: NSEvent.ModifierFlags { .command }
    override var targetFrame: WKFrameInfo? { WKFrameInfo() }
}

@MainActor
private final class DefaultPopupDelegate: NSObject, WKUIDelegate {
    var children: [WKWebView] = []
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        let child = WKWebView(frame: .zero, configuration: configuration)
        children.append(child)
        return child
    }
}
