import WebKit

/// 一个标签页：持有一个 WKWebView 及其浏览状态
final class BrowserTab: ObservableObject, Identifiable {
    let id = UUID()
    let webView: WKWebView

    @Published var title: String = "新标签页"
    @Published var urlText: String = ""
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false

    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 2.0
    private static let zoomStep: CGFloat = 0.1

    init(url: URL? = nil) {
        webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.allowsMagnification = true // 触控板双指缩放
        // 部分网站（如B站）对 Safari/WebKit 系 UA 做降级处理，只有 Chrome UA 才能获得完整体验
        webView.customUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
            + "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36"
        if let url {
            urlText = url.absoluteString
            webView.load(URLRequest(url: url))
        } else {
            // 新标签页：加载内置渐变页，避免空白页纯色难看/点击闪白
            webView.loadHTMLString(Self.newTabHTML, baseURL: nil)
        }
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
        webView.pageZoom = ZoomStore.shared.zoom(for: webView.url?.host)
    }

    // MARK: - 浏览操作

    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }
    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }

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
        guard let url = Self.resolve(urlText) else { return }
        webView.load(URLRequest(url: url))
    }

    static func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        // 已带 scheme（http://、https:// 等）
        if let url = URL(string: trimmed), let scheme = url.scheme,
           scheme == "http" || scheme == "https" {
            return url
        }
        // 形如 example.com，补 https://
        if !trimmed.contains(" "), trimmed.contains("."),
           let url = URL(string: "https://" + trimmed), url.host != nil {
            return url
        }
        // 否则按搜索处理
        let q = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: "https://www.bing.com/search?q=\(q)")
    }
}
