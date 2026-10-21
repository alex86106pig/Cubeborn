// 敵人資料定義：數值放這裡，行為在 entities/enemies/ 的各類別
// visual 對應造型風格的 characters 欄位（melee / ranged / boss）

export const ENEMIES = {
  grunt: {
    visual: 'melee',
    maxHp: 36,
    moveSpeed: 2.6,
    speedVariance: 0.2,
    turnSpeed: 6,
    radius: 0.45,
    mass: 1,
    contactDamage: 10,
    contactInterval: 0.8,
    contactKnockback: 9,
    hurtTime: 0.22,
    spawnTime: 0.7,
    corpseTime: 1.4,
  },

  archer: {
    visual: 'ranged',
    maxHp: 26,
    moveSpeed: 2.3,
    speedVariance: 0.15,
    turnSpeed: 8,
    radius: 0.42,
    mass: 1,
    contactDamage: 6,
    contactInterval: 1,
    contactKnockback: 6,
    hurtTime: 0.22,
    spawnTime: 0.7,
    corpseTime: 1.4,
    preferredRange: [6, 10],   // 保持與玩家的距離
    aimTime: 0.75,             // 出手前的預備動作（玩家的閃避提示）
    fireInterval: 2.4,
    projectileSpeed: 10,
    projectileDamage: 12,
    projectileRadius: 0.25,
    projectileRange: 18,
  },

  boss: {
    visual: 'boss',
    maxHp: 900,
    moveSpeed: 2.2,
    speedVariance: 0,
    turnSpeed: 3.5,
    radius: 1.0,
    mass: 30,
    knockbackMul: 0.12,
    contactDamage: 12,
    contactInterval: 1,
    contactKnockback: 12,
    spawnTime: 1.6,
    corpseTime: 3.5,
    slam: { triggerDistance: 3.2, radius: 3.4, windup: 0.85, recovery: 0.8, damage: 26, knockback: 16, cooldown: 3.5 },
    charge: { minDistance: 5, windup: 0.75, speed: 15, duration: 0.85, recovery: 1.0, wallStun: 1.6, damage: 22, knockback: 18, cooldown: 6 },
    summon: { hpThreshold: 0.75, count: 3, windup: 1.0, recovery: 0.4, cooldown: 14 },
    enrage: { hpThreshold: 0.5, speedMul: 1.3, cooldownMul: 0.65 },
  },
};
