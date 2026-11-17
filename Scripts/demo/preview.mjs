// 本地预览官网和 README：起一个只绑 127.0.0.1 的静态服务，用 Playwright 截全页图。
// 用法: node Scripts/demo/preview.mjs <输出目录>
import { createServer } from 'node:http';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../..');
const out = path.resolve(process.argv[2] || path.join(root, '.local/preview'));
mkdirSync(out, { recursive: true });
const require = createRequire(path.join(execFileSync('npm', ['root', '-g']).toString().trim(), '@playwright/cli/node_modules/'));
const { chromium } = require('playwright');

// README 用 GitHub 自己的 Markdown 渲染接口转成 HTML，外面套一层接近 GitHub 的样式
const readmeCSS = `
  body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", "Noto Sans", Helvetica, Arial, sans-serif; }
  :root { --bg: #ffffff; --fg: #1f2328; --line: #d1d9e0; --code: #f6f8fa; --link: #0969da; --mute: #59636e; }
  @media (prefers-color-scheme: dark) { :root { --bg: #0d1117; --fg: #f0f6fc; --line: #3d444d; --code: #151b23; --link: #4493f8; --mute: #9198a1; } }
  .box { max-width: 1012px; margin: 24px auto; border: 1px solid var(--line); border-radius: 6px; }
  .bar { padding: 8px 16px; border-bottom: 1px solid var(--line); font-size: 14px; font-weight: 600; }
  article { padding: 32px; }
  a { color: var(--link); text-decoration: none; }
  h1, h2 { border-bottom: 1px solid var(--line); padding-bottom: .3em; font-weight: 600; margin: 24px 0 16px; }
  h1 { font-size: 2em; margin-top: 0; } h2 { font-size: 1.5em; }
  p, ul, table, pre { margin: 0 0 16px; }
  img { max-width: 100%; box-sizing: content-box; }
  code { font: 85% ui-monospace, SFMono-Regular, Menlo, monospace; background: var(--code); padding: .2em .4em; border-radius: 6px; }
  pre { background: var(--code); padding: 16px; border-radius: 6px; overflow: auto; }
  pre code { background: none; padding: 0; font-size: 85%; }
  table { border-collapse: collapse; } th, td { border: 1px solid var(--line); padding: 6px 13px; } th { font-weight: 600; }
  tr:nth-child(2n) { background: var(--code); }
  .markdown-heading .anchor { display: none; }
`;
for (const [name, file] of [['readme-zh', 'README.md'], ['readme-en', 'README.en.md']]) {
  const html = execFileSync('gh', ['api', 'markdown', '-f', `text=${readFileSync(path.join(root, file), 'utf8')}`,
    '-f', 'mode=markdown', '-f', 'context=zhiyozhao/MiniBrowser']).toString();
  writeFileSync(path.join(root, '.local', `${name}.html`),
    `<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="color-scheme" content="light dark"><style>${readmeCSS}</style></head>` +
    `<body><div class="box"><div class="bar">${file}</div><article>${html}</article></div></body></html>`);
}

const types = { '.html': 'text/html; charset=utf-8', '.css': 'text/css', '.png': 'image/png', '.js': 'text/javascript' };
const server = createServer((req, res) => {
  let p = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  let file;
  if (p.startsWith('/MiniBrowser/')) {
    file = path.join(root, 'docs', p.slice('/MiniBrowser/'.length));
    if (p.endsWith('/')) file = path.join(file, 'index.html');
  } else if (p.startsWith('/readme/')) {
    file = p === '/readme/zh' ? path.join(root, '.local/readme-zh.html')
      : p === '/readme/en' ? path.join(root, '.local/readme-en.html')
      : path.join(root, p.slice('/readme/'.length));
  }
  if (!file || !file.startsWith(root) || !existsSync(file)) { res.writeHead(404).end(); return; }
  res.writeHead(200, { 'content-type': types[path.extname(file)] || 'application/octet-stream' });
  res.end(readFileSync(file));
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const base = `http://127.0.0.1:${server.address().port}`;

const cache = path.join(os.homedir(), 'Library/Caches/ms-playwright');
const shell = existsSync(cache) && readdirSync(cache).filter(d => d.startsWith('chromium_headless_shell-')).sort().pop();
const executablePath = shell && path.join(cache, shell, 'chrome-headless-shell-mac-arm64/chrome-headless-shell');
const browser = await chromium.launch(executablePath && existsSync(executablePath) ? { executablePath } : {});

const devices = { desktop: { viewport: { width: 1440, height: 900 }, deviceScaleFactor: 2 },
                  mobile: { viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true } };
const jobs = [];
for (const theme of ['light', 'dark']) {
  for (const lang of ['zh', 'en']) {
    for (const device of ['desktop', 'mobile']) {
      jobs.push({ name: `site-${lang}-${theme}-${device}`, url: `${base}/MiniBrowser/${lang === 'en' ? 'en/' : ''}`, theme, device });
    }
    // README 预览里的相对图片路径以仓库根目录为基准
    jobs.push({ name: `readme-${lang}-${theme}`, url: `${base}/readme/${lang}`, theme, device: 'desktop', readme: true });
  }
}
for (const job of jobs) {
  const ctx = await browser.newContext({ ...devices[job.device], colorScheme: job.theme });
  const page = await ctx.newPage();
  const failed = [];
  page.on('requestfailed', r => failed.push(r.url()));
  page.on('response', r => { if (r.status() >= 400) failed.push(`${r.status()} ${r.url()}`); });
  await page.goto(job.url);
  if (job.readme) {
    // GitHub 渲染后的图片地址指向 github.com 上的仓库文件，改为本地分支里的文件
    await page.evaluate(() => {
      for (const el of document.querySelectorAll('img, source')) {
        const attr = el.tagName === 'IMG' ? 'src' : 'srcset';
        const v = el.getAttribute(attr) || '';
        const m = v.match(/\/(?:blob|raw)\/[^/]+\/(.+)$/) || v.match(/^(docs\/.+)$/);
        if (m) el.setAttribute(attr, '/readme/' + m[1]);
        el.removeAttribute('data-canonical-src');
      }
      for (const a of document.querySelectorAll('a[target]')) a.removeAttribute('target');
      // github.com 上由 <themed-picture> 脚本按主题切换；本地预览去掉包在 img 外的链接，让 <source> 直接生效
      for (const a of document.querySelectorAll('picture > a')) a.replaceWith(...a.childNodes);
    });
  }
  await page.waitForLoadState('networkidle');
  await page.evaluate(() => Promise.all([...document.images].map(i => i.complete ? null : i.decode().catch(() => null))));
  const file = path.join(out, `${job.name}.png`);
  await page.screenshot({ path: file, fullPage: true });
  const bad = failed.filter(u => !u.includes('camo.githubusercontent'));
  console.log(job.name, bad.length ? `FAILED: ${bad.join(', ')}` : 'ok');
  await ctx.close();
}
await browser.close();
server.close();
