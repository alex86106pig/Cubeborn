// 近戰小怪：追擊玩家，貼身時以接觸傷害攻擊（附揮擊動畫）
import { angleTo, clamp, turnTowards } from '../../core/math.js';
import { BASE_ENEMY_STATES, Enemy, poseWalk } from '../Enemy.js';

const SWING_TIME = 0.3;

const STATES = {
  ...BASE_ENEMY_STATES,

  chase: {
    update(e, dt) {
      const player = e.game.player;
      if (player.isDead) {
        e.velocity.set(0, 0, 0);
        poseWalk(e, 0);
        return;
      }
      e.facing = turnTowards(e.facing, angleTo(e.position, player.position), e.def.turnSpeed * dt);
      e.velocity.set(Math.sin(e.facing), 0, Math.cos(e.facing)).multiplyScalar(e.speed);
      e.walkPhase += dt * e.speed * 2.2;
      poseWalk(e, 1, { armR: -0.6, armL: -0.3 });
      if (e.tryContactDamage(player)) e.swingTimer = SWING_TIME;

      // 命中時的揮擊動畫：武器由上往下砸
      if (e.swingTimer > 0) {
        e.swingTimer -= dt;
        const k = 1 - clamp(e.swingTimer / SWING_TIME, 0, 1);
        e.model.armR.rotation.x = k < 0.3 ? -2.6 : -2.6 + (k - 0.3) / 0.7 * 2.2;
      }
    },
  },
};

export class MeleeEnemy extends Enemy {
  static STATES = STATES;

  constructor(game, type, x, z, mul) {
    super(game, type, x, z, mul);
    this.swingTimer = 0;
  }
}
