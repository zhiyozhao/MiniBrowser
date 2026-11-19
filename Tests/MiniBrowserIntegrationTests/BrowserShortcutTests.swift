import AppKit
import SwiftUI
import Testing
import WebKit
@testable import MiniBrowser

@Suite("浏览器优先快捷键", .serialized)
@MainActor
struct BrowserShortcutTests {
    @Test("ABC/Dvorak/德语/法语布局及小键盘按字符识别缩放，不吞 Cmd 方括号")
    func zoomUsesCharactersAcrossLayouts() {
        // Corresponding NSEvent characters/key positions; no input source is
        // selected or changed by this test. Deliberately include US zoom key
        // positions that produce non-zoom characters in the other layouts.
        let layouts: [(String, [(UInt16, String, BrowserZoomShortcut?)])] = [
            ("ABC", [(24, "=", .zoomIn), (27, "-", .zoomOut), (29, "0", .resetZoom)]),
            ("Dvorak", [(30, "=", .zoomIn), (50, "-", .zoomOut), (27, "[", nil), (24, "]", nil)]),
            ("German", [(30, "+", .zoomIn), (44, "-", .zoomOut), (27, "ß", nil), (29, "0", .resetZoom)]),
            ("French", [(24, "-", .zoomOut), (44, "=", .zoomIn), (29, "à", nil), (29, "0", .resetZoom)]),
            ("Keypad", [(69, "+", .zoomIn), (78, "-", .zoomOut), (82, "0", .resetZoom)])
        ]
        for (layout, cases) in layouts {
            for (keyCode, character, expected) in cases {
                #expect(BrowserZoomShortcut.action(for: keyEvent(keyCode: keyCode, characters: character,
                            modifiers: [.command])) == expected, "layout=\(layout), character=\(character)")
            }
        }
        #expect(BrowserZoomShortcut.action(for: keyEvent(keyCode: 24, characters: "+", modifiers: [.command, .shift])) == .zoomIn)
        #expect(BrowserZoomShortcut.action(for: keyEvent(keyCode: 24, characters: "=", modifiers: [.command, .option])) == nil)
    }

    @Test("网页 preventDefault 不会拦截缩放，普通 Cmd K 仍交给网页")
    func zoomShortcutsBeatPagePreventDefault() async throws {
        let server = try LocalHTTPServer { _ in
            .init("""
            <html><head><title>shortcut-fixture</title></head><body><script>
            document.addEventListener('keydown', e => {
              if (e.metaKey && e.key.toLowerCase() === 'k') window.cmdKReceived = true;
              e.preventDefault();
            }, true);
            </script></body></html>
            """)
        }
        try await server.start()
        defer { server.stop() }

        let tab = BrowserTab(url: server.baseURL)
        let fixture = WebViewFixture(webView: tab.webView)
        defer { fixture.close() }
        let coordinator = WebViewRepresentable.Coordinator(tab: tab, onCreateWebView: { _, _, _ in nil })
        tab.webView.navigationDelegate = coordinator
        tab.webView.uiDelegate = coordinator
        try await waitUntil("shortcut fixture") { tab.title == "shortcut-fixture" }
        tab.webView.pageZoom = 1

        let applyShortcut: (UInt16, String, NSEvent.ModifierFlags) -> Void = { keyCode, chars, flags in
            guard let action = BrowserZoomShortcut.action(for: keyEvent(keyCode: keyCode, characters: chars, modifiers: flags)) else { return }
            switch action {
            case .zoomIn: tab.zoomIn()
            case .zoomOut: tab.zoomOut()
            case .resetZoom: tab.resetZoom()
            }
        }
        applyShortcut(24, "=", [.command])
        #expect(tab.webView.pageZoom > 1)
        applyShortcut(27, "-", [.command])
        #expect(abs(tab.webView.pageZoom - 1) < 0.001)
        applyShortcut(29, "0", [.command])
        #expect(abs(tab.webView.pageZoom - 1) < 0.001)
        applyShortcut(24, "+", [.command, .shift])
        #expect(tab.webView.pageZoom > 1)
        _ = try await tab.webView.evaluateJavaScript("document.dispatchEvent(new KeyboardEvent('keydown', {key:'k', metaKey:true, bubbles:true, cancelable:true}))")
        #expect(try await tab.webView.evaluateJavaScript("window.cmdKReceived === true") as? Bool == true)
        #expect(BrowserZoomShortcut.action(for: keyEvent(keyCode: 40, characters: "k", modifiers: [.command])) == nil)
    }

    private func keyEvent(keyCode: UInt16, characters: String,
                           modifiers: NSEvent.ModifierFlags) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: modifiers,
                         timestamp: 0, windowNumber: 0, context: nil,
                         characters: characters, charactersIgnoringModifiers: characters,
                         isARepeat: false, keyCode: keyCode)!
    }
}
