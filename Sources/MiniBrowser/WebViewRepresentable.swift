import MiniBrowserCore
import SwiftUI
import WebKit

/// 把 WKWebView 包进 SwiftUI，并同步浏览状态到 BrowserTab
typealias PopupWebViewFactory = (WKWebViewConfiguration, WKNavigationAction, WKWindowFeatures) -> WKWebView?

struct WebViewRepresentable: NSViewRepresentable {
    let tab: BrowserTab
    var onCreateWebView: PopupWebViewFactory

    func makeNSView(context: Context) -> WKWebView {
        tab.webView.uiDelegate = context.coordinator
        tab.webView.navigationDelegate = context.coordinator
        // 视图首次出现时应用一次站点缩放（防止 KVO 注册前页面已加载完）
        tab.applySiteZoom()
        return tab.webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(tab: tab, onCreateWebView: onCreateWebView)
    }

    @MainActor
    final class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate {
        private let tab: BrowserTab
        private let onCreateWebView: PopupWebViewFactory
        private let dialogs: JavaScriptDialogHandling
        private let isTabSelected: () -> Bool
        private let serverTrustSession: ServerTrustSession
        private let onPopupClosed: ((BrowserTab.ID, BrowserTab.ID?) -> Void)?
        private let validTrustHandler: ((SecTrust, @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) -> Void)?
        private var observations: [NSKeyValueObservation] = []
        private var lastMainFrameURL: URL?
        private var lastCommittedURL: URL?
        private var hasCommittedNavigation = false
        private var provisionalURL: URL?
        private var currentNavigationCommitted = false
        private var recoveryState = WebContentRecoveryState()
        private struct PendingCertificate {
            let token = UUID()
            let site: ServerTrustSession.Site
            let trust: SecTrust
            let url: URL
        }
        private var pendingCertificate: PendingCertificate?
        private var activeCertificateErrorToken: UUID?
        private var isLoadingCertificateErrorPage = false

        init(tab: BrowserTab,
             onCreateWebView: @escaping PopupWebViewFactory,
             dialogs: JavaScriptDialogHandling? = nil,
             isTabSelected: @escaping () -> Bool = { true },
             serverTrustSession: ServerTrustSession? = nil,
             validTrustHandler: ((SecTrust, @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) -> Void)? = nil,
             onPopupClosed: ((BrowserTab.ID, BrowserTab.ID?) -> Void)? = nil) {
            self.tab = tab
            self.onCreateWebView = onCreateWebView
            self.dialogs = dialogs ?? AppKitJavaScriptDialogs()
            self.isTabSelected = isTabSelected
            self.serverTrustSession = serverTrustSession ?? .shared
            self.validTrustHandler = validTrustHandler
            self.onPopupClosed = onPopupClosed
            super.init()

            let webView = tab.webView
            observations = [
                webView.observe(\.title) { [weak self] wv, _ in
                    DispatchQueue.main.async {
                        self?.tab.setDocumentTitle(wv.title)
                    }
                },
                webView.observe(\.url) { [weak self] wv, _ in
                    DispatchQueue.main.async {
                        // 内置新标签页（about:blank）不显示在地址栏
                        if self?.tab.loadFailed == false { self?.tab.updateURL(wv.url) }
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
                    DispatchQueue.main.async {
                        self?.tab.synchronizeLoading()
                    }
                },
                webView.observe(\.estimatedProgress) { [weak self] wv, _ in
                    DispatchQueue.main.async {
                        self?.tab.synchronizeLoading()
                    }
                },
            ]
        }

        func webView(_ webView: WKWebView,
                     requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                     initiatedByFrame frame: WKFrameInfo,
                     type: WKMediaCaptureType,
                     decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            guard isTabSelected() else { completionHandler(); return }
            dialogs.showAlert(message, in: webView, completion: completionHandler)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            guard isTabSelected() else { completionHandler(false); return }
            dialogs.showConfirm(message, in: webView, completion: completionHandler)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            guard isTabSelected() else { completionHandler(nil); return }
            dialogs.showPrompt(prompt, defaultText: defaultText, in: webView, completion: completionHandler)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            let url = navigationAction.request.url
            if url?.scheme?.lowercased() == "minibrowser" {
                if url?.host == "continue-certificate" {
                    continueCertificate(token: UUID(uuidString: url?.lastPathComponent ?? ""))
                }
                decisionHandler(.cancel)
                return
            }
            guard WebNavigationPolicy.allows(url) else {
                decisionHandler(.cancel)
                return
            }
            if navigationAction.navigationType == .linkActivated,
               navigationAction.modifierFlags.contains(.command),
               navigationAction.targetFrame != nil {
                let configuration = WebViewConfigurationFactory.make()
                configuration.websiteDataStore = webView.configuration.websiteDataStore
                if let destination = onCreateWebView(configuration, navigationAction, WKWindowFeatures()) {
                    destination.load(navigationAction.request)
                }
                decisionHandler(.cancel)
                return
            }
            if navigationAction.targetFrame?.isMainFrame == true {
                if !isLoadingCertificateErrorPage {
                    clearPendingCertificate()
                }
                lastMainFrameURL = url
                tab.updateURL(url)
            }
            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let isAttachment = (navigationResponse.response as? HTTPURLResponse)?.allHeaderFields.contains { key, value in
                String(describing: key).lowercased() == "content-disposition"
                    && String(describing: value).localizedCaseInsensitiveContains("attachment")
            } == true
            if !navigationResponse.canShowMIMEType || isAttachment {
                decisionHandler(.cancel)
                if navigationResponse.isForMainFrame, tab.openerTabID != nil, !hasCommittedNavigation {
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        self.onPopupClosed?(self.tab.id, self.tab.openerTabID)
                    }
                }
                if navigationResponse.isForMainFrame,
                   let lastCommittedURL,
                   lastCommittedURL != webView.url {
                    DispatchQueue.main.async {
                        webView.load(URLRequest(url: lastCommittedURL))
                    }
                }
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView,
                     didReceive challenge: URLAuthenticationChallenge,
                     completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust else {
                completionHandler(.performDefaultHandling, nil)
                return
            }
            if serverTrustSession.isValid(trust) {
                if let validTrustHandler {
                    validTrustHandler(trust, completionHandler)
                } else {
                    completionHandler(.performDefaultHandling, nil)
                }
                return
            }
            let site = ServerTrustSession.Site(protectionSpace: challenge.protectionSpace)
            if serverTrustSession.allows(site: site, trust: trust) {
                completionHandler(.useCredential, URLCredential(trust: trust))
                return
            }
            guard let url = lastMainFrameURL ?? webView.url,
                  ServerTrustSession.Site(url: url) == site else {
                // 子资源证书失败只拒绝该资源，不替换主页面。
                completionHandler(.cancelAuthenticationChallenge, nil)
                return
            }
            let pending = PendingCertificate(site: site, trust: trust, url: url)
            pendingCertificate = pending
            activeCertificateErrorToken = pending.token
            isLoadingCertificateErrorPage = true
            completionHandler(.cancelAuthenticationChallenge, nil)
            DispatchQueue.main.async { [weak self] in
                guard let self, self.pendingCertificate?.token == pending.token else { return }
                self.tab.showCertificateError(host: site.host, url: url, token: pending.token)
            }
        }

        private func clearPendingCertificate() {
            pendingCertificate = nil
            activeCertificateErrorToken = nil
            isLoadingCertificateErrorPage = false
        }

        private func continueCertificate(token: UUID?) {
            guard let token,
                  activeCertificateErrorToken == token,
                  let pendingCertificate,
                  pendingCertificate.token == token else { return }
            clearPendingCertificate()
            serverTrustSession.allow(site: pendingCertificate.site, trust: pendingCertificate.trust)
            tab.webView.load(URLRequest(url: pendingCertificate.url))
        }

        /// 页面加载完成后再应用一次，确保缩放生效
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            provisionalURL = lastMainFrameURL ?? webView.url
            currentNavigationCommitted = false
            tab.navigationStarted(provisionalURL)
            tab.synchronizeLoading()
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            hasCommittedNavigation = true
            currentNavigationCommitted = true
            if tab.openerTabID != nil, tab.hasRealURL, isTabSelected() {
                webView.window?.makeFirstResponder(webView)
            }
        }

        func webView(_ webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
            provisionalURL = webView.url
            tab.updateURL(webView.url)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            isLoadingCertificateErrorPage = false
            // WebKit may reject a network URL (for example an unsafe port)
            // by committing an empty about:blank document with no failure
            // callback. A real network response must not finish at blank.
            if let provisionalURL,
               ["http", "https"].contains(provisionalURL.scheme?.lowercased() ?? ""),
               webView.url?.absoluteString == "about:blank" ||
                (!currentNavigationCommitted && webView.url != provisionalURL) {
                tab.failLoading(error: NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost,
                                    userInfo: [NSURLErrorFailingURLErrorKey: provisionalURL]))
                return
            }
            lastCommittedURL = webView.url
            tab.setDocumentTitle(webView.title)
            tab.finishLoading()
            tab.applySiteZoom()
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            switch recoveryState.processDidTerminate() {
            case .reload:
                webView.reload()
            case .showError:
                tab.showWebContentError()
            }
        }
        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            tab.failLoading(error: error)
            NSLog("MiniBrowser 加载失败: %@, 错误: %@",
                  webView.url?.absoluteString ?? "(未知地址)", error.localizedDescription)
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            tab.failLoading(error: error)
            NSLog("MiniBrowser 加载中断: %@, 错误: %@",
                  webView.url?.absoluteString ?? "(未知地址)", error.localizedDescription)
        }

        /// 返回真实弹窗 WebView，保留 window.open 返回值、opener、POST 和关闭链路。
        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard WebNavigationPolicy.allows(navigationAction.request.url) else { return nil }
            configuration.websiteDataStore = webView.configuration.websiteDataStore
            WebViewConfigurationFactory.configure(configuration)
            return onCreateWebView(configuration, navigationAction, windowFeatures)
        }

        func webViewDidClose(_ webView: WKWebView) {
            onPopupClosed?(tab.id, tab.openerTabID)
        }
    }
}
