import SwiftUI
import WebKit

/// 把 WKWebView 包进 SwiftUI，并同步浏览状态到 BrowserTab
struct WebViewRepresentable: NSViewRepresentable {
    let tab: BrowserTab
    var onOpenNewTab: (URL) -> Void

    func makeNSView(context: Context) -> WKWebView {
        tab.webView.uiDelegate = context.coordinator
        tab.webView.navigationDelegate = context.coordinator
        // 视图首次出现时应用一次站点缩放（防止 KVO 注册前页面已加载完）
        tab.applySiteZoom()
        return tab.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab, onOpenNewTab: onOpenNewTab)
    }

    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        private let tab: BrowserTab
        private let onOpenNewTab: (URL) -> Void
        private var observations: [NSKeyValueObservation] = []

        init(tab: BrowserTab, onOpenNewTab: @escaping (URL) -> Void) {
            self.tab = tab
            self.onOpenNewTab = onOpenNewTab
            super.init()

            let webView = tab.webView
            observations = [
                webView.observe(\.title) { [weak self] wv, _ in
                    DispatchQueue.main.async {
                        self?.tab.title = (wv.title?.isEmpty == false) ? wv.title! : "新标签页"
                    }
                },
                webView.observe(\.url) { [weak self] wv, _ in
                    DispatchQueue.main.async {
                        // 内置新标签页（about:blank）不显示在地址栏
                        let urlString = wv.url?.absoluteString ?? ""
                        self?.tab.urlText = urlString == "about:blank" ? "" : urlString
                        // 根据新域名应用站点级缩放
                        self?.tab.applySiteZoom()
                    }
                },
                webView.observe(\.canGoBack) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.tab.canGoBack = wv.canGoBack }
                },
                webView.observe(\.canGoForward) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.tab.canGoForward = wv.canGoForward }
                },
                webView.observe(\.isLoading) { [weak self] wv, _ in
                    DispatchQueue.main.async { self?.tab.isLoading = wv.isLoading }
                },
            ]
        }

        /// 页面加载完成后再应用一次，确保缩放生效
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            tab.applySiteZoom()
        }
        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            NSLog("MiniBrowser 加载失败: %@, 错误: %@",
                  webView.url?.absoluteString ?? "(未知地址)", error.localizedDescription)
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            NSLog("MiniBrowser 加载中断: %@, 错误: %@",
                  webView.url?.absoluteString ?? "(未知地址)", error.localizedDescription)
        }

        /// 网页请求新开窗口（target=_blank 等）时，改为新开一个标签页
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = navigationAction.request.url {
                DispatchQueue.main.async { self.onOpenNewTab(url) }
            }
            return nil
        }
    }
}
