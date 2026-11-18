import AppKit
import Foundation
import MiniBrowserCore
import Testing
import WebKit
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

    @Test("make check 使用独立 suite 与 nonPersistent store，HOME 不变")
    @MainActor
    func injectedRuntimeIsolation() throws {
        let environment = ProcessInfo.processInfo.environment
        let suite = try #require(environment["MINIBROWSER_DEFAULTS_SUITE"])
        let directory = try #require(environment["MINIBROWSER_DATA_DIRECTORY"])
        #expect(AppEnvironment.defaultsSuite == suite)
        #expect(AppEnvironment.dataDirectoryPath == directory)
        let originalHome = String(cString: getenv("HOME"))
        let originalFixedHome = ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"]
        let configuration = WebViewConfigurationFactory.make()
        #expect(FileManager.default.fileExists(atPath: directory))
        #expect(String(cString: getenv("HOME")) == originalHome)
        #expect(ProcessInfo.processInfo.environment["CFFIXED_USER_HOME"] == originalFixedHome)
        #expect(originalHome != directory)
        #expect(!configuration.websiteDataStore.isPersistent)
        #expect(configuration.websiteDataStore === WebViewConfigurationFactory.make().websiteDataStore)

        ZoomStore.shared.set(zoom: 1.25, for: "isolation.test")
        let stored = AppEnvironment.userDefaults.dictionary(forKey: SiteZoomSettings.storageKey) as? [String: Double]
        #expect(stored?["isolation.test"] == 1.25)
    }

    @Test("nonPersistent WebKit store 加载加密页面时不显示系统对话框")
    @MainActor
    func nonPersistentStoreDoesNotPresentSystemDialog() async throws {
        let fixture = WebViewFixture(configuration: WebViewConfigurationFactory.make())
        defer { fixture.close() }
        fixture.webView.loadHTMLString("""
        <html><title>crypto-done</title><script>
        crypto.subtle.digest('SHA-256', new TextEncoder().encode('fixture'))
          .then(() => document.title = 'crypto-done')
          .catch(() => document.title = 'crypto-done');
        </script></html>
        """, baseURL: URL(string: "https://isolated.test")!)
        try await waitUntil("nonPersistent crypto page") { fixture.webView.title == "crypto-done" }
        #expect(!fixture.webView.configuration.websiteDataStore.isPersistent)
        #expect(fixture.window.attachedSheet == nil)
        #expect(NSApp.modalWindow == nil)
    }
}
