import MiniBrowserCore
import WebKit

/// 一个标签页：持有一个 WKWebView 及其浏览状态
final class BrowserTab: NSObject, ObservableObject, Identifiable, WKScriptMessageHandler {
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
    private let scriptMessageHandler = WeakScriptMessageHandler()
    var certificateContinueHandler: (() -> Void)?

    init(url: URL? = nil,
         configuration: WKWebViewConfiguration = WebViewConfigurationFactory.make(),
         loadsInitialContent: Bool = true) {
        WebViewConfigurationFactory.configure(configuration)
        configuration.userContentController.add(scriptMessageHandler, name: "miniBrowser")
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true // 触控板双指缩放
        super.init()
        scriptMessageHandler.delegate = self
        // 弹窗的首个导航由 WebKit 自己接续，不能重新发请求或先加载新标签页。
        guard loadsInitialContent else { return }
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
        guard let url = AddressResolver.resolve(urlText) else { return }
        webView.load(URLRequest(url: url))
    }

    func showCertificateError(host: String, url: URL) {
        webView.loadHTMLString(BrowserErrorPage.certificate(host: host), baseURL: url)
    }

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "miniBrowser", message.body as? String == "continueCertificate" else { return }
        certificateContinueHandler?()
    }
}
