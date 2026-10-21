// 敵人基底：數值套用（含波次倍率）、共用狀態（爬出 / 受擊 / 死亡）、接觸傷害、走路姿勢
import { angleTo, clamp, damp, distanceXZ, easeOutCubic, lerp, randRange } from '../core/math.js';
import { StateMachine } from '../core/StateMachine.js';
import { getStyle } from '../render/styles/index.js';
import { ENEMIES } from './enemyDefs.js';
import { Entity } from './Entity.js';

export function poseWalk(e, amount, { armR = -0.4, armL = -0.2 } = {}) {
  const swing = Math.sin(e.walkPhase) * 0.8 * amount;
  const m = e.model;
  m.legR.rotation.x = swing;
  m.legL.rotation.x = -swing;
  m.armR.rotation.x = armR - swing * 0.4;
  m.armL.rotation.x = armL + swing * 0.5;
  m.armR.rotation.y = 0;
  m.armL.rotation.y = 0;
  m.body.position.y = Math.abs(Math.sin(e.walkPhase)) * 0.04 * amount;
}

// 所有敵人共用的狀態；子類別合併自己的狀態並指定 mainState
export const BASE_ENEMY_STATES = {
  spawn: {
    enter(e) {
      e.game.events.emit('sfx:cue', { name: 'enemySpawn' });
      e.model.root.position.y = -e.height;
    },
    update(e, dt, fsm) {
      const k = clamp(fsm.time / e.def.spawnTime, 0, 1);
      e.model.root.position.y = lerp(-e.height, 0, easeOutCubic(k));
      if (Math.random() < 0.4) {
        e.game.effects.burst(e.position, { color: 0x6b4f2e, count: 1, speed: 2, up: 3, y: 0.1, size: 0.15 });
      }
      poseWalk(e, 0);
      if (k >= 1) fsm.change(e.mainState);
    },
    exit(e) {
      e.model.root.position.y = 0;
    },
  },

  hurt: {
    enter(e) {
      e.velocity.set(0, 0, 0);
    },
    update(e, dt, fsm) {
      const k = clamp(fsm.time / e.def.hurtTime, 0, 1);
      e.model.body.rotation.x = -0.35 * Math.sin(k * Math.PI);
      e.model.armR.rotation.x = damp(e.model.armR.rotation.x, -0.6, 20, dt);
      e.model.armL.rotation.x = damp(e.model.armL.rotation.x, -0.6, 20, dt);
      if (k >= 1) fsm.change(e.mainState);
    },
    exit(e) {
      e.model.body.rotation.x = 0;
    },
  },

  // 終止狀態：向後倒下 → 沉入地面 → 移除
  dead: {
    enter(e) {
      e.velocity.set(0, 0, 0);
      const style = getStyle();
      e.game.effects.burst(e.position, {
        color: e.isBoss ? style.colors.bossBlood : style.colors.blood,
        count: e.isBoss ? 40 : 14, speed: e.isBoss ? 8 : 4, up: 4, size: e.isBoss ? 0.3 : 0.18, y: e.height * 0.5,
      });
    },
    update(e, dt, fsm) {
      const t = fsm.time;
      const fall = clamp(t / 0.4, 0, 1);
      e.model.body.rotation.x = lerp(0, -Math.PI / 2, easeOutCubic(fall));
      e.model.body.position.y = 0.13 * fall;
      const sinkStart = e.def.corpseTime * 0.6;
      const sink = clamp((t - sinkStart) / (e.def.corpseTime - sinkStart), 0, 1);
      e.model.root.position.y = -0.8 * sink;
      if (t >= e.def.corpseTime) e.remove();
    },
  },
};

export class Enemy extends Entity {
  /**
   * @param type ENEMIES 的 key
   * @param mul 波次倍率 { hp, damage, speed }
   */
  constructor(game, type, x, z, mul = { hp: 1, damage: 1, speed: 1 }) {
    const def = ENEMIES[type];
    super(game, { radius: def.radius, maxHp: Math.round(def.maxHp * mul.hp), mass: def.mass, team: 'enemy' });
    this.def = def;
    this.type = type;
    this.damageMul = mul.damage;
    this.speed = def.moveSpeed * mul.speed * randRange(1 - def.speedVariance, 1 + def.speedVariance);
    this.knockbackMul = def.knockbackMul ?? 1;
    this.mainState = 'chase';
    this.walkPhase = Math.random() * Math.PI * 2;
    this.contactTimer = 0;
    this.position.set(x, 0, z);
    this.facing = angleTo(this.position, game.player.position);
    this.attachModel(this.createModel());
    this.fsm = new StateMachine(this, this.constructor.STATES, 'spawn');
    this.syncModel();
  }

  get isBoss() {
    return false;
  }

  get isSpawning() {
    return this.fsm.is('spawn');
  }

  get cdPrefix() {
    return `enemy${this.id}`;
  }

  createModel() {
    return getStyle().characters[this.def.visual]();
  }

  update(dt) {
    this.contactTimer = Math.max(0, this.contactTimer - dt);
    this.fsm.update(dt);
  }

  // 接觸傷害：貼到玩家時每隔一段時間造成傷害，回傳是否命中
  tryContactDamage(player) {
    if (this.contactTimer > 0 || player.isDead) return false;
    if (distanceXZ(this.position, player.position) > this.radius + player.radius + 0.15) return false;
    const hit = this.game.combat.applyDamage(this, player, {
      damage: this.def.contactDamage * this.damageMul, knockback: this.def.contactKnockback, color: 0xff4040,
    });
    if (hit) this.contactTimer = this.def.contactInterval;
    return hit;
  }

  onDamaged() {
    if (!this.isDead && !this.isSpawning && this.fsm.states.hurt) this.fsm.change('hurt');
  }

  onDied() {
    this.fsm.change('dead');
  }
}
