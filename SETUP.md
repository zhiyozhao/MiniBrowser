# SETUP — MiniBrowser

## 环境

- macOS 13+ 可运行，开发与 CI 使用 macOS 15。
- Xcode 16+（需包含 Swift Testing）；本机使用 Xcode 26.3 / Swift 6.2.4。
- 仅使用 SwiftPM 本地 target，无第三方包依赖，无需额外生成 Xcode 工程。
- 钥匙串必须有自签名代码签名证书 `DEV X`。项目不保存证书或密码，不读取证书文件，也不回退 ad-hoc 签名。
- 不需要 brew、npm、Python、端口、模拟器或后台开发服务。

## 常用命令

```bash
make check       # plist/脚本语法检查 + Swift Testing + debug 构建
make run         # release .app + DEV X 签名；启动 5 秒冒烟后关闭本次进程
make package     # MiniBrowser.app + MiniBrowser-<最近 tag 版本>.dmg
make clean       # 清理构建产物
```

`make check` 不需要签名、外部网络或系统隐私权限。`make run` 和 `make package` 需要 DEV X；`make run` 只启动仓库内构建的 `MiniBrowser.app`，不会关闭或重启 `/Applications/MiniBrowser.app`。

## 测试与本地副本隔离

`make check` 和 `make run` 都自动使用独立 UserDefaults suite 与数据目录，并在结束后清理；不会把测试缩放值写进用户的 `com.zhao.minibrowser.plist`。手工运行副本时可显式指定：

```bash
MINIBROWSER_DEFAULTS_SUITE=MiniBrowser.Local \
MINIBROWSER_DATA_DIRECTORY="$PWD/.local/manual" \
MiniBrowser.app/Contents/MacOS/MiniBrowser

# 等价启动参数
MiniBrowser.app/Contents/MacOS/MiniBrowser \
  -defaultsSuite MiniBrowser.Local \
  -dataDirectory "$PWD/.local/manual"
```

环境变量优先于启动参数。`cfprefsd` 不随 HOME 隔离，所以偏好必须使用独立 suite；WebKit 数据目录则在首次创建 WebView 前通过 HOME / CFFIXED_USER_HOME 隔离。`Scripts/test.sh` 还会逐字节比较检查前后的真实应用 plist，并检查测试 suite 文件已删除。

产物位于仓库根目录：`MiniBrowser.app`、`MiniBrowser-<版本>.dmg`，临时 DMG 目录为 `dmg/`。这些文件均被 git 忽略。

## CI 与发布

- `.github/workflows/check.yml` 在分支 push 和 PR 的 `macos-15` runner 上执行 `make check`。
- `.github/workflows/release.yml` 仍由 `v*` tag 触发；secrets 为 `SIGNING_P12_BASE64`、`SIGNING_P12_PASSWORD`。
- 本地 app/DMG 与 CI 都通过 `Scripts/version.sh` 从最近 git tag 读取版本。
- Release 说明来自 CHANGELOG 对应版本段；app 名、bundle id、DMG 命名和 Homebrew cask 接口不变。

## 重建与排障

```bash
make clean
rm -rf .build       # SwiftPM 缓存损坏时才需要
make check
make package
```

- 找不到 `Testing`：确认 `xcode-select -p` 指向完整 Xcode 16+，而非仅 Command Line Tools。
- 签名失败：`security find-certificate -c "DEV X"` 应能找到证书；缺失时停止，不要改用 ad-hoc。
- 钥匙串弹窗或签名等待超过 2 分钟：停止并报告，不要反复重试。
- 版本读取失败：确认仓库含有可读的 `v*` tag；不要通过手改 Info.plist 代替 tag。
- 单测异常读写真实设置：检查是否给 `SiteZoomSettings` 注入了独立 suite；生产单例才使用 `UserDefaults.standard`。

## 本项目额外安装

无。
