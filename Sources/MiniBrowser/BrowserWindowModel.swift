import Foundation

/// 一个窗口的所有标签页
final class BrowserWindowModel: ObservableObject {
    @Published var tabs: [BrowserTab] = []
    @Published var selectedID: BrowserTab.ID?

    var selectedTab: BrowserTab? {
        tabs.first { $0.id == selectedID }
    }

    init() {
        newTab()
    }

    @discardableResult
    func newTab(url: URL? = nil) -> BrowserTab {
        let tab = BrowserTab(url: url)
        tabs.append(tab)
        selectedID = tab.id
        return tab
    }

    func closeTab(_ id: BrowserTab.ID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedID == id {
            selectedID = tabs[min(index, tabs.count - 1)].id
        }
    }
}
