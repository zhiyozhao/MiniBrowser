import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var windowControllers: [BrowserWindowController] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMainMenu()
        openNewWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    @objc private func newWindowMenuAction(_ sender: Any?) {
        openNewWindow()
    }

    private func openNewWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        // 最小宽度 = 红绿灯区(68) + 地址栏下限(140) + 左右padding(20) = 228
        window.contentMinSize = NSSize(width: 228, height: 360)
        // 空工具栏：让红绿灯在更高的区域内垂直居中，地址栏才能获得上下留白且与红绿灯对齐
        let toolbar = NSToolbar(identifier: "MainToolbar")
        toolbar.showsBaselineSeparator = false
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact
        window.center()
        let hostingController = NSHostingController(rootView: BrowserView())
        hostingController.sizingOptions = [] // 不要用 SwiftUI 内容尺寸反推窗口大小
        window.contentViewController = hostingController

        let controller = BrowserWindowController(window: window)
        controller.onClose = { [weak self] closing in
            self?.windowControllers.removeAll { $0 === closing }
        }
        controller.showWindow(nil)
        // HostingController 会把窗口缩到最小，显示后强制恢复默认尺寸
        window.setContentSize(NSSize(width: 1100, height: 700))
        window.center()
        windowControllers.append(controller)
    }

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "退出 MiniBrowser",
                        action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let fileItem = NSMenuItem()
        let fileMenu = NSMenu(title: "文件")
        fileMenu.addItem(withTitle: "新建窗口",
                         action: #selector(newWindowMenuAction(_:)),
                         keyEquivalent: "n")
        fileItem.submenu = fileMenu
        mainMenu.addItem(fileItem)

        // 编辑菜单：让 Cmd+C/V/X/A/Z 在地址栏和网页里生效
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }
}

/// 窗口控制器：用 delegate 回调代替 NotificationCenter 观察，避免观察者残留
private final class BrowserWindowController: NSWindowController, NSWindowDelegate {
    var onClose: ((BrowserWindowController) -> Void)?

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        window?.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        onClose?(self)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.activate(ignoringOtherApps: true)
app.run()
