/// 每个标签页只自动恢复一次，避免 WebContent 崩溃形成刷新循环。
public struct WebContentRecoveryState {
    public enum Action: Equatable {
        case reload
        case showError
    }

    private var hasReloaded = false

    public init() {}

    public mutating func processDidTerminate() -> Action {
        if hasReloaded { return .showError }
        hasReloaded = true
        return .reload
    }
}
