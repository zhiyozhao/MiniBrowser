import Foundation
import WebKit

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
    private static let isolatedWebsiteDataStore: WKWebsiteDataStore = .nonPersistent()

    static func option(environmentKey: String, argument: String,
                       environment: [String: String] = ProcessInfo.processInfo.environment,
                       arguments: [String] = CommandLine.arguments) -> String? {
        if let value = environment[environmentKey], !value.isEmpty { return value }
        guard let index = arguments.firstIndex(of: argument), index + 1 < arguments.count else { return nil }
        let value = arguments[index + 1]
        return value.isEmpty ? nil : value
    }

    /// The test data directory is retained as a namespace for the isolated
    /// WebKit store. It must not rewrite HOME: WebKit and Security use HOME to
    /// locate the user's keychain, and changing it can trigger keychain UI.
    static func prepareDataDirectory() {
        preparationLock.lock()
        defer { preparationLock.unlock() }
        guard !didPrepareDataDirectory, let dataDirectoryPath else { return }
        didPrepareDataDirectory = true
        let directory = URL(fileURLWithPath: dataDirectoryPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    static func configureWebsiteDataStore(_ configuration: WKWebViewConfiguration) {
        prepareDataDirectory()
        guard dataDirectoryPath != nil else {
            return
        }
        // Any explicit data-directory override is an isolated test/dev copy.
        // Keep it non-persistent on every supported macOS version so it cannot
        // create a UUID store under the production bundle's WebKit directory.
        configuration.websiteDataStore = isolatedWebsiteDataStore
    }

    static func websiteDataStore(forDataDirectory dataDirectory: String?) -> WKWebsiteDataStore {
        dataDirectory == nil ? .default() : .nonPersistent()
    }
}
