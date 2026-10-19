// 傷害結算與命中判定查詢（扇形、圓形），並觸發受擊回饋
import * as THREE from 'three';
import { wrapAngle } from '../core/math.js';

const _dir = new THREE.Vector3();

export class Combat {
  constructor(game) {
    this.game = game;
  }

  // 回傳 owner 的敵對陣營中仍存活的實體
  hostilesOf(owner, out = []) {
    out.length = 0;
    const g = this.game;
    if (owner.team === 'player') {
      for (const e of g.enemies) if (!e.isDead) out.push(e);
    } else if (g.player && !g.player.isDead) {
      out.push(g.player);
    }
    return out;
  }

  /**
   * 對 target 造成傷害。擊退方向為 origin → target。
   * @returns {boolean} 是否實際命中
   */
  applyDamage(source, target, {
    damage, knockback = 0, origin = source.position, hitStop = 0, shake = 0,
    color = 0xffffff, isCrit = false,
  }) {
    if (!target?.canBeHit) return false;
    _dir.set(target.position.x - origin.x, 0, target.position.z - origin.z);
    if (_dir.lengthSq() < 1e-6) _dir.set(Math.sin(source.facing), 0, Math.cos(source.facing));
    _dir.normalize();

    const result = target.takeDamage(damage, _dir, knockback, source);
    if (!result) return false;

    const g = this.game;
    g.events.emit('entity:damaged', { target, amount: result.amount, source, knockback, isCrit });
    g.effects.burst(target.position, { color, count: isCrit ? 12 : 6, speed: isCrit ? 6 : 4, y: 1.1 });
    if (hitStop > 0) g.hitStop(hitStop);
    if (shake > 0) g.renderer.shake(shake, 0.15);
    return true;
  }

  // 扇形判定：考慮目標半徑，貼身目標一律命中
  querySector(origin, facing, range, arc, candidates, out = []) {
    out.length = 0;
    for (const c of candidates) {
      const dx = c.position.x - origin.x;
      const dz = c.position.z - origin.z;
      const dist = Math.hypot(dx, dz);
      if (dist > range + c.radius) continue;
      if (dist <= c.radius + 0.3) { out.push(c); continue; }
      const diff = Math.abs(wrapAngle(Math.atan2(dx, dz) - facing));
      const allowance = arc / 2 + Math.asin(Math.min(1, c.radius / dist));
      if (diff <= allowance) out.push(c);
    }
    return out;
  }

  queryCircle(center, radius, candidates, out = []) {
    out.length = 0;
    for (const c of candidates) {
      const r = radius + c.radius;
      const dx = c.position.x - center.x;
      const dz = c.position.z - center.z;
      if (dx * dx + dz * dz <= r * r) out.push(c);
    }
    return out;
  }
}
