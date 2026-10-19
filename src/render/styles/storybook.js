// 造型 A「童話繪本」：Q 版大頭、卡通著色（Toon）、明亮草原
// 騎士：圓盔紅羽；敵人：哥布林、哥布林弓手、哥布林王
import * as THREE from 'three';
import { createGround, perimeterPoints, scatterInside, scatterOutside } from '../environment.js';
import { G, PartKit, createHumanoidRig, toonMaterialFactory } from '../rig.js';

const makeMaterial = toonMaterialFactory();

const C = {
  skin: 0xf6cfa8, cheek: 0xf59a9a, eye: 0x2a1e1a, steel: 0xd7dee8, gold: 0xf2c14e,
  tabard: 0x3d6fd6, plume: 0xe2434b, leather: 0x8a5a32, pants: 0x4a4a5a,
  goblin: 0x7cbf4a, goblinDark: 0x5c9a36, goblinEye: 0xffe14a, cloth: 0x7a5230, hood: 0x3f6b2f,
};

// ───────── 角色 ─────────

function knight() {
  const rig = createHumanoidRig(makeMaterial, {
    neck: 1.05, shoulderY: 0.98, shoulderX: 0.33, armLen: 0.45, hipY: 0.5, hipX: 0.13, height: 1.95,
  });
  const m = (c, o) => rig.mat(c, o);

  rig.add(rig.body, G.cyl(0.25, 0.3, 0.5, 10), m(C.tabard), { y: 0.78 });
  rig.add(rig.body, G.cyl(0.31, 0.31, 0.07, 10), m(C.leather), { y: 0.58 });
  rig.add(rig.body, G.ico(0.07), m(C.gold), { y: 0.84, z: 0.27 });

  rig.add(rig.head, G.sphere(0.33, 12, 10), m(C.skin), { y: 0.32 });
  rig.add(rig.head, G.dome(0.37, 12, 6), m(C.steel), { y: 0.36 });
  rig.add(rig.head, G.torus(0.365, 0.035, 5, 16), m(C.steel), { y: 0.36, rx: Math.PI / 2 });
  rig.add(rig.head, G.capsule(0.07, 0.25, 3, 6), m(C.plume), { y: 0.8, z: -0.1, rx: -0.5 });
  for (const s of [-1, 1]) {
    rig.add(rig.head, G.sphere(0.045, 6, 5), m(C.eye), { x: s * 0.12, y: 0.32, z: 0.3 });
    rig.add(rig.head, G.sphere(0.05, 6, 5), m(C.cheek), { x: s * 0.2, y: 0.23, z: 0.25, sz: 0.5 });
  }

  for (const arm of [rig.armR, rig.armL]) {
    rig.add(arm, G.sphere(0.14, 8, 6), m(C.steel), { y: 0 });
    rig.add(arm, G.capsule(0.09, 0.22, 3, 8), m(C.steel), { y: -0.2 });
    rig.add(arm, G.sphere(0.1, 8, 6), m(C.leather), { y: -0.42 });
  }
  for (const leg of [rig.legR, rig.legL]) {
    rig.add(leg, G.capsule(0.1, 0.2, 3, 8), m(C.pants), { y: -0.2 });
    rig.add(leg, G.sphere(0.13, 8, 6), m(C.leather), { y: -0.42, z: 0.03, sy: 0.7, sz: 1.25 });
  }
  return rig;
}

function goblinBase(rig, { hood = false } = {}) {
  const m = (c, o) => rig.mat(c, o);
  rig.add(rig.body, G.capsule(0.22, 0.18, 3, 10), m(C.goblin), { y: 0.62 });
  rig.add(rig.body, G.cyl(0.24, 0.29, 0.18, 10), m(C.cloth), { y: 0.42 });

  rig.add(rig.head, G.sphere(0.3, 12, 10), m(C.goblin), { y: 0.25, sy: 0.9 });
  rig.add(rig.head, G.cone(0.08, 0.42, 6), m(C.goblin), { x: 0.32, y: 0.3, rz: -Math.PI / 2 + 0.3 });
  rig.add(rig.head, G.cone(0.08, 0.42, 6), m(C.goblin), { x: -0.32, y: 0.3, rz: Math.PI / 2 - 0.3 });
  rig.add(rig.head, G.cone(0.07, 0.2, 6), m(C.goblinDark), { y: 0.2, z: 0.33, rx: Math.PI / 2 });
  rig.add(rig.head, G.box(0.16, 0.03, 0.02), m(C.eye), { y: 0.08, z: 0.27 });
  for (const s of [-1, 1]) {
    rig.add(rig.head, G.sphere(0.065, 6, 5), m(C.goblinEye, { glow: true }), { x: s * 0.12, y: 0.3, z: 0.24 });
    rig.add(rig.head, G.sphere(0.03, 5, 4), m(C.eye), { x: s * 0.12, y: 0.3, z: 0.3 });
  }
  if (hood) {
    rig.add(rig.head, G.cone(0.36, 0.5, 8), m(C.hood), { y: 0.55, z: -0.03 });
    rig.add(rig.head, G.dome(0.33, 10, 5), m(C.hood), { y: 0.3, z: -0.05, rx: -0.4 });
  }

  for (const arm of [rig.armR, rig.armL]) {
    rig.add(arm, G.capsule(0.07, 0.25, 3, 6), m(C.goblin), { y: -0.18 });
    rig.add(arm, G.sphere(0.085, 6, 5), m(C.goblinDark), { y: -0.4 });
  }
  for (const leg of [rig.legR, rig.legL]) {
    rig.add(leg, G.capsule(0.08, 0.14, 3, 6), m(C.goblin), { y: -0.15 });
    rig.add(leg, G.sphere(0.1, 6, 5), m(C.cloth), { y: -0.32, z: 0.04, sy: 0.6, sz: 1.3 });
  }
}

function club(rig, parent, scale = 1) {
  const g = new THREE.Group();
  rig.add(g, G.cyl(0.1, 0.04, 0.65, 7), rig.mat(C.leather), { y: 0.3 });
  for (let i = 0; i < 4; i++) {
    const a = (i / 4) * Math.PI * 2;
    rig.add(g, G.cone(0.035, 0.12, 4), rig.mat(C.steel),
      { x: Math.cos(a) * 0.09, y: 0.5, z: Math.sin(a) * 0.09, rz: -Math.cos(a) * 1.4, rx: Math.sin(a) * 1.4 });
  }
  g.rotation.x = 2.6;
  g.scale.setScalar(scale);
  parent.add(g);
}

function bow(kit, parent, color) {
  const r = 0.38;
  const g = new THREE.Group();
  g.rotation.y = Math.PI / 2;
  g.position.y = r * 0.85;
  kit.add(g, G.torus(r, 0.028, 4, 10, Math.PI), kit.mat(color), { rx: Math.PI });
  kit.add(g, G.cyl(0.006, 0.006, r * 2, 3), kit.mat(0xeeeeee), { rx: Math.PI / 2 });
  parent.add(g);
}

function goblin() {
  const rig = createHumanoidRig(makeMaterial, {
    neck: 0.82, shoulderY: 0.78, shoulderX: 0.27, armLen: 0.42, hipY: 0.38, hipX: 0.12, height: 1.5,
  });
  goblinBase(rig);
  club(rig, rig.handR);
  return rig;
}

function goblinArcher() {
  const rig = createHumanoidRig(makeMaterial, {
    neck: 0.82, shoulderY: 0.78, shoulderX: 0.27, armLen: 0.42, hipY: 0.38, hipX: 0.12, height: 1.6,
  });
  goblinBase(rig, { hood: true });
  bow(rig, rig.handL, C.leather);
  rig.add(rig.body, G.cyl(0.08, 0.08, 0.45, 6), rig.mat(C.cloth), { y: 0.7, z: -0.24, rx: 0.3 });
  return rig;
}

function goblinKing() {
  const rig = createHumanoidRig(makeMaterial, {
    neck: 0.82, shoulderY: 0.78, shoulderX: 0.3, armLen: 0.42, hipY: 0.38, hipX: 0.13, height: 1.65, scale: 2.1,
  });
  goblinBase(rig);
  const m = (c, o) => rig.mat(c, o);
  rig.add(rig.body, G.sphere(0.3, 10, 8), m(C.goblinDark), { y: 0.55, z: 0.1 });
  rig.add(rig.body, G.box(0.62, 0.7, 0.04), m(C.plume), { y: 0.55, z: -0.26, rx: 0.12 });
  rig.add(rig.head, G.cyl(0.2, 0.2, 0.12, 10, true), m(C.gold), { y: 0.55 });
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * Math.PI * 2;
    rig.add(rig.head, G.cone(0.04, 0.12, 4), m(C.gold), { x: Math.cos(a) * 0.18, y: 0.66, z: Math.sin(a) * 0.18 });
  }
  club(rig, rig.handR, 1.5);
  return rig;
}

// ───────── 玩家武器 ─────────

function swordShield() {
  const kit = new PartKit(makeMaterial);
  const sword = new THREE.Group();
  kit.add(sword, G.cyl(0.035, 0.035, 0.2, 6), kit.mat(C.leather));
  kit.add(sword, G.sphere(0.05, 6, 5), kit.mat(C.gold), { y: -0.12 });
  kit.add(sword, G.box(0.3, 0.06, 0.08), kit.mat(C.gold), { y: 0.12 });
  kit.add(sword, G.cyl(0.02, 0.065, 0.75, 4), kit.mat(0xeef3f8), { y: 0.52, sz: 0.45 });
  sword.rotation.x = 2.8;

  const shield = new THREE.Group();
  kit.add(shield, G.cyl(0.3, 0.3, 0.07, 12), kit.mat(C.plume), { rz: Math.PI / 2 });
  kit.add(shield, G.torus(0.3, 0.035, 4, 16), kit.mat(C.steel), { ry: Math.PI / 2 });
  kit.add(shield, G.ico(0.08), kit.mat(C.gold), { x: 0.05 });
  shield.position.set(0.17, -0.3, 0);
  return { kit, main: sword, offhand: shield };
}

function staff() {
  const kit = new PartKit(makeMaterial);
  const g = new THREE.Group();
  kit.add(g, G.cyl(0.035, 0.04, 1.6, 6), kit.mat(C.leather), { y: 0.25 });
  kit.add(g, G.torus(0.12, 0.03, 4, 10), kit.mat(C.gold), { y: 1.12 });
  const gem = kit.add(g, G.ico(0.1), kit.mat(0x9be7ff, { glow: true }), { y: 1.12 });
  return { kit, main: g, offhand: null, gem };
}

// ───────── 投射物 ─────────

function enemyProjectile() {
  const kit = new PartKit(makeMaterial);
  const g = new THREE.Group();
  kit.add(g, G.cyl(0.02, 0.02, 0.6, 4), kit.mat(C.leather), { rx: Math.PI / 2, shadow: false });
  kit.add(g, G.cone(0.05, 0.14, 4), kit.mat(C.steel), { z: 0.36, rx: Math.PI / 2, shadow: false });
  kit.add(g, G.box(0.1, 0.02, 0.12), kit.mat(0xffffff), { z: -0.28, shadow: false });
  return { kit, mesh: g };
}

// ───────── 場地 ─────────

function buildArena(half) {
  const kit = new PartKit(makeMaterial);
  const group = new THREE.Group();
  group.add(createGround(kit, (half + 14) * 2, { colors: [0x5fae45, 0x7cc653, 0x9ad466], cell: 1.6 }));

  const wood = kit.mat(0x9a6a3c);
  const postGeo = G.cyl(0.11, 0.13, 1.1, 6);
  const capGeo = G.cone(0.14, 0.2, 6);
  kit.geometries.push(postGeo, capGeo);
  for (const p of perimeterPoints(half, 2, 0.4)) {
    const post = new THREE.Mesh(postGeo, wood);
    post.position.set(p.x, 0.55, p.z);
    post.castShadow = true;
    const cap = new THREE.Mesh(capGeo, wood);
    cap.position.set(p.x, 1.2, p.z);
    group.add(post, cap);
  }
  const e = half + 0.4;
  for (const y of [0.45, 0.85]) {
    for (const [x, z, ry] of [[0, -e, 0], [0, e, 0], [-e, 0, Math.PI / 2], [e, 0, Math.PI / 2]]) {
      kit.add(group, G.box(e * 2, 0.1, 0.06), wood, { x, y, z, ry });
    }
  }

  const trunk = kit.mat(0x7a5230);
  const leaves = [kit.mat(0x4f9a3a), kit.mat(0x63b047), kit.mat(0x7fc25a)];
  for (const p of scatterOutside(half, 34, 2, 11)) {
    const tree = new THREE.Group();
    tree.position.set(p.x, 0, p.z);
    tree.scale.setScalar(p.s * 1.3);
    kit.add(tree, G.cyl(0.12, 0.16, 0.9, 6), trunk, { y: 0.45 });
    kit.add(tree, G.ico(0.7, 0), leaves[Math.floor(Math.random() * 3)], { y: 1.3 });
    kit.add(tree, G.ico(0.5, 0), leaves[Math.floor(Math.random() * 3)], { y: 1.85, x: 0.15 });
    group.add(tree);
  }
  for (const p of scatterOutside(half, 30, 1.2, 10)) {
    kit.add(group, G.ico(0.35 * p.s, 0), leaves[Math.floor(Math.random() * 3)], { x: p.x, y: 0.2, z: p.z });
  }
  const petals = [0xffffff, 0xffd84a, 0xff8fb1, 0xb48cff].map((c) => kit.mat(c));
  const petalGeo = G.sphere(0.07, 5, 4);
  kit.geometries.push(petalGeo);
  for (const p of scatterInside(half, 50)) {
    const flower = new THREE.Mesh(petalGeo, petals[Math.floor(Math.random() * petals.length)]);
    flower.position.set(p.x, 0.08, p.z);
    group.add(flower);
  }
  return { kit, group };
}

export const storybook = {
  id: 'storybook',
  name: 'A 童話繪本',
  names: { knight: '見習騎士', melee: '哥布林', ranged: '哥布林弓手', boss: '哥布林王' },
  environment: {
    background: 0x9fd4f0,
    hemiSky: 0xffffff, hemiGround: 0x7a6a4a, hemiIntensity: 1.3,
    sunColor: 0xfff1d6, sunIntensity: 1.7,
  },
  colors: { blood: 0x7cbf4a, bossBlood: 0x5c9a36, enemyProjectile: 0xd9c49a, hitSpark: 0xffffff },
  characters: { knight, melee: goblin, ranged: goblinArcher, boss: goblinKing },
  weapons: { swordShield, staff },
  enemyProjectile,
  buildArena,
};
