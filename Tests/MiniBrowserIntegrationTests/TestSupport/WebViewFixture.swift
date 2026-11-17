import AppKit
import Foundation
import WebKit

struct WebViewTestError: Error, CustomStringConvertible {
    let description: String
}

@MainActor
final class WebViewFixture {
    let window: NSWindow
    let webView: WKWebView

    init(configuration: WKWebViewConfiguration? = nil) {
        webView = WKWebView(
            frame: NSRect(x: 0, y: 0, width: 520, height: 640),
            configuration: configuration ?? WKWebViewConfiguration()
        )
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.orderFront(nil)
    }

    func load(_ url: URL) {
        webView.load(URLRequest(url: url))
    }

    func evaluate(_ script: String) async throws -> Any? {
        try await webView.evaluateJavaScript(script)
    }

    func waitForTitle(_ title: String, timeout: TimeInterval = 8) async throws {
        try await waitUntil("document.title == \(title)", timeout: timeout) {
            self.webView.title == title
        }
    }

    func close() {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        window.contentView = nil
        window.close()
    }
}

@MainActor
func waitUntil(_ description: String, timeout: TimeInterval = 8,
               condition: @MainActor () throws -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(timeout))
    while ContinuousClock.now < deadline {
        if try condition() { return }
        try await Task.sleep(for: .milliseconds(25))
    }
    throw WebViewTestError(description: "Timed out waiting for \(description)")
}

func makeTemporaryDirectory(_ name: String) throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("MiniBrowserTests-\(name)-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
