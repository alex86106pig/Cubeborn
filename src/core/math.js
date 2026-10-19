// 共用數學小工具（角度、插值、緩動）

export const clamp = (v, min, max) => (v < min ? min : v > max ? max : v);
export const lerp = (a, b, t) => a + (b - a) * t;
export const randRange = (a, b) => a + Math.random() * (b - a);
export const easeOutCubic = (t) => 1 - (1 - t) ** 3;
export const easeInQuad = (t) => t * t;

// 與幀率無關的指數趨近
export const damp = (current, target, sharpness, dt) =>
  lerp(current, target, 1 - Math.exp(-sharpness * dt));

export function wrapAngle(a) {
  a = (a + Math.PI) % (Math.PI * 2);
  if (a < 0) a += Math.PI * 2;
  return a - Math.PI;
}

export function dampAngle(current, target, sharpness, dt) {
  return wrapAngle(current + wrapAngle(target - current) * (1 - Math.exp(-sharpness * dt)));
}

export function turnTowards(current, target, maxStep) {
  const diff = wrapAngle(target - current);
  if (Math.abs(diff) <= maxStep) return wrapAngle(target);
  return wrapAngle(current + Math.sign(diff) * maxStep);
}

// XZ 平面朝向角：方向向量為 (sin a, cos a)
export const angleTo = (from, to) => Math.atan2(to.x - from.x, to.z - from.z);

export const distanceXZ = (a, b) => Math.hypot(a.x - b.x, a.z - b.z);
