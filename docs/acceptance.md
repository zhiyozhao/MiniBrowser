# 兼容性验收

自动测试统一使用 `make check` 中的 Swift Testing；网页测试只连接随机端口的本地服务，使用真实 `WKWebView`，不访问外部网站。原生 sheet 的点击不依赖辅助功能，委托结果由可控替代注入验证。

| 项目 | 最终做法 | 自动证据 |
| --- | --- | --- |
| P1 弹窗 | `window.open` / `target=_blank` 同步创建 520×640 小窗口，返回真实 WebView；复用 configuration 和 websiteDataStore，保留 opener、POST 与 `window.close()`。 | `PopupTests.windowOpenOpenerAndClose`：本地 OAuth 模拟页回传消息并关闭弹窗；`targetBlankPreservesPOST`：本地表单请求体完整且弹窗渲染。 |
| P9 UA | 所有页面使用同一 Safari UA；通过 `applicationNameForUserAgent` 补 Safari 段，保留真实 WebKit 版本，不按域名分支。 | `UserAgentTests.uniformSafariUserAgent`：两个本地源的服务端请求头与 `navigator.userAgent` 一致，包含 Safari/WebKit 段且不含 Chrome。 |
