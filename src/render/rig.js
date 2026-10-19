// 角色骨架（Rig）與零件組（PartKit）
// Rig 是所有造型風格共用的關節階層，動畫程式只轉動關節：
//   root（位置/朝向）→ body（整體姿勢，樞紐在腳底）→ head / armR / armL / legR / legL；手掌掛點 handR / handL
// 角色面向 +Z，右側為 -X；四肢往 -Y 延伸
import * as THREE from 'three';

// 追蹤自己建立的材質與幾何體，可統一閃白、淡出與釋放
export class PartKit {
  #materialCache = new Map();

  constructor(makeMaterial) {
    this.makeMaterial = makeMaterial;
    this.materials = [];
    this.geometries = [];
  }

  // 依顏色與選項取得專屬材質；glow 為不受光照的自發光材質
  mat(color, options = {}) {
    const key = `${color}|${options.glow ? 'g' : ''}|${options.metal ? 'm' : ''}`;
    if (!this.#materialCache.has(key)) {
      const material = options.glow
        ? new THREE.MeshBasicMaterial({ color })
        : this.makeMaterial(color, options);
      this.#materialCache.set(key, material);
      this.materials.push(material);
    }
    return this.#materialCache.get(key);
  }

  add(parent, geometry, material, t = {}) {
    this.geometries.push(geometry);
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.set(t.x ?? 0, t.y ?? 0, t.z ?? 0);
    mesh.rotation.set(t.rx ?? 0, t.ry ?? 0, t.rz ?? 0);
    if (t.s !== undefined) mesh.scale.setScalar(t.s);
    if (t.sx !== undefined || t.sy !== undefined || t.sz !== undefined) {
      mesh.scale.set(t.sx ?? 1, t.sy ?? 1, t.sz ?? 1);
    }
    mesh.castShadow = t.shadow ?? true;
    parent.add(mesh);
    return mesh;
  }

  // 受擊閃白，k 為 0~1（自發光材質沒有 emissive，不受影響）
  setFlash(k) {
    for (const m of this.materials) m.emissive?.setScalar(k);
  }

  setOpacity(opacity) {
    for (const m of this.materials) {
      m.transparent = opacity < 1;
      m.opacity = opacity;
    }
  }

  dispose() {
    for (const m of this.materials) m.dispose();
    for (const g of this.geometries) g.dispose();
  }
}

export class Rig extends PartKit {
  constructor(makeMaterial) {
    super(makeMaterial);
    this.root = new THREE.Group();
    this.body = new THREE.Group();
    this.root.add(this.body);
    this.head = new THREE.Group();
    this.armR = Rig.#joint();
    this.armL = Rig.#joint();
    this.legR = Rig.#joint();
    this.legL = Rig.#joint();
    this.handR = new THREE.Group();
    this.handL = new THREE.Group();
    this.armR.add(this.handR);
    this.armL.add(this.handL);
    this.body.add(this.head, this.armR, this.armL, this.legR, this.legL);
    this.height = 2;      // 頭頂高度（世界單位），供浮動數字等定位
    this.accessories = []; // 額外掛上的零件組（例如武器），一起閃白
  }

  static #joint() {
    const g = new THREE.Group();
    g.rotation.order = 'YXZ'; // 先前後抬起，再水平揮動
    return g;
  }

  setFlash(k) {
    super.setFlash(k);
    for (const a of this.accessories) a.setFlash(k);
  }

  setOpacity(opacity) {
    super.setOpacity(opacity);
    for (const a of this.accessories) a.setOpacity(opacity);
  }
}

/**
 * 建立指定比例的人形骨架。
 * @param j { neck, shoulderY, shoulderX, armLen, hipY, hipX, height, scale? }
 */
export function createHumanoidRig(makeMaterial, j) {
  const rig = new Rig(makeMaterial);
  rig.head.position.y = j.neck;
  rig.armR.position.set(-j.shoulderX, j.shoulderY, 0);
  rig.armL.position.set(j.shoulderX, j.shoulderY, 0);
  rig.legR.position.set(-j.hipX, j.hipY, 0);
  rig.legL.position.set(j.hipX, j.hipY, 0);
  rig.handR.position.y = -j.armLen;
  rig.handL.position.y = -j.armLen;
  const scale = j.scale ?? 1;
  rig.body.scale.setScalar(scale);
  rig.height = j.height * scale;
  return rig;
}

// 常用幾何體工廠（低多邊形，分段數刻意偏低）
export const G = {
  box: (w, h, d) => new THREE.BoxGeometry(w, h, d),
  sphere: (r, w = 8, h = 6) => new THREE.SphereGeometry(r, w, h),
  dome: (r, w = 10, h = 5) => new THREE.SphereGeometry(r, w, h, 0, Math.PI * 2, 0, Math.PI / 2),
  ico: (r, detail = 0) => new THREE.IcosahedronGeometry(r, detail),
  cyl: (rt, rb, h, seg = 8) => new THREE.CylinderGeometry(rt, rb, h, seg),
  cone: (r, h, seg = 8) => new THREE.ConeGeometry(r, h, seg),
  capsule: (r, len, cap = 3, radial = 8) => new THREE.CapsuleGeometry(r, len, cap, radial),
  torus: (r, tube, radial = 6, tubular = 12, arc = Math.PI * 2) => new THREE.TorusGeometry(r, tube, radial, tubular, arc),
};

// ───────── 材質工廠（每種風格一個） ─────────

export function toonMaterialFactory() {
  const gradient = new THREE.DataTexture(new Uint8Array([110, 190, 255]), 3, 1, THREE.RedFormat);
  gradient.minFilter = gradient.magFilter = THREE.NearestFilter;
  gradient.needsUpdate = true;
  return (color) => new THREE.MeshToonMaterial({ color, gradientMap: gradient });
}

export function flatLambertFactory() {
  return (color) => new THREE.MeshLambertMaterial({ color, flatShading: true });
}

export function flatStandardFactory() {
  return (color, { metal = false } = {}) => new THREE.MeshStandardMaterial({
    color, flatShading: true, roughness: metal ? 0.35 : 0.85, metalness: metal ? 0.55 : 0,
  });
}
