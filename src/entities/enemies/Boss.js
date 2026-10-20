// Boss：霸體（不硬直、擊退大幅減免），招式有地面預警
// 招式：重砸（近身範圍）、衝鋒（直線，撞牆會暈眩）、召喚小怪；血量低於一半進入狂暴
import * as THREE from 'three';
import { WORLD } from '../../core/config.js';
import { angleTo, clamp, distanceXZ, easeOutCubic, lerp, randRange, turnTowards } from '../../core/math.js';
import { getStyle } from '../../render/styles/index.js';
import { BASE_ENEMY_STATES, Enemy, poseWalk } from '../Enemy.js';

const TELEGRAPH_COLOR = 0xff3030;
const _targets = [];

function poseArms(e, rx, ry = 0) {
  e.model.armR.rotation.set(rx, -ry, 0);
  e.model.armL.rotation.set(rx, ry, 0);
}

const STATES = {
  ...BASE_ENEMY_STATES,

  spawn: {
    ...BASE_ENEMY_STATES.spawn,
    enter(e) {
      BASE_ENEMY_STATES.spawn.enter(e);
      e.game.renderer.shake(0.4, e.def.spawnTime);
    },
  },

  chase: {
    update(e, dt, fsm) {
      const player = e.game.player;
      if (player.isDead) {
        e.velocity.set(0, 0, 0);
        poseWalk(e, 0);
        return;
      }
      const dist = distanceXZ(e.position, player.position);
      const cd = e.game.cooldowns;
      const d = e.def;

      if (fsm.time > 0.4) {
        if (dist <= d.slam.triggerDistance && cd.isReady(e.cd('slam'))) return void fsm.change('slam');
        if (dist >= d.charge.minDistance && cd.isReady(e.cd('charge'))) return void fsm.change('charge');
        if (e.hp / e.maxHp <= d.summon.hpThreshold && cd.isReady(e.cd('summon'))) return void fsm.change('summon');
      }

      e.facing = turnTowards(e.facing, angleTo(e.position, player.position), d.turnSpeed * dt);
      const speed = e.speed * e.enrageMul('speedMul');
      e.velocity.set(Math.sin(e.facing), 0, Math.cos(e.facing)).multiplyScalar(speed);
      e.walkPhase += dt * speed * 1.6;
      poseWalk(e, 1, { armR: -0.5, armL: -0.3 });
      e.tryContactDamage(player);
    },
  },

  // 重砸：舉起雙手 → 落地造成圓形範圍傷害
  slam: {
    enter(e, data) {
      e.game.events.emit('sfx:cue', { name: 'bossSlamWindup' });
      const s = e.def.slam;
      e.velocity.set(0, 0, 0);
      e.game.cooldowns.start(e.cd('slam'), s.cooldown * e.enrageMul('cooldownMul'));
      e.game.effects.telegraph(e.position, s.radius, { color: TELEGRAPH_COLOR, life: s.windup });
      data.hasHit = false;
    },
    update(e, dt, fsm) {
      const s = e.def.slam;
      const t = fsm.time;
      if (t < s.windup) {
        const k = easeOutCubic(t / s.windup);
        poseArms(e, lerp(-0.4, -3.0, k), 0.3);
        e.model.body.rotation.x = lerp(0, -0.2, k);
        return;
      }
      if (!fsm.data.hasHit) {
        fsm.data.hasHit = true;
        e.slamImpact();
      }
      const k = clamp((t - s.windup) / 0.12, 0, 1);
      poseArms(e, lerp(-3.0, -0.9, k), 0.3);
      e.model.body.rotation.x = lerp(-0.2, 0.3, k);
      if (t >= s.windup + s.recovery) fsm.change('chase');
    },
    exit(e) {
      e.model.body.rotation.x = 0;
    },
  },

  // 衝鋒：鎖定方向蓄力 → 直線衝刺；撞牆會暈眩（玩家的輸出時機）
  charge: {
    enter(e, data) {
      e.game.events.emit('sfx:cue', { name: 'bossChargeWindup' });
      const c = e.def.charge;
      e.velocity.set(0, 0, 0);
      e.game.cooldowns.start(e.cd('charge'), c.cooldown * e.enrageMul('cooldownMul'));
      e.facing = angleTo(e.position, e.game.player.position);
      data.dir = new THREE.Vector3(Math.sin(e.facing), 0, Math.cos(e.facing));
      data.phase = 'windup';
      data.phaseTime = 0;
      data.hasHit = false;
      e.game.effects.telegraphLine(e.position, data.dir, c.speed * c.duration, e.radius * 2, {
        color: TELEGRAPH_COLOR, life: c.windup,
      });
    },
    update(e, dt, fsm) {
      const c = e.def.charge;
      const d = fsm.data;
      d.phaseTime += dt;

      if (d.phase === 'windup') {
        const k = easeOutCubic(clamp(d.phaseTime / c.windup, 0, 1));
        poseArms(e, lerp(-0.4, 0.6, k));
        e.model.body.rotation.x = lerp(0, 0.35, k);
        if (d.phaseTime >= c.windup) { d.phase = 'dash'; d.phaseTime = 0; }
        return;
      }

      if (d.phase === 'dash') {
        e.velocity.copy(d.dir).multiplyScalar(c.speed);
        e.walkPhase += dt * c.speed * 1.2;
        poseWalk(e, 1, { armR: 0.6, armL: 0.6 });
        e.model.body.rotation.x = 0.35;
        if (Math.random() < 0.6) {
          e.game.effects.burst(e.position, { color: 0x8a7a5a, count: 1, speed: 2, up: 2, y: 0.1, size: 0.2 });
        }
        const player = e.game.player;
        if (!d.hasHit && !player.isDead && distanceXZ(e.position, player.position) < e.radius + player.radius + 0.3) {
          d.hasHit = e.game.combat.applyDamage(e, player, {
            damage: c.damage * e.damageMul, knockback: c.knockback, color: 0xff4040, shake: 0.4, hitStop: 0.06,
          });
        }
        const limit = WORLD.arenaHalfSize - e.radius - 0.05;
        const hitWall = Math.abs(e.position.x) >= limit || Math.abs(e.position.z) >= limit;
        if (hitWall) {
          e.game.events.emit('sfx:cue', { name: 'bossWallHit' });
          d.phase = 'stunned';
          d.phaseTime = 0;
          e.velocity.set(0, 0, 0);
          e.game.renderer.shake(0.6, 0.35);
          e.game.effects.ring(e.position, 2.5, { color: 0xffffff, life: 0.35 });
          e.game.effects.burst(e.position, { color: 0x9a9a9a, count: 20, speed: 6, up: 5, y: 1, size: 0.22 });
        } else if (d.phaseTime >= c.duration) {
          d.phase = 'recovery';
          d.phaseTime = 0;
          e.velocity.set(0, 0, 0);
        }
        return;
      }

      // 後搖或撞牆暈眩
      e.velocity.set(0, 0, 0);
      const duration = d.phase === 'stunned' ? c.wallStun : c.recovery;
      const k = clamp(d.phaseTime / duration, 0, 1);
      if (d.phase === 'stunned') {
        e.model.body.rotation.x = -0.25 + Math.sin(d.phaseTime * 18) * 0.05;
        e.model.head.rotation.y = Math.sin(d.phaseTime * 6) * 0.4;
        if (Math.random() < 0.2) {
          e.game.effects.mote({ x: e.position.x + randRange(-0.5, 0.5), z: e.position.z + randRange(-0.5, 0.5) },
            { color: 0xffe14a, size: 0.15, life: 0.4, y: e.height + 0.2, vy: 0.4 });
        }
      } else {
        e.model.body.rotation.x = lerp(0.35, 0, k);
      }
      poseArms(e, -0.3);
      if (k >= 1) fsm.change('chase');
    },
    exit(e) {
      e.model.body.rotation.x = 0;
      e.model.head.rotation.y = 0;
    },
  },

  // 召喚：高舉雙手後在身邊召喚小怪
  summon: {
    enter(e, data) {
      e.game.events.emit('sfx:cue', { name: 'bossSummon' });
      e.velocity.set(0, 0, 0);
      e.game.cooldowns.start(e.cd('summon'), e.def.summon.cooldown * e.enrageMul('cooldownMul'));
      data.done = false;
    },
    update(e, dt, fsm) {
      const s = e.def.summon;
      const k = clamp(fsm.time / s.windup, 0, 1);
      poseArms(e, lerp(-0.4, -2.9, easeOutCubic(k)), 0.5);
      if (Math.random() < 0.7) {
        e.game.effects.mote({ x: e.position.x + randRange(-1.5, 1.5), z: e.position.z + randRange(-1.5, 1.5) },
          { color: getStyle().colors.bossBlood, size: 0.15, life: 0.5, y: randRange(0.2, 1), vy: 2 });
      }
      if (k >= 1 && !fsm.data.done) {
        fsm.data.done = true;
        e.summonMinions();
      }
      if (fsm.time >= s.windup + s.recovery) fsm.change('chase');
    },
  },
};

export class Boss extends Enemy {
  static STATES = STATES;

  constructor(game, type, x, z, mul) {
    super(game, type, x, z, mul);
    this.isEnraged = false;
    // 開場給玩家一點時間
    game.cooldowns.start(this.cd('charge'), 3);
    game.cooldowns.start(this.cd('summon'), 2);
  }

  get isBoss() {
    return true;
  }

  get displayName() {
    return getStyle().names.boss;
  }

  cd(name) {
    return `${this.cdPrefix}.${name}`;
  }

  enrageMul(key) {
    return this.isEnraged ? this.def.enrage[key] : 1;
  }

  slamImpact() {
    const g = this.game;
    g.events.emit('sfx:cue', { name: 'bossSlam' });
    const s = this.def.slam;
    for (const target of g.combat.queryCircle(this.position, s.radius, g.combat.hostilesOf(this, _targets), [])) {
      g.combat.applyDamage(this, target, {
        damage: s.damage * this.damageMul, knockback: s.knockback, color: 0xff4040, hitStop: 0.06,
      });
    }
    g.effects.ring(this.position, s.radius, { color: 0xffffff, life: 0.35 });
    g.effects.ring(this.position, s.radius * 1.3, { color: 0x9a8a6a, life: 0.5, opacity: 0.5 });
    g.effects.burst(this.position, { color: 0x8a7a5a, count: 30, speed: 7, up: 6, y: 0.2, size: 0.25 });
    g.renderer.shake(0.7, 0.35);
  }

  summonMinions() {
    const g = this.game;
    const n = this.def.summon.count;
    for (let i = 0; i < n; i++) {
      const a = this.facing + Math.PI + (i - (n - 1) / 2) * 0.9;
      const limit = WORLD.arenaHalfSize - 1.5;
      const x = clamp(this.position.x + Math.sin(a) * 2.5, -limit, limit);
      const z = clamp(this.position.z + Math.cos(a) * 2.5, -limit, limit);
      g.spawner.spawnAt('grunt', x, z);
    }
  }

  onDamaged() {
    if (!this.isEnraged && !this.isDead && this.hp / this.maxHp <= this.def.enrage.hpThreshold) {
      this.isEnraged = true;
      this.game.events.emit('boss:enraged', { boss: this });
      this.game.effects.ring(this.position, 4, { color: getStyle().colors.bossBlood, life: 0.5 });
      this.game.renderer.shake(0.5, 0.4);
    }
  }

  onDied() {
    super.onDied();
    this.game.onBossDefeated(this);
  }

  remove() {
    for (const name of ['slam', 'charge', 'summon']) this.game.cooldowns.reset(this.cd(name));
    super.remove();
  }
}
