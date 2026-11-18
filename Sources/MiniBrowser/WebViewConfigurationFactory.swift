import WebKit

enum WebViewConfigurationFactory {
    /// 保留 WKWebView 真实的系统与 AppleWebKit 版本，只补齐 Safari 身份段。
    /// 不伪造完整 UA，避免系统升级后引擎版本和 UA 长期失配。
    static let safariApplicationName = "Version/18.0 Safari/605.1.15"

    static func configure(_ configuration: WKWebViewConfiguration) {
        configuration.applicationNameForUserAgent = safariApplicationName
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        MainActor.assumeIsolated { PopupGestureGate.install(in: configuration) }
        // An explicit data-directory override always means an isolated copy;
        // apply its nonPersistent store even when a caller supplied a custom
        // configuration with a different store.
        AppEnvironment.configureWebsiteDataStore(configuration)
    }

    static func make() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configure(configuration)
        return configuration
    }
}
