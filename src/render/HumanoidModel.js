// 方塊人形建構器：頭/身體/雙手/雙腳群組，關節在頂端，供程序化動畫直接旋轉
import * as THREE from 'three';

// 幾何體全域共用（不在 dispose 時釋放）
const HEAD = new THREE.BoxGeometry(0.5, 0.5, 0.5).translate(0, 0.25, 0);
const HAIR = new THREE.BoxGeometry(0.54, 0.12, 0.54).translate(0, 0.5, 0);
const HAIR_BACK = new THREE.BoxGeometry(0.54, 0.3, 0.1).translate(0, 0.36, -0.23);
const EYE = new THREE.BoxGeometry(0.1, 0.08, 0.02);
const TORSO = new THREE.BoxGeometry(0.5, 0.75, 0.26);
const LIMB = new THREE.BoxGeometry(0.24, 0.75, 0.24).translate(0, -0.375, 0);
const SLEEVE = new THREE.BoxGeometry(0.26, 0.3, 0.26).translate(0, -0.15, 0);
const SHOE = new THREE.BoxGeometry(0.26, 0.14, 0.27).translate(0, -0.68, 0.01);

export class HumanoidModel {
  constructor(colors) {
    const mat = (color) => new THREE.MeshLambertMaterial({ color });
    this.materials = {
      skin: mat(colors.skin),
      hair: mat(colors.hair),
      shirt: mat(colors.shirt),
      pants: mat(colors.pants),
      shoes: mat(colors.shoes),
      eyes: mat(colors.eyes),
    };
    const m = this.materials;

    this.root = new THREE.Group();   // 位置與朝向（由 Entity 同步）
    this.body = new THREE.Group();   // 整體姿勢：倒地、前傾、彈跳，樞紐在腳底
    this.root.add(this.body);

    const torso = this.#mesh(TORSO, m.shirt);
    torso.position.y = 1.125;

    this.head = new THREE.Group();
    this.head.position.y = 1.5;
    this.head.add(this.#mesh(HEAD, m.skin), this.#mesh(HAIR, m.hair), this.#mesh(HAIR_BACK, m.hair));
    for (const x of [-0.11, 0.11]) {
      const eye = this.#mesh(EYE, m.eyes);
      eye.position.set(x, 0.27, 0.255);
      eye.castShadow = false;
      this.head.add(eye);
    }

    // 角色面向 +Z，右側為 -X
    this.armR = this.#limb(-0.37, 1.48, m.skin, m.shirt);
    this.armL = this.#limb(0.37, 1.48, m.skin, m.shirt);
    this.legR = this.#limb(-0.125, 0.75, m.pants, null, m.shoes);
    this.legL = this.#limb(0.125, 0.75, m.pants, null, m.shoes);

    // 手掌掛點：武器掛在這裡
    this.handR = new THREE.Group();
    this.handR.position.y = -0.68;
    this.armR.add(this.handR);
    this.handL = new THREE.Group();
    this.handL.position.y = -0.68;
    this.armL.add(this.handL);

    this.body.add(torso, this.head, this.armR, this.armL, this.legR, this.legL);
  }

  #mesh(geometry, material) {
    const mesh = new THREE.Mesh(geometry, material);
    mesh.castShadow = true;
    return mesh;
  }

  #limb(x, y, material, sleeveMaterial, shoeMaterial) {
    const pivot = new THREE.Group();
    pivot.position.set(x, y, 0);
    pivot.rotation.order = 'YXZ'; // 先前後抬起，再水平揮動
    pivot.add(this.#mesh(LIMB, material));
    if (sleeveMaterial) pivot.add(this.#mesh(SLEEVE, sleeveMaterial));
    if (shoeMaterial) pivot.add(this.#mesh(SHOE, shoeMaterial));
    return pivot;
  }

  // 受擊閃白，k 為 0~1
  setFlash(k) {
    for (const mat of Object.values(this.materials)) mat.emissive.setScalar(k);
  }

  setOpacity(opacity) {
    for (const mat of Object.values(this.materials)) {
      mat.transparent = opacity < 1;
      mat.opacity = opacity;
    }
  }

  dispose() {
    for (const mat of Object.values(this.materials)) mat.dispose();
  }
}
