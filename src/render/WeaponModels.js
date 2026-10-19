// 武器外觀：以方塊組合劍、盾、法杖，回傳掛載節點與每幀姿勢同步函式
import * as THREE from 'three';

function box(w, h, d, color, x = 0, y = 0, z = 0, basic = false) {
  const material = basic
    ? new THREE.MeshBasicMaterial({ color })
    : new THREE.MeshLambertMaterial({ color });
  const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), material);
  mesh.position.set(x, y, z);
  mesh.castShadow = true;
  return mesh;
}

function disposeTree(object) {
  object.traverse((child) => {
    if (child.isMesh) {
      child.geometry.dispose();
      child.material.dispose();
    }
  });
}

function buildSwordShield() {
  // 劍：在自身座標中刀刃朝 +Y，握柄在原點
  const sword = new THREE.Group();
  sword.add(
    box(0.07, 0.24, 0.07, 0x6b4423, 0, 0),
    box(0.32, 0.06, 0.09, 0xc9a227, 0, 0.14),
    box(0.11, 0.85, 0.04, 0xdfe6ee, 0, 0.6),
    box(0.06, 0.1, 0.04, 0xdfe6ee, 0, 1.06),
  );
  sword.rotation.x = 2.8; // 刀刃大致延伸手臂方向並略微前傾

  // 盾：貼在左前臂外側
  const shield = new THREE.Group();
  shield.add(
    box(0.08, 0.62, 0.52, 0x8a5a2b),
    box(0.1, 0.66, 0.06, 0x9aa3ad, 0, 0, 0.27),
    box(0.1, 0.66, 0.06, 0x9aa3ad, 0, 0, -0.27),
    box(0.11, 0.16, 0.16, 0xc9a227),
  );
  shield.position.set(0.17, -0.42, 0);

  return {
    main: sword,
    offhand: shield,
    sync() {},
    dispose() { disposeTree(sword); disposeTree(shield); },
  };
}

function buildStaff() {
  const staff = new THREE.Group();
  const gem = box(0.2, 0.2, 0.2, 0x9be7ff, 0, 1.22, 0, true);
  gem.rotation.set(Math.PI / 4, 0, Math.PI / 4);
  staff.add(
    box(0.07, 1.7, 0.07, 0x5b3a1d, 0, 0.25),
    box(0.24, 0.06, 0.06, 0xc9a227, 0, 1.08),
    gem,
  );

  return {
    main: staff,
    offhand: null,
    gem,
    // 法杖的世界傾角由 player.weaponTilt 決定，與手臂角度脫鉤
    sync(player) {
      staff.rotation.x = player.weaponTilt - player.model.armR.rotation.x;
      gem.rotation.y += 0.05;
    },
    dispose() { disposeTree(staff); },
  };
}

const BUILDERS = { swordShield: buildSwordShield, staff: buildStaff };

export function createWeaponModel(kind) {
  const build = BUILDERS[kind];
  if (!build) throw new Error(`Unknown weapon model: ${kind}`);
  return build();
}
