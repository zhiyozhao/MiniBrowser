# 兼容性验收

自动测试统一使用 `make check` 中的 Swift Testing；网页测试只连接随机端口的本地服务，使用真实 `WKWebView`，不访问外部网站。原生 sheet 的点击不依赖辅助功能，委托结果由可控替代注入验证。

| 项目 | 最终做法 | 自动证据 |
| --- | --- | --- |
| P1 弹窗 | `window.open` / `target=_blank` 同步创建 520×640 小窗口，返回真实 WebView；复用 configuration 和 websiteDataStore，保留 opener、POST 与 `window.close()`。 | `PopupTests.windowOpenOpenerAndClose`：本地 OAuth 模拟页回传消息并关闭弹窗；`targetBlankPreservesPOST`：本地表单请求体完整且弹窗渲染。 |
| P3 JS 对话框 | alert、confirm、prompt 使用所属窗口的原生 sheet；确认/取消及文本结果原样交还页面。 | `JavaScriptDialogTests`：本地页面实际调用三种 JS 对话框，覆盖确认、输入以及取消后的 `false` / `null`；sheet 点击由注入替代，无需辅助功能。 |
| P8 证书 | 首次证书错误取消并显示明确错误页；“仍然继续”只记录当前源与当前证书，在内存中保留到会话结束，不写持久化。 | `CertificateTests.continueOnlyForCurrentSessionAndSite`：本地自签 HTTPS 页验证错误页、点击继续、同源会话内重载，以及不同端口仍被拒绝。 |
| P11 崩溃恢复 | 每个标签页第一次 WebContent 崩溃自动 reload；再次崩溃显示最简错误页，无重试按钮或额外界面。 | `WebContentRecoveryTests` 验证状态；`WebContentRecoveryIntegrationTests` 验证本地页只收到一次自动重载，随后显示错误页且无按钮。 |
| P14 缩放记忆 | 存储键与规范化域名使用不同变量，始终写入 `MiniBrowserZoomLevels`。 | `SiteZoomSettingsTests.persistence`：检查固定 key 中的字典，并由新实例读回；`normalizedHost` 覆盖大小写和 `www`。 |
| P9 UA | 所有页面使用同一 Safari UA；通过 `applicationNameForUserAgent` 补 Safari 段，保留真实 WebKit 版本，不按域名分支。 | `UserAgentTests.uniformSafariUserAgent`：两个本地源的服务端请求头与 `navigator.userAgent` 一致，包含 Safari/WebKit 段且不含 Chrome。 |
