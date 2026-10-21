// 全域可調參數：迴圈、世界、相機、玩家、敵人、生成與除錯開關

export const FIXED_DT = 1 / 60;
export const MAX_STEPS_PER_FRAME = 5;

export const WORLD = {
  arenaHalfSize: 16,
};

export const CAMERA = {
  viewHalfHeight: 10,          // 正交相機可視範圍的一半高度（世界單位）
  distance: 40,
  azimuth: Math.PI / 4,        // 從 +X+Z 方向看向場地
  elevation: 0.7,              // 約 40°，比標準等距角略高，戰鬥較好讀
  followSharpness: 8,
  aimPlaneHeight: 0.9,         // 滑鼠瞄準射線投射的平面高度（約胸口）
};

export const COMBAT = {
  knockbackDamping: 9,
  flashTime: 0.12,
};

export const PLAYER = {
  maxHp: 100,
  moveSpeed: 6.5,
  turnSpeed: 25,
  radius: 0.45,
  mass: 2,
  invulnTime: 0.6,
  staggerTime: 0.15,
  actionBufferTime: 0.25,
  startWeapon: 'swordShield',
  slots: ['heal', 'sprint', null, null, null],
};

export const SPAWNER = {
  firstDelay: 1.0,
  waveDelay: 2.5,
  spawnInterval: 0.35,
  minDistanceFromPlayer: 8,
};

// 音量（0~1）：實際音量 = master × 分類音量
export const AUDIO = {
  master: 0.7,
  sfx: 0.8,
  music: 0.5,
};

export const DEBUG = {
  showHitboxes: false,
};
