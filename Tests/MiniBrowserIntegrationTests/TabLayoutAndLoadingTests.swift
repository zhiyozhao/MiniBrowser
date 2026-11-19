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

    @Test("慢响应在 title 到达前显示 host 和加载状态，随后换成真实标题")
    func slowNavigationShowsHostThenTitle() async throws {
        let server = try LocalHTTPServer { request in
            guard request.path == "/slow" else { return .init("<title>not-found</title>") }
            Thread.sleep(forTimeInterval: 0.35)
            return .init("<html><head><title>慢页面完成</title></head><body>done</body></html>")
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
            Thread.sleep(forTimeInterval: 0.25)
            return .init("<html><head><title>popup 完成</title></head></html>")
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
        let url = URL(string: "https://failed.fixture/failed")!
        let tab = BrowserTab(url: url)
        let model = BrowserWindowModel(initialTab: tab)
        let window = try makeWindow(model: model, width: 420)
        defer { closeWindow(window, model: model) }
        let coordinator = try #require(tab.webView.navigationDelegate as? WebViewRepresentable.Coordinator)
        tab.beginLoading(url)
        coordinator.webView(tab.webView, didFailProvisionalNavigation: nil,
                            withError: NSError(domain: NSURLErrorDomain,
                                               code: NSURLErrorCannotConnectToHost))
        #expect(tab.title == "加载失败")
        #expect(tab.title != "新标签页")
        #expect(tab.urlText == url.absoluteString)
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
            try await Task.sleep(for: .milliseconds(100))
            window.displayIfNeeded()
            let image = try #require(snapshot(window))
            try image.write(to: output.appendingPathComponent("tabs-15-\(Int(width)).png"))
        }

        let loadingModel = BrowserWindowModel(initialTab: BrowserTab(url: URL(string: "https://loading.fixture/article")!))
        _ = loadingModel.newTab()
        loadingModel.selectedID = loadingModel.tabs[0].id
        let loadingWindow = try makeWindow(model: loadingModel, width: 420)
        defer { closeWindow(loadingWindow, model: loadingModel) }
        loadingModel.selectedTab?.beginLoading(URL(string: "https://loading.fixture/article"))
        try await Task.sleep(for: .milliseconds(100))
        loadingWindow.displayIfNeeded()
        let loadingImage = try #require(snapshot(loadingWindow))
        try loadingImage.write(to: output.appendingPathComponent("loading-tab.png"))
    }

    private func makeWindow(model: BrowserWindowModel, width: CGFloat) throws -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 500),
                              styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
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

}
