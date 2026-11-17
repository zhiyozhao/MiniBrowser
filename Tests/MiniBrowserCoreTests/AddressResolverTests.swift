import Foundation
import Testing
@testable import MiniBrowserCore

@Suite("地址栏输入解析")
struct AddressResolverTests {
    @Test("空白输入不导航")
    func blankInput() {
        #expect(AddressResolver.resolve("") == nil)
        #expect(AddressResolver.resolve("   ") == nil)
    }

    @Test("保留 HTTP 和 HTTPS 地址")
    func explicitURLs() {
        #expect(AddressResolver.resolve("https://example.com/path")?.absoluteString == "https://example.com/path")
        #expect(AddressResolver.resolve("http://example.com")?.absoluteString == "http://example.com")
    }

    @Test("域名自动补 HTTPS 并去除首尾空格")
    func bareDomain() {
        #expect(AddressResolver.resolve("  example.com/docs  ")?.absoluteString == "https://example.com/docs")
    }

    @Test("搜索词使用 Bing")
    func searchTerms() {
        #expect(AddressResolver.resolve("Mini Browser")?.absoluteString == "https://www.bing.com/search?q=Mini%20Browser")
    }

    @Test("搜索词进行 URL 编码")
    func encodedSearchTerms() {
        #expect(AddressResolver.resolve("极简 浏览器")?.absoluteString == "https://www.bing.com/search?q=%E6%9E%81%E7%AE%80%20%E6%B5%8F%E8%A7%88%E5%99%A8")
    }
}
