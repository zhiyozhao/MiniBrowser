import MiniBrowserCore
import WebKit

/// 一个标签页：持有一个 WKWebView 及其浏览状态
final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView
    /// The tab that opened this one, if it came from a popup navigation.
    var openerTabID: ID?

    @Published var title: String = "新标签页"
    @Published var urlText: String = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var estimatedProgress = 0.0
    @Published var loadFailed = false

    /// The URL used for the provisional navigation.  It lets the tab show a
    /// useful name before WebKit has received a document title.
    private(set) var loadingHost: String?
    private var documentTitle: String?
    private var isNewTabPage: Bool
    private var stoppedTitle: String?

    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 2.0
    private static let zoomStep: CGFloat = 0.1

    init(url: URL? = nil,
         configuration: WKWebViewConfiguration = WebViewConfigurationFactory.make(),
         loadsInitialContent: Bool = true) {
        isNewTabPage = loadsInitialContent && url == nil
        WebViewConfigurationFactory.configure(configuration)
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true // 触控板双指缩放
        // 弹窗的首个导航由 WebKit 自己接续，不能重新发请求或先加载新标签页。
        guard loadsInitialContent else {
            title = "正在打开…"
            return
        }
        if let url {
            urlText = Self.addressText(for: url)
            loadingHost = url.host
            title = url.host ?? "正在打开…"
            webView.load(URLRequest(url: url))
        } else {
            // 新标签页：加载内置渐变页，避免空白页纯色难看/点击闪白
            webView.loadHTMLString(Self.newTabHTML, baseURL: nil)
        }
    }

    var hasRealURL: Bool {
        !Self.addressText(for: webView.url).isEmpty
    }

    private static func addressText(for url: URL?) -> String {
        guard let url else { return "" }
        let address = url.absoluteString.removingPercentEncoding ?? url.absoluteString
        let base = address.lowercased().split(whereSeparator: { $0 == "#" || $0 == "?" }).first
        if base == "about:blank" { return "" }
        return url.absoluteString
    }

    /// Called only when WebKit starts a new document, never from policy
    /// decisions (which also include anchors and history API changes).
    func navigationStarted(_ url: URL?) {
        loadFailed = false
        stoppedTitle = nil
        documentTitle = nil
        updateURL(url)
        updateTitle()
    }

    func updateURL(_ url: URL?) {
        guard let url else { return } // provisional failures can leave WebKit.url nil
        urlText = Self.addressText(for: url)
        loadingHost = url.host
        if !urlText.isEmpty { isNewTabPage = false }
        updateTitle()
    }

    /// Both fields come directly from WebKit KVO. Progress does not reset
    /// titles or failure state, including notifications queued after failure.
    func synchronizeLoading() {
        isLoading = webView.isLoading
        estimatedProgress = webView.estimatedProgress
        updateTitle()
    }

    func setDocumentTitle(_ value: String?) {
        if let value, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            documentTitle = value
        } else {
            documentTitle = nil
        }
        updateTitle()
    }

    func finishLoading() {
        synchronizeLoading()
    }

    func failLoading(error: Error) {
        let error = error as NSError
        if error.domain == NSURLErrorDomain, error.code == NSURLErrorCancelled {
            synchronizeLoading()
            return
        }
        loadFailed = true
        if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            updateURL(url)
        }
        synchronizeLoading()
    }

    private func updateTitle() {
        if loadFailed { title = "加载失败" }
        else if let stoppedTitle { title = stoppedTitle }
        else if let documentTitle { title = documentTitle }
        else if let loadingHost { title = loadingHost }
        else { title = isNewTabPage ? "新标签页" : "正在打开…" }
    }

    /// 内置新标签页：跟随系统深/浅色的柔和渐变
    private static let newTabHTML = """
        <!DOCTYPE html><html><head><meta name="color-scheme" content="light dark">
        <style>
        html, body { margin: 0; height: 100%; }
        body { background: linear-gradient(180deg, #f7f7fa 0%, #eaeaef 100%); }
        @media (prefers-color-scheme: dark) {
            body { background: linear-gradient(180deg, #2f2d2d 0%, #232121 100%); }
        }
        </style></head><body></body></html>
        """

    /// 根据当前页面域名应用已保存的站点缩放（www 前缀会忽略）
    func applySiteZoom() {
        let zoom = ZoomStore.shared.zoom(for: webView.url?.host)
        if webView.pageZoom != zoom { webView.pageZoom = zoom }
    }

    // MARK: - 浏览操作

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stop() {
        guard webView.isLoading else { return }
        stoppedTitle = title
        webView.stopLoading()
    }

    func zoomIn() { setZoom(webView.pageZoom + Self.zoomStep) }
    func zoomOut() { setZoom(webView.pageZoom - Self.zoomStep) }
    func resetZoom() { setZoom(1.0) }

    private func setZoom(_ value: CGFloat) {
        let z = min(Self.maxZoom, max(Self.minZoom, value))
        webView.pageZoom = z
        ZoomStore.shared.set(zoom: z, for: webView.url?.host)
    }

    /// 从地址栏输入加载：合法 URL 直接打开，否则当作搜索词
    func loadAddress() {
        guard let url = AddressResolver.resolve(urlText) else { return }
        webView.load(URLRequest(url: url))
    }

    func showCertificateError(host: String, url: URL, token: UUID) {
        webView.loadHTMLString(BrowserErrorPage.certificate(host: host, token: token), baseURL: url)
    }

    func showWebContentError() {
        webView.loadHTMLString(BrowserErrorPage.webContentTerminated(), baseURL: webView.url)
    }

}
