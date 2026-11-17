import Foundation

enum AppEnvironment {
    static let defaultsSuite = option(
        environmentKey: "MINIBROWSER_DEFAULTS_SUITE",
        argument: "-defaultsSuite"
    )
    static let dataDirectoryPath = option(
        environmentKey: "MINIBROWSER_DATA_DIRECTORY",
        argument: "-dataDirectory"
    )
    static let userDefaults: UserDefaults = {
        if let defaultsSuite, let defaults = UserDefaults(suiteName: defaultsSuite) {
            return defaults
        }
        return .standard
    }()

    private static let preparationLock = NSLock()
    private static var didPrepareDataDirectory = false

    static func option(environmentKey: String, argument: String,
                       environment: [String: String] = ProcessInfo.processInfo.environment,
                       arguments: [String] = CommandLine.arguments) -> String? {
        if let value = environment[environmentKey], !value.isEmpty { return value }
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        let value = arguments[index + 1]
        return value.isEmpty ? nil : value
    }

    /// cfprefsd 不随 HOME 隔离，因此偏好单独走 suite；WebKit 数据则在首次使用前
    /// 通过 HOME/CFFIXED_USER_HOME 指向副本目录。
    static func prepareDataDirectory() {
        preparationLock.lock()
        defer { preparationLock.unlock() }
        guard !didPrepareDataDirectory, let dataDirectoryPath else { return }
        didPrepareDataDirectory = true
        let directory = URL(fileURLWithPath: dataDirectoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        setenv("HOME", directory.path, 1)
        setenv("CFFIXED_USER_HOME", directory.path, 1)
    }
}
