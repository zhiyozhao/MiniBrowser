# MiniBrowser

[中文](README.md) · English · [Website](https://zhiyozhao.github.io/MiniBrowser/en/) · [Install](#install)

A macOS browser that can shrink to a very small window, kept apart from the browser you normally use.<br>
Leave a page open in a corner of the screen and keep working.

## Install

```bash
brew install --cask zhiyozhao/tap/minibrowser
```

Or download the DMG from [Releases](https://github.com/zhiyozhao/MiniBrowser/releases/latest) and drag MiniBrowser into Applications. Requires macOS 13 or later. The menus are in Chinese; the toolbar is icons only.

If you install from the DMG, macOS says it can't verify the developer the first time you open it, because the app isn't notarized by Apple. Open it once, then go to System Settings → Privacy & Security and click "Open Anyway" near the bottom. Installing with Homebrew avoids this.

## How it differs from a normal browser

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/assets/hero-en-dark.png">
  <img src="docs/assets/hero-en-light.png" width="1200" alt="Mock-up: on the left, an editor window drawn with grey blocks; in the top-right corner, a real screenshot of a 320 pt wide MiniBrowser window showing a sample article">
</picture>

- **The window shrinks to 228 × 360 pt.** The narrower it gets, the fewer buttons it shows, down to just the address bar. Shortcuts still work for the buttons that fold away.
- **Fully separate from your other browsers.** Its cookies, cache and sign-ins are its own. It can't see your accounts or history in Safari or Chrome, and pages opened here don't show up there. No accounts, no analytics.

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

## Left out on purpose

Downloads, file uploads, opening other apps (such as `mailto:` links), camera and microphone, bookmarks and history. Clicking a download link does nothing.

## FAQ

**Does it remember the window size?**
No. Windows opened with `⌘ N` are always 1100 × 700; sign-in and payment pop-ups opened by a page are 520 × 640.

**Some sites won't let me sign in?**
MiniBrowser doesn't support passkeys, and sign-ins that rely on third-party cookies may fail.

**How do I uninstall it?**
`brew uninstall --cask --zap minibrowser` removes the app along with its website data, cookies, cache and settings.

---

[MIT License](LICENSE) · [Changelog](CHANGELOG.md) · [Development notes](docs/DEVELOPMENT.md)
