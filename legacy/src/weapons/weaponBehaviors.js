// 武器行為：由玩家的 attack / special 狀態在 windup → active → recovery 各階段呼叫
// 介面：enter(p, def, data) / phase(p, def, data, name) / update(p, def, data, name, k, dt) / exit(p, def, data)
// k 為目前階段的進度 0~1；data 是本次出手的暫存資料（data.lockFacing 可鎖定轉向）
import * as THREE from 'three';
import { PLAYER } from '../core/config.js';
import { clamp, easeOutCubic, lerp, randRange } from '../core/math.js';
import { Projectile } from '../entities/Projectile.js';

const _candidates = [];
const _hits = [];
const _dir = new THREE.Vector3();
const _pos = new THREE.Vector3();

function forward(p, out = _dir) {
  return out.set(Math.sin(p.facing), 0, Math.cos(p.facing));
}

function aimDirection(p, out = _dir) {
  out.set(p.aimPoint.x - p.position.x, 0, p.aimPoint.z - p.position.z);
  if (out.lengthSq() < 0.25) return forward(p, out);
  return out.normalize();
}

const meleeSwing = {
  enter(p, def, data) {
    p.comboStep = p.comboTimer > 0 ? (p.comboStep + 1) % 3 : 0;
    data.isFinisher = p.comboStep === 2;
    data.swingDir = p.comboStep === 1 ? -1 : 1;   // 第二段反手
    data.scale = data.isFinisher ? 1.25 : 1;
    data.hit = new Set();
    if (data.isFinisher) data.durations[2] = def.recovery * 1.6;
  },

  phase(p, def, data, name) {
    if (name === 'active') {
      data.lockFacing = true;
      p.game.effects.slash(p.position, p.facing, def.range * data.scale, def.arc * data.scale, {
        color: data.isFinisher ? 0xffe27a : 0xffffff,
        swingDir: data.swingDir,
      });
      p.knockback.addScaledVector(forward(p), def.lunge * data.scale);
    } else if (name === 'recovery') {
      data.lockFacing = false;
    }
  },

  update(p, def, data, name, k) {
    const s = data.swingDir;
    const arm = p.model.armR;
    const body = p.model.body;
    const idle = p.weapon.idle;
    p.model.armL.rotation.x = lerp(p.model.armL.rotation.x, -0.6, 0.3);

    if (name === 'windup') {
      const e = easeOutCubic(k);
      arm.rotation.x = lerp(idle.armR, -1.35, e);
      arm.rotation.y = lerp(0, -1.3 * s, e);
      body.rotation.y = lerp(0, -0.25 * s, e);
      return;
    }

    if (name === 'active') {
      const e = easeOutCubic(k);
      arm.rotation.x = -1.45;
      arm.rotation.y = lerp(-1.3 * s, 1.2 * s, e);
      body.rotation.y = lerp(-0.25 * s, 0.35 * s, e);
      this.hitTargets(p, def, data);
      return;
    }

    const e = easeOutCubic(k);
    arm.rotation.x = lerp(-1.45, idle.armR, e);
    arm.rotation.y = lerp(1.2 * s, 0, e);
    body.rotation.y = lerp(0.35 * s, 0, e);
  },

  hitTargets(p, def, data) {
    const combat = p.game.combat;
    const fin = data.isFinisher;
    const targets = combat.querySector(p.position, p.facing, def.range * data.scale, def.arc * data.scale,
      combat.hostilesOf(p, _candidates), _hits);
    for (const target of targets) {
      if (data.hit.has(target)) continue;
      data.hit.add(target);
      combat.applyDamage(p, target, {
        damage: def.damage * (fin ? def.finisherMul : 1),
        knockback: def.knockback * (fin ? 1.8 : 1),
        hitStop: def.hitStop * (fin ? 1.8 : 1),
        shake: def.shake * (fin ? 2.5 : 1),
        isCrit: fin,
      });
    }
  },

  exit(p, def) {
    p.comboTimer = def.comboWindow;
  },
};

const shieldBash = {
  enter(p, def, data) {
    data.dir = aimDirection(p, new THREE.Vector3());
    data.hit = new Set();
    data.lockFacing = true;
    p.facing = Math.atan2(data.dir.x, data.dir.z);
    p.damageTakenMul = def.damageTakenMul;
    p.knockbackMul = 0;
  },

  phase(p, def, data, name) {
    if (name === 'active') {
      p.forcedVelocity.copy(data.dir).multiplyScalar(def.dashSpeed);
      p.hasForcedVelocity = true;
      p.mass = 8; // 衝鋒時把殭屍推開
      p.game.effects.ring(p.position, 1.4, { color: 0xffd36b, life: 0.25 });
    } else if (name === 'recovery') {
      p.hasForcedVelocity = false;
      p.mass = PLAYER.mass;
    }
  },

  update(p, def, data, name, k) {
    const m = p.model;
    if (name === 'windup') {
      const e = easeOutCubic(k);
      m.armL.rotation.x = lerp(-0.1, -1.5, e);
      m.armL.rotation.y = lerp(0, -0.6, e);
      m.armR.rotation.x = lerp(-0.35, 0.5, e);
      m.body.rotation.x = lerp(0, 0.25, e);
      return;
    }
    if (name === 'active') {
      m.armL.rotation.set(-1.5, -0.6, 0);
      m.armR.rotation.x = 0.5;
      m.body.rotation.x = 0.25;
      const g = p.game;
      g.effects.burst(p.position, { color: 0x9c8a6a, count: 1, speed: 1.5, up: 2, y: 0.1, size: 0.12 });
      _pos.copy(p.position).addScaledVector(data.dir, 0.5);
      const targets = g.combat.queryCircle(_pos, def.radius, g.combat.hostilesOf(p, _candidates), _hits);
      for (const target of targets) {
        if (data.hit.has(target)) continue;
        data.hit.add(target);
        g.combat.applyDamage(p, target, {
          damage: def.damage, knockback: def.knockback, origin: p.position,
          hitStop: def.hitStop, shake: def.shake, color: 0xffd36b, isCrit: true,
        });
      }
      return;
    }
    const e = easeOutCubic(k);
    m.body.rotation.x = lerp(0.25, 0, e);
  },

  exit(p) {
    p.hasForcedVelocity = false;
    p.mass = PLAYER.mass;
    p.damageTakenMul = 1;
    p.knockbackMul = 1;
  },
};

const fireBolt = {
  phase(p, def, data, name) {
    if (name !== 'active') return;
    const g = p.game;
    const dir = aimDirection(p);
    p.facing = Math.atan2(dir.x, dir.z);
    _pos.copy(p.position).addScaledVector(dir, 0.6);
    g.projectiles.push(new Projectile(g, {
      owner: p, position: _pos, direction: dir, speed: def.projectileSpeed, range: def.range,
      radius: def.projectileRadius, damage: def.damage, knockback: def.knockback,
      color: def.color, hitStop: def.hitStop, shake: def.shake,
    }));
    g.effects.burst(_pos, { color: def.color, count: 5, speed: 2.5, up: 1.5, y: 1.25, size: 0.1, life: 0.25 });
  },

  update(p, def, data, name, k) {
    const arm = p.model.armR;
    const idle = p.weapon.idle;
    if (name === 'windup') {
      const e = easeOutCubic(k);
      arm.rotation.x = lerp(idle.armR, -1.5, e);
      p.weaponTilt = lerp(0, 1.3, e);
    } else {
      const e = name === 'active' ? 0 : easeOutCubic(k);
      arm.rotation.x = lerp(-1.5, idle.armR, e);
      p.weaponTilt = lerp(1.3, 0, e);
    }
  },
};

const arcaneBurst = {
  enter(p, def, data) {
    const v = new THREE.Vector3(p.aimPoint.x - p.position.x, 0, p.aimPoint.z - p.position.z);
    const len = clamp(v.length(), def.minRange, def.range);
    data.dir = v.lengthSq() > 0.01 ? v.normalize() : forward(p, new THREE.Vector3());
    data.dist = len;
    data.target = p.position.clone().addScaledVector(data.dir, len);
    data.lockFacing = true;
    p.facing = Math.atan2(data.dir.x, data.dir.z);
    p.game.effects.telegraph(data.target, def.explosionRadius, {
      color: def.color, life: def.windup + len / def.projectileSpeed,
    });
  },

  phase(p, def, data, name) {
    if (name !== 'active') return;
    const g = p.game;
    _pos.copy(p.position).addScaledVector(data.dir, 0.6);
    g.projectiles.push(new Projectile(g, {
      owner: p, position: _pos, direction: data.dir, speed: def.projectileSpeed, range: data.dist - 0.6,
      radius: def.projectileRadius, damage: 0, color: def.color,
      explosion: {
        radius: def.explosionRadius, damage: def.damage, knockback: def.knockback,
        hitStop: def.hitStop, shake: def.shake,
      },
    }));
  },

  update(p, def, data, name, k) {
    const m = p.model;
    const idle = p.weapon.idle;
    if (name === 'windup') {
      const e = easeOutCubic(k);
      m.armR.rotation.x = lerp(idle.armR, -2.7, e);
      m.armL.rotation.x = lerp(0, -1.2, e);
      p.weaponTilt = lerp(0, -0.3, e);
      // 蓄力：魔力粒子往杖頭聚集
      _pos.copy(p.position).addScaledVector(data.dir, 0.3);
      p.game.effects.mote(
        { x: _pos.x + randRange(-0.8, 0.8), z: _pos.z + randRange(-0.8, 0.8) },
        { color: def.color, size: 0.12, life: 0.3, y: randRange(1.6, 2.8), vy: 0.8 },
      );
      return;
    }
    const e = name === 'active' ? 0 : easeOutCubic(k);
    m.armR.rotation.x = lerp(-1.6, idle.armR, e);
    m.armL.rotation.x = lerp(-0.6, 0, e);
    p.weaponTilt = lerp(1.2, 0, e);
  },
};

export const WEAPON_BEHAVIORS = { meleeSwing, shieldBash, fireBolt, arcaneBurst };
