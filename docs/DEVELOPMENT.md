# 开发文档

环境、依赖与重建见 [SETUP.md](../SETUP.md)，项目约束见 [AGENTS.md](../AGENTS.md)。

## 模块与测试

- `MiniBrowserCore`：`AddressResolver` 负责地址栏输入，`BrowserWindowState` 负责单个窗口的标签顺序与选择，`SiteZoomSettings` 负责按规范化域名读写缩放。
- `MiniBrowser` executable：`BrowserWindowModel` 将纯状态映射到 `BrowserTab` / `WKWebView`，SwiftUI 和 AppKit 负责界面及窗口生命周期，`ZoomStore` 把 Core 的 `Double` 适配为 WebKit 使用的 `CGFloat`。
- `Tests/MiniBrowserCoreTests` 使用 Swift Testing。测试不创建 WebView、不访问真实网站、不读取用户真实设置；每个设置测试使用唯一 `UserDefaults` suite 并在结束时清理。
- `Tests/MiniBrowserIntegrationTests` 使用真实 NSWindow/WKWebView 和随机端口本地 HTTP 服务；自签 HTTPS 测试由系统 `/usr/bin/openssl` 生成临时证书并启动测试服，结束后终止进程、删除目录。有效证书用例另建本地 CA 和 CA 签发证书，只把 CA 注入该次 `SecTrust` 评估，不改系统钥匙串。所有测试不访问外部网站、不登录账号，也不需要辅助功能权限。
- `Scripts/test.sh` 给整个测试进程注入唯一 defaults suite 和 HOME 数据目录，比较真实 `com.zhao.minibrowser.plist` 的前后 SHA-256，并检查无 `MiniBrowserCoreTests.*.plist` 遗留。Core 测试清理时同步执行独立 suite 的 `defaults delete`，避免 cfprefsd 并行重建空 plist。

核心逻辑修改采用红绿 TDD：先运行能复现问题的测试并确认失败，再实现修改。不要为了通过测试而删除用例、降低断言或加入 skip。

## 行为边界

地址栏保留原有规则：空输入不导航；显式 HTTP(S) URL 直接打开；不含空格且含点的输入补 `https://`；其他输入交给 Bing。站点缩放继续使用 `MiniBrowserZoomLevels`，域名忽略大小写和开头的 `www.`。

UA 对所有网站统一使用 Safari 身份。实现选择 `applicationNameForUserAgent = "Version/18.0 Safari/605.1.15"`，而不是维护一份完整 UA：WKWebView 会继续提供真实系统和 AppleWebKit 版本，只补上 Safari 识别段，避免完整伪造在系统升级后长期失配，也不存在按域名切换造成的子资源身份错位。

WebContent 崩溃恢复由 `WebContentRecoveryState` 限制为每个标签页一次自动 reload；后续崩溃只显示最简错误页，避免刷新循环，不加入重试按钮。

证书例外由 `ServerTrustSession` 只存内存中的「scheme/host/port + 叶子证书数据」。首次 serverTrust 质询会取消并显示错误页；用户点击“仍然继续”后重试原 URL，后续相同质询才通过 `URLCredential(trust:)` 接受。继续 URL 含一次性 UUID，只在当前错误页、该次 pending 导航和同一份 `SecTrust` 上有效；任何新的主框架导航都会清空 pending，使用后也立即作废，其他页面不能用固定内部 URL 触发放行。不能写入 UserDefaults、钥匙串或系统信任设置，也不能把例外扩展到其他源或其他证书。

弹窗由 `createWebViewWith` 同步返回真实 WebView，不能改成另开标签或重新加载 URL，否则会丢失 opener、POST 和 `window.close()`。弹窗窗口固定为 520×640，复用 WebKit 传入的 configuration，并显式沿用 opener 的 websiteDataStore。

`BrowserWindowState` 只存 UUID，不持有 WebView。关闭选中标签时优先选择原位置的后一个标签，末尾则选择前一个；关闭未选中标签不改变选择。正常 UI 关闭最后一个标签仍由窗口层处理，本次拆分没有改变该流程。

## 有意不做

以下均按用户明确的极简定位排除，不增加替代面板、设置或外开入口：

- **下载**：不实现 `WKDownload`；附件和无法显示的 MIME 响应直接取消导航，停留在当前页面。
- **文件上传**：不实现 `runOpenPanelWith`，保持 WebKit 默认禁用行为，不弹文件选择器。
- **外部 App 协议**：不调用 `NSWorkspace`，`weixin:`、`alipays:`、`mailto:` 等直接取消导航，不弹确认框。
- **摄像头和麦克风**：权限请求直接拒绝，不弹框、不记忆选择，Info.plist 不增加用途说明。
- **HTTP Basic 认证**：不提供账号密码输入框，非 serverTrust 质询交回 WebKit 默认处理。
- **默认浏览器打开**：不添加菜单、快捷键或自动外开逻辑。

## 已知限制

- P6：YouTube 首页信息流问题未处理，播放页问题不在本次修复范围。
- P10：WKWebView 的 ITP / 第三方 Cookie 没有受支持的关闭 API，嵌套登录和 3DS 仍可能失败。
- P12：WebAuthn / 通行密钥需要额外 App 集成，本次不支持。
- P13：网页定位与通知未接入；证书错误则由上方的会话内例外流程处理。

## 构建、签名与产物

`Scripts/build-app.sh` 是唯一的 app 组装入口：release 构建、复制可执行文件和图标、写入 tag 版本、用 `DEV X` 签名并校验。找不到证书会直接失败，不再回退 ad-hoc。

`Scripts/version.sh` 用最近 git tag 作为本地 app/DMG 和 CI 的产品版本来源。`Resources/Info.plist` 中的静态版本只是模板；构建只修改 app 内副本。CI 仍按原流程为发布构建写入 `GITHUB_RUN_NUMBER` 作为 bundle build number。

`make package` 和 release workflow 使用相同 DMG 结构：`MiniBrowser.app`、`/Applications` 符号链接、UDZO，资产名为 `MiniBrowser-VERSION.dmg`。不要改变 `com.zhao.minibrowser`、app 名、DMG 模板或 release secrets。

Release 说明由 `Scripts/release-notes.sh` 截取 CHANGELOG 的对应版本段，缺段或空段会失败。这一改动只替换 `gh release create` 的 notes 来源；tag 触发、DEV X 签名、DMG 资产名和 cask URL 格式均不变，因此不影响发布与 Homebrew 兼容。

发布清单：更新 CHANGELOG → `make check` → 提交并推送 main → 打 annotated `vX.Y.Z` tag 并推送 → 等 Release 和 tap 同步完成。版本无需手改 Info.plist；开发任务中不执行推送或打 tag。

## 运行与调试安全

`make run` 只执行本仓库 app 内的二进制，记录其 PID，5 秒后结束并等待该 PID；异常退出时也由 trap 清理。不要用 `killall MiniBrowser`，不要操作用户正在运行的实例或 `/Applications/MiniBrowser.app`。

单元测试不覆盖真实网页加载、UA 指纹或网站兼容性。需要调查网站问题时，应单独记录 URL、导航/重定向过程、UA 和 WebKit 错误，不在本检查流程中访问真实网站。
