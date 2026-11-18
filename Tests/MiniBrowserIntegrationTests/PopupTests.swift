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

    @Test("LRU 只挂三个标签，重新挂载保留 WebView 与委托")
    func mountCacheRetainsObjectsAndDelegates() {
        let model = BrowserWindowModel()
        let host = WebViewStackRepresentable.HostView(maxMountedTabs: 3)
        model.webViewHost = host
        host.sync(model: model)
        let first = model.tabs[0]
        let webView = first.webView
        let delegate = webView.navigationDelegate
        for _ in 0..<6 {
            model.newTab()
            host.sync(model: model)
            #expect(host.subviews.count <= 3)
        }
        #expect(webView.superview == nil)
        model.selectedID = first.id
        #expect(first.webView === webView)
        #expect(first.webView.navigationDelegate === delegate)
        #expect(first.webView.superview === host)
        #expect(!first.webView.isHidden)
        #expect(host.subviews.count == 3)
        for tab in model.tabs { model.closeTab(tab.id) }
        #expect(host.subviews.isEmpty)
    }

    @Test("后台标签实际调用 JS 对话框时静默结束")
    func backgroundDialogsDoNotShowSheets() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        fixture.model.selectedID = fixture.other.id
        _ = try await fixture.main.webView.evaluateJavaScript("""
        alert('hidden'); window.hiddenConfirm=confirm('hidden');
        window.hiddenPrompt=prompt('hidden'); document.title='hidden-dialogs-done';
        """)
        try await waitUntil("hidden dialogs completed") { fixture.main.title == "hidden-dialogs-done" }
        #expect(try await fixture.main.webView.evaluateJavaScript("hiddenConfirm === false && hiddenPrompt === null") as? Bool == true)
        #expect(fixture.window.attachedSheet == nil)
        #expect(fixture.model.selectedID == fixture.other.id)
        fixture.assertOneWindow()
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

    @Test("弹窗附件被取消后自动关闭空标签")
    func popupAttachmentClosesTab() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        _ = try await evaluateUserGesture(fixture.main.webView, "window.open('/attachment', '_blank'); void(0)")
        try await waitUntil("attachment popup closed") { fixture.model.tabs.count == 2 }
        #expect(fixture.model.selectedID == fixture.main.id)
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
        _ = try await evaluateUserGesture(fixture.main.webView, "window.child = window.open('/oauth', '_blank'); void(0)")
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
        _ = try await evaluateUserGesture(fixture.main.webView, """
        window.child=window.open('about:blank','_blank');
        child.document.write('<title>written</title><body>body preserved</body>'); child.document.close();
        """)
        try await waitUntil("document.write popup") { fixture.model.tabs.count == 3 }
        let popup = try #require(fixture.model.tabs.first { $0.openerTabID == fixture.main.id })
        #expect(try await popup.webView.evaluateJavaScript("document.body.textContent") as? String == "body preserved")
        _ = try await fixture.main.webView.evaluateJavaScript("child.close()")
        try await waitUntil("popup removed") { fixture.model.tabs.count == 2 }
        _ = try await evaluateUserGesture(fixture.main.webView, "window.open('about:blank','_blank').close()")
        try await waitUntil("immediate popup removed") { fixture.model.tabs.count == 2 }
        #expect(fixture.model.selectedID == fixture.main.id)
        fixture.assertOneWindow()
    }

    @Test("嵌套弹窗关闭返回直接 opener，opener 已关时安全回退")
    func nestedPopupAndMissingOpener() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        let first = try await fixture.open("window.open('/child','_blank')")
        _ = try await evaluateUserGesture(first.webView, "window.open('/child','_blank'); void(0)")
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
        _ = try await evaluateUserGesture(fixture.main.webView, "void(0)")
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
        fixture.main.webView.loadHTMLString(Self.popupBurstHTML, baseURL: fixture.server.baseURL)
        try await waitUntil("automatic popup burst completed") { fixture.main.title == "timer-done" }
        #expect(try await fixture.main.webView.evaluateJavaScript("window.timerOpened") as? Int == 0)
        #expect(fixture.model.tabs.count == 2)
        #expect(fixture.main.webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically == false)
        _ = try await evaluateUserGesture(fixture.main.webView, "document.getElementById('burst').click()")
        try await waitUntil("user popup burst completed") { fixture.main.title == "burst-done" }
        #expect(try await fixture.main.webView.evaluateJavaScript("window.userOpened") as? Int == 1)
        #expect(fixture.model.tabs.count == 3)
        fixture.assertOneWindow()
    }

    @Test("慢点击和点击后 400ms 的弹窗仍能打开")
    func delayedActivationStillOpensPopup() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        _ = try await fixture.main.webView.callAsyncJavaScript(
            "webkit.messageHandlers.minibrowserPopupGesture.postMessage('mouse-up');",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        try await Task.sleep(for: .milliseconds(400))
        _ = try await fixture.main.webView.evaluateJavaScript("window.open('/child', '_blank'); void(0)")
        try await waitUntil("delayed popup ready") { fixture.model.tabs.contains { $0.openerTabID == fixture.main.id && $0.title == "child-ready" } }
        fixture.assertOneWindow()
    }

    @Test("mousedown 触发的弹窗能打开")
    func mousedownActivationOpensPopup() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        _ = try await fixture.main.webView.callAsyncJavaScript(
            "webkit.messageHandlers.minibrowserPopupGesture.postMessage('pointer:test-down');",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        _ = try await fixture.main.webView.evaluateJavaScript("window.open('/child', '_blank'); void(0)")
        try await waitUntil("mousedown popup ready") { fixture.model.tabs.contains { $0.openerTabID == fixture.main.id && $0.title == "child-ready" } }
        fixture.assertOneWindow()
    }

    @Test("同一次点击的 mousedown 和 mouseup 最多打开一个标签")
    func downAndUpShareOneActivation() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        for _ in 0..<2 {
            _ = try await fixture.main.webView.callAsyncJavaScript(
                "webkit.messageHandlers.minibrowserPopupGesture.postMessage('pointer:same-click');",
                arguments: [:], in: nil, contentWorld: .defaultClient)
            _ = try await fixture.main.webView.evaluateJavaScript("window.open('/child', '_blank'); void(0)")
        }
        try await waitUntil("down/up popup") { fixture.model.tabs.count == 3 }
        #expect(fixture.model.tabs.filter { $0.openerTabID == fixture.main.id }.count == 1)
        fixture.assertOneWindow()
    }

    @Test("按住链接 400ms 后松开仍能打开弹窗")
    func heldActivationOpensAfterMouseUp() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        try await Task.sleep(for: .milliseconds(400))
        _ = try await fixture.main.webView.callAsyncJavaScript(
            "webkit.messageHandlers.minibrowserPopupGesture.postMessage('mouse-up');",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        _ = try await fixture.main.webView.evaluateJavaScript("window.open('/child', '_blank'); void(0)")
        try await waitUntil("held-click popup ready") { fixture.model.tabs.contains { $0.openerTabID == fixture.main.id && $0.title == "child-ready" } }
        fixture.assertOneWindow()
    }

    @Test("右键菜单在新标签打开使用一次用户激活")
    func contextMenuOpenInNewTabUsesActivationPermit() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        _ = try await fixture.main.webView.callAsyncJavaScript(
            "webkit.messageHandlers.minibrowserPopupGesture.postMessage('contextmenu');",
            arguments: [:], in: nil, contentWorld: .defaultClient)
        _ = try await fixture.main.webView.evaluateJavaScript("window.open('/child', '_blank'); void(0)")
        try await waitUntil("context-menu popup ready") { fixture.model.tabs.contains { $0.openerTabID == fixture.main.id && $0.title == "child-ready" } }
        fixture.assertOneWindow()
    }

    @Test("新建空标签把焦点留在地址栏")
    func blankTabFocusesAddressField() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        _ = fixture.model.newTab()
        try await waitUntil("address field focus") {
            let responderName = fixture.window.firstResponder.map { String(describing: type(of: $0)) } ?? ""
            return responderName.contains("FieldEditor") || fixture.window.firstResponder is NSTextField
        }
        let responderName = fixture.window.firstResponder.map { String(describing: type(of: $0)) } ?? ""
        #expect(responderName.contains("FieldEditor") || fixture.window.firstResponder is NSTextField)
        #expect(fixture.window.firstResponder !== fixture.model.selectedTab?.webView)
        fixture.assertOneWindow()
    }

    @Test("关闭非当前弹窗不改变选中标签")
    func closingBackgroundPopupKeepsSelection() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        let popup = try await fixture.open("window.open('/child', '_blank')")
        fixture.model.selectedID = fixture.other.id
        fixture.model.closeTab(popup.id)
        #expect(fixture.model.selectedID == fixture.other.id)
        fixture.assertOneWindow()
    }

    @Test("切换和 OAuth 弹窗关闭后焦点落在当前 WebView")
    func switchingAndPopupCloseRestoreWebViewFocus() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        fixture.other.webView.load(URLRequest(url: fixture.server.baseURL.appendingPathComponent("child")))
        try await waitUntil("other tab loaded") { fixture.other.title == "child-ready" && !fixture.other.isLoading }
        fixture.model.selectedID = fixture.other.id
        #expect(fixture.window.firstResponder === fixture.other.webView)
        let popup = try await fixture.open("window.open('/child', '_blank')")
        try await waitUntil("popup WebView focus") { fixture.window.firstResponder === popup.webView }
        _ = try await popup.webView.evaluateJavaScript("window.close()")
        try await waitUntil("popup closed") { fixture.model.tabs.count == 2 }
        #expect(fixture.model.selectedID == fixture.main.id)
        #expect(fixture.window.firstResponder === fixture.main.webView)
        fixture.assertOneWindow()
    }

    @Test("关闭空白标签后回到已加载页面并恢复页面焦点")
    func closingBlankTabRestoresLoadedWebViewFocus() async throws {
        let fixture = try await PopupFixture.make()
        defer { fixture.close() }
        fixture.model.selectedID = fixture.other.id
        fixture.model.closeTab(fixture.other.id)
        try await waitUntil("loaded tab focus") { fixture.window.firstResponder === fixture.main.webView }
        #expect(fixture.model.selectedID == fixture.main.id)
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

    private static let popupBurstHTML = """
    <html><title>burst-start</title><body><button id="burst" onclick="
    window.userOpened=0; for (let i=0;i<50;i++) { if (window.open('/child?user='+i, '_blank')) window.userOpened++; }
    document.title='burst-done';">burst</button><script>
    setTimeout(() => { window.timerOpened=0; for (let i=0;i<20;i++) { if (window.open('/child?timer='+i, '_blank')) window.timerOpened++; } document.title='timer-done'; }, 0);
    </script></body></html>
    """
}
@MainActor
private final class PopupFixture {
    let server: LocalHTTPServer
    let main: BrowserTab
    let other: BrowserTab
    let model: BrowserWindowModel
    let window: NSWindow
    let delegate: AppDelegate

    static func make(redirect: URL? = nil) async throws -> PopupFixture {
        let server = try LocalHTTPServer { request in
            if request.path == "/oauth", let redirect {
                return .init("", status: "302 Found", headers: ["Location": redirect.absoluteString])
            }
            if request.path.hasPrefix("/child") { return .init("<html><title>child-ready</title><body>child</body></html>") }
            if request.path == "/attachment" {
                return .init(data: Data("download".utf8), headers: ["Content-Disposition": "attachment; filename=popup.txt"])
            }
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
        _ = NSApplication.shared
        delegate = AppDelegate()
        delegate.applicationDidFinishLaunching(Notification(name: NSApplication.didFinishLaunchingNotification))
        let controller = delegate.windowControllers[0]
        model = controller.model
        window = controller.window!
        main = model.selectedTab!
        main.webView.load(URLRequest(url: server.baseURL))
        other = model.newTab()
        model.selectedID = main.id
        window.setContentSize(NSSize(width: 1000, height: 700))
    }

    func open(_ script: String) async throws -> BrowserTab {
        model.selectedID = main.id
        _ = try await evaluateUserGesture(main.webView, script + "; void(0)")
        try await waitUntil("popup ready") { model.tabs.contains { $0.openerTabID == main.id && $0.title == "child-ready" } }
        return try #require(model.tabs.first { $0.openerTabID == main.id })
    }

    func assertOneWindow(sourceLocation: SourceLocation = #_sourceLocation) {
        let windows = NSApp.windows.filter {
            $0.isVisible && !($0 is NSColorPanel) && $0.sheetParent == nil
        }
        #expect(windows.count == 1, sourceLocation: sourceLocation)
        #expect(windows.first === self.window, sourceLocation: sourceLocation)
        #expect(model.tabs.allSatisfy { $0.webView.window == nil || $0.webView.window === self.window }, sourceLocation: sourceLocation)
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
