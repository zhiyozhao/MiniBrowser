// 把 capture.sh 截到的窗口原图合成为 README / 官网用的 2x PNG。
// 用法: node Scripts/demo/render.mjs   （需要全局安装的 Playwright 及其 Chromium）
import { copyFileSync, existsSync, mkdirSync, readdirSync } from 'node:fs';
import os from 'node:os';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const work = path.join(root, '.local/demo');
const out = path.join(root, 'docs/assets');
const globalRoot = execFileSync('npm', ['root', '-g']).toString().trim();
const require = createRequire(path.join(globalRoot, '@playwright/cli/node_modules/'));
const { chromium } = require('playwright');

mkdirSync(out, { recursive: true });
copyFileSync(path.join(here, 'scene.html'), path.join(work, 'scene.html'));

const scenes = [
  { kind: 'hero', w: 1200, h: 720 },
  { kind: 'widths', w: 1200, h: 560 },
  { kind: 'corner', w: 640, h: 720 },
  { kind: 'bars', w: 560, h: 380 },
];
// 全局 Playwright 与已下载的浏览器版本不一致时，退回到缓存中最新的 headless shell
const cache = path.join(os.homedir(), 'Library/Caches/ms-playwright');
const shell = existsSync(cache) && readdirSync(cache).filter(d => d.startsWith('chromium_headless_shell-')).sort().pop();
const executablePath = process.env.DEMO_CHROMIUM
  || (shell ? path.join(cache, shell, 'chrome-headless-shell-mac-arm64/chrome-headless-shell') : undefined);
const browser = await chromium.launch(executablePath && existsSync(executablePath) ? { executablePath } : {});
for (const theme of ['light', 'dark']) {
  const page = await browser.newPage({ deviceScaleFactor: 2, colorScheme: theme });
  for (const lang of ['zh', 'en']) {
    for (const s of scenes) {
      await page.setViewportSize({ width: s.w, height: s.h });
      const url = pathToFileURL(path.join(work, 'scene.html'));
      url.search = new URLSearchParams({ theme, lang, kind: s.kind, w: s.w, h: s.h });
      await page.goto(url.href);
      await page.evaluate(() => Promise.all([...document.images].map(i => i.decode())));
      const file = path.join(out, `${s.kind}-${lang}-${theme}.png`);
      await page.screenshot({ path: file });
      console.log(path.relative(root, file));
    }
  }
  await page.close();
}
await browser.close();
