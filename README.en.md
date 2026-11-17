<p align="center">
  <img src="docs/assets/icon-256.png" width="128" height="128" alt="">
</p>

<h1 align="center">MiniBrowser</h1>

<p align="center">
  A macOS browser that shrinks to a very small window, so a page can stay open in a corner of your screen.<br>
  <a href="README.md">中文</a> · English · <a href="https://zhiyozhao.github.io/MiniBrowser/en/">Website</a>
</p>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/hero-en-dark.png">
  <img src="docs/assets/hero-en-light.png" width="1200" alt="Mock-up: on the left, an editor window drawn with grey blocks; in the top-right corner, a real screenshot of a 320 pt wide MiniBrowser window showing a sample article">
</picture>

## Install

Requires macOS 13 or later. The menus are in Chinese; the toolbar is icons only.

**With Homebrew**

```bash
brew install --cask zhiyozhao/tap/minibrowser
```

**By hand**

1. Download the DMG from [Releases](https://github.com/zhiyozhao/MiniBrowser/releases/latest).
2. Open the DMG and drag MiniBrowser into Applications.
3. If macOS says it can't verify the developer the first time you open it, close the message, go to System Settings → Privacy & Security, and click "Open Anyway" near the bottom.

## Features

- **Usable at any width.** The narrower the window, the fewer buttons it shows, down to just the address bar.
- **Its own sign-ins and data.** Accounts and cookies in MiniBrowser belong to MiniBrowser alone and don't touch the browser you use every day.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/widths-en-dark.png">
  <img src="docs/assets/widths-en-light.png" width="1200" alt="Real screenshots of MiniBrowser at 420, 300 and 228 pt wide on the same sample page: 420 pt shows back, forward, reload and new tab, 300 pt only back, 228 pt only the address bar">
</picture>

## Shortcuts

| Shortcut | Action |
| --- | --- |
| `⌘ T` | New tab |
| `⌘ W` | Close tab |
| `⌘ N` | New window |
| `⌘ [` / `⌘ ]` | Back / Forward |
| `⌘ R` | Reload |
| `⌘ -` / `⌘ =` / `⌘ 0` | Zoom out / Zoom in / Actual size |

Shortcuts keep working when a narrow window hides their buttons.

## Not supported

Downloading and uploading files, links that open other apps, camera and microphone, bookmarks, history.

## FAQ

**Does it remember the window size?**
No. Windows opened with `⌘ N` are always 1100 × 700.

**Some sites won't let me sign in?**
Some sign-in methods don't work, such as passkeys.

**How do I uninstall it?**
`brew uninstall --cask --zap minibrowser` also removes website data and settings. If you installed it by hand, drag MiniBrowser to the Trash.

---

[MIT License](LICENSE) · [Changelog](CHANGELOG.md)
