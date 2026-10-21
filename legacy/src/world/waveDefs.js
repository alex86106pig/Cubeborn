// 波次資料：每波生成的敵人數量；最後一波為 Boss 戰，打倒 Boss 即通關

export const WAVES = [
  { spawns: { grunt: 5 } },
  { spawns: { grunt: 6, archer: 1 } },
  { spawns: { grunt: 7, archer: 2 } },
  { spawns: { grunt: 9, archer: 3 } },
  { isBoss: true, spawns: { boss: 1, grunt: 2 } },
];

// 每多一波，小怪數值成長的比例（Boss 不套用）
export const WAVE_SCALING = { hp: 0.15, damage: 0.12, speed: 0.03 };

export function waveMultipliers(wave) {
  const n = Math.max(0, wave - 1);
  return {
    hp: 1 + WAVE_SCALING.hp * n,
    damage: 1 + WAVE_SCALING.damage * n,
    speed: 1 + WAVE_SCALING.speed * n,
  };
}
