import Foundation
import MiniBrowserCore
import Testing
@testable import MiniBrowser

@Suite("运行副本环境隔离")
struct RuntimeEnvironmentTests {
    @Test("环境变量优先，启动参数可指定 suite 和数据目录")
    func optionParsing() {
        let environment = ["MINIBROWSER_DEFAULTS_SUITE": "Environment.Suite"]
        #expect(AppEnvironment.option(
            environmentKey: "MINIBROWSER_DEFAULTS_SUITE",
            argument: "-defaultsSuite",
            environment: environment,
            arguments: ["MiniBrowser", "-defaultsSuite", "Argument.Suite"]
        ) == "Environment.Suite")
        #expect(AppEnvironment.option(
            environmentKey: "MINIBROWSER_DATA_DIRECTORY",
            argument: "-dataDirectory",
            environment: [:],
            arguments: ["MiniBrowser", "-dataDirectory", "/tmp/MiniBrowserCopy"]
        ) == "/tmp/MiniBrowserCopy")
    }

    @Test("make check 为 WebView 副本提供独立 suite 与 HOME")
    func injectedRuntimeIsolation() throws {
        let environment = ProcessInfo.processInfo.environment
        let suite = try #require(environment["MINIBROWSER_DEFAULTS_SUITE"])
        let directory = try #require(environment["MINIBROWSER_DATA_DIRECTORY"])
        #expect(AppEnvironment.defaultsSuite == suite)
        #expect(AppEnvironment.dataDirectoryPath == directory)
        AppEnvironment.prepareDataDirectory()
        #expect(FileManager.default.fileExists(atPath: directory))
        #expect(String(cString: getenv("HOME")) == directory)

        ZoomStore.shared.set(zoom: 1.25, for: "isolation.test")
        let stored = AppEnvironment.userDefaults.dictionary(forKey: SiteZoomSettings.storageKey) as? [String: Double]
        #expect(stored?["isolation.test"] == 1.25)
    }
}
