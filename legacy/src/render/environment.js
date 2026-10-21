// 場景建構工具：低多邊形地面、邊界點位、外圍裝飾散佈（供各風格的 buildArena 使用）
import * as THREE from 'three';
import { lerp } from '../core/math.js';

const _a = new THREE.Color();
const _b = new THREE.Color();

// 平滑的偽隨機雜訊（0~1），不需要外部函式庫
export function softNoise(x, z) {
  return 0.5
    + 0.25 * Math.sin(x * 0.35 + 1.3) * Math.cos(z * 0.27 - 0.4)
    + 0.25 * Math.sin((x + z) * 0.15 + 2.1);
}

/**
 * 每個三角形單色的低多邊形地面。
 * mode 'noise'：依雜訊在 colors 間漸變並帶隨機深淺；'tiles'：每格一色，棋盤交錯。
 */
export function createGround(kit, size, { colors, cell = 1.5, mode = 'noise', jitter = 0.06 }) {
  const segs = Math.max(1, Math.round(size / cell));
  const geometry = new THREE.PlaneGeometry(size, size, segs, segs).toNonIndexed();
  geometry.rotateX(-Math.PI / 2);
  const pos = geometry.attributes.position;
  const colorAttr = new Float32Array(pos.count * 3);
  const palette = colors.map((c) => new THREE.Color(c));

  const pick = (t) => {
    const scaled = Math.min(0.999, Math.max(0, t)) * (palette.length - 1);
    const i = Math.floor(scaled);
    return _a.copy(palette[i]).lerp(palette[i + 1] ?? palette[i], scaled - i);
  };

  const vertsPerGroup = mode === 'tiles' ? 6 : 3;
  for (let v = 0; v < pos.count; v += vertsPerGroup) {
    let cx = 0;
    let cz = 0;
    for (let k = 0; k < vertsPerGroup; k++) {
      cx += pos.getX(v + k);
      cz += pos.getZ(v + k);
    }
    cx /= vertsPerGroup;
    cz /= vertsPerGroup;

    if (mode === 'tiles') {
      const ix = Math.floor(cx / cell);
      const iz = Math.floor(cz / cell);
      pick(((ix + iz) & 1) ? 0.25 : 0.65);
    } else {
      pick(softNoise(cx, cz));
    }
    const shade = 1 + (Math.random() - 0.5) * 2 * jitter;
    _b.copy(_a).multiplyScalar(shade);
    for (let k = 0; k < vertsPerGroup; k++) {
      colorAttr[(v + k) * 3] = _b.r;
      colorAttr[(v + k) * 3 + 1] = _b.g;
      colorAttr[(v + k) * 3 + 2] = _b.b;
    }
  }
  geometry.setAttribute('color', new THREE.BufferAttribute(colorAttr, 3));
  kit.geometries.push(geometry);
  const material = new THREE.MeshLambertMaterial({ vertexColors: true });
  kit.materials.push(material);
  const mesh = new THREE.Mesh(geometry, material);
  mesh.receiveShadow = true;
  return mesh;
}

// 沿著正方形場地邊界的等距點位（offset 為離邊界向外的距離）
export function perimeterPoints(half, spacing, offset = 0.5) {
  const points = [];
  const e = half + offset;
  const count = Math.max(1, Math.round((e * 2) / spacing));
  for (let i = 0; i < count; i++) {
    const t = lerp(-e, e, i / count);
    points.push(
      { x: t, z: -e, ry: 0 },
      { x: e, z: t, ry: Math.PI / 2 },
      { x: -t, z: e, ry: Math.PI },
      { x: -e, z: -t, ry: -Math.PI / 2 },
    );
  }
  return points;
}

// 場地外圍環帶中的隨機點位（inner 為離邊界最近距離，outer 為最遠）
export function scatterOutside(half, count, inner = 1.5, outer = 9) {
  const points = [];
  while (points.length < count) {
    const x = (Math.random() * 2 - 1) * (half + outer);
    const z = (Math.random() * 2 - 1) * (half + outer);
    const d = Math.max(Math.abs(x), Math.abs(z));
    if (d < half + inner) continue;
    points.push({ x, z, ry: Math.random() * Math.PI * 2, s: 0.7 + Math.random() * 0.6 });
  }
  return points;
}

// 場地內的少量裝飾點位（不影響碰撞，只放小東西）
export function scatterInside(half, count, margin = 1.5) {
  const points = [];
  for (let i = 0; i < count; i++) {
    points.push({
      x: (Math.random() * 2 - 1) * (half - margin),
      z: (Math.random() * 2 - 1) * (half - margin),
      ry: Math.random() * Math.PI * 2,
      s: 0.6 + Math.random() * 0.6,
    });
  }
  return points;
}
