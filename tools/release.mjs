// 檢查與推送（Windows / Mac 都能跑，只用 Node 內建模組）。規則見 PROJECT_GUIDELINES.md 第 12、13 節
//   node tools/release.mjs --check                        只跑 Godot 匯入 + check.gd（有逾時）
//   node tools/release.mjs --summary "摘要"               推送：更新（rebase）→ 決定版號 → 檢查 → commit + tag → push
//   node tools/release.mjs --summary "摘要" --dry-run     不動 git 歷史、不推：只 fetch、算版號、改檔跑檢查，最後還原
//   加 --bump=minor|patch 可以蓋過自動判斷的版號
// Godot：--godot <console 執行檔路徑> 或環境變數 GODOT（每台電腦的路徑寫在 CLAUDE.local.md）
// git：環境變數 GIT，沒有就用 PATH 上的 git（Windows 找不到時改用 Program Files 裡的）
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
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
  if (!chk.ok && !chk.out.includes('通過')) console.log((chk.err || '').split('\n').slice(-15).join('\n'));
  return chk.ok;
}

if (has('check')) process.exit(runChecks() ? 0 : 1);

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
const changelog = readFileSync(CHANGELOG, 'utf8');
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
