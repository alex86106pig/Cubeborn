// 實體基底：位置、速度、半徑、血量、擊退、受傷/死亡流程與模型同步
import * as THREE from 'three';
import { COMBAT, DEBUG } from '../core/config.js';

const DEBUG_RING_GEO = new THREE.RingGeometry(0.92, 1, 32).rotateX(-Math.PI / 2);
const DEBUG_RING_MAT = new THREE.MeshBasicMaterial({ color: 0xffee00, transparent: true, opacity: 0.8, depthWrite: false });

let nextId = 1;

export class Entity {
  constructor(game, { radius, maxHp, mass = 1, team }) {
    this.game = game;
    this.id = nextId++;
    this.team = team;
    this.radius = radius;
    this.mass = mass;
    this.maxHp = maxHp;
    this.hp = maxHp;
    this.position = new THREE.Vector3();
    this.velocity = new THREE.Vector3();   // 本步主動移動速度，由各實體 update 設定
    this.knockback = new THREE.Vector3();  // 被動位移速度，指數衰減
    this.facing = 0;
    this.damageTakenMul = 1;
    this.knockbackMul = 1;
    this.invulnTimer = 0;
    this.flashTimer = 0;
    this.isDead = false;
    this.isRemoved = false;
    this.model = null;
  }

  attachModel(model) {
    this.model = model;
    this.debugRing = new THREE.Mesh(DEBUG_RING_GEO, DEBUG_RING_MAT);
    this.debugRing.scale.setScalar(this.radius);
    this.debugRing.position.y = 0.03;
    model.root.add(this.debugRing);
    this.game.renderer.scene.add(model.root);
  }

  get canBeHit() {
    return !this.isDead && this.invulnTimer <= 0;
  }

  // dir 為已正規化的 XZ 方向；回傳 { amount } 或 null（未命中）
  takeDamage(amount, dir, knockback, source) {
    if (!this.canBeHit) return null;
    const dealt = Math.max(0, Math.round(amount * this.damageTakenMul));
    this.hp = Math.max(0, this.hp - dealt);
    this.flashTimer = COMBAT.flashTime;
    this.knockback.addScaledVector(dir, (knockback * this.knockbackMul) / this.mass);
    this.onDamaged(dealt, source);
    if (this.hp <= 0) this.die(source);
    return { amount: dealt };
  }

  heal(amount) {
    if (this.isDead) return 0;
    const before = this.hp;
    this.hp = Math.min(this.maxHp, this.hp + amount);
    return this.hp - before;
  }

  die(source) {
    if (this.isDead) return;
    this.isDead = true;
    this.velocity.set(0, 0, 0);
    this.game.events.emit('entity:died', { entity: this, source });
    this.onDied(source);
  }

  onDamaged() {}
  onDied() {}

  integrate(dt) {
    this.position.x += (this.velocity.x + this.knockback.x) * dt;
    this.position.z += (this.velocity.z + this.knockback.z) * dt;
    this.knockback.multiplyScalar(Math.exp(-COMBAT.knockbackDamping * dt));
    this.invulnTimer = Math.max(0, this.invulnTimer - dt);
    this.flashTimer = Math.max(0, this.flashTimer - dt);
  }

  syncModel() {
    if (!this.model) return;
    const root = this.model.root;
    root.position.x = this.position.x;
    root.position.z = this.position.z;
    root.rotation.y = this.facing;
    this.model.setFlash(this.flashTimer > 0 ? 0.9 * (this.flashTimer / COMBAT.flashTime) : 0);
    this.debugRing.visible = DEBUG.showHitboxes;
  }

  remove() {
    if (this.isRemoved) return;
    this.isRemoved = true;
    if (this.model) {
      this.game.renderer.scene.remove(this.model.root);
      this.model.dispose();
    }
  }
}
