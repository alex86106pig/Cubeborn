// 玩家雙層狀態機定義：移動層（腿部、位移）與動作層（攻擊、技能、硬直、上半身）
import { PLAYER } from '../core/config.js';
import { clamp, damp, easeOutCubic, lerp } from '../core/math.js';
import { WEAPON_BEHAVIORS } from '../weapons/weaponBehaviors.js';

const PHASES = ['windup', 'active', 'recovery'];

// ───────── 移動層 ─────────

function poseLegs(p) {
  const swing = Math.sin(p.walkPhase) * 0.9 * p.walkAmount;
  p.model.legR.rotation.x = swing;
  p.model.legL.rotation.x = -swing;
  p.model.body.position.y = Math.abs(Math.sin(p.walkPhase)) * 0.06 * p.walkAmount;
}

export const LOCOMOTION_STATES = {
  idle: {
    update(p, dt, fsm) {
      p.walkAmount = damp(p.walkAmount, 0, 12, dt);
      poseLegs(p);
      if (p.moveInput.lengthSq() > 0.01) fsm.change('move');
    },
  },

  move: {
    update(p, dt, fsm) {
      p.walkAmount = damp(p.walkAmount, 1, 12, dt);
      p.walkPhase += dt * p.velocity.length() * 1.7;
      poseLegs(p);
      if (p.moveInput.lengthSq() <= 0.01) fsm.change('idle');
    },
  },

  // 終止狀態：向前倒地
  dead: {
    enter(p) {
      p.walkAmount = 0;
    },
    update(p, dt, fsm) {
      const k = easeOutCubic(clamp(fsm.time / 0.45, 0, 1));
      p.model.body.rotation.x = lerp(0, Math.PI / 2, k);
      p.model.body.position.y = 0.13 * k;
      p.model.armR.rotation.x = lerp(p.model.armR.rotation.x, -2.6, 0.2);
      p.model.armL.rotation.x = lerp(p.model.armL.rotation.x, -2.6, 0.2);
    },
  },
};

// ───────── 動作層 ─────────

// 上半身平滑回到武器待機姿勢；手臂隨走路擺動
function poseIdleUpperBody(p, dt) {
  const m = p.model;
  const idle = p.weapon.idle;
  const swing = Math.sin(p.walkPhase) * 0.6 * p.walkAmount;
  const s = 18;
  m.armR.rotation.x = damp(m.armR.rotation.x, idle.armR - swing * 0.5, s, dt);
  m.armR.rotation.y = damp(m.armR.rotation.y, 0, s, dt);
  m.armL.rotation.x = damp(m.armL.rotation.x, idle.armL + swing, s, dt);
  m.armL.rotation.y = damp(m.armL.rotation.y, 0, s, dt);
  m.body.rotation.x = damp(m.body.rotation.x, 0, s, dt);
  m.body.rotation.y = damp(m.body.rotation.y, 0, s, dt);
  p.weaponTilt = damp(p.weaponTilt, idle.tilt, s, dt);
}

// 攻擊與特殊技共用的三段式動作狀態
function createTimedActionState(kind) {
  return {
    enter(p, data) {
      const def = p.weapon[kind];
      data.def = def;
      data.behavior = WEAPON_BEHAVIORS[def.behavior];
      data.durations = [def.windup, def.active, def.recovery];
      data.phaseIndex = 0;
      data.phaseTime = 0;
      data.moveSpeedMul = def.moveSpeedMul ?? 1;
      data.lockFacing = false;
      if (kind === 'special') {
        p.game.cooldowns.start('player.special', def.cooldown);
        p.game.events.emit('skill:used', { key: 'player.special', def });
      }
      data.behavior.enter?.(p, def, data);
      data.behavior.phase?.(p, def, data, PHASES[0]);
    },

    update(p, dt, fsm) {
      const d = fsm.data;
      d.phaseTime += dt;
      while (d.phaseIndex < PHASES.length && d.phaseTime >= d.durations[d.phaseIndex]) {
        d.phaseTime -= d.durations[d.phaseIndex];
        d.phaseIndex++;
        if (d.phaseIndex < PHASES.length) d.behavior.phase?.(p, d.def, d, PHASES[d.phaseIndex]);
      }
      if (d.phaseIndex >= PHASES.length) {
        fsm.change('ready');
        return;
      }
      const name = PHASES[d.phaseIndex];
      const duration = d.durations[d.phaseIndex];
      d.behavior.update?.(p, d.def, d, name, duration > 0 ? d.phaseTime / duration : 1, dt);
      // 後搖可被緩衝中的技能取消，手感較跟手
      if (name === 'recovery' && p.bufferedAction) fsm.change('ready');
    },

    exit(p, fsm) {
      fsm.data.behavior.exit?.(p, fsm.data.def, fsm.data);
    },
  };
}

export const ACTION_STATES = {
  ready: {
    enter(p, data) {
      data.moveSpeedMul = 1;
    },
    update(p, dt, fsm) {
      const buffered = p.bufferedAction;
      if (buffered) {
        p.bufferedAction = null;
        if (buffered.type === 'special') {
          if (p.game.cooldowns.isReady('player.special')) return void fsm.change('special');
          p.game.events.emit('skill:onCooldown', { key: 'player.special' });
        } else if (buffered.type === 'slot') {
          if (p.slots.canUse(buffered.index)) return void fsm.change('useItem', { index: buffered.index });
          p.slots.notifyBlocked(buffered.index);
        }
      }
      if (p.game.input.mouse.left) return void fsm.change('attack');
      poseIdleUpperBody(p, dt);
    },
  },

  attack: createTimedActionState('attack'),
  special: createTimedActionState('special'),

  useItem: {
    enter(p, data) {
      data.moveSpeedMul = 1;
      p.slots.use(data.index);
    },
    update(p, dt, fsm) {
      const k = clamp(fsm.time / 0.18, 0, 1);
      p.model.armL.rotation.x = lerp(0, -2.4, Math.sin(k * Math.PI));
      if (k >= 1) fsm.change('ready');
    },
  },

  stagger: {
    enter(p, data) {
      data.moveSpeedMul = 0.4;
    },
    update(p, dt, fsm) {
      const k = clamp(fsm.time / PLAYER.staggerTime, 0, 1);
      p.model.body.rotation.x = -0.3 * Math.sin(k * Math.PI);
      if (k >= 1) fsm.change('ready');
    },
  },
};
