// 造型風格登錄：遊戲透過 getStyle() 取得目前風格（已定案為暗黑幻想）
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

export const STYLES = [darkFantasy];

export function getStyle() {
  return darkFantasy;
}
