import Foundation
import Testing
@testable import MiniBrowserCore

@Suite("站点缩放设置")
struct SiteZoomSettingsTests {
    private func isolatedDefaults() throws -> (defaults: UserDefaults, suiteName: String) {
        let suiteName = "MiniBrowserCoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return (defaults, suiteName)
    }

    @Test("没有保存值时使用实际大小")
    func defaultZoom() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SiteZoomSettings(defaults: defaults)
        #expect(settings.zoom(for: "example.com") == 1.0)
        #expect(settings.zoom(for: nil) == 1.0)
    }

    @Test("域名忽略大小写和 www 前缀")
    func normalizedHost() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SiteZoomSettings(defaults: defaults)
        settings.set(zoom: 1.4, for: "WWW.Example.COM")
        #expect(settings.zoom(for: "example.com") == 1.4)
        #expect(settings.zoom(for: "www.example.com") == 1.4)
        #expect(settings.zoom(for: "sub.example.com") == 1.0)
    }

    @Test("设置写入后由新实例读回")
    func persistence() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        SiteZoomSettings(defaults: defaults).set(zoom: 1.75, for: "example.com")
        let reloaded = SiteZoomSettings(defaults: defaults)
        #expect(reloaded.zoom(for: "example.com") == 1.75)
        let stored = try #require(defaults.dictionary(forKey: SiteZoomSettings.storageKey) as? [String: Double])
        #expect(stored == ["example.com": 1.75])
    }

    @Test("无域名时不写入设置")
    func nilHostDoesNotWrite() throws {
        let (defaults, suiteName) = try isolatedDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = SiteZoomSettings(defaults: defaults)
        settings.set(zoom: 1.5, for: nil)
        #expect(defaults.dictionary(forKey: SiteZoomSettings.storageKey) == nil)
    }
}
