# MiniBrowser

中文 | [English](README.en.md)

一个可以缩到很小的独立浏览器窗口。放在屏幕一角悄悄打开网页，和你平时用的浏览器互不打扰。

[![最新版本](https://img.shields.io/github/v/release/zhiyozhao/MiniBrowser?label=%E6%9C%80%E6%96%B0%E7%89%88%E6%9C%AC)](https://github.com/zhiyozhao/MiniBrowser/releases/latest)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-black)

<img src="docs/assets/demo-small.png" alt="缩到很小的 MiniBrowser 窗口停在网页一角，地址栏和前进后退按钮都还在" width="340">

```bash
brew install --cask zhiyozhao/tap/minibrowser
```

不用 Homebrew 的话，到 [Releases](https://github.com/zhiyozhao/MiniBrowser/releases/latest) 下载 DMG，把 MiniBrowser 拖进“应用程序”。支持 macOS 13 及以上。

## 亮点

- **窗口可以很小。** 最小缩到 228×360，缩窄时按钮会自动一个个让位，地址栏一直可用。
- **和平时用的浏览器分开。** 独立窗口、独立 Cookie、独立缓存，不读取也不共享 Safari、Chrome 的任何数据，放在一旁隐蔽使用互不干扰。
- **不打扰。** 没有通知、没有账号、没有推送，不请求摄像头和麦克风权限。
- 网页里的弹窗（登录、支付这类小窗口）会正常打开，登录状态不会丢。
- 网页弹出的 alert / confirm / prompt 对话框正常显示；证书出错时可以选择“仍然继续”。
- 页面崩溃后自动重新加载；每个网站的缩放比例会被记住。

## 怎么用

<img src="docs/assets/demo.png" alt="普通大小的 MiniBrowser 窗口，顶部是地址栏和前进后退刷新按钮，窗口里打开着网页" width="960">

**快捷键**

| 快捷键 | 作用 |
| --- | --- |
| `Command + T` | 新建标签页 |
| `Command + W` | 关闭标签页（只剩一个标签时关闭窗口） |
| `Command + N` | 新建窗口 |
| `Command + [` / `Command + ]` | 后退 / 前进 |
| `Command + R` | 刷新（加载中按下为停止） |
| `Command + -` / `Command + =` / `Command + 0` | 缩小 / 放大 / 实际大小 |
| `Command + Q` | 退出 |

**地址栏**：直接输入网址就打开网址；输入文字就用 Bing 搜索。新建标签页会自动聚焦地址栏，落地就能打字。

**窗口**：想缩多小就缩多小（下限 228×360），顶部空白处可以拖动窗口；窗口的大小和位置会被记住。标签开多了才出现标签栏，平时只有一行地址栏。网页本身也支持触控板双指缩放，缩放比例按网站分别记住。

## 隐私

- MiniBrowser 自己不联网：除了你打开的网页本身加载内容，没有任何上报、统计或账号体系。
- 所有数据都留在本机：网页的 Cookie 和缓存在 `~/Library/WebKit/com.zhao.minibrowser`，设置（各网站缩放比例、窗口位置）在 `~/Library/Preferences/com.zhao.minibrowser.plist`。
- 和其他浏览器完全隔离：不读取 Safari、Chrome 的历史、Cookie 和密码，自己的登录状态也不会带出去。
- 证书“仍然继续”的例外只记在内存里，退出 MiniBrowser 就失效，不会写进任何文件。
- 网站索要摄像头、麦克风权限时一律直接拒绝，不弹框、不记忆。

## 常见问题

**为什么不能下载文件、上传文件？**
有意不做的。MiniBrowser 是极简的小窗浏览器，不是完整浏览器；下载、文件上传、跳转外部 app、摄像头和麦克风这些都明确不做。遇到下载链接时 MiniBrowser 会停在当前页面，不会开始下载。

**点了“用微信打开”“发邮件”这类按钮没反应？**
同样是有意不做的。MiniBrowser 不跳转到其他 app，这类链接会被直接忽略。

**打开证书出错的网站怎么办？**
MiniBrowser 会显示错误页，确认网站没问题的话可以点“仍然继续”。例外只对这个站点、本次运行有效，退出后要重新确认。

**打开 DMG 里的 app 时，提示“无法验证开发者”？**
这个 app 没有经过 Apple 公证。macOS 15 上先双击打开一次，再到“系统设置 → 隐私与安全性”页面底部点“仍要打开”，输入密码确认；macOS 14 也可以在 Finder 中右键选择“打开”。用 Homebrew 安装会自动处理下载隔离，不会遇到这个提示。

**怎么卸载？**
执行 `brew uninstall --cask --zap minibrowser` 会同时清掉偏好设置；或者把“应用程序”里的 MiniBrowser 拖到废纸篓。想删干净的话，再手动移除 `~/Library/WebKit/com.zhao.minibrowser` 和 `~/Library/Preferences/com.zhao.minibrowser.plist`。

## 许可证

[MIT](LICENSE)

---

[更新记录](CHANGELOG.md) · [开发文档](docs/DEVELOPMENT.md)
