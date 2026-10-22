// 匯出網頁版（legacy/）的全部數值資料成 JSON，給 Godot 的 tests/check.gd 逐欄比對
// 用法（在專案根目錄）：node tools/dump_web_defs.mjs
// 網頁版資料檔沒有引用 three.js，不需要 npm install；網頁版已凍結，只有改到網頁版資料時才需要重跑
import { writeFileSync } from 'node:fs';
import * as config from '../legacy/src/core/config.js';
import { WEAPONS } from '../legacy/src/weapons/weaponDefs.js';
import { ENEMIES } from '../legacy/src/entities/enemyDefs.js';
import { SKILLS } from '../legacy/src/skills/skillDefs.js';
import { WAVES, WAVE_SCALING } from '../legacy/src/world/waveDefs.js';

const OUT = new URL('../godot/tests/web_defs.json', import.meta.url);

const data = {
  FIXED_DT: config.FIXED_DT,
  MAX_STEPS_PER_FRAME: config.MAX_STEPS_PER_FRAME,
  WORLD: config.WORLD,
  CAMERA: config.CAMERA,
  COMBAT: config.COMBAT,
  PLAYER: config.PLAYER,
  SPAWNER: config.SPAWNER,
  AUDIO: config.AUDIO,
  WEAPONS,
  ENEMIES,
  SKILLS,
  WAVES,
  WAVE_SCALING,
};

writeFileSync(OUT, JSON.stringify(data, null, 2) + '\n');
console.log(`已寫入 ${OUT.pathname}`);
