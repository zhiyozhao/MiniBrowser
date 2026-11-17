import Foundation

/// 地址栏输入解析：HTTP(S) URL 直接打开，域名补 HTTPS，其余交给 Bing 搜索。
public enum AddressResolver {
    public static func resolve(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let scheme = url.scheme,
           scheme == "http" || scheme == "https" {
            return url
        }

        if !trimmed.contains(" "), trimmed.contains("."),
           let url = URL(string: "https://" + trimmed), url.host != nil {
            return url
        }

        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: "https://www.bing.com/search?q=\(query)")
    }
}
