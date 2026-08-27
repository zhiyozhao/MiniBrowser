import Foundation

/// 站点级缩放记忆：每个域名保存自己的缩放比例，重启后仍然有效
final class ZoomStore {
    static let shared = ZoomStore()
    private let key = "MiniBrowserZoomLevels"
    private var levels: [String: Double]

    init() {
        levels = UserDefaults.standard.dictionary(forKey: key) as? [String: Double] ?? [:]
    }

    private func normalizedHost(_ host: String?) -> String? {
        guard let host = host?.lowercased() else { return nil }
        // 把 www.zhihu.com 和 zhihu.com 视为同一站点
        if host.hasPrefix("www.") { return String(host.dropFirst(4)) }
        return host
    }

    func zoom(for host: String?) -> CGFloat {
        guard let host, let key = normalizedHost(host) else { return 1.0 }
        return CGFloat(levels[key] ?? 1.0)
    }

    func set(zoom: CGFloat, for host: String?) {
        guard let host, let key = normalizedHost(host) else { return }
        levels[key] = Double(zoom)
        UserDefaults.standard.set(levels, forKey: key)
    }
}
