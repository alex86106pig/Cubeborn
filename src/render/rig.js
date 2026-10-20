// 角色骨架（Rig）與零件組（PartKit）
// Rig 是所有造型風格共用的關節階層，動畫程式只轉動關節：
//   root（位置/朝向）→ body（整體姿勢，樞紐在腳底）→ head / armR / armL / legR / legL；手掌掛點 handR / handL
// 角色面向 +Z，右側為 -X；四肢往 -Y 延伸
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

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

  /**
   * 合併靜態零件以減少繪製次數：anchors 是會各自移動的節點（關節、武器根節點），
   * 每個零件依「最近的 anchor 祖先 + 材質 + 陰影設定」分組，合併成一個 mesh 掛回該 anchor。
   * keep 內的 mesh（例如會自轉的寶石）不合併。anchor 以下的非 anchor 節點視為固定不動。
   */
  mergeStatic(root, anchors, keep = []) {
    root.updateMatrixWorld(true);
    const anchorSet = new Set(anchors);
    const keepSet = new Set(keep);
    const buckets = new Map();
    const merged = [];
    root.traverse((obj) => {
      if (!obj.isMesh || keepSet.has(obj)) return;
      let anchor = obj.parent;
      while (anchor && !anchorSet.has(anchor)) anchor = anchor.parent;
      if (!anchor) return;
      const geo = obj.geometry.index ? obj.geometry.toNonIndexed() : obj.geometry.clone();
      geo.applyMatrix4(_rel.copy(anchor.matrixWorld).invert().multiply(obj.matrixWorld));
      const attrs = Object.keys(geo.attributes).sort().join(',');
      const key = `${anchor.id}|${obj.material.uuid}|${obj.castShadow}|${obj.receiveShadow}|${attrs}`;
      if (!buckets.has(key)) buckets.set(key, { anchor, source: obj, geos: [] });
      buckets.get(key).geos.push(geo);
      merged.push(obj);
    });

    const removed = new Set(merged.map((m) => m.geometry));
    for (const obj of merged) obj.removeFromParent();
    for (const { anchor, source, geos } of buckets.values()) {
      const geometry = geos.length === 1 ? geos[0] : mergeGeometries(geos);
      if (geos.length > 1) for (const g of geos) g.dispose();
      const mesh = new THREE.Mesh(geometry, source.material);
      mesh.castShadow = source.castShadow;
      mesh.receiveShadow = source.receiveShadow;
      anchor.add(mesh);
      this.geometries.push(geometry);
    }
    for (const g of removed) g.dispose();
    this.geometries = this.geometries.filter((g) => !removed.has(g));
    pruneEmptyGroups(root, anchorSet);
    return this;
  }
}

const _rel = new THREE.Matrix4();

// 移除合併後留下的空群組（anchor 除外）
function pruneEmptyGroups(obj, anchorSet) {
  for (const child of [...obj.children]) {
    pruneEmptyGroups(child, anchorSet);
    if (!child.isMesh && child.children.length === 0 && !anchorSet.has(child)) child.removeFromParent();
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

  // 角色建好後呼叫：每個關節的零件合併成少數幾個 mesh
  optimize() {
    const { root, body, head, armR, armL, legR, legL, handR, handL } = this;
    return this.mergeStatic(root, [root, body, head, armR, armL, legR, legL, handR, handL]);
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

// ───────── 材質工廠 ─────────

export function flatLambertFactory() {
  return (color) => new THREE.MeshLambertMaterial({ color, flatShading: true });
}
