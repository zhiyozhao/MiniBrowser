// 打印指定 PID 的屏上普通窗口：window_id x y width height（单位 pt）
// 用法: swift Scripts/demo/windows.swift <pid>
import CoreGraphics
import Foundation

guard CommandLine.arguments.count == 2, let pid = Int(CommandLine.arguments[1]) else {
    FileHandle.standardError.write("usage: windows.swift <pid>\n".data(using: .utf8)!)
    exit(2)
}
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for info in list {
    guard (info[kCGWindowOwnerPID as String] as? Int) == pid,
          (info[kCGWindowLayer as String] as? Int) == 0,
          let id = info[kCGWindowNumber as String] as? Int,
          let b = info[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
    print(id, Int(b["X"] ?? 0), Int(b["Y"] ?? 0), Int(b["Width"] ?? 0), Int(b["Height"] ?? 0))
}
