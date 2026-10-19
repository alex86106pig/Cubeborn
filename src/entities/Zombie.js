// 殭屍：從地底爬出、追擊玩家、接觸傷害、受擊硬直、倒地消失
import { ZOMBIE } from '../core/config.js';
import { angleTo, clamp, damp, distanceXZ, easeOutCubic, lerp, randRange, turnTowards } from '../core/math.js';
import { StateMachine } from '../core/StateMachine.js';
import { HumanoidModel } from '../render/HumanoidModel.js';
import { Entity } from './Entity.js';

function poseWalk(z, amount) {
  const swing = Math.sin(z.walkPhase) * 0.7 * amount;
  z.model.legR.rotation.x = swing;
  z.model.legL.rotation.x = -swing;
  // 經典殭屍姿勢：雙手前伸並微微晃動
  z.model.armR.rotation.x = -1.45 + Math.sin(z.walkPhase * 0.5) * 0.12;
  z.model.armL.rotation.x = -1.45 - Math.sin(z.walkPhase * 0.5) * 0.12;
}

const ZOMBIE_STATES = {
  spawn: {
    enter(z) {
      z.model.root.position.y = -1.9;
    },
    update(z, dt, fsm) {
      const k = clamp(fsm.time / ZOMBIE.spawnTime, 0, 1);
      z.model.root.position.y = lerp(-1.9, 0, easeOutCubic(k));
      if (Math.random() < 0.4) {
        z.game.effects.burst(z.position, { color: 0x6b4f2e, count: 1, speed: 2, up: 3, y: 0.1, size: 0.15 });
      }
      poseWalk(z, 0);
      if (k >= 1) fsm.change('chase');
    },
  },

  chase: {
    update(z, dt) {
      const player = z.game.player;
      if (player.isDead) {
        z.velocity.set(0, 0, 0);
        poseWalk(z, 0);
        return;
      }
      const target = angleTo(z.position, player.position);
      z.facing = turnTowards(z.facing, target, ZOMBIE.turnSpeed * dt);
      z.velocity.set(Math.sin(z.facing), 0, Math.cos(z.facing)).multiplyScalar(z.speed);
      z.walkPhase += dt * z.speed * 2.2;
      poseWalk(z, 1);
      z.tryContactDamage(player);
    },
  },

  hurt: {
    enter(z) {
      z.velocity.set(0, 0, 0);
    },
    update(z, dt, fsm) {
      const k = clamp(fsm.time / ZOMBIE.hurtTime, 0, 1);
      z.model.body.rotation.x = -0.35 * Math.sin(k * Math.PI);
      z.model.armR.rotation.x = damp(z.model.armR.rotation.x, -0.6, 20, dt);
      z.model.armL.rotation.x = damp(z.model.armL.rotation.x, -0.6, 20, dt);
      if (k >= 1) fsm.change('chase');
    },
    exit(z) {
      z.model.body.rotation.x = 0;
    },
  },

  // 終止狀態：向後倒下 → 沉入地面 → 移除
  dead: {
    enter(z) {
      z.velocity.set(0, 0, 0);
      z.game.effects.burst(z.position, { color: 0x5fa04e, count: 14, speed: 4, up: 4, size: 0.18, y: 1 });
    },
    update(z, dt, fsm) {
      const t = fsm.time;
      z.model.body.rotation.x = lerp(0, -Math.PI / 2, easeOutCubic(clamp(t / 0.35, 0, 1)));
      z.model.body.position.y = 0.13 * clamp(t / 0.35, 0, 1);
      const sink = clamp((t - 0.8) / (ZOMBIE.corpseTime - 0.8), 0, 1);
      z.model.root.position.y = -0.6 * sink;
      if (t >= ZOMBIE.corpseTime) z.remove();
    },
  },
};

export class Zombie extends Entity {
  constructor(game, x, z, { hpMul = 1 } = {}) {
    super(game, { radius: ZOMBIE.radius, maxHp: Math.round(ZOMBIE.maxHp * hpMul), mass: ZOMBIE.mass, team: 'enemy' });
    this.attachModel(new HumanoidModel(ZOMBIE.colors));
    this.position.set(x, 0, z);
    this.speed = ZOMBIE.moveSpeed * randRange(1 - ZOMBIE.speedVariance, 1 + ZOMBIE.speedVariance);
    this.walkPhase = Math.random() * Math.PI * 2;
    this.contactTimer = 0;
    this.facing = angleTo(this.position, game.player.position);
    this.fsm = new StateMachine(this, ZOMBIE_STATES, 'spawn');
    this.syncModel();
  }

  get isSpawning() {
    return this.fsm.is('spawn');
  }

  update(dt) {
    this.contactTimer = Math.max(0, this.contactTimer - dt);
    this.fsm.update(dt);
  }

  tryContactDamage(player) {
    if (this.contactTimer > 0) return;
    if (distanceXZ(this.position, player.position) > this.radius + player.radius + 0.15) return;
    const hit = this.game.combat.applyDamage(this, player, {
      damage: ZOMBIE.contactDamage, knockback: 9, color: 0xff4040,
    });
    if (hit) this.contactTimer = ZOMBIE.contactInterval;
  }

  onDamaged() {
    if (!this.isDead && !this.isSpawning) this.fsm.change('hurt');
  }

  onDied() {
    this.fsm.change('dead');
  }
}
