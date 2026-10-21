// 分波生成：依 waveDefs 逐隻從遠離玩家的位置生成；場上清空後倒數進入下一波
import { SPAWNER, WORLD } from '../core/config.js';
import { randRange } from '../core/math.js';
import { Boss } from '../entities/enemies/Boss.js';
import { MeleeEnemy } from '../entities/enemies/MeleeEnemy.js';
import { RangedEnemy } from '../entities/enemies/RangedEnemy.js';
import { WAVES, waveMultipliers } from './waveDefs.js';

const ENEMY_CLASSES = { grunt: MeleeEnemy, archer: RangedEnemy, boss: Boss };
const NO_SCALING = { hp: 1, damage: 1, speed: 1 };

export class Spawner {
  constructor(game) {
    this.game = game;
    this.reset();
  }

  get totalWaves() {
    return WAVES.length;
  }

  reset() {
    this.wave = 0;
    this.queue = [];
    this.waveTimer = SPAWNER.firstDelay;
    this.spawnTimer = 0;
    this.finished = false;
  }

  update(dt) {
    const g = this.game;
    if (g.player.isDead || g.isOver || this.finished) return;

    if (this.queue.length > 0) {
      this.spawnTimer -= dt;
      if (this.spawnTimer <= 0) {
        this.#spawnFromQueue(this.queue.shift());
        this.spawnTimer = SPAWNER.spawnInterval;
      }
      return;
    }

    if (g.enemies.some((e) => !e.isDead)) return;
    if (this.wave >= WAVES.length) {
      this.finished = true;
      return;
    }
    this.waveTimer -= dt;
    if (this.waveTimer > 0) return;
    this.#startWave(this.wave + 1);
  }

  #startWave(wave) {
    const def = WAVES[wave - 1];
    this.wave = wave;
    this.waveTimer = SPAWNER.waveDelay;
    this.spawnTimer = def.isBoss ? 1.2 : 0.6;

    const queue = [];
    for (const [type, count] of Object.entries(def.spawns)) {
      for (let i = 0; i < count; i++) queue.push(type);
    }
    // Boss 先出場，其餘隨機排序
    queue.sort((a, b) => (b === 'boss') - (a === 'boss') || Math.random() - 0.5);
    this.queue = queue;

    this.game.stats.wave = wave;
    this.game.events.emit('wave:started', { wave, total: WAVES.length, isBoss: !!def.isBoss });
  }

  #spawnFromQueue(type) {
    const g = this.game;
    const p = g.player.position;
    const limit = WORLD.arenaHalfSize - 2;
    let x = 0;
    let z = 0;
    if (type === 'boss') {
      // 出現在玩家對面、靠近場地中央
      const len = Math.hypot(p.x, p.z);
      const s = len > 1 ? -Math.min(8, limit) / len : 0;
      x = len > 1 ? p.x * s : 0;
      z = len > 1 ? p.z * s : -8;
    } else {
      for (let attempt = 0; attempt < 20; attempt++) {
        x = randRange(-limit, limit);
        z = randRange(-limit, limit);
        if (Math.hypot(x - p.x, z - p.z) >= SPAWNER.minDistanceFromPlayer) break;
      }
    }
    this.spawnAt(type, x, z);
  }

  spawnAt(type, x, z) {
    const g = this.game;
    const Cls = ENEMY_CLASSES[type];
    const mul = type === 'boss' ? NO_SCALING : waveMultipliers(this.wave);
    const enemy = new Cls(g, type, x, z, mul);
    g.enemies.push(enemy);
    if (enemy.isBoss) g.boss = enemy;
    return enemy;
  }
}
