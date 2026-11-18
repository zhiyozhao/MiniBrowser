import Foundation
import Testing
@testable import MiniBrowserCore

@Suite("窗口标签状态")
struct BrowserWindowStateTests {
    @Test("初始标签被选中")
    func initialTab() {
        let id = UUID()
        let state = BrowserWindowState(initialTabID: id)
        #expect(state.tabIDs == [id])
        #expect(state.selectedID == id)
    }

    @Test("新标签追加并选中")
    func newTab() {
        let first = UUID()
        let second = UUID()
        var state = BrowserWindowState(initialTabID: first)
        state.newTab(id: second)
        #expect(state.tabIDs == [first, second])
        #expect(state.selectedID == second)
    }

    @Test("弹窗标签插入打开它的标签右侧")
    func insertPopupAfterOpener() {
        let first = UUID()
        let second = UUID()
        let popup = UUID()
        var state = BrowserWindowState(initialTabID: first)
        state.newTab(id: second)
        state.selectedID = first
        state.insertTab(id: popup, after: first)
        #expect(state.tabIDs == [first, popup, second])
        #expect(state.selectedID == popup)
    }

    @Test("后台弹窗插入右侧但不抢焦点")
    func insertBackgroundPopupAfterOpener() {
        let first = UUID()
        let second = UUID()
        let popup = UUID()
        var state = BrowserWindowState(initialTabID: first)
        state.newTab(id: second)
        state.selectedID = first
        state.insertTab(id: popup, after: first, select: false)
        #expect(state.tabIDs == [first, popup, second])
        #expect(state.selectedID == first)
    }

    @Test("关闭选中的中间标签后选中后一个")
    func closeSelectedMiddleTab() {
        let ids = [UUID(), UUID(), UUID()]
        var state = BrowserWindowState(initialTabID: ids[0])
        state.newTab(id: ids[1])
        state.newTab(id: ids[2])
        state.selectedID = ids[1]
        state.closeTab(id: ids[1])
        #expect(state.tabIDs == [ids[0], ids[2]])
        #expect(state.selectedID == ids[2])
    }

    @Test("关闭选中的末尾标签后选中前一个")
    func closeSelectedLastTab() {
        let first = UUID()
        let last = UUID()
        var state = BrowserWindowState(initialTabID: first)
        state.newTab(id: last)
        state.closeTab(id: last)
        #expect(state.tabIDs == [first])
        #expect(state.selectedID == first)
    }

    @Test("关闭未选中的标签不改变选择")
    func closeUnselectedTab() {
        let first = UUID()
        let second = UUID()
        var state = BrowserWindowState(initialTabID: first)
        state.newTab(id: second)
        state.closeTab(id: first)
        #expect(state.tabIDs == [second])
        #expect(state.selectedID == second)
    }

    @Test("关闭未知或最后一个标签安全更新状态")
    func closeUnknownAndOnlyTab() {
        let only = UUID()
        var state = BrowserWindowState(initialTabID: only)
        state.closeTab(id: UUID())
        #expect(state.tabIDs == [only])
        #expect(state.selectedID == only)
        state.closeTab(id: only)
        #expect(state.tabIDs.isEmpty)
        #expect(state.selectedID == nil)
    }
}
