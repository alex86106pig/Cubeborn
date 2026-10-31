// 檢查與推送（Windows / Mac 都能跑，只用 Node 內建模組）。規則見 PROJECT_GUIDELINES.md 第 12、13 節
//   node tools/release.mjs --check                        只跑 Godot 匯入 + check.gd（有逾時）
//   node tools/release.mjs --web                          匯出網頁版並開本機伺服器 http://localhost:8060（--port 換埠）
//   node tools/release.mjs --perf                         匯出網頁版，在不開視窗的 Chrome 原地轉身 30 秒量效能（--chrome <路徑> 或環境變數 CHROME；環境變數 PERF_QUERY 換網址參數）
//   node tools/release.mjs --balance                      跑平衡數字表（武器、技能、怪物），寫進 docs/平衡數字.md
//   node tools/release.mjs --load                         匯出網頁版，在不開視窗的 Chrome 開兩次（沒有 / 有瀏覽器快取），量開場時間軸與著色器編譯
//   node tools/release.mjs --summary "摘要"               推送：更新（rebase）→ 決定版號 → 檢查 → commit + tag → push
//   node tools/release.mjs --summary "摘要" --dry-run     不動 git 歷史、不推：只 fetch、算版號、改檔跑檢查，最後還原
//   加 --bump=minor|patch 可以蓋過自動判斷的版號
// Godot：--godot <console 執行檔路徑> 或環境變數 GODOT（每台電腦的路徑寫在 CLAUDE.local.md）
// git：環境變數 GIT，沒有就用 PATH 上的 git（Windows 找不到時改用 Program Files 裡的）
import { spawn, spawnSync } from 'node:child_process';
import { createReadStream, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { dirname, extname, join, normalize } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const GODOT_DIR = join(ROOT, 'godot');
const CHANGELOG = join(ROOT, 'CHANGELOG.md');
const VERSION_GD = join(ROOT, 'godot', 'core', 'version.gd');
const UNRELEASED = '## [未發布]';
// 逾時：-s 腳本有編譯錯誤時 Godot 不會結束（CLAUDE.md 5.2），一定要能自己停
// 正常：匯入幾秒～1 分鐘（新電腦第一次較久）、check.gd 約 25 秒（2026-10-25 RTX 3070）
const IMPORT_TIMEOUT = 5 * 60 * 1000;
const CHECK_TIMEOUT = 3 * 60 * 1000;

const args = process.argv.slice(2);
const opt = name => {
  const i = args.findIndex(a => a === `--${name}` || a.startsWith(`--${name}=`));
  if (i === -1) return null;
  return args[i].includes('=') ? args[i].slice(args[i].indexOf('=') + 1) : (args[i + 1] ?? '');
};
const has = name => args.includes(`--${name}`);

const fail = msg => { console.log(`✘ ${msg}`); process.exit(1); };

// CHANGELOG 設了 merge=union：對方推送後把他的 [未發布] 換成版號，我們 rebase 時自己的 [未發布] 會接在那個版號後面。
// 把所有 [未發布] 段合成一段、同名的「### 分類」合在一起，放回第一個版號前面
function normalizeUnreleased(text) {
  const lines = text.split('\n');
  const isHeading = l => l.startsWith('## [');
  const isUnreleased = l => l.trimEnd() === UNRELEASED;
  const firstHeading = lines.findIndex(isHeading);
  const count = lines.filter(isUnreleased).length;
  if (count === 0 || (count === 1 && isUnreleased(lines[firstHeading]))) return text;

  const trim = arr => { const a = [...arr]; while (a.length && !a[0].trim()) a.shift(); while (a.length && !a.at(-1).trim()) a.pop(); return a; };
  const kept = [], intro = [], sections = new Map();   // intro：[未發布] 底下、第一個「###」之前的文字
  let inside = false, cur = null, piece = [];
  const flush = () => {
    const p = trim(piece);
    if (p.length) (cur === null ? intro : sections.get(cur)).push(...(cur === null && intro.length ? ['', ...p] : p));
    piece = [];
  };
  for (const line of lines) {
    if (isHeading(line)) {
      if (inside) flush();
      inside = isUnreleased(line);
      cur = null;
      if (inside) continue;
    }
    if (!inside) { kept.push(line); continue; }
    if (line.startsWith('### ')) {
      flush();
      cur = line.trimEnd();
      if (!sections.has(cur)) sections.set(cur, []);
      continue;
    }
    piece.push(line);
  }
  if (inside) flush();

  const block = [UNRELEASED, ''];
  if (intro.length) block.push(...intro, '');
  for (const [name, body] of sections) if (body.length) block.push(name, ...body, '');
  const at = kept.findIndex(isHeading);
  kept.splice(at === -1 ? kept.length : at, 0, ...block);
  return kept.join('\n');
}

const GIT = process.env.GIT || (() => {
  if (spawnSync('git', ['--version']).status === 0) return 'git';
  const win = join(process.env.ProgramFiles || 'C:\\Program Files', 'Git', 'cmd', 'git.exe');
  return existsSync(win) ? win : 'git';
})();

function git(...a) {
  const r = spawnSync(GIT, a, { cwd: ROOT, encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  return { ok: r.status === 0, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
}

function gitOrFail(...a) {
  const r = git(...a);
  if (!r.ok) fail(`git ${a.join(' ')}\n    ${r.err || r.out}`);
  return r.out;
}

function godotPath() {
  const p = opt('godot') || process.env.GODOT;
  if (!p) fail('沒有指定 Godot：加 --godot <console 執行檔路徑> 或設環境變數 GODOT（路徑在 CLAUDE.local.md）');
  if (!existsSync(p)) fail(`找不到 Godot：${p}`);
  return p;
}

function runGodot(godot, a, timeout, label) {
  const r = spawnSync(godot, a, { cwd: GODOT_DIR, encoding: 'utf8', timeout, maxBuffer: 64 * 1024 * 1024 });
  if (r.error && r.error.code === 'ETIMEDOUT') {
    return { ok: false, out: `${label}超過 ${timeout / 60000} 分鐘沒結束，已強制停止（多半是腳本編譯錯誤，看下面的錯誤訊息）\n${(r.stderr || '').trim().split('\n').slice(-15).join('\n')}` };
  }
  if (r.error) return { ok: false, out: `${label}無法執行：${r.error.message}` };
  return { ok: r.status === 0, out: (r.stdout || '').trim(), err: (r.stderr || '').trim() };
}

// 匯入 + check.gd；印出 check.gd 的摘要（只有沒過的項目與總數，細節在 godot/tests/check_last.log）
function runChecks() {
  const godot = godotPath();
  const imp = runGodot(godot, ['--headless', '--import', '--path', '.'], IMPORT_TIMEOUT, '匯入');
  if (!imp.ok && imp.out.includes('強制停止')) { console.log(imp.out); return false; }
  const chk = runGodot(godot, ['--headless', '--path', '.', '-s', 'res://tests/check.gd'], CHECK_TIMEOUT, 'check.gd ');
  const lines = chk.out.split('\n').filter(l => !l.startsWith('Godot Engine') && !/^(Vulkan|OpenGL|WARNING)/.test(l));
  console.log(lines.join('\n').trim());
  // 要看到「N / N 通過」才算過：check.gd 編譯失敗時 Godot 照樣以 0 結束、什麼都不印（2026-10-27 踩過，會被當成通過）
  const total = chk.out.match(/(\d+) \/ (\d+) 通過/);
  if (!total) {
    const errs = `${chk.err || ''}\n${chk.out}`.split('\n').filter(l => /ERROR|Error/.test(l)).slice(-15).join('\n');
    console.log(`✘ check.gd 沒有跑完（沒有印出「N / N 通過」，多半是腳本編譯失敗）\n${errs}`);
    return false;
  }
  if (!chk.ok && !chk.out.includes('通過')) console.log((chk.err || '').split('\n').slice(-15).join('\n'));
  // 程式結束時沒釋放的物件（2026-10-27 查到兩種，都沒人發現：檢查建的實體沒加進 World 128 個、連線客戶端結束時音樂又被播起來 2 個）
  // 警告只印在 stderr（--log-file 那時已經關了）；check.gd 開的子程序（兩個程序連線、結束程式不洩漏）也共用這個 stderr，一起擋
  const leak = (chk.err || '').match(/\d+ ObjectDB instances were leaked|\d+ resources still in use at exit/);
  if (leak) {
    console.log(`✘ 結束時有物件沒釋放（${leak[0]}）：check.gd 本身多半是檢查建的實體沒加進 World、或 World 沒登錄到 _worlds；子程序多半是遊戲結束流程\n` +
      '    找是哪一項：在 godot/ 內 <Godot> --headless --path . -s res://tests/check.gd -- --only=標題開頭，逐項單獨跑看哪一項會出現這行');
    return false;
  }
  return chk.ok && total[1] === total[2];
}

if (has('check')) process.exit(runChecks() ? 0 : 1);

// 平衡數字表（godot/tests/balance_report.gd）：照現在的 defs/ 實際跑模擬，寫進 docs/平衡數字.md
if (has('balance')) {
  const godot = godotPath();
  const out = join(ROOT, 'docs', '平衡數字.md');
  runGodot(godot, ['--headless', '--import', '--path', '.'], IMPORT_TIMEOUT, '匯入');
  const r = runGodot(godot, ['--headless', '--path', '.', '-s', 'res://tests/balance_report.gd', '--', `--out=${out}`], CHECK_TIMEOUT, '平衡數字表');
  if (!r.ok || !r.out.includes('寫入')) fail(`平衡數字表沒有跑完\n${(r.err || r.out || '').split('\n').filter(l => /ERROR|Error/.test(l)).slice(-15).join('\n')}`);
  const off = readFileSync(out, 'utf8').split('\n').filter(l => /偏低|偏高/.test(l) && !/保留：/.test(l));
  console.log(`✔ 寫入 docs/平衡數字.md${off.length ? `；不在目標內 ${off.length} 項：\n${off.join('\n')}` : '；招式都在目標內（或標了保留）'}`);
  process.exit(0);
}

// 匯出網頁版到 build/web；字型不做子集化（CI 才做），第一次載入比網站慢
function exportWeb() {
  const godot = godotPath();
  const out = join(ROOT, 'build', 'web');
  mkdirSync(out, { recursive: true });
  const exp = runGodot(godot, ['--headless', '--path', '.', '--export-release', 'Web', '../build/web/index.html'], IMPORT_TIMEOUT, '匯出');
  if (!existsSync(join(out, 'index.wasm')) || !exp.ok) {
    const missing = /No export template found|template file not found/i.test(`${exp.out}\n${exp.err}`);
    fail(missing ? '找不到 Godot 的網頁版匯出模板：照 docs/新電腦設定.md 安裝' : `匯出失敗\n${`${exp.out}\n${exp.err || ''}`.trim().split('\n').slice(-15).join('\n')}`);
  }
  return out;
}

// 只聽本機的靜態伺服器（.wasm 要用 application/wasm 才能串流編譯）
function serveWeb(out, port) {
  const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8', '.wasm': 'application/wasm',
    '.pck': 'application/octet-stream', '.png': 'image/png', '.svg': 'image/svg+xml', '.json': 'application/json' };
  const server = createServer((req, res) => {
    const path = decodeURIComponent(new URL(req.url, 'http://x').pathname);
    const file = normalize(join(out, path === '/' ? 'index.html' : path));
    if (!file.startsWith(out) || !existsSync(file) || statSync(file).isDirectory()) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': types[extname(file)] || 'application/octet-stream', 'Cache-Control': 'no-store' });
    createReadStream(file).pipe(res);
  });
  return new Promise((resolve, reject) => { server.on('error', reject); server.listen(port, '127.0.0.1', () => resolve(server)); });
}

if (has('web') && !has('perf') && !has('load')) {
  const port = Number(opt('port')) || 8060;
  await serveWeb(exportWeb(), port).catch(e => fail(`開不了伺服器（埠 ${port}）：${e.message}`));
  console.log(`✔ 已匯出網頁版：http://localhost:${port}/（量幀時間加 ?perf；Ctrl+C 結束）`);
  await new Promise(() => {});   // 伺服器一直開著，不往下跑推送
}

// 網頁版效能：匯出後開獨立的 headless Chrome（自己的設定資料夾、不開視窗、關掉背景限速；新版 headless 照樣用顯示卡畫），
// 原地讓 60 群怪圍過來、每 0.5 秒用滑鼠來回轉身 180°，跑 30 秒；印出 WebGL 用的顯示卡、遊戲的 perf 統計、Console 錯誤
const PERF_SECONDS = 30;
const PERF_QUERY = process.env.PERF_QUERY || `?perf&seconds=${PERF_SECONDS}&horde=60&elites&player-hp=99999`;
const TURN_SECONDS = 0.5;

function chromePath() {
  const p = opt('chrome') || process.env.CHROME;
  if (p) return existsSync(p) ? p : fail(`找不到 Chrome：${p}`);
  const found = [
    join(process.env.ProgramFiles || 'C:\\Program Files', 'Google', 'Chrome', 'Application', 'chrome.exe'),
    join(process.env['ProgramFiles(x86)'] || 'C:\\Program Files (x86)', 'Google', 'Chrome', 'Application', 'chrome.exe'),
    join(process.env.LOCALAPPDATA || '', 'Google', 'Chrome', 'Application', 'chrome.exe'),
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  ].find(existsSync);
  return found || fail('找不到 Chrome：加 --chrome <路徑> 或設環境變數 CHROME（路徑寫在 CLAUDE.local.md）');
}

async function webPerf() {
  const chrome = chromePath();
  const port = Number(opt('port')) || 8061;
  const server = await serveWeb(exportWeb(), port).catch(e => fail(`開不了伺服器（埠 ${port}）：${e.message}`));
  const debugPort = 9333;
  const profile = mkdtempSync(join(tmpdir(), 'cubeborn-chrome-'));
  const proc = spawn(chrome, [
    `--remote-debugging-port=${debugPort}`, `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check',
    '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows',
    '--headless=new', '--mute-audio', '--disable-features=Translate', '--window-size=960,540', `http://localhost:${port}/${PERF_QUERY}`,
  ], { stdio: 'ignore' });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const lines = [];
  let hitches = 0, ok = false, timer = null;
  const close = async () => {
    clearInterval(timer);
    try {
      const v = await (await fetch(`http://127.0.0.1:${debugPort}/json/version`)).json();
      const b = new WebSocket(v.webSocketDebuggerUrl);
      b.onopen = () => b.send(JSON.stringify({ id: 1, method: 'Browser.close' }));
    } catch {}
    await sleep(1500);
    try { proc.kill(); } catch {}
    try { rmSync(profile, { recursive: true, force: true }); } catch {}
    server.close();
  };
  let page = null;
  for (let i = 0; i < 60 && !page; i++) {
    await sleep(500);
    try { page = (await (await fetch(`http://127.0.0.1:${debugPort}/json`)).json()).find(t => t.type === 'page' && t.url.includes(`:${port}/`)); } catch {}
  }
  if (!page) { await close(); fail('Chrome 開不起來或連不上除錯介面'); }
  await new Promise(resolve => {
    const ws = new WebSocket(page.webSocketDebuggerUrl);
    let id = 10;
    const send = (method, params = {}) => ws.send(JSON.stringify({ id: ++id, method, params }));
    const deadline = setTimeout(() => { lines.push('✘ 逾時：遊戲沒有印出 perf 統計'); resolve(); }, (PERF_SECONDS + 90) * 1000);
    ws.onopen = () => {
      send('Runtime.enable');
      // 實際畫 WebGL 的顯示卡（SwiftShader = 軟體繪製，數字不能用）
      ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { returnByValue: true, expression:
        "(() => { const g = document.createElement('canvas').getContext('webgl2'); const e = g && g.getExtension('WEBGL_debug_renderer_info'); return g ? (e ? g.getParameter(e.UNMASKED_RENDERER_WEBGL) : g.getParameter(g.RENDERER)) : '沒有 WebGL2'; })()" } }));
    };
    ws.onmessage = ev => {
      const m = JSON.parse(ev.data);
      if (m.id === 1) lines.push(`顯示卡：${m.result?.result?.value}`);
      if (m.method === 'Runtime.exceptionThrown') lines.push(`例外：${m.params.exceptionDetails.text}`);
      if (m.method !== 'Runtime.consoleAPICalled') return;
      const text = m.params.args.map(a => a.value ?? a.description ?? '').join(' ');
      if (/^perf load /.test(text)) return;   // 開場時間點是給 --load 的，不算遊戲開始跑
      if (/^perf hitch/.test(text)) { if (++hitches <= 20) lines.push(text); return; }
      // 第一行 perf 出現 = 遊戲開始跑了：開始來回轉身（滑鼠在畫面中央左右兩側，角色面向跟著滑鼠）
      if (/^perf|^Build configuration/.test(text) && !timer) {
        let side = 1;
        timer = setInterval(() => { side = -side; send('Input.dispatchMouseEvent', { type: 'mouseMoved', x: 472 + side * 250, y: 250 }); }, TURN_SECONDS * 1000);
      }
      if (/^perf /.test(text)) lines.push(text);
      else if (/ERROR|SCRIPT/.test(text) && !/webrtc_native|GDExtension/.test(text)) lines.push(`Console：${text}`);
      if (/^perf view_sync_parts_ms/.test(text)) { ok = true; clearTimeout(deadline); resolve(); }
    };
  });
  await close();
  console.log(lines.join('\n'));
  if (hitches > 20) console.log(`（hitch 共 ${hitches} 筆，只列前 20）`);
  return ok;
}

if (has('perf')) process.exit(await webPerf() ? 0 : 1);

// 網頁版開場載入（--load）：匯出後用全新設定資料夾的 headless Chrome 開兩次（第一次沒有瀏覽器的著色器快取、第二次有，
// 同玩家第一次 / 之後再來），攔截 WebGL 的著色器編譯，印出開場時間軸、編了幾個著色器程式、等編譯的時間與最慢的程式
// 程式類型看 Godot 編進去的 #define：一般繪製（BASE_PASS）、陰影深度（MODE_RENDER_DEPTH）、點光源疊加（USE_ADDITIVE_LIGHTING）
// 只量得到 WebGL 呼叫裡等編譯的時間；驅動延到第一次畫才編的部分算在預熱的其餘時間裡
const LOAD_TIMEOUT = 3 * 60 * 1000;
const LOAD_KEYS = ['BASE_PASS', 'MODE_RENDER_DEPTH', 'USE_ADDITIVE_LIGHTING', 'MODE_UNSHADED', 'USE_INSTANCING'];

// 在頁面裡執行（轉成字串注入）：每個程式的耗時 = 連結 + 查連結結果 + 它的著色器編譯與查編譯結果
function loadHook(keys) {
  const S = window.__load = { programs: [], marks: [], waitMs: 0 };
  const NL = String.fromCharCode(10);
  const src = new WeakMap(), shMs = new WeakMap(), att = new WeakMap(), prog = new WeakMap();
  const P = WebGL2RenderingContext.prototype;
  const timed = (name, after) => {
    const f = P[name];
    P[name] = function (...a) {
      const t = performance.now();
      const r = f.apply(this, a);
      const d = performance.now() - t;
      S.waitMs += d;
      after(a, d);
      return r;
    };
  };
  const ss = P.shaderSource;
  P.shaderSource = function (sh, code) { src.set(sh, code); return ss.call(this, sh, code); };
  const as = P.attachShader;
  P.attachShader = function (pr, sh) { if (!att.has(pr)) att.set(pr, []); att.get(pr).push(sh); return as.call(this, pr, sh); };
  timed('compileShader', (a, d) => shMs.set(a[0], (shMs.get(a[0]) || 0) + d));
  timed('getShaderParameter', (a, d) => shMs.set(a[0], (shMs.get(a[0]) || 0) + d));
  timed('linkProgram', (a, d) => {
    const shs = att.get(a[0]) || [];
    const defs = new Set();
    for (const sh of shs) {
      for (const line of (src.get(sh) || '').split(NL)) {
        const l = line.trim();
        if (l.startsWith('#define ')) defs.add(l.slice(8).trim());
      }
    }
    const e = { t: Math.round(performance.now()), ms: d + shs.reduce((x, sh) => x + (shMs.get(sh) || 0), 0), defs: keys.filter(k => defs.has(k)) };
    S.programs.push(e);
    prog.set(a[0], e);
  });
  timed('getProgramParameter', (a, d) => { const e = prog.get(a[0]); if (e) e.ms += d; });
  const log = console.log;
  console.log = function (...a) {
    const s = a.join(' ');
    if (s.startsWith('perf load ')) S.marks.push([s.split(' ')[2], performance.now()]);
    else if (s.startsWith('Godot Engine')) S.marks.push(['engine', performance.now()]);
    return log.apply(this, a);
  };
}

// 開一次 Chrome（profile 沿用就有上一次的瀏覽器快取），等到預熱結束，回傳頁面量到的資料與 Console 錯誤
async function loadRun(chrome, url, profile) {
  const debugPort = 9335;
  const proc = spawn(chrome, [
    `--remote-debugging-port=${debugPort}`, `--user-data-dir=${profile}`, '--no-first-run', '--no-default-browser-check',
    '--disable-background-timer-throttling', '--disable-renderer-backgrounding', '--disable-backgrounding-occluded-windows',
    '--headless=new', '--mute-audio', '--disable-features=Translate', '--window-size=960,540', 'about:blank',
  ], { stdio: 'ignore' });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  let page = null;
  for (let i = 0; i < 60 && !page; i++) {
    await sleep(500);
    try { page = (await (await fetch(`http://127.0.0.1:${debugPort}/json`)).json()).find(t => t.type === 'page'); } catch {}
  }
  if (!page) { try { proc.kill(); } catch {} fail('Chrome 開不起來或連不上除錯介面'); }
  const ws = new WebSocket(page.webSocketDebuggerUrl);
  const pending = {};
  const errors = [];
  let id = 0;
  const send = (method, params = {}) => new Promise(resolve => { pending[++id] = resolve; ws.send(JSON.stringify({ id, method, params })); });
  ws.onmessage = ev => {
    const m = JSON.parse(ev.data);
    if (pending[m.id]) { pending[m.id](m.result); delete pending[m.id]; }
    if (m.method === 'Runtime.exceptionThrown') errors.push(`例外：${m.params.exceptionDetails.text}`);
    if (m.method === 'Runtime.consoleAPICalled') {
      const text = m.params.args.map(a => a.value ?? a.description ?? '').join(' ');
      if (/ERROR|SCRIPT/.test(text) && !/webrtc_native|GDExtension/.test(text)) errors.push(`Console：${text}`);
    }
  };
  await new Promise(r => { ws.onopen = r; });
  const evaluate = async expression => (await send('Runtime.evaluate', { expression, returnByValue: true }))?.result?.value;
  await send('Runtime.enable');
  await send('Page.enable');
  await send('Page.addScriptToEvaluateOnNewDocument', { source: `(${loadHook})(${JSON.stringify(LOAD_KEYS)});` });
  await send('Page.navigate', { url });
  const start = Date.now();
  let done = false;
  while (!done && Date.now() - start < LOAD_TIMEOUT) {
    await sleep(500);
    done = await evaluate("!!(window.__load && window.__load.marks.some(m => m[0] === 'warm_done'))");
  }
  const data = await evaluate('window.__load');
  if (!data) { try { proc.kill(); } catch {} fail('頁面沒有載入量測腳本（window.__load 不存在）'); }
  data.resources = await evaluate("performance.getEntriesByType('resource').filter(e => /index[.](wasm|pck)$/.test(e.name)).map(e => [e.name.split('/').pop(), e.responseEnd])");
  data.renderer = await evaluate("(() => { const g = document.createElement('canvas').getContext('webgl2'); const e = g && g.getExtension('WEBGL_debug_renderer_info'); return g ? (e ? g.getParameter(e.UNMASKED_RENDERER_WEBGL) : g.getParameter(g.RENDERER)) : '沒有 WebGL2'; })()");
  data.done = done;
  try { await send('Browser.close'); } catch {}
  await sleep(1500);
  try { proc.kill(); } catch {}
  return { data, errors };
}

function loadReport(title, { data, errors }) {
  const sec = ms => `${(ms / 1000).toFixed(2)} 秒`;
  const mark = name => data.marks.find(m => m[0] === name)?.[1];
  const kind = defs => defs.includes('MODE_RENDER_DEPTH') ? '陰影深度' : defs.includes('USE_ADDITIVE_LIGHTING') ? '點光源疊加' : defs.includes('BASE_PASS') ? '一般繪製' : '其他';
  const tags = defs => defs.filter(d => d === 'MODE_UNSHADED' || d === 'USE_INSTANCING').map(d => d === 'MODE_UNSHADED' ? '不吃光' : 'MultiMesh');
  const lines = [`[${title}]`];
  const ready = mark('ready'), warm = mark('warm_done');
  if (!data.done || ready === undefined || warm === undefined) lines.push(`  ✘ ${LOAD_TIMEOUT / 60000} 分鐘內沒有等到預熱結束（時間點：${JSON.stringify(data.marks)}）`);
  else lines.push(`  時間軸：引擎啟動 ${sec(mark('engine') ?? 0)} → _ready ${sec(ready)} → 預熱結束 ${sec(warm)}（預熱 ${sec(warm - ready)}）`);
  lines.push(`  下載（本機伺服器，不含網路）：${data.resources.map(([n, t]) => `${n} ${sec(t)}`).join('、')}`);
  const ps = data.programs;
  const during = ready === undefined ? 0 : ps.filter(p => p.t >= ready && (warm === undefined || p.t <= warm)).length;
  const kinds = {};
  for (const p of ps) kinds[kind(p.defs)] = (kinds[kind(p.defs)] || 0) + 1;
  lines.push(`  著色器：${ps.length} 個程式（_ready 到預熱結束 ${during} 個），等編譯合計 ${sec(data.waitMs)}；${Object.entries(kinds).sort((a, b) => b[1] - a[1]).map(([k, n]) => `${k} ${n}`).join('、')}`);
  const slow = [...ps].sort((a, b) => b.ms - a.ms).slice(0, 10);
  lines.push(`  最慢 10 個：${slow.map(p => `${Math.round(p.ms)} ms ${kind(p.defs)}${tags(p.defs).length ? `（${tags(p.defs).join('、')}）` : ''}`).join('、')}`);
  for (const e of errors.slice(0, 10)) lines.push(`  ${e}`);
  console.log(lines.join('\n'));
  return data.done;
}

async function webLoad() {
  const chrome = chromePath();
  const port = Number(opt('port')) || 8062;
  const server = await serveWeb(exportWeb(), port).catch(e => fail(`開不了伺服器（埠 ${port}）：${e.message}`));
  const profile = mkdtempSync(join(tmpdir(), 'cubeborn-chrome-'));
  const url = `http://localhost:${port}/?perf`;
  let ok = true;
  try {
    const first = await loadRun(chrome, url, profile);
    console.log(`顯示卡：${first.data.renderer}`);
    ok = loadReport('第一次開（沒有瀏覽器快取）', first) && ok;
    ok = loadReport('第二次開（有上一次的瀏覽器快取）', await loadRun(chrome, url, profile)) && ok;
  } finally {
    try { rmSync(profile, { recursive: true, force: true }); } catch {}
    server.close();
  }
  return ok;
}

if (has('load')) process.exit(await webLoad() ? 0 : 1);

// ---- 推送 ----
const dryRun = has('dry-run');
const summary = opt('summary');

if (gitOrFail('rev-parse', '--abbrev-ref', 'HEAD') !== 'main') fail('不在 main 分支上');
if (gitOrFail('status', '--porcelain', '--untracked-files=no') !== '') fail('有還沒 commit 的修改：先 commit 再推送');

// 1. 更新：只 rebase 還沒推送的 commit。CHANGELOG.md、docs/進度.md 在 .gitattributes 設了 merge=union，兩邊新加的行都會留下、不會衝突
if (dryRun) {
  gitOrFail('fetch', 'origin', 'main');
} else {
  const pull = git('pull', '--rebase', 'origin', 'main');
  if (!pull.ok) {
    const conflicts = git('diff', '--name-only', '--diff-filter=U').out;
    if (existsSync(join(ROOT, '.git', 'rebase-merge')) || existsSync(join(ROOT, '.git', 'rebase-apply'))) git('rebase', '--abort');
    fail(`更新失敗，已還原到更新前（你的 commit 都還在）。${conflicts ? `\n    衝突的檔案：${conflicts.split('\n').join('、')}\n    兩邊改到同一段程式，請手動決定怎麼合併` : `\n    ${pull.err || pull.out}`}`);
  }
}
const ahead = Number(gitOrFail('rev-list', '--count', 'origin/main..HEAD'));
const behind = Number(gitOrFail('rev-list', '--count', 'HEAD..origin/main'));
if (ahead === 0) fail('沒有要推送的 commit');

// 2. 決定版號：[未發布] 有內容才升；有「### 新增」升次版號，否則升修訂號
const raw = readFileSync(CHANGELOG, 'utf8');
const changelog = normalizeUnreleased(raw);
if (changelog !== raw) console.log('CHANGELOG：[未發布] 不在最上面（rebase 時 union 合併接到對方的版號後面），已搬回最上面');
const latest = (changelog.match(/## \[(\d+)\.(\d+)\.(\d+)\]/) || []).slice(1).map(Number);
if (latest.length !== 3) fail('CHANGELOG.md 讀不到最新的版號');
const latestTag = git('tag', '--list', 'v*', '--sort=-v:refname').out.split('\n')[0];
if (latestTag && latestTag !== `v${latest.join('.')}`) fail(`CHANGELOG 最新版 v${latest.join('.')} 和最新的 tag ${latestTag} 不一樣，先查清楚再推送`);

const at = changelog.indexOf(UNRELEASED);
let body = '';
if (at !== -1) {
  const next = changelog.indexOf('\n## [', at + UNRELEASED.length);
  body = changelog.slice(at + UNRELEASED.length, next === -1 ? undefined : next).trim();
}
let version = null;
if (body) {
  const bump = opt('bump') || (/^### 新增/m.test(body) ? 'minor' : 'patch');
  if (!['minor', 'patch'].includes(bump)) fail(`--bump 只能是 minor 或 patch：${bump}`);
  const [ma, mi, pa] = latest;
  version = bump === 'minor' ? `${ma}.${mi + 1}.0` : `${ma}.${mi}.${pa + 1}`;
  if (!summary) fail('有未發布的改動，要升版號：加 --summary "這次的摘要"（會寫進 commit 訊息）');
}

// 3. 改 CHANGELOG 與 version.gd（保留原本的換行與 BOM）
const restore = () => git('checkout', '--', 'CHANGELOG.md', 'godot/core/version.gd');
if (version) {
  const d = new Date();
  const date = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  writeFileSync(CHANGELOG, changelog.replace(UNRELEASED, `## [${version}] - ${date}`));
  const vgd = readFileSync(VERSION_GD, 'utf8');
  if (!/const VERSION := "[^"]*"/.test(vgd)) { restore(); fail('version.gd 找不到 VERSION'); }
  writeFileSync(VERSION_GD, vgd.replace(/const VERSION := "[^"]*"/, `const VERSION := "${version}"`));
}

// 4. 檢查（更新後的版本一定要再驗一次：兩邊的改動合起來可能文字沒衝突、邏輯卻壞了）
console.log(`檢查中（${version ? `v${latest.join('.')} → v${version}` : '不升版號'}）…`);
if (!runChecks()) { restore(); fail('檢查沒過，已還原版號的修改，沒有推送'); }

if (dryRun) {
  restore();
  console.log(`✔ 試跑完成，沒有推送。本機領先 ${ahead} 個 commit、落後 ${behind} 個${behind ? '（正式推送時會先 rebase）' : ''}；${version ? `會發布 v${version}：${summary}` : '[未發布] 是空的，會直接推、不升版號'}`);
  process.exit(0);
}

// 5. commit + tag + 推送；被拒絕（剛好有人搶先推）就撤掉這次的版號 commit 與 tag
if (version) {
  gitOrFail('add', 'CHANGELOG.md', 'godot/core/version.gd');
  gitOrFail('commit', '-m', `v${version}: ${summary}`);
  gitOrFail('tag', `v${version}`);
}
const push = version ? git('push', '--atomic', 'origin', 'main', `v${version}`) : git('push', 'origin', 'main');
if (!push.ok) {
  if (version) { git('tag', '-d', `v${version}`); git('reset', '--keep', 'HEAD~1'); }
  const undone = version ? '已撤掉這次的版號 commit 與 tag，回到推送前' : '本機沒有改動';
  // 依錯誤訊息判斷原因：權限不夠時重跑沒用，要先請 repo 擁有者加協作者（2026-10-25 第一次推送踩過）
  const reason = /403|Permission .* denied|permission denied/i.test(push.err)
    ? '這個 GitHub 帳號沒有 repo 的寫入權限：請 repo 擁有者到 Settings → Collaborators 加入、接受邀請後再推'
    : /rejected|fetch first|non-fast-forward/i.test(push.err)
      ? '剛好有人先推了：重跑一次即可（會先 rebase 再推）'
      : /Could not resolve|unable to access|timed out|Connection/i.test(push.err)
        ? '連不上 GitHub：確認網路後重跑'
        : '原因看下面 git 的訊息';
  fail(`推送失敗，${undone}。${reason}\n    ${push.err}`);
}
console.log(version
  ? `✔ 已推送 v${version}：網站約數分鐘後更新，GitHub Actions 會建立 Release`
  : '✔ 已推送（沒有升版號）：網站約數分鐘後更新');
