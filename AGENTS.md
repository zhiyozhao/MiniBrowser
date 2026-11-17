# MiniBrowser

macOS 极简独立浏览器：SwiftPM executable + `MiniBrowserCore` library，SwiftUI / AppKit / WKWebView，macOS 13+，无 Xcode 工程。

## 命令与完成定义

- `make check`：plist/脚本静态检查、Swift Testing、debug 构建；必须退出 0 且测试数大于 0。
- `make run`：release 组装和 DEV X 签名，启动 5 秒冒烟后只关闭本次仓库内进程。
- `make package`：复用发布结构，产出 `MiniBrowser.app`、`MiniBrowser-<版本>.dmg`。
- 环境、重建、CI 见 `SETUP.md`；模块与发布说明见 `docs/DEVELOPMENT.md`。
- 核心逻辑用红绿 TDD；完成前 `make check` 全绿并提交。单元测试不用固定 sleep，不删测试或加 skip 来求绿。
- 不安装全局工具，不 push、打 tag、改 GitHub 设置或读取签名证书文件；这些边界上报 Devs。

## 模块与可测试性

- `Sources/MiniBrowserCore`：地址栏解析、窗口标签状态、站点缩放设置；只依赖 Foundation。
- `Sources/MiniBrowser`：app 生命周期、SwiftUI/AppKit 界面、WKWebView 和缩放适配。
- `Tests/MiniBrowserCoreTests` 使用 Swift Testing；设置测试必须注入独立 `UserDefaults` suite，不能读写用户真实偏好。
- 不把 WebKit 或 AppKit 引入 Core；跨 target 的行为由 Core API 表达，UI 外壳保持轻量。
- 地址栏仍是 HTTP(S) 直开、带点开头的域名补 HTTPS、其余 Bing 搜索；改动解析规则先补边界测试。

## 打包与发布（不可破坏）

- bundle id `com.zhao.minibrowser`、app 名 `MiniBrowser.app`、DMG `MiniBrowser-VERSION.dmg`、`v*` tag 发布和 Homebrew cask 接口保持不变。
- 本地和 CI 都只用钥匙串中的自签名 **DEV X**；找不到证书直接失败，禁止 ad-hoc 回退。不要读取或修改 `~/Codes/dev-x-signing`。
- release secrets 仍是 `SIGNING_P12_BASE64`、`SIGNING_P12_PASSWORD`；不要改名或增加发布前置条件。
- `Scripts/version.sh` 从最近 tag 读取版本；Release 说明由 `Scripts/release-notes.sh` 从 CHANGELOG 对应版本段生成，缺段或空段必须失败。
- `make package` 与 release workflow 必须保持相同 DMG 结构：app、`/Applications` 符号链接、UDZO。

## 操作边界与已知事项

- 只在当前工作副本操作，不碰 `~/Codes/MiniBrowser`。不要退出、重启或替换 `/Applications/MiniBrowser.app` 及用户正在运行的实例。
- `make run` 只允许结束自己启动的 PID；签名或钥匙串等待超过 2 分钟应停止并报告，不反复重试。
- 网站兼容性需要另行调查和验证，不在 Core 单元测试中访问真实网站。
