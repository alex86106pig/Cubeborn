// 視覺特效：方塊粒子、揮砍弧光、衝擊環（命中停頓與震動由 Game / Renderer 提供）
import * as THREE from 'three';
import { randRange } from '../core/math.js';

const PARTICLE_GEO = new THREE.BoxGeometry(1, 1, 1);
const RING_GEO = new THREE.RingGeometry(0.85, 1, 48).rotateX(-Math.PI / 2);
const MAX_PARTICLES = 600;

export class Effects {
  #particleMaterials = new Map();
  #slashGeometries = new Map();
  #particles = [];
  #free = [];
  #transients = [];

  constructor(game) {
    this.scene = game.renderer.scene;
  }

  #particleMaterial(color) {
    if (!this.#particleMaterials.has(color)) {
      this.#particleMaterials.set(color, new THREE.MeshBasicMaterial({ color }));
    }
    return this.#particleMaterials.get(color);
  }

  // 方塊粒子爆發
  burst(position, { color = 0xffffff, count = 8, speed = 4, size = 0.14, life = 0.45, gravity = 14, up = 3, y = 1 } = {}) {
    for (let i = 0; i < count; i++) {
      if (this.#particles.length >= MAX_PARTICLES) return;
      const mesh = this.#free.pop() ?? new THREE.Mesh(PARTICLE_GEO, null);
      mesh.material = this.#particleMaterial(color);
      mesh.position.set(position.x, y, position.z);
      mesh.rotation.set(Math.random() * 3, Math.random() * 3, 0);
      const angle = Math.random() * Math.PI * 2;
      const s = speed * randRange(0.4, 1);
      const maxLife = life * randRange(0.6, 1.2);
      this.#particles.push({
        mesh,
        vx: Math.sin(angle) * s,
        vy: up * randRange(0.5, 1.2),
        vz: Math.cos(angle) * s,
        gravity,
        size: size * randRange(0.7, 1.3),
        life: maxLife,
        maxLife,
      });
      this.scene.add(mesh);
    }
  }

  // 單顆漂浮粒子（拖尾、蓄力）
  mote(position, { color = 0xffffff, size = 0.1, life = 0.3, y = position.y, vy = 0.5 } = {}) {
    this.burst({ x: position.x, z: position.z }, { color, count: 1, speed: 0.3, size, life, gravity: -vy * 2, up: vy, y });
  }

  // 近戰弧光：扇形面片，朝 facing 展開
  slash(position, facing, range, arc, { color = 0xffffff, life = 0.16, y = 1, swingDir = 1 } = {}) {
    const key = `${range.toFixed(2)}|${arc.toFixed(2)}`;
    if (!this.#slashGeometries.has(key)) {
      this.#slashGeometries.set(key,
        new THREE.RingGeometry(range * 0.35, range, 24, 1, -Math.PI / 2 - arc / 2, arc).rotateX(-Math.PI / 2));
    }
    const material = new THREE.MeshBasicMaterial({
      color, transparent: true, opacity: 0.75, side: THREE.DoubleSide, depthWrite: false,
    });
    const mesh = new THREE.Mesh(this.#slashGeometries.get(key), material);
    mesh.position.set(position.x, y, position.z);
    mesh.rotation.y = facing;
    mesh.scale.x = swingDir;
    this.#addTransient(mesh, life, (k) => {
      material.opacity = 0.75 * (1 - k);
      mesh.scale.z = 0.85 + 0.15 * k;
    });
  }

  // 衝擊環：由小擴張到 radius 並淡出
  ring(position, radius, { color = 0xffffff, life = 0.35, y = 0.05, opacity = 0.8 } = {}) {
    const material = new THREE.MeshBasicMaterial({ color, transparent: true, opacity, depthWrite: false });
    const mesh = new THREE.Mesh(RING_GEO, material);
    mesh.position.set(position.x, y, position.z);
    this.#addTransient(mesh, life, (k) => {
      const s = radius * (0.25 + 0.75 * Math.sqrt(k));
      mesh.scale.set(s, 1, s);
      material.opacity = opacity * (1 - k);
    });
  }

  // 預警圈：固定大小、閃爍，用於範圍技落點
  telegraph(position, radius, { color = 0xffffff, life = 0.4 } = {}) {
    const material = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.5, depthWrite: false });
    const mesh = new THREE.Mesh(RING_GEO, material);
    mesh.position.set(position.x, 0.05, position.z);
    mesh.scale.set(radius, 1, radius);
    this.#addTransient(mesh, life, (k) => {
      material.opacity = 0.35 + 0.35 * Math.sin(k * Math.PI * 6) ** 2;
    });
  }

  #addTransient(mesh, life, update) {
    this.scene.add(mesh);
    update(0);
    this.#transients.push({ mesh, life, maxLife: life, update });
  }

  update(dt) {
    for (let i = this.#particles.length - 1; i >= 0; i--) {
      const p = this.#particles[i];
      p.life -= dt;
      if (p.life <= 0) {
        this.scene.remove(p.mesh);
        this.#free.push(p.mesh);
        this.#particles.splice(i, 1);
        continue;
      }
      p.vy -= p.gravity * dt;
      const m = p.mesh;
      m.position.x += p.vx * dt;
      m.position.y = Math.max(0.05, m.position.y + p.vy * dt);
      m.position.z += p.vz * dt;
      m.rotation.x += dt * 6;
      m.scale.setScalar(p.size * (p.life / p.maxLife));
    }

    for (let i = this.#transients.length - 1; i >= 0; i--) {
      const t = this.#transients[i];
      t.life -= dt;
      if (t.life <= 0) {
        this.#removeTransient(t);
        this.#transients.splice(i, 1);
        continue;
      }
      t.update(1 - t.life / t.maxLife);
    }
  }

  #removeTransient(t) {
    this.scene.remove(t.mesh);
    t.mesh.material.dispose();
  }

  clear() {
    for (const p of this.#particles) {
      this.scene.remove(p.mesh);
      this.#free.push(p.mesh);
    }
    this.#particles.length = 0;
    for (const t of this.#transients) this.#removeTransient(t);
    this.#transients.length = 0;
  }
}
