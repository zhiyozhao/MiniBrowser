import Foundation
import MiniBrowserCore

/// 一个窗口的所有标签页
final class BrowserWindowModel: ObservableObject {
    @Published private var state: BrowserWindowState
    private var tabsByID: [BrowserTab.ID: BrowserTab]

    var tabs: [BrowserTab] {
        state.tabIDs.compactMap { tabsByID[$0] }
    }

    var selectedID: BrowserTab.ID? {
        get { state.selectedID }
        set { state.selectedID = newValue }
    }

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedID }
    }

    init() {
        let tab = BrowserTab()
        tabsByID = [tab.id: tab]
        state = BrowserWindowState(initialTabID: tab.id)
    }

    @discardableResult
    func newTab(url: URL? = nil) -> BrowserTab {
        let tab = BrowserTab(url: url)
        tabsByID[tab.id] = tab
        state.newTab(id: tab.id)
        return tab
    }

    func closeTab(_ id: BrowserTab.ID) {
        guard tabsByID[id] != nil else { return }
        state.closeTab(id: id)
        tabsByID[id] = nil
    }
}
