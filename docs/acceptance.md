# 兼容性验收

自动测试统一通过 `make check` 内的 `Scripts/test.sh` 执行 Swift Testing。网页测试只连接随机端口的本地服务，使用真实 `WKWebView`，不访问外部网站；原生 sheet 的委托结果由可控替代注入，不需要辅助功能权限。

| 项目 | 最终做法 | 自动证据 |
| --- | --- | --- |
| P1 弹窗 | `window.open` / `target=_blank` 同步返回真实 WebView，插入 opener 右侧的新标签；关闭自动弹窗、一次用户手势一个 permit、附件空标签关闭；所有网页弹窗留在当前 NSWindow，复用 configuration 和 websiteDataStore，保留 opener、POST 与 `window.close()`。⌘点击后台打开。 | `PopupTests.automaticPopupMatchesWebKitDefaultAndOneWindow`、`popupAttachmentClosesTab`、`closingBackgroundPopupKeepsSelection`、`switchingAndPopupCloseRestoreWebViewFocus`、`popupScenariosDoNotCreateWindows` 等。 |
| 标签切换性能与内存 | WKWebView/委托常驻，host 默认只挂当前和最近 4 个，未挂载标签切换时重新挂载原对象。 | `TabSwitchPerformanceTests.switchingLoadedTabs`：真实模式页面加载失败即失败并报告 URL；20 个本地重页面全挂、挂 3 个、挂 4 个峰值 RSS 实测约 1.466/1.397/1.531 GB；挂 4 个未挂载标签切换主线程 p95 13.29 ms。 |
| P3 JS 对话框 | alert、confirm、prompt 使用所属窗口的原生 sheet。 | `JavaScriptDialogTests`：本地页面覆盖确认、输入以及取消后的 `false` / `null`。 |
| P8 有效证书 | 先执行 `SecTrustEvaluateWithError`，有效证书走 `.performDefaultHandling`，不进入错误页。 | `ValidCertificateTests`：本地 CA 与 CA 签发的 localhost 证书真实加载。CA 只注入该次 `SecTrust` 评估，测试用 `validTrustHandler` 避免修改系统信任；生产默认处置不变。修复前测试超时，修复后通过。 |
| P8 子资源隔离 | 只有质询源与主框架导航源一致时才显示错误页；子资源失败只拒绝该请求。 | `SubresourceCertificateTests`：HTTP 主页面 fetch 坏证书 HTTPS 子资源，修复前主页面被劫持，修复后 URL、标题和正文保持。 |
| P8 继续入口安全 | 一次性 UUID 绑定当前错误页、pending URL 和同一份 `SecTrust`；新主框架导航或使用后立即作废。 | `CertificateContinuationSecurityTests`：恶意页面复用旧继续 URL，修复前会放行，修复后留在原页且旧证书未获信任；新错误页 token 不同。 |
| P8 会话例外 | 无效证书显示错误页；例外仅内存保存当前源与证书，不写持久化。 | `CertificateTests`：无效证书错误页、合法按钮继续、同源会话内重载，以及不同端口仍需确认。 |
| P11 崩溃恢复 | 每个标签页第一次 WebContent 崩溃自动 reload；再次崩溃显示无按钮错误页。 | `WebContentRecoveryTests` 验证状态；`WebContentRecoveryIntegrationTests` 验证只自动重载一次，随后显示错误页。 |
| P14 缩放记忆 | 存储键与规范化域名分离，始终写入 `MiniBrowserZoomLevels`。 | `SiteZoomSettingsTests.persistence`：固定 key 写入和新实例读回；`normalizedHost` 覆盖大小写和 `www`。 |
| P9 UA | 所有页面使用同一 Safari UA，保留真实 WebKit 版本，不按域名分支。 | `UserAgentTests`：两个本地源的请求头与 `navigator.userAgent` 一致，含 Safari/WebKit 段且不含 Chrome。 |
| 测试与副本隔离 | suite 由 `MINIBROWSER_DEFAULTS_SUITE` / `-defaultsSuite` 指定；数据目录由 `MINIBROWSER_DATA_DIRECTORY` / `-dataDirectory` 指定。`make run` 自动使用并清理独立副本。 | `RuntimeEnvironmentTests` 验证参数优先级、独立 HOME 和 suite 写入；`Scripts/test.sh` 对真实 `com.zhao.minibrowser.plist` 做前后 SHA-256 比较，并断言无 `MiniBrowserCoreTests.*.plist` 遗留。 |

## 有意不做的验证

`UnsupportedFeatureTests` 使用本地附件和 `weixin:` 页面验证取消导航后仍停留在原页。媒体权限委托固定返回 `.deny`，不弹框；当前 WKWebView 测试上下文未暴露 `mediaDevices`，因此不做真实硬件或权限 UI 测试。文件上传保持 WebKit 默认禁用；Basic 认证无自定义 UI；没有默认浏览器入口。完整范围见 `DEVELOPMENT.md` 的“有意不做”。
