// 造型 B「暗黑幻想」：寫實比例、硬朗多面體（flat shading）、月夜墓地
// 騎士：黑鋼重甲；敵人：骷髏戰士、骷髏弓手、亡骸騎士
import * as THREE from 'three';
import { createGround, perimeterPoints, scatterInside, scatterOutside } from '../environment.js';
import { G, PartKit, createHumanoidRig, flatLambertFactory } from '../rig.js';

const makeMaterial = flatLambertFactory();

const C = {
  steel: 0x8a93a3, steelDark: 0x4a505c, iron: 0x2a2d33, cape: 0x6b1d24, leather: 0x3b2a20,
  bone: 0xd8d2bf, boneDark: 0xa39d88, socket: 0x1a1612, eyeRed: 0xff3b2f, hood: 0x2c2a35,
  rust: 0x8a6a4a, deathArmor: 0x23262e, deathEye: 0x55e0ff, wood: 0x4a3526,
};

const KNIGHT_JOINTS = { neck: 1.6, shoulderY: 1.55, shoulderX: 0.36, armLen: 0.7, hipY: 0.95, hipX: 0.14, height: 2.1 };

// ───────── 角色 ─────────

function armoredBody(rig, { armor, trim, cape, eye = null, horns = false }) {
  const m = (c, o) => rig.mat(c, o);
  rig.add(rig.body, G.cyl(0.3, 0.24, 0.62, 6), m(armor, { metal: true }), { y: 1.28 });
  rig.add(rig.body, G.cyl(0.25, 0.3, 0.26, 6), m(trim), { y: 0.9 });
  rig.add(rig.body, G.box(0.56, 0.95, 0.04), m(cape), { y: 1.05, z: -0.22, rx: 0.08 });
  rig.add(rig.body, G.box(0.28, 0.5, 0.02), m(cape), { y: 0.98, z: 0.2 });

  rig.add(rig.head, G.cyl(0.19, 0.21, 0.38, 7), m(armor, { metal: true }), { y: 0.2 });
  rig.add(rig.head, G.box(0.3, 0.035, 0.03), eye ? m(eye, { glow: true }) : m(C.socket), { y: 0.24, z: 0.19 });
  rig.add(rig.head, G.box(0.035, 0.12, 0.42), m(trim), { y: 0.42 });
  if (horns) {
    for (const s of [-1, 1]) {
      rig.add(rig.head, G.cone(0.06, 0.4, 5), m(C.boneDark), { x: s * 0.24, y: 0.42, rz: -s * 0.9 });
    }
  }

  for (const [arm, s] of [[rig.armR, -1], [rig.armL, 1]]) {
    rig.add(arm, G.ico(0.17, 0), m(armor, { metal: true }), { x: s * 0.04, y: 0.02, sy: 0.8 });
    rig.add(arm, G.cyl(0.085, 0.075, 0.4, 6), m(armor, { metal: true }), { y: -0.22 });
    rig.add(arm, G.box(0.14, 0.17, 0.14), m(trim), { y: -0.58 });
  }
  for (const leg of [rig.legR, rig.legL]) {
    rig.add(leg, G.cyl(0.1, 0.09, 0.45, 6), m(trim), { y: -0.22 });
    rig.add(leg, G.cyl(0.095, 0.11, 0.42, 6), m(armor, { metal: true }), { y: -0.64 });
    rig.add(leg, G.box(0.16, 0.12, 0.27), m(C.iron), { y: -0.9, z: 0.04 });
  }
}

function longSword(kit, parent, { blade, guard, length = 1, glow = null }) {
  const g = new THREE.Group();
  kit.add(g, G.cyl(0.03, 0.03, 0.25, 5), kit.mat(C.leather));
  kit.add(g, G.ico(0.05), kit.mat(guard), { y: -0.15 });
  kit.add(g, G.box(0.36, 0.05, 0.07), kit.mat(guard), { y: 0.14 });
  kit.add(g, G.cyl(0.018, 0.055, length, 4), glow ? kit.mat(glow, { glow: true }) : kit.mat(blade, { metal: true }),
    { y: 0.16 + length / 2, sz: 0.35 });
  g.rotation.x = 2.8;
  parent.add(g);
  return g;
}

function bow(kit, parent, color) {
  const r = 0.45;
  const g = new THREE.Group();
  g.rotation.y = Math.PI / 2;
  g.position.y = r * 0.85;
  kit.add(g, G.torus(r, 0.025, 4, 9, Math.PI), kit.mat(color), { rx: Math.PI });
  kit.add(g, G.cyl(0.005, 0.005, r * 2, 3), kit.mat(0xcccccc), { rx: Math.PI / 2 });
  parent.add(g);
}

function knight() {
  const rig = createHumanoidRig(makeMaterial, KNIGHT_JOINTS);
  armoredBody(rig, { armor: C.steel, trim: C.steelDark, cape: C.cape });
  return rig.optimize();
}

function skeletonBase(rig, { hood = false } = {}) {
  const m = (c, o) => rig.mat(c, o);
  const bone = m(C.bone);
  rig.add(rig.body, G.cyl(0.04, 0.04, 0.55, 5), bone, { y: 1.15 });
  for (let i = 0; i < 3; i++) {
    rig.add(rig.body, G.torus(0.19 - i * 0.02, 0.025, 4, 8), bone, { y: 1.38 - i * 0.1, rx: Math.PI / 2, sy: 0.7 });
  }
  rig.add(rig.body, G.cyl(0.03, 0.03, 0.62, 4), bone, { y: 1.47, rz: Math.PI / 2 });
  rig.add(rig.body, G.box(0.3, 0.1, 0.15), bone, { y: 0.92 });
  rig.add(rig.body, G.box(0.3, 0.32, 0.02), m(C.hood), { y: 0.78, z: 0.09 });

  rig.add(rig.head, G.ico(0.18, 1), bone, { y: 0.2, sy: 1.1 });
  rig.add(rig.head, G.box(0.17, 0.07, 0.14), m(C.boneDark), { y: 0.03, z: 0.04 });
  for (const s of [-1, 1]) {
    rig.add(rig.head, G.sphere(0.05, 5, 4), m(C.socket), { x: s * 0.07, y: 0.22, z: 0.14 });
    rig.add(rig.head, G.sphere(0.025, 4, 3), m(C.eyeRed, { glow: true }), { x: s * 0.07, y: 0.22, z: 0.17, shadow: false });
  }
  if (hood) {
    rig.add(rig.head, G.dome(0.24, 7, 4), m(C.hood), { y: 0.22, z: -0.03, rx: -0.3 });
    rig.add(rig.body, G.box(0.5, 0.9, 0.03), m(C.hood), { y: 1.0, z: -0.16, rx: 0.06 });
  }

  for (const arm of [rig.armR, rig.armL]) {
    rig.add(arm, G.cyl(0.03, 0.03, 0.3, 4), bone, { y: -0.17 });
    rig.add(arm, G.sphere(0.04, 5, 4), bone, { y: -0.33 });
    rig.add(arm, G.cyl(0.028, 0.025, 0.28, 4), bone, { y: -0.48 });
    rig.add(arm, G.box(0.07, 0.1, 0.04), bone, { y: -0.65 });
  }
  for (const leg of [rig.legR, rig.legL]) {
    rig.add(leg, G.cyl(0.035, 0.03, 0.42, 4), bone, { y: -0.22 });
    rig.add(leg, G.sphere(0.045, 5, 4), bone, { y: -0.45 });
    rig.add(leg, G.cyl(0.03, 0.028, 0.4, 4), bone, { y: -0.67 });
    rig.add(leg, G.box(0.08, 0.05, 0.18), bone, { y: -0.9, z: 0.04 });
  }
}

const SKELETON_JOINTS = { neck: 1.5, shoulderY: 1.45, shoulderX: 0.3, armLen: 0.68, hipY: 0.92, hipX: 0.12, height: 1.95 };

function skeleton() {
  const rig = createHumanoidRig(makeMaterial, SKELETON_JOINTS);
  skeletonBase(rig);
  longSword(rig, rig.handR, { blade: C.rust, guard: C.iron, length: 0.8 });
  return rig.optimize();
}

function skeletonArcher() {
  const rig = createHumanoidRig(makeMaterial, SKELETON_JOINTS);
  skeletonBase(rig, { hood: true });
  bow(rig, rig.handL, C.wood);
  return rig.optimize();
}

function deathKnight() {
  const rig = createHumanoidRig(makeMaterial, { ...KNIGHT_JOINTS, scale: 1.85 });
  armoredBody(rig, { armor: C.deathArmor, trim: C.iron, cape: 0x1c1a22, eye: C.deathEye, horns: true });
  longSword(rig, rig.handR, { blade: 0x9aa4b4, guard: C.iron, length: 1.35, glow: 0x7fe8ff });
  return rig.optimize();
}

// ───────── 玩家武器 ─────────

function swordShield() {
  const kit = new PartKit(makeMaterial);
  const holder = new THREE.Group();
  longSword(kit, holder, { blade: 0xb8c0cc, guard: C.steelDark, length: 0.95 });

  const shield = new THREE.Group();
  kit.add(shield, G.box(0.07, 0.42, 0.46), kit.mat(C.cape), { y: 0.1 });
  kit.add(shield, G.cone(0.33, 0.42, 4), kit.mat(C.cape), { y: -0.31, rx: Math.PI, ry: Math.PI / 4, sx: 0.15, sz: 0.98 });
  kit.add(shield, G.box(0.09, 0.44, 0.05), kit.mat(C.steel, { metal: true }), { y: 0.1 });
  kit.add(shield, G.ico(0.07), kit.mat(C.steel, { metal: true }), { x: 0.05, y: 0.1 });
  shield.position.set(0.18, -0.4, 0);
  kit.mergeStatic(holder, [holder]).mergeStatic(shield, [shield]);
  return { kit, main: holder, offhand: shield };
}

function staff() {
  const kit = new PartKit(makeMaterial);
  const g = new THREE.Group();
  kit.add(g, G.cyl(0.03, 0.045, 1.8, 5), kit.mat(C.wood), { y: 0.3 });
  for (const s of [-1, 1]) {
    kit.add(g, G.cone(0.03, 0.3, 4), kit.mat(C.wood), { x: s * 0.08, y: 1.28, rz: -s * 0.4 });
  }
  const gem = kit.add(g, G.ico(0.1), kit.mat(0xb48cff, { glow: true }), { y: 1.3 });
  kit.mergeStatic(g, [g], [gem]);
  return { kit, main: g, offhand: null, gem };
}

// ───────── 投射物 ─────────

function enemyProjectile() {
  const kit = new PartKit(makeMaterial);
  const g = new THREE.Group();
  kit.add(g, G.cyl(0.018, 0.018, 0.7, 4), kit.mat(0x2a2420), { rx: Math.PI / 2, shadow: false });
  kit.add(g, G.cone(0.05, 0.16, 4), kit.mat(0xb48cff, { glow: true }), { z: 0.42, rx: Math.PI / 2, shadow: false });
  return { kit, mesh: g };
}

// ───────── 場地 ─────────

function buildArena(half) {
  const kit = new PartKit(makeMaterial);
  const group = new THREE.Group();
  group.add(createGround(kit, (half + 14) * 2, { colors: [0x2b3528, 0x3a4431, 0x4a4a3a], cell: 1.8, jitter: 0.1 }));

  const rocks = [kit.mat(0x55585e), kit.mat(0x6a6d72), kit.mat(0x46484d)];
  for (const p of perimeterPoints(half, 1.1, 0.6)) {
    const s = 0.45 + Math.random() * 0.45;
    kit.add(group, G.ico(s, 0), rocks[Math.floor(Math.random() * 3)], {
      x: p.x + (Math.random() - 0.5) * 0.4, y: s * 0.5, z: p.z + (Math.random() - 0.5) * 0.4,
      rx: Math.random() * 3, ry: Math.random() * 3, sy: 0.8 + Math.random() * 0.6,
    });
  }

  const stone = kit.mat(0x6b6e75);
  for (const p of scatterOutside(half, 26, 1.8, 9)) {
    const grave = new THREE.Group();
    grave.position.set(p.x, 0, p.z);
    grave.rotation.set((Math.random() - 0.5) * 0.25, p.ry, (Math.random() - 0.5) * 0.2);
    kit.add(grave, G.box(0.5, 0.6, 0.12), stone, { y: 0.3 });
    kit.add(grave, G.cyl(0.25, 0.25, 0.12, 6), stone, { y: 0.6, rx: Math.PI / 2 });
    group.add(grave);
  }
  const bark = kit.mat(0x2e241c);
  for (const p of scatterOutside(half, 16, 3, 11)) {
    const tree = new THREE.Group();
    tree.position.set(p.x, 0, p.z);
    tree.scale.setScalar(p.s * 1.4);
    tree.rotation.y = p.ry;
    kit.add(tree, G.cyl(0.07, 0.15, 2, 5), bark, { y: 1 });
    kit.add(tree, G.cyl(0.03, 0.06, 0.9, 4), bark, { x: 0.25, y: 1.6, rz: -0.8 });
    kit.add(tree, G.cyl(0.03, 0.05, 0.7, 4), bark, { x: -0.2, y: 1.9, rz: 0.9 });
    group.add(tree);
  }
  const boneMat = kit.mat(C.boneDark);
  for (const p of scatterInside(half, 18)) {
    kit.add(group, G.cyl(0.03, 0.03, 0.35, 4), boneMat, { x: p.x, y: 0.03, z: p.z, rz: Math.PI / 2, ry: p.ry, shadow: false });
  }
  kit.mergeStatic(group, [group]);
  return { kit, group };
}

export const darkFantasy = {
  id: 'darkFantasy',
  name: '暗黑幻想',
  names: { knight: '黑鋼騎士', melee: '骷髏戰士', ranged: '骷髏弓手', boss: '亡骸騎士' },
  environment: {
    background: 0x0e1220,
    hemiSky: 0x8a9aba, hemiGround: 0x2a2420, hemiIntensity: 1.2,
    sunColor: 0xb8ceff, sunIntensity: 2.0,
  },
  colors: { blood: 0xd8d2bf, bossBlood: 0x55e0ff, enemyProjectile: 0xb48cff, hitSpark: 0xdfe8ff },
  characters: { knight, melee: skeleton, ranged: skeletonArcher, boss: deathKnight },
  weapons: { swordShield, staff },
  enemyProjectile,
  buildArena,
};
