import MiniBrowserCore
import Testing

@Suite("WebContent 崩溃恢复状态")
struct WebContentRecoveryTests {
    @Test("连续崩溃只自动刷新一次")
    func consecutiveCrashes() {
        var state = WebContentRecoveryState()
        #expect(state.processDidTerminate() == .reload)
        #expect(state.processDidTerminate() == .showError)
    }

}
