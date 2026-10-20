// 遠程小怪：與玩家保持距離並橫移，冷卻好時停下瞄準（有預備動作）後發射投射物
import * as THREE from 'three';
import { angleTo, clamp, distanceXZ, easeOutCubic, lerp, randRange, turnTowards } from '../../core/math.js';
import { getStyle } from '../../render/styles/index.js';
import { Projectile } from '../Projectile.js';
import { BASE_ENEMY_STATES, Enemy, poseWalk } from '../Enemy.js';

const _dir = new THREE.Vector3();
const _pos = new THREE.Vector3();

const STATES = {
  ...BASE_ENEMY_STATES,

  kite: {
    update(e, dt) {
      const player = e.game.player;
      if (player.isDead) {
        e.velocity.set(0, 0, 0);
        poseWalk(e, 0);
        return;
      }
      const toPlayer = angleTo(e.position, player.position);
      const dist = distanceXZ(e.position, player.position);
      const [min, max] = e.def.preferredRange;

      e.strafeTimer -= dt;
      if (e.strafeTimer <= 0) {
        e.strafeDir = Math.random() < 0.5 ? -1 : 1;
        e.strafeTimer = randRange(1.2, 2.6);
      }

      let moveAngle;
      let speedMul = 1;
      if (dist > max) moveAngle = toPlayer;
      else if (dist < min) moveAngle = toPlayer + Math.PI;
      else {
        moveAngle = toPlayer + (Math.PI / 2) * e.strafeDir;
        speedMul = 0.6;
      }
      e.velocity.set(Math.sin(moveAngle), 0, Math.cos(moveAngle)).multiplyScalar(e.speed * speedMul);
      e.facing = turnTowards(e.facing, toPlayer, e.def.turnSpeed * dt);
      e.walkPhase += dt * e.speed * speedMul * 2.2;
      poseWalk(e, 1, { armR: -0.2, armL: -0.5 });
      e.tryContactDamage(player);

      const cdKey = `${e.cdPrefix}.fire`;
      if (dist <= max + 3 && e.game.cooldowns.isReady(cdKey)) {
        e.game.cooldowns.start(cdKey, e.def.fireInterval * randRange(0.8, 1.25));
        e.fsm.change('aim');
      }
    },
  },

  aim: {
    enter(e) {
      e.game.events.emit('sfx:cue', { name: 'bowDraw' });
      e.velocity.set(0, 0, 0);
    },
    update(e, dt, fsm) {
      const player = e.game.player;
      const k = clamp(fsm.time / e.def.aimTime, 0, 1);
      // 前 75% 追蹤玩家，之後鎖定方向，讓玩家有閃避的機會
      if (k < 0.75 && !player.isDead) {
        e.facing = turnTowards(e.facing, angleTo(e.position, player.position), e.def.turnSpeed * 1.5 * dt);
      }
      const m = e.model;
      const draw = easeOutCubic(Math.min(1, k * 1.5));
      m.armL.rotation.x = lerp(-0.5, -1.55, draw);
      m.armR.rotation.x = lerp(-0.2, -1.45, draw);
      m.armR.rotation.y = lerp(0, 0.5, draw);
      m.legR.rotation.x = 0;
      m.legL.rotation.x = 0;

      if (Math.random() < 0.5) {
        _pos.set(Math.sin(e.facing), 0, Math.cos(e.facing)).multiplyScalar(0.7).add(e.position);
        e.game.effects.mote(_pos, { color: getStyle().colors.enemyProjectile, size: 0.08, life: 0.25, y: e.height * 0.65, vy: 0.6 });
      }
      if (k >= 1) {
        e.fire();
        fsm.change('kite');
      }
    },
    exit(e) {
      e.model.armR.rotation.y = 0;
    },
  },
};

export class RangedEnemy extends Enemy {
  static STATES = STATES;

  constructor(game, type, x, z, mul) {
    super(game, type, x, z, mul);
    this.mainState = 'kite';
    this.strafeDir = 1;
    this.strafeTimer = 0;
    // 剛出生時給一點延遲才第一次射擊
    game.cooldowns.start(`${this.cdPrefix}.fire`, randRange(0.8, 2));
  }

  fire() {
    const g = this.game;
    g.events.emit('sfx:cue', { name: 'arrowShot' });
    const style = getStyle();
    _dir.set(Math.sin(this.facing), 0, Math.cos(this.facing));
    _pos.copy(this.position).addScaledVector(_dir, 0.7);
    const d = this.def;
    g.projectiles.push(new Projectile(g, {
      owner: this, position: _pos, direction: _dir, speed: d.projectileSpeed, range: d.projectileRange,
      radius: d.projectileRadius, height: this.height * 0.6, damage: d.projectileDamage * this.damageMul,
      knockback: 6, color: style.colors.enemyProjectile, model: style.enemyProjectile(),
    }));
  }

  remove() {
    this.game.cooldowns.reset(`${this.cdPrefix}.fire`);
    super.remove();
  }
}
