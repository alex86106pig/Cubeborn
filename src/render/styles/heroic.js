// 造型 C「英雄卡通」：誇張壯碩比例、鮮豔配色、金屬質感（Standard flat）、夕陽競技場
// 騎士：金白聖騎士；敵人：獸人戰士、獸人薩滿、牛頭魔王
import * as THREE from 'three';
import { createGround, perimeterPoints, scatterOutside } from '../environment.js';
import { G, PartKit, createHumanoidRig, flatStandardFactory } from '../rig.js';

const makeMaterial = flatStandardFactory();

const C = {
  skin: 0xf1c08f, armor: 0xf0f0f4, gold: 0xf2b632, cape: 0xc0392b, under: 0x2c3e75, eye: 0x1a1a1a,
  orc: 0x6f8f4e, orcDark: 0x56733b, leather: 0x6b4a2b, iron: 0x5a5f66, tusk: 0xf4ecd8, orcEye: 0xffcc33,
  fur: 0x7a4a2e, furDark: 0x5a341f, horn: 0xe8dcc0, bossEye: 0xff4422, wood: 0x7a5636,
  feather: [0xe74c3c, 0x3498db, 0xf1c40f],
};

// ───────── 角色 ─────────

function knight() {
  const rig = createHumanoidRig(makeMaterial, {
    neck: 1.5, shoulderY: 1.42, shoulderX: 0.44, armLen: 0.62, hipY: 0.7, hipX: 0.16, height: 2.15,
  });
  const m = (c, o) => rig.mat(c, o);
  rig.add(rig.body, G.cyl(0.38, 0.26, 0.62, 7), m(C.armor, { metal: true }), { y: 1.18 });
  rig.add(rig.body, G.cyl(0.27, 0.27, 0.08, 7), m(C.gold, { metal: true }), { y: 0.86 });
  rig.add(rig.body, G.cyl(0.27, 0.34, 0.24, 7), m(C.cape), { y: 0.73 });
  rig.add(rig.body, G.ico(0.09), m(C.gold, { metal: true }), { y: 1.25, z: 0.34 });
  rig.add(rig.body, G.box(0.72, 1.0, 0.04), m(C.cape), { y: 1.0, z: -0.31, rx: 0.1 });

  rig.add(rig.head, G.sphere(0.2, 10, 8), m(C.skin), { y: 0.2 });
  rig.add(rig.head, G.dome(0.235, 10, 5), m(C.armor, { metal: true }), { y: 0.24 });
  rig.add(rig.head, G.box(0.04, 0.14, 0.36), m(C.gold, { metal: true }), { y: 0.47 });
  for (const s of [-1, 1]) {
    rig.add(rig.head, G.box(0.06, 0.18, 0.16), m(C.armor, { metal: true }), { x: s * 0.2, y: 0.14, z: 0.03 });
    rig.add(rig.head, G.sphere(0.03, 5, 4), m(C.eye), { x: s * 0.075, y: 0.22, z: 0.18 });
    rig.add(rig.head, G.box(0.08, 0.02, 0.02), m(0x6b4423), { x: s * 0.075, y: 0.27, z: 0.18, rz: s * 0.15 });
  }

  for (const [arm, s] of [[rig.armR, -1], [rig.armL, 1]]) {
    rig.add(arm, G.dome(0.25, 8, 4), m(C.armor, { metal: true }), { x: s * 0.04, y: 0.02, rz: -s * 0.3 });
    rig.add(arm, G.torus(0.22, 0.03, 4, 10), m(C.gold, { metal: true }), { x: s * 0.04, y: 0.02, rx: Math.PI / 2, rz: -s * 0.3 });
    rig.add(arm, G.cyl(0.1, 0.09, 0.32, 7), m(C.under), { y: -0.2 });
    rig.add(arm, G.cyl(0.11, 0.13, 0.2, 7), m(C.armor, { metal: true }), { y: -0.47 });
    rig.add(arm, G.sphere(0.1, 7, 5), m(C.gold, { metal: true }), { y: -0.62 });
  }
  for (const leg of [rig.legR, rig.legL]) {
    rig.add(leg, G.cyl(0.12, 0.1, 0.35, 7), m(C.under), { y: -0.2 });
    rig.add(leg, G.cyl(0.12, 0.14, 0.24, 7), m(C.armor, { metal: true }), { y: -0.5 });
    rig.add(leg, G.box(0.2, 0.1, 0.28), m(C.gold, { metal: true }), { y: -0.65, z: 0.05 });
  }
  return rig;
}

function orcBase(rig, { lean = false } = {}) {
  const m = (c, o) => rig.mat(c, o);
  const w = lean ? 0.8 : 1;
  rig.add(rig.body, G.cyl(0.42 * w, 0.3 * w, 0.58, 7), m(C.orc), { y: 1.08, rx: 0.15 });
  rig.add(rig.body, G.box(0.1, 0.75, 0.03), m(C.leather), { y: 1.1, z: 0.3 * w, rz: 0.7 });
  rig.add(rig.body, G.cyl(0.3 * w, 0.36 * w, 0.24, 7), m(C.leather), { y: 0.72 });

  rig.add(rig.head, G.ico(0.22, 0), m(C.orc), { y: 0.15, z: 0.08, sx: 1.1 });
  rig.add(rig.head, G.box(0.3, 0.12, 0.2), m(C.orcDark), { y: 0.03, z: 0.15 });
  rig.add(rig.head, G.box(0.3, 0.05, 0.08), m(C.orcDark), { y: 0.25, z: 0.22 });
  for (const s of [-1, 1]) {
    rig.add(rig.head, G.cone(0.03, 0.13, 4), m(C.tusk), { x: s * 0.1, y: 0.12, z: 0.25 });
    rig.add(rig.head, G.sphere(0.03, 5, 4), m(C.orcEye, { glow: true }), { x: s * 0.08, y: 0.2, z: 0.26, shadow: false });
    rig.add(rig.head, G.cone(0.05, 0.18, 4), m(C.orc), { x: s * 0.24, y: 0.18, rz: -s * 1.3 });
  }

  for (const arm of [rig.armR, rig.armL]) {
    rig.add(arm, G.cyl(0.12 * w, 0.1 * w, 0.34, 7), m(C.orc), { y: -0.2 });
    rig.add(arm, G.cyl(0.11 * w, 0.12 * w, 0.26, 7), m(C.leather), { y: -0.48 });
    rig.add(arm, G.sphere(0.12 * w, 7, 5), m(C.orc), { y: -0.65 });
  }
  for (const leg of [rig.legR, rig.legL]) {
    rig.add(leg, G.cyl(0.13 * w, 0.11 * w, 0.32, 7), m(C.leather), { y: -0.17 });
    rig.add(leg, G.box(0.2 * w, 0.12, 0.28), m(C.iron), { y: -0.52, z: 0.05 });
  }
}

const ORC_JOINTS = { neck: 1.38, shoulderY: 1.35, shoulderX: 0.46, armLen: 0.66, hipY: 0.62, hipX: 0.17, height: 1.95 };

function axe(kit, parent, scale = 1) {
  const g = new THREE.Group();
  kit.add(g, G.cyl(0.03, 0.035, 0.85, 5), kit.mat(C.wood), { y: 0.3 });
  kit.add(g, G.box(0.05, 0.32, 0.3), kit.mat(C.iron, { metal: true }), { y: 0.62, z: 0.14 });
  g.rotation.x = 2.6;
  g.scale.setScalar(scale);
  parent.add(g);
}

function orc() {
  const rig = createHumanoidRig(makeMaterial, ORC_JOINTS);
  orcBase(rig);
  rig.add(rig.armL, G.dome(0.2, 7, 4), rig.mat(C.iron, { metal: true }), { y: 0.03, x: 0.04 });
  axe(rig, rig.handR);
  return rig;
}

function orcShaman() {
  const rig = createHumanoidRig(makeMaterial, { ...ORC_JOINTS, shoulderX: 0.38, height: 2.1 });
  orcBase(rig, { lean: true });
  const m = (c, o) => rig.mat(c, o);
  rig.add(rig.head, G.ico(0.15, 0), m(C.tusk), { y: 0.2, z: 0.2, sz: 0.6 });
  C.feather.forEach((color, i) => {
    rig.add(rig.head, G.cone(0.04, 0.35, 4), m(color), { x: (i - 1) * 0.12, y: 0.45, z: -0.05, rz: (1 - i) * 0.35, rx: -0.3 });
  });
  const stick = new THREE.Group();
  rig.add(stick, G.cyl(0.025, 0.03, 1.3, 5), m(C.wood), { y: 0.2 });
  rig.add(stick, G.ico(0.1), m(0xff8a3d, { glow: true }), { y: 0.9 });
  stick.rotation.x = -Math.PI / 2; // 舉起時杖頭朝前
  rig.handL.add(stick);
  return rig;
}

function minotaur() {
  const rig = createHumanoidRig(makeMaterial, { ...ORC_JOINTS, scale: 1.9, height: 2.1 });
  const m = (c, o) => rig.mat(c, o);
  rig.add(rig.body, G.cyl(0.44, 0.3, 0.6, 7), m(C.fur), { y: 1.08, rx: 0.15 });
  rig.add(rig.body, G.cyl(0.3, 0.36, 0.26, 7), m(C.leather), { y: 0.72 });
  rig.add(rig.body, G.cyl(0.38, 0.38, 0.06, 7), m(C.iron, { metal: true }), { y: 0.87 });

  rig.add(rig.head, G.box(0.36, 0.3, 0.3), m(C.fur), { y: 0.2, z: 0.05 });
  rig.add(rig.head, G.box(0.26, 0.2, 0.22), m(C.furDark), { y: 0.1, z: 0.25 });
  rig.add(rig.head, G.torus(0.06, 0.015, 4, 8), m(C.gold, { metal: true }), { y: 0.04, z: 0.37 });
  for (const s of [-1, 1]) {
    rig.add(rig.head, G.cone(0.07, 0.38, 5), m(C.horn), { x: s * 0.3, y: 0.35, rz: -s * 1.0 });
    rig.add(rig.head, G.cone(0.04, 0.2, 5), m(C.horn), { x: s * 0.45, y: 0.52, rz: -s * 0.1 });
    rig.add(rig.head, G.sphere(0.035, 5, 4), m(C.bossEye, { glow: true }), { x: s * 0.11, y: 0.25, z: 0.2, shadow: false });
  }
  for (const arm of [rig.armR, rig.armL]) {
    rig.add(arm, G.cyl(0.13, 0.11, 0.34, 7), m(C.fur), { y: -0.2 });
    rig.add(arm, G.cyl(0.12, 0.13, 0.26, 7), m(C.iron, { metal: true }), { y: -0.48 });
    rig.add(arm, G.sphere(0.12, 7, 5), m(C.furDark), { y: -0.65 });
  }
  for (const leg of [rig.legR, rig.legL]) {
    rig.add(leg, G.cyl(0.14, 0.1, 0.34, 7), m(C.fur), { y: -0.17 });
    rig.add(leg, G.cyl(0.09, 0.12, 0.16, 6), m(C.furDark), { y: -0.5 });
  }

  const g = new THREE.Group();
  rig.add(g, G.cyl(0.035, 0.04, 1.3, 6), m(C.wood), { y: 0.4 });
  for (const s of [-1, 1]) {
    const blade = new THREE.CylinderGeometry(0.38, 0.38, 0.04, 9, 1, false, 0, Math.PI);
    rig.add(g, blade, m(C.iron, { metal: true }), { y: 0.92, rz: Math.PI / 2, ry: s > 0 ? 0 : Math.PI });
  }
  g.rotation.x = 2.6;
  rig.handR.add(g);
  return rig;
}

// ───────── 玩家武器 ─────────

function swordShield() {
  const kit = new PartKit(makeMaterial);
  const sword = new THREE.Group();
  kit.add(sword, G.cyl(0.035, 0.035, 0.22, 6), kit.mat(C.under));
  kit.add(sword, G.ico(0.06), kit.mat(C.gold, { metal: true }), { y: -0.14 });
  kit.add(sword, G.box(0.4, 0.07, 0.09), kit.mat(C.gold, { metal: true }), { y: 0.13 });
  for (const s of [-1, 1]) kit.add(sword, G.ico(0.05), kit.mat(C.gold, { metal: true }), { x: s * 0.21, y: 0.15 });
  kit.add(sword, G.cyl(0.035, 0.085, 0.9, 4), kit.mat(0xe8eef6, { metal: true }), { y: 0.62, sz: 0.3 });
  sword.rotation.x = 2.8;

  const shield = new THREE.Group();
  kit.add(shield, G.cyl(0.36, 0.36, 0.08, 6), kit.mat(C.armor, { metal: true }), { rz: Math.PI / 2 });
  kit.add(shield, G.cyl(0.27, 0.27, 0.09, 6), kit.mat(C.under), { rz: Math.PI / 2 });
  kit.add(shield, G.ico(0.1), kit.mat(C.gold, { metal: true }), { x: 0.06 });
  shield.position.set(0.2, -0.36, 0);
  return { kit, main: sword, offhand: shield };
}

function staff() {
  const kit = new PartKit(makeMaterial);
  const g = new THREE.Group();
  kit.add(g, G.cyl(0.035, 0.04, 1.7, 6), kit.mat(C.armor, { metal: true }), { y: 0.25 });
  for (const s of [-1, 1]) {
    kit.add(g, G.box(0.04, 0.22, 0.12), kit.mat(C.gold, { metal: true }), { x: s * 0.12, y: 1.15, rz: s * 0.5 });
  }
  const gem = kit.add(g, G.ico(0.12, 0), kit.mat(0x7fd8ff, { glow: true }), { y: 1.2 });
  return { kit, main: g, offhand: null, gem };
}

// ───────── 投射物 ─────────

function enemyProjectile() {
  const kit = new PartKit(makeMaterial);
  const g = new THREE.Group();
  kit.add(g, G.ico(0.22, 0), kit.mat(0xff8a3d, { glow: true }), { shadow: false });
  kit.add(g, G.ico(0.13, 0), kit.mat(0xffe08a, { glow: true }), { z: 0.08, shadow: false });
  return { kit, mesh: g };
}

// ───────── 場地 ─────────

function buildArena(half) {
  const kit = new PartKit(makeMaterial);
  const group = new THREE.Group();
  group.add(createGround(kit, half * 2, { colors: [0xc9a77a, 0xdcc196], cell: 2, mode: 'tiles', jitter: 0.05 }));
  group.add(createGround(kit, (half + 14) * 2, { colors: [0xb08a5a, 0xc29a68], cell: 2.5, jitter: 0.08 }));
  group.children[1].position.y = -0.01;

  const sandstone = kit.mat(0xd9c39a);
  const sandDark = kit.mat(0xb59a6e);
  const e = half + 0.5;
  for (const [x, z, ry] of [[0, -e, 0], [0, e, 0], [-e, 0, Math.PI / 2], [e, 0, Math.PI / 2]]) {
    kit.add(group, G.box(e * 2, 0.8, 0.6), sandDark, { x, y: 0.4, z, ry });
  }
  const banner = kit.mat(C.cape);
  const fire = kit.mat(0xffa040, { glow: true });
  perimeterPoints(half, 4, 0.5).forEach((p, i) => {
    const pillar = new THREE.Group();
    pillar.position.set(p.x, 0, p.z);
    pillar.rotation.y = p.ry;
    kit.add(pillar, G.cyl(0.35, 0.4, 2.6, 8), sandstone, { y: 1.3 });
    kit.add(pillar, G.box(0.95, 0.25, 0.95), sandDark, { y: 2.7 });
    if (i % 3 === 0) {
      kit.add(pillar, G.box(0.55, 1.1, 0.03), banner, { y: 1.6, z: 0.42 });
      kit.add(pillar, G.box(0.55, 0.08, 0.04), kit.mat(C.gold, { metal: true }), { y: 2.12, z: 0.42 });
    } else if (i % 3 === 1) {
      kit.add(pillar, G.cone(0.22, 0.5, 5), fire, { y: 3.08, shadow: false });
    }
    group.add(pillar);
  });
  const crate = kit.mat(0x8a6236);
  for (const p of scatterOutside(half, 20, 1.6, 7)) {
    kit.add(group, G.box(0.7 * p.s, 0.7 * p.s, 0.7 * p.s), crate, { x: p.x, y: 0.35 * p.s, z: p.z, ry: p.ry });
  }
  return { kit, group };
}

export const heroic = {
  id: 'heroic',
  name: 'C 英雄卡通',
  names: { knight: '聖騎士', melee: '獸人戰士', ranged: '獸人薩滿', boss: '牛頭魔王' },
  environment: {
    background: 0xe9a86f,
    hemiSky: 0xffe2c0, hemiGround: 0x6a4a30, hemiIntensity: 1.1,
    sunColor: 0xffc890, sunIntensity: 2.2,
  },
  colors: { blood: 0x8a1c1c, bossBlood: 0x8a1c1c, enemyProjectile: 0xff8a3d, hitSpark: 0xfff2c0 },
  characters: { knight, melee: orc, ranged: orcShaman, boss: minotaur },
  weapons: { swordShield, staff },
  enemyProjectile,
  buildArena,
};
