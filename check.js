// 自動檢查：不開瀏覽器驗證資料完整性與核心機制。執行：node check.js（或 npm run check）
// 規則：檢查失敗時先證明遊戲邏輯正確，才可以改這裡（見 CLAUDE.md 1.4）
import assert from 'node:assert/strict';
import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import * as THREE from 'three';
import { CUES, Sound } from './src/audio/Sound.js';
import { Combat } from './src/combat/Combat.js';
import { COMBAT } from './src/core/config.js';
import { CooldownManager } from './src/core/CooldownManager.js';
import { EventBus } from './src/core/EventBus.js';
import { StateMachine } from './src/core/StateMachine.js';
import { ENEMIES } from './src/entities/enemyDefs.js';
import { Entity } from './src/entities/Entity.js';
import { getStyle } from './src/render/styles/index.js';
import { G, PartKit } from './src/render/rig.js';
import { SKILL_BEHAVIORS } from './src/skills/skillBehaviors.js';
import { SKILLS } from './src/skills/skillDefs.js';
import { WEAPON_BEHAVIORS } from './src/weapons/weaponBehaviors.js';
import { WEAPONS } from './src/weapons/weaponDefs.js';
import { WAVE_SCALING, WAVES, waveMultipliers } from './src/world/waveDefs.js';

const results = [];
function check(name, fn) {
  try {
    fn();
    results.push({ name, ok: true });
  } catch (err) {
    results.push({ name, ok: false, err });
  }
}
const near = (actual, expected, msg) => assert.ok(Math.abs(actual - expected) < 1e-9, `${msg}：預期 ${expected}，實際 ${actual}`);

// 最小假遊戲物件：只提供 Entity / Combat 需要的欄位，並記錄呼叫
function stubGame() {
  const log = { hitStop: [], shake: [], burst: 0 };
  return {
    log,
    events: new EventBus(),
    enemies: [],
    player: null,
    effects: { burst: () => { log.burst++; } },
    hitStop: (t) => log.hitStop.push(t),
    renderer: { shake: (s) => log.shake.push(s) },
  };
}
function makeEntity(game, opts = {}) {
  const e = new Entity(game, { radius: 0.5, maxHp: 100, team: 'enemy', ...opts });
  e.onDamaged = () => {};
  e.onDied = () => {};
  return e;
}

// ───────── 資料完整性 ─────────

check('武器：每個攻擊/特殊技的 behavior 都存在，且三段時間為正數', () => {
  for (const w of Object.values(WEAPONS)) {
    for (const slot of ['attack', 'special']) {
      const a = w[slot];
      assert.ok(WEAPON_BEHAVIORS[a.behavior], `${w.id}.${slot} 的 behavior「${a.behavior}」不存在`);
      for (const k of ['windup', 'active', 'recovery']) {
        if (a[k] !== undefined) assert.ok(a[k] >= 0, `${w.id}.${slot}.${k} 不可為負`);
      }
    }
    assert.ok(w.special.cooldown > 0, `${w.id} 特殊技必須有 CD`);
  }
});

check('武器：外觀模型在目前風格中都存在', () => {
  const style = getStyle();
  for (const w of Object.values(WEAPONS)) {
    assert.equal(typeof style.weapons[w.model], 'function', `風格缺少武器模型 ${w.model}`);
  }
});

check('技能：behavior 存在，mode 與次數設定一致', () => {
  for (const s of Object.values(SKILLS)) {
    assert.ok(SKILL_BEHAVIORS[s.behavior], `${s.id} 的 behavior「${s.behavior}」不存在`);
    assert.ok(['cooldown', 'charges'].includes(s.mode), `${s.id} 的 mode 不合法`);
    if (s.mode === 'charges') assert.ok(s.charges > 0, `${s.id} 是 charges 模式但沒有次數`);
    assert.ok(s.cooldown > 0, `${s.id} 必須有 CD`);
  }
});

check('敵人：visual 在目前風格中都有角色模型', () => {
  const style = getStyle();
  for (const [id, def] of Object.entries(ENEMIES)) {
    assert.equal(typeof style.characters[def.visual], 'function', `${id} 的 visual「${def.visual}」不存在`);
  }
});

check('波次：共 5 波、只有最後一波是 Boss、生成的類型都存在', () => {
  assert.equal(WAVES.length, 5);
  WAVES.forEach((w, i) => {
    assert.equal(Boolean(w.isBoss), i === WAVES.length - 1, `第 ${i + 1} 波 isBoss 設定錯誤`);
    for (const type of Object.keys(w.spawns)) assert.ok(ENEMIES[type], `第 ${i + 1} 波的敵人類型「${type}」不存在`);
  });
  assert.equal(WAVES.at(-1).spawns.boss, 1, '最後一波必須剛好 1 隻 Boss');
});

check('波次：第 1~4 波小怪總數為 5 / 7 / 9 / 12', () => {
  const totals = WAVES.slice(0, 4).map((w) => Object.values(w.spawns).reduce((a, b) => a + b, 0));
  assert.deepEqual(totals, [5, 7, 9, 12]);
});

check('波次成長：第 1 波倍率為 1，第 N 波依 WAVE_SCALING 線性成長', () => {
  const m1 = waveMultipliers(1);
  assert.deepEqual(m1, { hp: 1, damage: 1, speed: 1 });
  const m4 = waveMultipliers(4);
  near(m4.hp, 1 + WAVE_SCALING.hp * 3, '第 4 波血量倍率');
  near(m4.damage, 1 + WAVE_SCALING.damage * 3, '第 4 波傷害倍率');
  near(m4.speed, 1 + WAVE_SCALING.speed * 3, '第 4 波移速倍率');
});

check('造型：角色、武器、投射物、場地都能建立且結構正確', () => {
  const style = getStyle();
  for (const k of ['knight', 'melee', 'ranged', 'boss']) {
    const rig = style.characters[k]();
    for (const joint of ['root', 'body', 'head', 'armR', 'armL', 'legR', 'legL', 'handR', 'handL']) {
      assert.ok(rig[joint], `${k} 缺少關節 ${joint}`);
    }
    assert.ok(style.names[k], `${k} 缺少顯示名稱`);
  }
  for (const w of Object.values(style.weapons)) assert.ok(w().main, '武器缺少 main');
  assert.ok(style.enemyProjectile().mesh, '敵人投射物缺少 mesh');
  assert.ok(style.buildArena(11).group, '場地缺少 group');
});

// ───────── 核心機制 ─────────

check('CD：時間未到不可用，時間到後可用，progress 由 0 走到 1', () => {
  const cd = new CooldownManager();
  cd.start('player.special', 4);
  assert.equal(cd.isReady('player.special'), false);
  near(cd.progress('player.special'), 0, '剛開始 progress');
  for (let i = 0; i < 120; i++) cd.tick(1 / 60); // 2 秒
  assert.equal(cd.isReady('player.special'), false, '2 秒時不應可用');
  near(cd.remaining('player.special'), 2, '2 秒時剩餘');
  for (let i = 0; i < 121; i++) cd.tick(1 / 60); // 再約 2 秒
  assert.equal(cd.isReady('player.special'), true, '4 秒後應可用');
  assert.equal(cd.progress('player.special'), 1);
});

check('CD：reset 立即可用，其他 key 不受影響', () => {
  const cd = new CooldownManager();
  cd.start('a.x', 5);
  cd.start('b.y', 5);
  cd.reset('a.x');
  assert.equal(cd.isReady('a.x'), true);
  assert.equal(cd.isReady('b.y'), false);
});

check('狀態機：依序呼叫 exit → enter，time 歸零，canExit 可擋下切換', () => {
  const calls = [];
  const fsm = new StateMachine({}, {
    idle: { exit: () => calls.push('idle.exit') },
    attack: { enter: () => calls.push('attack.enter'), canExit: (_, next) => next !== 'idle' },
    dead: {},
  }, 'idle');
  fsm.update(0.5);
  assert.ok(fsm.change('attack'));
  assert.deepEqual(calls, ['idle.exit', 'attack.enter']);
  assert.equal(fsm.time, 0);
  assert.equal(fsm.change('idle'), false, 'canExit 應擋下');
  assert.ok(fsm.is('attack'));
  assert.ok(fsm.change('dead'));
  assert.throws(() => fsm.change('notExist'));
});

check('事件：on 收得到、off 後收不到', () => {
  const bus = new EventBus();
  let count = 0;
  const off = bus.on('entity:damaged', () => count++);
  bus.emit('entity:damaged', {});
  off();
  bus.emit('entity:damaged', {});
  assert.equal(count, 1);
});

check('受傷：扣血、受傷倍率、擊退方向與大小、無敵中不受傷', () => {
  const g = stubGame();
  const e = makeEntity(g, { mass: 2 });
  e.damageTakenMul = 0.5;
  const r = e.takeDamage(20, { x: 1, y: 0, z: 0 }, 8, null);
  assert.equal(r.amount, 10);
  assert.equal(e.hp, 90);
  near(e.knockback.x, 4, '擊退 = 力道 / 質量');
  assert.equal(e.flashTimer, COMBAT.flashTime);
  e.invulnTimer = 1;
  assert.equal(e.takeDamage(20, { x: 1, y: 0, z: 0 }, 0, null), null);
  assert.equal(e.hp, 90);
});

check('死亡：血量歸零發出 entity:died，死後不再受傷', () => {
  const g = stubGame();
  const e = makeEntity(g, { maxHp: 10 });
  let died = 0;
  g.events.on('entity:died', ({ entity }) => { if (entity === e) died++; });
  e.takeDamage(999, { x: 0, y: 0, z: 1 }, 0, null);
  assert.equal(e.hp, 0);
  assert.equal(e.isDead, true);
  assert.equal(died, 1);
  assert.equal(e.takeDamage(5, { x: 0, y: 0, z: 1 }, 0, null), null);
});

check('戰鬥：applyDamage 發出事件、觸發命中停頓與震動，擊退方向為來源 → 目標', () => {
  const g = stubGame();
  const combat = new Combat(g);
  const src = makeEntity(g, { team: 'player' });
  const tgt = makeEntity(g);
  tgt.position.set(0, 0, 3);
  let damaged = null;
  g.events.on('entity:damaged', (p) => { damaged = p; });
  assert.ok(combat.applyDamage(src, tgt, { damage: 12, knockback: 7, hitStop: 0.04, shake: 0.08 }));
  assert.equal(damaged.amount, 12);
  assert.deepEqual(g.log.hitStop, [0.04]);
  assert.deepEqual(g.log.shake, [0.08]);
  assert.ok(tgt.knockback.z > 0 && Math.abs(tgt.knockback.x) < 1e-9, '應往 +Z 擊退');
});

check('命中判定：扇形只打到前方範圍內，貼身目標一律命中', () => {
  const combat = new Combat(stubGame());
  const at = (x, z, radius = 0.5) => ({ position: { x, z }, radius });
  const front = at(0, 2);
  const behind = at(0, -2);
  const far = at(0, 5);
  const touching = at(0, -0.6);
  const hits = combat.querySector({ x: 0, z: 0 }, 0, 2.3, Math.PI * 0.65, [front, behind, far, touching]);
  assert.ok(hits.includes(front), '前方應命中');
  assert.ok(!hits.includes(behind), '後方不應命中');
  assert.ok(!hits.includes(far), '超出距離不應命中');
  assert.ok(hits.includes(touching), '貼身應命中');
});

check('命中判定：圓形範圍考慮目標半徑', () => {
  const combat = new Combat(stubGame());
  const at = (x, z, radius = 0.5) => ({ position: { x, z }, radius });
  const edge = at(2.4, 0);   // 2 + 0.5 = 2.5 內
  const out = at(2.6, 0);
  const hits = combat.queryCircle({ x: 0, z: 0 }, 2, [edge, out]);
  assert.deepEqual(hits, [edge]);
});

// ───────── 渲染效能 ─────────

function meshStats(root) {
  let meshes = 0;
  let vertices = 0;
  root.traverse((o) => {
    if (!o.isMesh) return;
    meshes++;
    vertices += o.geometry.index ? o.geometry.index.count : o.geometry.attributes.position.count;
  });
  root.updateMatrixWorld(true);
  return { meshes, vertices, box: new THREE.Box3().setFromObject(root) };
}

check('零件合併：頂點數與外框不變、材質保留、keep 的零件不被合併、會動的節點保留', () => {
  const kit = new PartKit((color) => new THREE.MeshLambertMaterial({ color }));
  const root = new THREE.Group();
  const arm = new THREE.Group();
  arm.position.set(0.5, 1, 0);
  arm.rotation.z = 0.4;
  root.add(arm);
  const sub = new THREE.Group(); // 非 anchor 的子群組：應被併入 arm
  sub.position.set(0, -0.3, 0.1);
  sub.rotation.x = 0.7;
  arm.add(sub);
  const red = kit.mat(0xff0000);
  const blue = kit.mat(0x0000ff);
  kit.add(root, G.box(0.4, 0.6, 0.3), red, { y: 1 });
  kit.add(root, G.cyl(0.1, 0.1, 0.5, 6), red, { x: 0.3, rz: 0.5 });
  kit.add(arm, G.ico(0.1, 0), red, { y: -0.2 });
  kit.add(sub, G.box(0.1, 0.1, 0.1), red, { s: 2 });
  kit.add(sub, G.cone(0.1, 0.2, 4), blue);
  const gem = kit.add(arm, G.ico(0.05), blue, { y: -0.5 });

  const before = meshStats(root);
  kit.mergeStatic(root, [root, arm], [gem]);
  const after = meshStats(root);
  assert.equal(after.vertices, before.vertices, '頂點數應不變');
  assert.ok(after.box.min.distanceTo(before.box.min) < 1e-6 && after.box.max.distanceTo(before.box.max) < 1e-6, '外框應不變');
  assert.equal(after.meshes, 4, 'root 紅、arm 紅、arm 藍、gem 共 4 個');
  assert.equal(gem.parent, arm, 'keep 的零件應留在原位');
  assert.equal(arm.parent, root, 'anchor 應保留');
  assert.equal(sub.parent, null, '空的子群組應移除');
  const mats = new Set();
  root.traverse((o) => { if (o.isMesh) mats.add(o.material); });
  assert.deepEqual([...mats].sort((a, b) => a.id - b.id), [red, blue].sort((a, b) => a.id - b.id));
});

check('零件合併：角色零件數在上限內（避免卡頓）', () => {
  const style = getStyle();
  const limits = { knight: 20, melee: 16, ranged: 16, boss: 22 };
  for (const [k, limit] of Object.entries(limits)) {
    const { meshes } = meshStats(style.characters[k]().root);
    assert.ok(meshes <= limit, `${k} 有 ${meshes} 個零件，上限 ${limit}`);
  }
  const { meshes } = meshStats(style.buildArena(11).group);
  assert.ok(meshes <= 12, `場地有 ${meshes} 個零件，上限 12`);
});

// ───────── 音效 ─────────

function sourceFiles(dir, out = []) {
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    if (statSync(p).isDirectory()) sourceFiles(p, out);
    else if (p.endsWith('.js')) out.push(p);
  }
  return out;
}

check('音效：程式中 sfx:cue 與武器 sfx 指定的音效名稱都存在', () => {
  const names = new Set();
  for (const file of sourceFiles('src')) {
    const text = readFileSync(file, 'utf8');
    for (const m of text.matchAll(/'sfx:cue', \{ name: '(\w+)' \}/g)) names.add(m[1]);
  }
  assert.ok(names.size >= 5, `程式中只比對到 ${names.size} 個 sfx:cue，比對規則可能失效`);
  for (const w of Object.values(WEAPONS)) {
    for (const a of [w.attack, w.special]) {
      assert.ok(a.sfx, `${w.id} 的 ${a.name} 沒有指定音效`);
      names.add(a.sfx);
      if (a.sfxHeavy) names.add(a.sfxHeavy);
    }
  }
  for (const n of names) assert.ok(CUES[n], `音效「${n}」不存在於 CUES`);
});

check('音效：每個遊戲事件都對應到存在的音效', () => {
  const events = new EventBus();
  const boss = { team: 'enemy' };
  const sound = new Sound({ events, boss });
  const played = [];
  sound.play = (name) => played.push(name);
  const emits = [
    ['entity:damaged', { target: { team: 'player' } }],
    ['entity:damaged', { target: { team: 'enemy' }, isCrit: false }],
    ['entity:damaged', { target: { team: 'enemy' }, isCrit: true }],
    ['entity:died', { entity: { team: 'enemy' } }],
    ['entity:died', { entity: boss }],
    ['skill:used', { def: SKILLS.heal }],
    ['skill:used', { def: SKILLS.sprint }],
    ['skill:onCooldown', {}],
    ['wave:started', { isBoss: false }],
    ['wave:started', { isBoss: true }],
    ['boss:enraged', {}],
    ['player:died', {}],
    ['game:victory', {}],
    ['game:restart', {}],
    ['game:paused', { paused: true }],
    ['game:paused', { paused: false }],
  ];
  for (const [name, payload] of emits) {
    const n = played.length;
    events.emit(name, payload);
    assert.equal(played.length, n + 1, `事件 ${name} 沒有播放音效`);
    assert.ok(CUES[played.at(-1)], `事件 ${name} 對應的音效「${played.at(-1)}」不存在`);
  }
});

// ───────── 輸出 ─────────

const failed = results.filter((r) => !r.ok);
for (const r of results) {
  console.log(`${r.ok ? '✔' : '✘'} ${r.name}`);
  if (!r.ok) console.log(`    ${r.err.message.split('\n').join('\n    ')}`);
}
console.log(`\n${results.length - failed.length} / ${results.length} 通過`);
process.exitCode = failed.length ? 1 : 0;
