import Foundation
import MiniBrowserCore
import Testing

@Suite("不支持的外部协议")
struct WebNavigationPolicyTests {
    @Test("网页内部协议保留")
    func webSchemes() {
        for value in ["https://example.com", "http://example.com", "about:blank", "data:text/html,ok", "blob:https://example.com/id", "file:///tmp/a"] {
            #expect(WebNavigationPolicy.allows(URL(string: value)))
        }
    }

    @Test("外部 App 协议取消")
    func externalSchemes() {
        for value in ["weixin://pay", "alipays://pay", "mailto:a@example.com"] {
            #expect(!WebNavigationPolicy.allows(URL(string: value)))
        }
    }
}
