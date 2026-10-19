// 造型風格登錄：所有風格實作相同介面，遊戲透過 getStyle() 取得目前風格
//
// 風格介面：
//   id, name, names { knight, melee, ranged, boss }
//   environment { background, hemiSky, hemiGround, hemiIntensity, sunColor, sunIntensity }
//   colors { blood, bossBlood, enemyProjectile, hitSpark }
//   characters { knight, melee, ranged, boss }  → () => Rig
//   weapons { swordShield, staff }              → () => { kit, main, offhand, gem? }
//   enemyProjectile()                            → { kit, mesh }（沿 +Z 建模）
//   buildArena(halfSize)                         → { kit, group }
import { darkFantasy } from './darkFantasy.js';
import { heroic } from './heroic.js';
import { storybook } from './storybook.js';

export const STYLES = [storybook, darkFantasy, heroic];

const STORAGE_KEY = 'cubeborn.style';
let current = STYLES[0];

try {
  const saved = localStorage.getItem(STORAGE_KEY);
  current = STYLES.find((s) => s.id === saved) ?? current;
} catch { /* 無法存取 localStorage 時使用預設 */ }

export function getStyle() {
  return current;
}

export function setStyle(id) {
  current = STYLES.find((s) => s.id === id) ?? current;
  try { localStorage.setItem(STORAGE_KEY, current.id); } catch { /* 忽略 */ }
  return current;
}

export function nextStyle() {
  const i = STYLES.indexOf(current);
  return setStyle(STYLES[(i + 1) % STYLES.length].id);
}
