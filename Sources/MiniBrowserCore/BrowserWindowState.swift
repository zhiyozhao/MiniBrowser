import Foundation

/// 单个浏览器窗口的标签顺序与选中状态，不依赖 AppKit 或 WebKit。
public struct BrowserWindowState {
    public private(set) var tabIDs: [UUID]
    public var selectedID: UUID?

    public init(initialTabID: UUID) {
        tabIDs = [initialTabID]
        selectedID = initialTabID
    }

    public mutating func newTab(id: UUID) {
        tabIDs.append(id)
        selectedID = id
    }

    /// Inserts a tab immediately after another tab. This is used for popup
    /// navigations so the new tab stays next to the tab that opened it.
    public mutating func insertTab(id: UUID, after openerID: UUID, select: Bool = true) {
        guard !tabIDs.contains(id) else { return }
        if let index = tabIDs.firstIndex(of: openerID) {
            tabIDs.insert(id, at: index + 1)
        } else {
            tabIDs.append(id)
        }
        if select {
            selectedID = id
        }
    }

    public mutating func closeTab(id: UUID) {
        guard let index = tabIDs.firstIndex(of: id) else { return }
        tabIDs.remove(at: index)
        if selectedID == id {
            selectedID = tabIDs.isEmpty ? nil : tabIDs[min(index, tabIDs.count - 1)]
        }
    }
}
