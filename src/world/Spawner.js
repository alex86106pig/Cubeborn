// 殭屍分波生成：場上清空後倒數，下一波逐隻從遠離玩家的位置爬出
import { SPAWNER, WORLD, ZOMBIE } from '../core/config.js';
import { randRange } from '../core/math.js';
import { Zombie } from '../entities/Zombie.js';

export class Spawner {
  constructor(game) {
    this.game = game;
    this.reset();
  }

  reset() {
    this.wave = 0;
    this.pending = 0;
    this.waveTimer = SPAWNER.firstDelay;
    this.spawnTimer = 0;
  }

  update(dt) {
    const g = this.game;
    if (g.player.isDead) return;

    if (this.pending > 0) {
      this.spawnTimer -= dt;
      if (this.spawnTimer <= 0) {
        this.#spawnOne();
        this.pending--;
        this.spawnTimer = SPAWNER.spawnInterval;
      }
      return;
    }

    if (g.enemies.some((e) => !e.isDead)) return;
    this.waveTimer -= dt;
    if (this.waveTimer > 0) return;

    this.wave++;
    this.pending = Math.min(SPAWNER.maxWaveCount, SPAWNER.firstWaveCount + (this.wave - 1) * SPAWNER.countPerWave);
    this.waveTimer = SPAWNER.waveDelay;
    this.spawnTimer = 0.6;
    g.stats.wave = this.wave;
    g.events.emit('wave:started', { wave: this.wave });
  }

  #spawnOne() {
    const g = this.game;
    const limit = WORLD.arenaHalfSize - 1.5;
    const p = g.player.position;
    let x = 0;
    let z = 0;
    for (let attempt = 0; attempt < 20; attempt++) {
      x = randRange(-limit, limit);
      z = randRange(-limit, limit);
      if (Math.hypot(x - p.x, z - p.z) >= SPAWNER.minDistanceFromPlayer) break;
    }
    const hpMul = 1 + (this.wave - 1) * ZOMBIE.hpPerWave;
    g.enemies.push(new Zombie(g, x, z, { hpMul }));
  }
}
