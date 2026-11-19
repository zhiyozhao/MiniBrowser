import AppKit
import SwiftUI
import Testing
import WebKit
@testable import MiniBrowser

@Suite("标签布局和加载状态", .serialized)
@MainActor
struct TabLayoutAndLoadingTests {
    @Test("228/300/420/800pt 下标签栏不溢出并在最小宽度后滚动")
    func tabBarWidthsStayWithinWindow() {
        for windowWidth in [CGFloat(228), 300, 420, 800] {
            for count in [1, 5, 15, 40] {
                let itemWidth = TabBarLayout.itemWidth(containerWidth: windowWidth, tabCount: count)
                let contentWidth = TabBarLayout.contentWidth(containerWidth: windowWidth, tabCount: count)
                #expect(itemWidth >= TabBarLayout.minimumWidth)
                if contentWidth <= windowWidth {
                    #expect(contentWidth <= windowWidth)
                    #expect(itemWidth <= TabBarLayout.idealWidth)
                } else {
                    #expect(itemWidth == TabBarLayout.minimumWidth)
                }
            }
        }
    }

    @Test("真实标签栏在选择、新建及缩窗后完整显示当前标签")
    func selectedTabRemainsVisibleAfterResize() async throws {
        for count in [1, 5, 15, 40] {
            let model = BrowserWindowModel()
            for _ in 0..<(count - 1) { model.newTab() }
            let window = try makeWindow(model: model, width: 800)
            defer { closeWindow(window, model: model) }
            for index in [count - 1, count / 2, 0, count - 1] {
                model.selectedID = model.tabs[index].id
                for width in [CGFloat(800), 420, 300, 228] {
                    window.setContentSize(NSSize(width: width, height: 500))
                    await nextLayout(window)
                    if count == 1 {
                        #expect(window.contentView!.bounds.width <= width + 1)
                        continue
                    }
                    try await waitUntil("selected tab visible \(count) tabs at \(width)pt") {
                        guard let scroll = tabScrollView(in: window.contentView!) else { return false }
                        let visible = scroll.documentVisibleRect
                        let itemWidth = TabBarLayout.itemWidth(containerWidth: scroll.bounds.width, tabCount: count)
                        let left = TabBarLayout.horizontalPadding + CGFloat(index) * (itemWidth + TabBarLayout.spacing)
                        return scroll.bounds.width <= width + 1 && left >= visible.minX - 1 && left + itemWidth <= visible.maxX + 1
                    }
                }
            }
        }
    }

    @Test("慢响应在 title 到达前显示 host 和加载状态，随后换成真实标题")
    func slowNavigationShowsHostThenTitle() async throws {
        let server = try LocalHTTPServer { request in
            guard request.path == "/slow" else { return .init("<title>not-found</title>") }
            var response = LocalHTTPServer.Response("<html><head><title>慢页面完成</title></head><body>done</body></html>")
            response.delay = 3
            return response
        }
        try await server.start()
        defer { server.stop() }

        let url = server.baseURL.appendingPathComponent("slow")
        let tab = BrowserTab(url: url)
        let model = BrowserWindowModel(initialTab: tab)
        let window = try makeWindow(model: model, width: 420)
        defer { closeWindow(window, model: model) }

        try await waitUntil("slow page starts loading") { tab.isLoading }
        #expect(tab.title == server.baseURL.host)
        #expect(tab.urlText == url.absoluteString)
        #expect(tab.isLoading)
        try await waitUntil("slow title") { tab.title == "慢页面完成" && !tab.isLoading }
        #expect(!tab.loadFailed)
    }

    @Test("popup 尚未导航时显示正在打开，导航后显示 host")
    func popupShowsOpeningStateBeforeNavigation() async throws {
        let server = try LocalHTTPServer { _ in
            var response = LocalHTTPServer.Response("<html><head><title>popup 完成</title></head></html>")
            response.delay = 1
            return response
        }
        try await server.start()
        defer { server.stop() }

        let model = BrowserWindowModel()
        let window = try makeWindow(model: model, width: 420)
        defer { closeWindow(window, model: model) }
        let opener = try #require(model.selectedTab)
        let popup = try #require(model.newPopupTab(
            configuration: WebViewConfigurationFactory.make(), openerID: opener.id, select: true))
        #expect(popup.title == "正在打开…")
        let url = server.baseURL.appendingPathComponent("popup")
        popup.webView.load(URLRequest(url: url))
        try await waitUntil("popup loading host") { popup.isLoading }
        #expect(popup.title == server.baseURL.host)
        try await waitUntil("popup title") { popup.title == "popup 完成" && !popup.isLoading }
    }

    @Test("失败导航显示失败状态，不停留在新标签页")
    func failedNavigationShowsFailureState() async throws {
        let model = BrowserWindowModel()
        let window = try makeWindow(model: model, width: 420)
        defer { closeWindow(window, model: model) }
        let server = try LocalHTTPServer { _ in .init("<title>loaded</title>") }
        try await server.start()
        defer { server.stop() }
        let tab = try #require(model.selectedTab)
        try await waitUntil("blank load settled") { !tab.webView.isLoading }
        let closedServer = try LocalHTTPServer { _ in .init("unused") }
        try await closedServer.start()
        let refusedAddress = closedServer.baseURL.appendingPathComponent("refused").absoluteString
        closedServer.stop()
        for startsLoaded in [false, true] {
            for address in ["http://127.0.0.1:9/failed", refusedAddress, "http://does-not-exist.invalid/failed"] {
                if startsLoaded {
                    tab.webView.load(URLRequest(url: server.baseURL))
                    try await waitUntil("loaded before failure") { tab.title == "loaded" && !tab.isLoading }
                }
                let url = URL(string: address)!
                tab.webView.load(URLRequest(url: url))
                try await waitUntil("real failure \(address)", timeout: 15) {
                    tab.loadFailed && !tab.isLoading && !tab.webView.isLoading && tab.urlText == address
                }
                #expect(tab.title == "加载失败")
                #expect(tab.urlText == url.absoluteString)
            }
        }
    }

    @Test("新标签与 about:blank 地址栏为空，切回空标签仍聚焦地址栏")
    func blankAddressAndFocusSurviveNavigation() async throws {
        let model = BrowserWindowModel()
        let window = try makeWindow(model: model, width: 420)
        defer { closeWindow(window, model: model) }
        let blank = try #require(model.selectedTab)
        try await waitUntil("blank finished") { blank.webView.url != nil && !blank.webView.isLoading }
        #expect(blank.urlText.isEmpty)
        #expect(!blank.hasRealURL)
        let other = model.newTab()
        try await waitUntil("second blank finished") { other.webView.url != nil && !other.webView.isLoading }
        model.selectedID = blank.id
        try await waitUntil("blank address focus") { isAddressFocused(window) }
        #expect(blank.urlText.isEmpty)
        blank.webView.load(URLRequest(url: URL(string: "about:blank")!))
        try await waitUntil("explicit blank finished") { !blank.webView.isLoading }
        #expect(blank.urlText.isEmpty)
        #expect(!blank.hasRealURL)
        _ = try await blank.webView.evaluateJavaScript("location.hash='section'")
        try await waitUntil("blank fragment address synchronized") { blank.urlText.isEmpty }
        #expect(blank.urlText.isEmpty)
        #expect(!blank.hasRealURL)
    }

    @Test("锚点和 history API 不启动加载，保留文档标题")
    func sameDocumentNavigationDoesNotSpin() async throws {
        let server = try LocalHTTPServer { _ in .init("""
        <title>document-title</title><a id="jump" href="#section">jump</a><div id="section">section</div>
        """) }
        try await server.start()
        defer { server.stop() }
        let tab = BrowserTab(url: server.baseURL)
        let model = BrowserWindowModel(initialTab: tab)
        let window = try makeWindow(model: model, width: 420)
        defer { closeWindow(window, model: model) }
        try await waitUntil("document loaded") { tab.title == "document-title" && !tab.isLoading }
        for script in ["document.getElementById('jump').click()",
                       "history.pushState({}, '', '#pushed')", "history.replaceState({}, '', '#replaced')"] {
            _ = try await tab.webView.evaluateJavaScript(script)
            try await waitUntil("same-document URL synchronized") { tab.urlText == tab.webView.url?.absoluteString }
            #expect(!tab.webView.isLoading)
            #expect(!tab.isLoading)
            #expect(tab.title == "document-title")
        }
    }

    @Test("停止真实慢加载保留标题或 host，不显示加载失败")
    func stoppingSlowLoadDoesNotFail() async throws {
        let server = try LocalHTTPServer { request in
            var response = LocalHTTPServer.Response("<title>\(request.path == "/slow" ? "slow" : "ready")</title>")
            if request.path == "/slow" { response.delay = 3 }
            return response
        }
        try await server.start()
        defer { server.stop() }
        let tab = BrowserTab(url: server.baseURL)
        let model = BrowserWindowModel(initialTab: tab)
        let window = try makeWindow(model: model, width: 420)
        defer { closeWindow(window, model: model) }
        try await waitUntil("page ready") { tab.title == "ready" && !tab.isLoading }
        tab.webView.load(URLRequest(url: server.baseURL.appendingPathComponent("slow")))
        try await waitUntil("slow request reached server") { tab.isLoading && server.requests.contains { $0.path == "/slow" } }
        let titleBeforeStop = tab.title
        tab.stop()
        try await waitUntil("load stopped") { !tab.webView.isLoading && !tab.isLoading }
        #expect(!tab.loadFailed)
        #expect(tab.title == titleBeforeStop)
        #expect(tab.title != "加载失败")
        tab.webView.load(URLRequest(url: server.baseURL))
        try await waitUntil("successful navigation after stop") { tab.title == "ready" && !tab.isLoading }
    }

    @Test("真实请求超时显示加载失败")
    func requestTimeoutShowsFailure() async throws {
        let server = try LocalHTTPServer { _ in
            var response = LocalHTTPServer.Response("<title>too late</title>")
            response.delay = 10
            return response
        }
        try await server.start()
        defer { server.stop() }
        let model = BrowserWindowModel()
        let window = try makeWindow(model: model, width: 420)
        defer { closeWindow(window, model: model) }
        let tab = try #require(model.selectedTab)
        try await waitUntil("blank before timeout") { !tab.webView.isLoading }
        let request = URLRequest(url: server.baseURL, timeoutInterval: 1)
        tab.webView.load(request)
        try await waitUntil("request timed out", timeout: 8) { tab.loadFailed && !tab.isLoading }
        #expect(tab.title == "加载失败")
    }

    @Test("无标题和清空标题都回退 host")
    func emptyTitleFallsBackToHost() async throws {
        let server = try LocalHTTPServer { _ in .init("<body>no title</body>") }
        try await server.start()
        defer { server.stop() }
        let tab = BrowserTab(url: server.baseURL)
        let model = BrowserWindowModel(initialTab: tab)
        let window = try makeWindow(model: model, width: 420)
        defer { closeWindow(window, model: model) }
        try await waitUntil("untitled loaded") { !server.requests.isEmpty && !tab.webView.isLoading }
        #expect(tab.title == server.baseURL.host)
        _ = try await tab.webView.evaluateJavaScript("document.title='named'")
        try await waitUntil("named title") { tab.title == "named" }
        _ = try await tab.webView.evaluateJavaScript("document.title=''")
        try await waitUntil("empty title fallback") { tab.title == server.baseURL.host }
    }

    @Test("重定向和加载中修改 history/title 不误报失败")
    func redirectAndHistoryDuringLoadKeepTitle() async throws {
        let server = try LocalHTTPServer { request in
            if request.path == "/redirect" {
                return .init(status: "302 Found", headers: ["Location": "/document"])
            }
            if request.path == "/delayed.js" {
                var response = LocalHTTPServer.Response("window.resourceLoaded=true", contentType: "text/javascript")
                response.delay = 1
                return response
            }
            return .init("""
            <html><title>redirect-title</title><script>history.replaceState({}, '', '/changed'); document.title='history-title';</script>
            <script src="/delayed.js"></script><body>done</body></html>
            """)
        }
        try await server.start()
        defer { server.stop() }
        let tab = BrowserTab(url: server.baseURL.appendingPathComponent("redirect"))
        let model = BrowserWindowModel(initialTab: tab)
        let window = try makeWindow(model: model, width: 420)
        defer { closeWindow(window, model: model) }
        try await waitUntil("history title during load") { tab.isLoading && tab.title == "history-title" }
        try await waitUntil("redirect completed") { !tab.isLoading }
        #expect(tab.title == "history-title")
        #expect(!tab.loadFailed)
        #expect(tab.urlText.hasSuffix("/changed"))
    }

    @Test("生成窄窗口标签栏和加载中截图")
    func tabLayoutScreenshots() async throws {
        let output = URL(fileURLWithPath: "/Users/zhao/Codes/Agents/Devs/MiniBrowser-shots/tabs-1119",
                         isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for width in [CGFloat(228), 300, 420, 800] {
            let model = BrowserWindowModel()
            for _ in 0..<14 { _ = model.newTab() }
            let window = try makeWindow(model: model, width: width)
            defer { closeWindow(window, model: model) }
            try await waitUntil("blank screenshot tabs settled") { model.tabs.allSatisfy { !$0.webView.isLoading } }
            await nextLayout(window)
            try await waitUntil("screenshot selection visible") {
                guard let scroll = tabScrollView(in: window.contentView!) else { return false }
                return scroll.documentVisibleRect.maxX >= TabBarLayout.contentWidth(containerWidth: width, tabCount: 15) - 11
            }
            window.displayIfNeeded()
            let image = try #require(snapshot(window))
            try image.write(to: output.appendingPathComponent("tabs-15-\(Int(width)).png"))
        }

        let server = try LocalHTTPServer { _ in
            var response = LocalHTTPServer.Response("<title>finished</title>")
            response.delay = 3
            return response
        }
        try await server.start()
        defer { server.stop() }
        let loadingModel = BrowserWindowModel(initialTab: BrowserTab(url: server.baseURL.appendingPathComponent("slow")))
        _ = loadingModel.newTab()
        loadingModel.selectedID = loadingModel.tabs[0].id
        let loadingWindow = try makeWindow(model: loadingModel, width: 420)
        defer { closeWindow(loadingWindow, model: loadingModel) }
        try await waitUntil("loading screenshot") { loadingModel.selectedTab?.isLoading == true }
        await nextLayout(loadingWindow)
        loadingWindow.displayIfNeeded()
        let loadingImage = try #require(snapshot(loadingWindow))
        try loadingImage.write(to: output.appendingPathComponent("loading-tab.png"))
    }

    private func makeWindow(model: BrowserWindowModel, width: CGFloat) throws -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 500),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        if let screen = NSScreen.screens.first(where: { $0.localizedName == "Mi Monitor" }) {
            window.setFrameOrigin(NSPoint(x: screen.visibleFrame.minX + 80, y: screen.visibleFrame.minY + 80))
        }
        let hosting = NSHostingController(rootView: BrowserView(model: model))
        hosting.sizingOptions = []
        window.contentViewController = hosting
        window.orderFront(nil)
        window.setContentSize(NSSize(width: width, height: 500))
        hosting.view.layoutSubtreeIfNeeded()
        return window
    }

    private func closeWindow(_ window: NSWindow, model: BrowserWindowModel) {
        for tab in model.tabs { model.closeTab(tab.id) }
        window.contentViewController = nil
        window.close()
    }

    private func snapshot(_ window: NSWindow) -> Data? {
        guard let contentView = window.contentView else { return nil }
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                   pixelsWide: max(1, Int(contentView.bounds.width * 2)),
                                   pixelsHigh: max(1, Int(contentView.bounds.height * 2)),
                                   bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB,
                                   bitmapFormat: [], bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep else { return nil }
        rep.size = contentView.bounds.size
        contentView.cacheDisplay(in: contentView.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    private func isAddressFocused(_ window: NSWindow) -> Bool {
        window.firstResponder is NSTextField ||
        window.firstResponder.map { String(describing: type(of: $0)).contains("FieldEditor") } == true
    }

    private func nextLayout(_ window: NSWindow) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                window.contentView?.layoutSubtreeIfNeeded()
                continuation.resume()
            }
        }
    }

    private func tabScrollView(in view: NSView) -> NSScrollView? {
        if view is WKWebView { return nil }
        if let scroll = view as? NSScrollView, scroll.bounds.height <= 40 { return scroll }
        for child in view.subviews {
            if let result = tabScrollView(in: child) { return result }
        }
        return nil
    }

}
