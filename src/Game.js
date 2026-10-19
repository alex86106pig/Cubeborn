// 遊戲主體（組合根）：建立並持有所有系統、固定步長主迴圈、命中停頓、重新開始
import { CooldownManager } from './core/CooldownManager.js';
import { DEBUG, FIXED_DT, MAX_STEPS_PER_FRAME, WORLD } from './core/config.js';
import { EventBus } from './core/EventBus.js';
import { Input } from './core/Input.js';
import { Combat } from './combat/Combat.js';
import { clampToArena, separateEntities } from './combat/Physics.js';
import { Player } from './entities/Player.js';
import { Effects } from './render/Effects.js';
import { Renderer } from './render/Renderer.js';
import { getStyle, nextStyle } from './render/styles/index.js';
import { HUD } from './ui/HUD.js';
import { Arena } from './world/Arena.js';
import { Spawner } from './world/Spawner.js';

const HIT_STOP_TIME_SCALE = 0.05;
const VICTORY_DELAY = 2.2;

export class Game {
  #accumulator = 0;
  #lastTime = 0;
  #hitStopTimer = 0;
  #victoryTimer = 0;
  #bodies = [];

  constructor(container, hudRoot) {
    this.events = new EventBus();
    this.cooldowns = new CooldownManager();
    this.renderer = new Renderer(container);
    this.input = new Input(this.renderer.domElement);
    this.effects = new Effects(this);
    this.combat = new Combat(this);
    this.arena = new Arena(this);
    this.spawner = new Spawner(this);

    this.player = null;
    this.boss = null;
    this.enemies = [];
    this.projectiles = [];
    this.stats = { wave: 0, kills: 0, time: 0 };
    this.isOver = false; // 通關後為 true

    this.events.on('entity:died', ({ entity }) => {
      if (entity.team === 'enemy') this.stats.kills++;
    });

    this.#applyEnvironment(getStyle());
    this.restart();
    this.hud = new HUD(this, hudRoot);
  }

  #applyEnvironment(style) {
    this.renderer.applyEnvironment(style.environment);
    this.arena.applyStyle(style);
  }

  // 切換造型風格：重建場地與所有角色模型，遊戲狀態不變
  applyStyle(style) {
    this.#applyEnvironment(style);
    this.player.rebuildModel();
    for (const e of this.enemies) e.rebuildModel();
    this.events.emit('style:changed', { style });
  }

  onBossDefeated(boss) {
    this.isOver = true;
    this.#victoryTimer = VICTORY_DELAY;
    this.hitStop(0.25);
    this.renderer.shake(0.8, 0.6);
    for (const e of this.enemies) if (e !== boss && !e.isDead) e.die();
    for (const p of this.projectiles) if (p.owner.team === 'enemy') p.remove();
  }

  start() {
    this.#lastTime = performance.now();
    requestAnimationFrame(this.#frame);
  }

  restart() {
    for (const e of this.enemies) e.remove();
    for (const p of this.projectiles) p.remove();
    this.player?.remove();
    this.enemies = [];
    this.projectiles = [];
    this.effects.clear();
    this.cooldowns.resetAll();
    this.player = new Player(this);
    this.boss = null;
    this.isOver = false;
    this.spawner.reset();
    this.stats.wave = 0;
    this.stats.kills = 0;
    this.stats.time = 0;
    this.#hitStopTimer = 0;
    this.#victoryTimer = 0;
    this.renderer.follow(this.player.position, 0, true);
    this.events.emit('game:restart', {});
  }

  // 命中停頓：以真實時間計算，期間邏輯時間大幅放慢
  hitStop(duration) {
    this.#hitStopTimer = Math.max(this.#hitStopTimer, duration);
  }

  #frame = (now) => {
    const realDt = Math.min((now - this.#lastTime) / 1000, 0.25);
    this.#lastTime = now;

    let scale = 1;
    if (this.#hitStopTimer > 0) {
      this.#hitStopTimer -= realDt;
      scale = HIT_STOP_TIME_SCALE;
    }

    this.#accumulator += realDt * scale;
    let steps = 0;
    while (this.#accumulator >= FIXED_DT && steps < MAX_STEPS_PER_FRAME) {
      this.update(FIXED_DT);
      this.input.endStep();
      this.#accumulator -= FIXED_DT;
      steps++;
    }
    if (steps === MAX_STEPS_PER_FRAME) this.#accumulator = 0;

    this.player.syncModel();
    for (const e of this.enemies) e.syncModel();
    this.renderer.follow(this.player.position, realDt);
    this.hud.update(realDt);
    this.renderer.render();
    requestAnimationFrame(this.#frame);
  };

  update(dt) {
    this.#handleSystemKeys();
    this.cooldowns.tick(dt);

    this.player.update(dt);
    for (const e of this.enemies) e.update(dt);
    for (const p of this.projectiles) p.update(dt);

    const bodies = this.#bodies;
    bodies.length = 0;
    bodies.push(this.player, ...this.enemies);
    for (const b of bodies) b.integrate(dt);
    separateEntities(bodies);
    for (const b of bodies) clampToArena(b, WORLD.arenaHalfSize);

    this.spawner.update(dt);
    this.effects.update(dt);

    this.enemies = this.enemies.filter((e) => !e.isRemoved);
    this.projectiles = this.projectiles.filter((p) => !p.isRemoved);
    if (this.boss?.isRemoved) this.boss = null;

    if (!this.isOver && !this.player.isDead) this.stats.time += dt;
    if (this.#victoryTimer > 0) {
      this.#victoryTimer -= dt;
      if (this.#victoryTimer <= 0) this.events.emit('game:victory', { stats: this.stats });
    }
  }

  #handleSystemKeys() {
    const input = this.input;
    if (input.wasPressed('KeyR') && (this.player.isDead || this.isOver)) this.restart();
    if (input.wasPressed('F3')) this.applyStyle(nextStyle());
    if (input.wasPressed('F1') && !this.player.isDead) {
      this.player.equipWeapon(this.player.weapon.id === 'swordShield' ? 'staff' : 'swordShield');
    }
    if (input.wasPressed('F2')) DEBUG.showHitboxes = !DEBUG.showHitboxes;
  }
}
