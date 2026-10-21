// 主動技能/道具行為：canUse 為額外使用條件（選用），activate 執行效果

export const SKILL_BEHAVIORS = {
  heal: {
    canUse: (game, owner) => owner.hp < owner.maxHp,
    activate(game, owner, def) {
      const healed = owner.heal(def.amount);
      game.events.emit('entity:healed', { target: owner, amount: healed });
      game.effects.ring(owner.position, 1.6, { color: def.color, life: 0.4 });
      game.effects.burst(owner.position, { color: def.color, count: 14, speed: 1.5, up: 4, gravity: -2, y: 0.4, life: 0.7 });
    },
  },

  speedBuff: {
    activate(game, owner, def) {
      owner.addBuff(def.id, def.duration, { speedMul: def.speedMul, trailColor: def.color });
      game.effects.ring(owner.position, 1.3, { color: def.color, life: 0.3 });
    },
  },
};
