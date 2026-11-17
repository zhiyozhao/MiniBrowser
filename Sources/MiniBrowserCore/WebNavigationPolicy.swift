import Foundation

public enum WebNavigationPolicy {
    /// 仅保留网页自身需要的 scheme；外部 App 协议一律取消，不弹框也不外开。
    public static func allows(_ url: URL?) -> Bool {
        guard let scheme = url?.scheme?.lowercased() else { return true }
        return ["http", "https", "about", "data", "blob", "file"].contains(scheme)
    }
}
