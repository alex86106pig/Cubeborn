// HUD（DOM）：血條、技能欄 CD、波次/擊殺、版號、浮動傷害數字、受擊暗角、死亡畫面
import * as THREE from 'three';
import { SLOT_COUNT } from '../skills/ActiveSlots.js';
import { VERSION } from '../core/version.js';
import { getStyle } from '../render/styles/index.js';

function formatTime(seconds) {
  const m = Math.floor(seconds / 60);
  const s = Math.floor(seconds % 60);
  return `${m}:${String(s).padStart(2, '0')}`;
}

const _world = new THREE.Vector3();
const _screen = { x: 0, y: 0 };

function el(tag, className, parent, text) {
  const node = document.createElement(tag);
  if (className) node.className = className;
  if (text !== undefined) node.textContent = text;
  parent?.appendChild(node);
  return node;
}

export class HUD {
  #floaters = [];
  #slotEls = new Map(); // cdKey -> slot element bundle
  #weaponId = null;

  constructor(game, root) {
    this.game = game;
    this.root = root;
    this.#build();
    this.#bindEvents();
  }

  #build() {
    const r = this.root;
    const tl = el('div', 'hud-top-left', r);
    const hp = el('div', 'hp-bar', tl);
    this.hpGhost = el('div', 'hp-ghost', hp);
    this.hpFill = el('div', 'hp-fill', hp);
    this.hpText = el('span', 'hp-text', hp);
    this.weaponName = el('div', 'weapon-name', tl);

    const tr = el('div', 'hud-top-right', r);
    this.waveText = el('div', 'wave', tr);
    this.killText = el('div', 'kills', tr);
    this.timeText = el('div', 'kills', tr);
    el('div', 'version', tr, `v${VERSION}`);

    this.bossBar = el('div', 'boss-bar hidden', r);
    this.bossName = el('div', 'boss-name', this.bossBar);
    const bossTrack = el('div', 'boss-track', this.bossBar);
    this.bossGhost = el('div', 'boss-ghost', bossTrack);
    this.bossFill = el('div', 'boss-fill', bossTrack);
    this.bossGhostValue = 1;

    this.skillbar = el('div', 'skillbar', r);
    this.banner = el('div', 'banner', r);
    this.vignette = el('div', 'vignette', r);
    this.floaterLayer = el('div', 'floaters', r);

    this.gameOver = el('div', 'gameover hidden', r);
    this.gameOverTitle = el('h1', '', this.gameOver);
    this.gameOverStats = el('p', '', this.gameOver);
    el('p', 'hint', this.gameOver, '按 R 重新開始');

    el('div', 'help', r, 'WASD 移動 · 滑鼠瞄準 · 左鍵攻擊 · 右鍵特殊技 · 1~5 道具 · F1 切換武器 · F2 顯示判定');
    this.hpGhostValue = 1;
  }

  #buildSkillbar() {
    const player = this.game.player;
    const w = player.weapon;
    this.skillbar.replaceChildren();
    this.#slotEls.clear();
    this.#addSlot(null, w.attack.icon, '左鍵', w.attack.name);
    this.#addSlot('player.special', w.special.icon, '右鍵', w.special.name);
    el('div', 'skill-divider', this.skillbar);
    for (let i = 0; i < SLOT_COUNT; i++) {
      const slot = player.slots.slots[i];
      this.#addSlot(player.slots.cdKey(i), slot?.def.icon ?? '', String(i + 1), slot?.def.name ?? '', slot, i);
    }
    this.#weaponId = w.id;
  }

  #addSlot(key, icon, keyLabel, title, slotData = undefined, index = -1) {
    const node = el('div', 'slot', this.skillbar);
    if (slotData === null) node.classList.add('empty');
    node.title = title;
    el('div', 'icon', node, icon);
    const cd = el('div', 'cd', node);
    const cdText = el('div', 'cd-text', node);
    const charges = el('div', 'charges', node);
    el('div', 'key', node, keyLabel);
    if (key) this.#slotEls.set(key, { node, cd, cdText, charges, slotData, index });
  }

  #bindEvents() {
    const ev = this.game.events;
    ev.on('entity:damaged', ({ target, amount, isCrit }) => {
      const isPlayer = target === this.game.player;
      this.#spawnFloater(target, `${amount}`, isPlayer ? 'dmg-player' : isCrit ? 'dmg-crit' : 'dmg');
      if (isPlayer) this.#restartAnimation(this.vignette, 'flash');
    });
    ev.on('entity:healed', ({ target, amount }) => {
      if (amount > 0) this.#spawnFloater(target, `+${amount}`, 'heal');
    });
    ev.on('skill:onCooldown', ({ key }) => {
      const slot = this.#slotEls.get(key);
      if (slot) this.#restartAnimation(slot.node, 'deny');
    });
    ev.on('skill:used', ({ key }) => {
      const slot = this.#slotEls.get(key);
      if (slot) this.#restartAnimation(slot.node, 'used');
    });
    ev.on('wave:started', ({ wave, total, isBoss }) => {
      this.#showBanner(isBoss ? `BOSS 戰：${getStyle().names.boss}` : `第 ${wave} / ${total} 波`, isBoss);
    });
    ev.on('boss:enraged', () => this.#showBanner('狂暴化！', true));
    ev.on('player:died', () => {
      const s = this.game.stats;
      this.gameOverTitle.textContent = '你倒下了';
      this.gameOverStats.textContent = `撐到第 ${s.wave} 波 · 擊殺 ${s.kills} · 時間 ${formatTime(s.time)}`;
      this.gameOver.classList.remove('victory');
      setTimeout(() => {
        if (this.game.player.isDead) this.gameOver.classList.remove('hidden');
      }, 700);
    });
    ev.on('game:victory', ({ stats }) => {
      this.gameOverTitle.textContent = '勝利！';
      this.gameOverStats.textContent = `擊敗 ${getStyle().names.boss} · 擊殺 ${stats.kills} · 通關時間 ${formatTime(stats.time)}`;
      this.gameOver.classList.add('victory');
      this.gameOver.classList.remove('hidden');
    });
    ev.on('game:restart', () => {
      this.gameOver.classList.add('hidden');
      this.bossGhostValue = 1;
      this.#weaponId = null;
      this.hpGhostValue = 1;
      for (const f of this.#floaters) f.node.remove();
      this.#floaters.length = 0;
    });
  }

  #showBanner(text, isAlert = false) {
    this.banner.textContent = text;
    this.banner.classList.toggle('alert', isAlert);
    this.#restartAnimation(this.banner, 'show');
  }

  #restartAnimation(node, className) {
    node.classList.remove(className);
    void node.offsetWidth; // 強制 reflow 讓動畫重播
    node.classList.add(className);
  }

  #spawnFloater(target, text, className) {
    const { position, height } = target;
    const node = el('div', `floater ${className}`, this.floaterLayer, text);
    const world = new THREE.Vector3(position.x + (Math.random() - 0.5) * 0.6, height + 0.3, position.z);
    this.#floaters.push({ node, world, life: 0.8, maxLife: 0.8 });
  }

  update(dt) {
    const g = this.game;
    const player = g.player;
    if (player.weapon.id !== this.#weaponId) this.#buildSkillbar();

    const ratio = player.hp / player.maxHp;
    this.hpGhostValue = Math.max(ratio, this.hpGhostValue - dt * 0.5);
    this.hpFill.style.width = `${ratio * 100}%`;
    this.hpGhost.style.width = `${this.hpGhostValue * 100}%`;
    this.hpText.textContent = `${player.hp} / ${player.maxHp}`;
    this.weaponName.textContent = `武器：${player.weapon.name}`;
    this.waveText.textContent = g.stats.wave > 0 ? `第 ${g.stats.wave} / ${g.spawner.totalWaves} 波` : '準備中';
    this.killText.textContent = `擊殺 ${g.stats.kills}`;
    this.timeText.textContent = formatTime(g.stats.time);

    const boss = g.boss;
    this.bossBar.classList.toggle('hidden', !boss || boss.isSpawning && boss.fsm.time < 0.3);
    if (boss) {
      const r = boss.hp / boss.maxHp;
      this.bossGhostValue = Math.max(r, this.bossGhostValue - dt * 0.3);
      this.bossName.textContent = `${boss.displayName}${boss.isEnraged ? '（狂暴）' : ''}`;
      this.bossFill.style.width = `${r * 100}%`;
      this.bossGhost.style.width = `${this.bossGhostValue * 100}%`;
      this.bossBar.classList.toggle('enraged', boss.isEnraged);
    }

    for (const [key, s] of this.#slotEls) {
      const progress = g.cooldowns.progress(key);
      s.cd.style.setProperty('--p', `${(1 - progress) * 100}%`);
      const remaining = g.cooldowns.remaining(key);
      s.cdText.textContent = remaining > 0 ? remaining.toFixed(remaining < 1 ? 1 : 0) : '';
      if (s.slotData && s.slotData.def.mode === 'charges') {
        s.charges.textContent = `${s.slotData.charges}`;
        s.node.classList.toggle('depleted', s.slotData.charges <= 0);
      }
    }

    for (let i = this.#floaters.length - 1; i >= 0; i--) {
      const f = this.#floaters[i];
      f.life -= dt;
      if (f.life <= 0) {
        f.node.remove();
        this.#floaters.splice(i, 1);
        continue;
      }
      f.world.y += dt * 1.6;
      g.renderer.worldToScreen(_world.copy(f.world), _screen);
      const k = f.life / f.maxLife;
      f.node.style.transform = `translate(${_screen.x}px, ${_screen.y}px) translate(-50%, -50%) scale(${0.8 + 0.4 * Math.min(1, (1 - k) * 6)})`;
      f.node.style.opacity = `${Math.min(1, k * 2.5)}`;
    }
  }
}
