import Darwin
import Foundation

func cleanupTestDefaults(_ defaults: UserDefaults, suiteName: String) {
    defaults.removePersistentDomain(forName: suiteName)
    defaults.synchronize()
    // 等 cfprefsd 处理完删除，避免并行测试时空 plist 在 API 返回后被重建。
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/defaults")
    process.arguments = ["delete", suiteName]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    guard let password = getpwuid(getuid()) else { return }
    let preferences = URL(fileURLWithPath: String(cString: password.pointee.pw_dir))
        .appendingPathComponent("Library/Preferences", isDirectory: true)
    try? FileManager.default.removeItem(
        at: preferences.appendingPathComponent("\(suiteName).plist")
    )
}
