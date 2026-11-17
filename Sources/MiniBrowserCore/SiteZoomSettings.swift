import Foundation

/// 按站点保存缩放比例；注入 UserDefaults 便于测试且不操作用户真实设置。
public final class SiteZoomSettings {
    public static let storageKey = "MiniBrowserZoomLevels"

    private let defaults: UserDefaults
    private let storageKey: String
    private var levels: [String: Double]

    public init(defaults: UserDefaults = .standard, key: String = SiteZoomSettings.storageKey) {
        self.defaults = defaults
        storageKey = key
        levels = defaults.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    public func zoom(for host: String?) -> Double {
        guard let key = Self.normalizedHost(host) else { return 1.0 }
        return levels[key] ?? 1.0
    }

    public func set(zoom: Double, for host: String?) {
        guard let hostKey = Self.normalizedHost(host) else { return }
        levels[hostKey] = zoom
        defaults.set(levels, forKey: storageKey)
    }

    private static func normalizedHost(_ host: String?) -> String? {
        guard let host = host?.lowercased() else { return nil }
        if host.hasPrefix("www.") {
            return String(host.dropFirst(4))
        }
        return host
    }
}
