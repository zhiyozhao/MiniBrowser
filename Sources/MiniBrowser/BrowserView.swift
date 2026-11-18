import SwiftUI
import WebKit

/// 一个浏览器窗口：工具栏（与红绿灯同行）+ 标签栏 + 网页区域
@MainActor
struct BrowserView: View {
    @StateObject private var model: BrowserWindowModel
    init(model: BrowserWindowModel? = nil) {
        _model = StateObject(wrappedValue: model ?? BrowserWindowModel())
    }

    var body: some View {
        VStack(spacing: 0) {
            if let tab = model.selectedTab {
                TopBarView(tab: tab, model: model)
            }
            Divider()
            WebViewStackRepresentable(model: model)
        }
        .ignoresSafeArea() // 内容延伸到标题栏区域，工具栏与红绿灯同一行
        .background(
            Button("关闭标签页") { closeSelectedTab() }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()
        )
    }

    private func closeSelectedTab() {
        guard let id = model.selectedID else {
            NSApp.keyWindow?.close()
            return
        }
        if model.tabs.count <= 1 {
            NSApp.keyWindow?.close()
        } else {
            model.closeTab(id)
        }
    }
}

/// Keeps the current and recently used tab WKWebViews attached to one AppKit
/// host. Other tab objects stay alive with their delegates and are reattached
/// on demand; switching never creates a new WKWebView.
struct WebViewStackRepresentable: NSViewRepresentable {
    @ObservedObject var model: BrowserWindowModel

    func makeNSView(context: Context) -> HostView {
        let configuredLimit = Int(ProcessInfo.processInfo.environment["MINIBROWSER_MOUNTED_TABS"] ?? "")
            .map { max(1, min($0, 100)) } ?? HostView.defaultMaxMountedTabs
        let host = HostView(maxMountedTabs: configuredLimit)
        model.webViewHost = host
        host.sync(model: model)
        return host
    }

    func updateNSView(_ nsView: HostView, context: Context) {
        nsView.sync(model: model)
    }

    final class HostView: NSView {
        static let defaultMaxMountedTabs = 4
        let maxMountedTabs: Int
        private var viewsByID: [BrowserTab.ID: WKWebView] = [:]
        private var selectedID: BrowserTab.ID?
        private var recentIDs: [BrowserTab.ID] = []
        private(set) var mountedTabIDs: Set<BrowserTab.ID> = []

        init(maxMountedTabs: Int = defaultMaxMountedTabs) {
            self.maxMountedTabs = max(1, maxMountedTabs)
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) {
            maxMountedTabs = Self.defaultMaxMountedTabs
            super.init(coder: coder)
        }

        func sync(model: BrowserWindowModel) {
            let tabs = model.tabs
            let ids = Set(tabs.map(\.id))
            viewsByID = Dictionary(uniqueKeysWithValues: tabs.map { ($0.id, $0.webView) })
            recentIDs.removeAll { !ids.contains($0) }
            updateMounts(preferredID: model.selectedID)
            show(model.selectedID, focusWebView: shouldFocusWebView(model.selectedID, model: model))
        }

        func select(_ id: BrowserTab.ID?, focusWebView: Bool = true) {
            updateMounts(preferredID: id)
            show(id, focusWebView: focusWebView)
        }

        private func shouldFocusWebView(_ id: BrowserTab.ID?, model: BrowserWindowModel) -> Bool {
            guard let id,
                  let tab = model.tabs.first(where: { tab in tab.id == id }) else { return false }
            return !tab.urlText.isEmpty || tab.openerTabID != nil
        }

        private func updateMounts(preferredID: BrowserTab.ID?) {
            if let preferredID {
                recentIDs.removeAll { $0 == preferredID }
                recentIDs.insert(preferredID, at: 0)
            }
            let desiredIDs = Set(recentIDs.prefix(maxMountedTabs))
            for subview in subviews {
                guard let webView = subview as? WKWebView else { continue }
                guard let id = viewsByID.first(where: { $0.value === webView })?.key else {
                    webView.removeFromSuperview()
                    continue
                }
                if !desiredIDs.contains(id) {
                    webView.isHidden = true
                    webView.removeFromSuperview()
                }
            }
            for id in desiredIDs {
                guard let webView = viewsByID[id] else { continue }
                if webView.superview !== self {
                    webView.isHidden = true
                    webView.frame = bounds
                    webView.autoresizingMask = [.width, .height]
                    addSubview(webView)
                }
            }
            mountedTabIDs = desiredIDs
        }

        private func show(_ id: BrowserTab.ID?, focusWebView: Bool) {
            guard selectedID != id || id.flatMap({ viewsByID[$0] })?.isHidden == true else { return }
            for (tabID, view) in viewsByID where mountedTabIDs.contains(tabID) {
                view.isHidden = tabID != id
            }
            selectedID = id
            if let id, let view = viewsByID[id], mountedTabIDs.contains(id) {
                view.isHidden = false
                if focusWebView {
                    window?.makeFirstResponder(view)
                    DispatchQueue.main.async { [weak self, weak view] in
                        guard let self, let view, self.selectedID == id,
                              view.superview === self, !view.isHidden else { return }
                        self.window?.makeFirstResponder(view)
                    }
                } else {
                    focusAddressField()
                }
            }
        }

        private func focusAddressField() {
            guard let window else { return }
            func editableField(in view: NSView) -> NSTextField? {
                if let field = view as? NSTextField, field.isEditable, !field.isHidden {
                    return field
                }
                for child in view.subviews {
                    if let field = editableField(in: child) { return field }
                }
                return nil
            }
            let focus = { [weak window] in
                guard let window,
                      let contentView = window.contentView,
                      let field = editableField(in: contentView) else { return }
                window.makeKeyAndOrderFront(nil)
                window.makeFirstResponder(field)
            }
            focus()
            // SwiftUI may construct the replacement toolbar after this view
            // update; retry once after it has committed the new tab identity.
            DispatchQueue.main.async(execute: focus)
        }

        override func layout() {
            super.layout()
            for subview in subviews { subview.frame = bounds }
        }
    }
}

/// 顶部区域：第一行是工具栏（与红绿灯同高），第二行是标签栏（≥2个标签才显示）
private struct TopBarView: View {
    @ObservedObject var tab: BrowserTab
    @ObservedObject var model: BrowserWindowModel
    @FocusState private var addressFocused: Bool
    @State private var barWidth: CGFloat = 1000

    // 收缩优先级：空白拖动区（下限12pt）→ 地址栏（下限140）→ 按钮从右往左逐个隐藏（加号→刷新→前进→后退）
    private var showPlus: Bool { barWidth >= 364 }
    private var showReload: Bool { barWidth >= 338 }
    private var showForward: Bool { barWidth >= 308 }
    private var showBack: Bool { barWidth >= 278 }
    private var showNav: Bool { showBack || showForward || showReload }

    private var navWidth: CGFloat {
        let count = [showBack, showForward, showReload].filter { $0 }.count
        guard count > 0 else { return 0 }
        return CGFloat(count) * 26 + CGFloat(count - 1) * 4
    }

    /// 地址栏宽度：优先取窗口的 55%（上限 680）；空白缩到下限后地址栏继续收缩到
    /// 140 下限。右侧空白仅在加号存在时保持 12pt（与左侧对称），加号消失后只留窗口边距
    private var addressWidth: CGFloat {
        let fixed: CGFloat = 88 + (showNav ? navWidth + 12 : 0) + (showPlus ? 12 + 26 : 0)
        let available = barWidth - fixed
        return min(680, max(80, min(max(140, barWidth * 0.55), available)))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if model.tabs.count > 1 {
                tabBar
            }
        }
        .background(WindowDragView(onWindowResize: { barWidth = $0 }))
        .background(.regularMaterial)
        .onAppear {
            // 新建（空）标签页时自动聚焦地址栏
            if tab.urlText.isEmpty {
                DispatchQueue.main.async { addressFocused = true }
            }
        }
        .onChange(of: tab.id) { _ in
            addressFocused = tab.urlText.isEmpty
        }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 0) {
            Spacer().frame(width: 68) // 红绿灯占位：使红绿灯→导航组间距与导航组→地址栏间距一致

            // 导航按钮组：组内紧凑，窄窗口时逐级隐藏
            if showNav {
                HStack(spacing: 4) {
                    if showBack {
                        Button { tab.goBack() } label: {
                            Image(systemName: "chevron.left")
                        }
                        .disabled(!tab.canGoBack)
                        .help("后退")
                    }
                    if showForward {
                        Button { tab.goForward() } label: {
                            Image(systemName: "chevron.right")
                        }
                        .disabled(!tab.canGoForward)
                        .help("前进")
                    }
                    if showReload {
                        if tab.isLoading {
                            Button { tab.stop() } label: {
                                Image(systemName: "xmark")
                            }
                            .help("停止加载")
                        } else {
                            Button { tab.reload() } label: {
                                Image(systemName: "arrow.clockwise")
                            }
                            .help("刷新")
                        }
                    }
                }
                .buttonStyle(HoverButtonStyle())

                Spacer().frame(width: 12) // 组间留白：与红绿灯→导航组间距一致（12pt）
            }

            TextField("搜索或输入网址", text: $tab.urlText)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .focused($addressFocused)
                .onSubmit { tab.loadAddress() }
                .padding(.horizontal, 12)
                .frame(width: addressWidth, height: 26)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )

            // 空白拖动区：收缩时最先让位；加号在时最小 12pt（与左侧对称），加号消失后不保留
            Spacer(minLength: showPlus ? 12 : 0)

            if showPlus {
                Button { model.newTab() } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(HoverButtonStyle())
                .help("新建标签页")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .animation(.easeInOut(duration: 0.15), value: showBack)
        .animation(.easeInOut(duration: 0.15), value: showForward)
        .animation(.easeInOut(duration: 0.15), value: showReload)
        .animation(.easeInOut(duration: 0.15), value: showPlus)
        .background(
            // 所有快捷键都放在隐藏按钮上：按钮因窗口窄被隐藏后快捷键依然可用
            HStack {
                Button("后退") { tab.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!tab.canGoBack)
                Button("前进") { tab.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!tab.canGoForward)
                Button("刷新/停止") { tab.isLoading ? tab.stop() : tab.reload() }
                    .keyboardShortcut("r", modifiers: .command)
                Button("新建标签页") { model.newTab() }
                    .keyboardShortcut("t", modifiers: .command)
                Button("缩小") { tab.zoomOut() }.keyboardShortcut("-", modifiers: .command)
                Button("放大") { tab.zoomIn() }.keyboardShortcut("=", modifiers: .command)
                Button("实际大小") { tab.resetZoom() }.keyboardShortcut("0", modifiers: .command)
            }
            .hidden()
        )
    }

    // MARK: - 标签栏

    private var tabBar: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(model.tabs) { t in
                        TabChip(tab: t,
                                isSelected: t.id == model.selectedID,
                                onSelect: { model.selectedID = t.id },
                                onClose: { closeTab(t.id) })
                            .id(t.id)
                    }
                }
                .padding(.horizontal, 10)
            }
            .onChange(of: model.selectedID) { id in
                if let id { proxy.scrollTo(id) }
            }
        }
        .frame(height: 34)
    }

    private func closeTab(_ id: BrowserTab.ID) {
        if model.tabs.count <= 1 {
            NSApp.keyWindow?.close()
        } else {
            model.closeTab(id)
        }
    }
}

/// 等宽标签
private struct TabChip: View {
    @ObservedObject var tab: BrowserTab
    let isSelected: Bool
    let onSelect: () -> Void
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(tab.title)
                .font(.system(size: 12))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            if hovering || isSelected {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(TabCloseButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 180, height: 26)
        .background(
            isSelected
                ? Color(nsColor: .textBackgroundColor)
                : (hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: isSelected ? .black.opacity(0.15) : .clear, radius: 2, y: 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
        .onHover { hovering = $0 }
    }
}

/// 悬停时显示浅灰底的小图标按钮；不可用时置灰
private struct HoverButtonStyle: ButtonStyle {
    @State private var hovering = false
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? Color.primary : Color.secondary)
            .frame(width: 26, height: 26)
            .background(isEnabled && hovering ? Color.primary.opacity(0.07) : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.5 : 1) : 0.4)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// 标签页关闭按钮：悬停时显示圆形灰底
private struct TabCloseButtonStyle: ButtonStyle {
    @State private var hovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(hovering ? Color.primary : Color.secondary)
            .frame(width: 16, height: 16)
            .background(hovering ? Color.primary.opacity(0.15) : Color.clear)
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
    }
}

/// 让顶部区域的空白处可以拖动窗口；监听窗口尺寸变化并回调内容区宽度
private struct WindowDragView: NSViewRepresentable {
    var onWindowResize: ((CGFloat) -> Void)? = nil

    func makeNSView(context: Context) -> NSView {
        let view = DragView()
        view.onWindowResize = onWindowResize
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? DragView)?.onWindowResize = onWindowResize
    }

    final class DragView: NSView {
        var onWindowResize: ((CGFloat) -> Void)?
        private var observer: NSObjectProtocol?

        override var mouseDownCanMoveWindow: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window else { return }
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = NotificationCenter.default.addObserver(
                forName: NSWindow.didResizeNotification, object: window, queue: .main
            ) { [weak self] _ in
                self?.reportWidth()
            }
            reportWidth()
        }

        private func reportWidth() {
            guard let window else { return }
            onWindowResize?(window.contentLayoutRect.width)
        }

        deinit {
            if let observer { NotificationCenter.default.removeObserver(observer) }
        }
    }
}
