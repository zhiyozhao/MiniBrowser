import Foundation
import MiniBrowserCore

/// 站点级缩放记忆：每个域名保存自己的缩放比例，重启后仍然有效
final class ZoomStore {
    static let shared = ZoomStore()
    private let settings = SiteZoomSettings()

    func zoom(for host: String?) -> CGFloat {
        CGFloat(settings.zoom(for: host))
    }

    func set(zoom: CGFloat, for host: String?) {
        settings.set(zoom: Double(zoom), for: host)
    }
}
