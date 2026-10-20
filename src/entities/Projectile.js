// 投射物：直線飛行，命中或飛到最大距離時結束；設定 explosion 時結束會造成範圍爆炸
import * as THREE from 'three';
import { WORLD } from '../core/config.js';

const SPHERE = new THREE.IcosahedronGeometry(1, 1);
const _targets = [];
const _origin = new THREE.Vector3();

export class Projectile {
  constructor(game, {
    owner, position, direction, speed, range, radius = 0.25, height = 1.25,
    damage, knockback = 0, color = 0xffffff, hitStop = 0, shake = 0, explosion = null,
    model = null, // 選用：{ kit, mesh } 自訂外觀（沿 +Z 建模），未提供時使用發光球體
  }) {
    this.game = game;
    this.owner = owner;
    this.position = position.clone().setY(0);
    this.direction = direction.clone().setY(0).normalize();
    this.speed = speed;
    this.range = range;
    this.radius = radius;
    this.height = height;
    this.damage = damage;
    this.knockback = knockback;
    this.color = color;
    this.hitStop = hitStop;
    this.shake = shake;
    this.explosion = explosion; // { radius, damage, knockback, hitStop, shake }
    this.traveled = 0;
    this.isRemoved = false;
    this.age = 0;

    if (model) {
      this.kit = model.kit;
      this.mesh = model.mesh;
      this.mesh.rotation.y = Math.atan2(this.direction.x, this.direction.z);
      this.spins = false;
    } else {
      this.kit = null;
      this.mesh = new THREE.Mesh(SPHERE, new THREE.MeshBasicMaterial({ color }));
      this.mesh.scale.setScalar(radius);
      this.spins = true;
    }
    this.#syncMesh();
    game.renderer.scene.add(this.mesh);
  }

  update(dt) {
    if (this.isRemoved) return;
    const step = this.speed * dt;
    this.position.addScaledVector(this.direction, step);
    this.traveled += step;
    this.age += dt;

    const g = this.game;
    g.effects.mote(this.position, { color: this.color, size: this.radius * 0.6, life: 0.25, y: this.height });

    for (const target of g.combat.hostilesOf(this.owner, _targets)) {
      const r = this.radius + target.radius;
      const dx = target.position.x - this.position.x;
      const dz = target.position.z - this.position.z;
      if (dx * dx + dz * dz <= r * r) {
        this.#onHit(target);
        return;
      }
    }

    const half = WORLD.arenaHalfSize;
    const outside = Math.abs(this.position.x) > half || Math.abs(this.position.z) > half;
    if (this.traveled >= this.range || outside) {
      this.#expire();
      return;
    }
    this.#syncMesh();
  }

  #syncMesh() {
    this.mesh.position.set(this.position.x, this.height, this.position.z);
    if (this.spins) this.mesh.rotation.y += 0.3;
  }

  #onHit(target) {
    if (this.explosion) {
      this.#explode();
    } else {
      // 擊退方向沿飛行方向
      _origin.copy(this.position).addScaledVector(this.direction, -1);
      this.game.combat.applyDamage(this.owner, target, {
        damage: this.damage, knockback: this.knockback, origin: _origin,
        hitStop: this.hitStop, shake: this.shake, color: this.color,
      });
    }
    this.remove();
  }

  #expire() {
    if (this.explosion) this.#explode();
    else this.game.effects.burst(this.position, { color: this.color, count: 4, speed: 2, y: this.height, size: 0.1 });
    this.remove();
  }

  #explode() {
    const g = this.game;
    g.events.emit('sfx:cue', { name: 'explosion' });
    const ex = this.explosion;
    const targets = g.combat.queryCircle(this.position, ex.radius, g.combat.hostilesOf(this.owner, _targets), []);
    for (const target of targets) {
      g.combat.applyDamage(this.owner, target, {
        damage: ex.damage, knockback: ex.knockback, origin: this.position,
        hitStop: ex.hitStop, color: this.color, isCrit: true,
      });
    }
    g.effects.ring(this.position, ex.radius, { color: this.color, life: 0.4 });
    g.effects.ring(this.position, ex.radius * 0.6, { color: 0xffffff, life: 0.25 });
    g.effects.burst(this.position, { color: this.color, count: 26, speed: 9, up: 6, size: 0.2, life: 0.6, y: 0.6 });
    g.renderer.shake(ex.shake, 0.3);
  }

  remove() {
    if (this.isRemoved) return;
    this.isRemoved = true;
    this.game.renderer.scene.remove(this.mesh);
    if (this.kit) this.kit.dispose();
    else this.mesh.material.dispose();
  }
}
