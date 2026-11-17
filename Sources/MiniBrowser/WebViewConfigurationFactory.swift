import WebKit

enum WebViewConfigurationFactory {
    /// 保留 WKWebView 真实的系统与 AppleWebKit 版本，只补齐 Safari 身份段。
    /// 不伪造完整 UA，避免系统升级后引擎版本和 UA 长期失配。
    static let safariApplicationName = "Version/18.0 Safari/605.1.15"

    static func configure(_ configuration: WKWebViewConfiguration) {
        configuration.applicationNameForUserAgent = safariApplicationName
    }

    static func make() -> WKWebViewConfiguration {
        let configuration = WKWebViewConfiguration()
        configure(configuration)
        return configuration
    }
}
