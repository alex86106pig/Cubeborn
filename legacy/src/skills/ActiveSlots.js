// 數字鍵 1~5 主動欄位：裝備、使用條件判斷（CD、次數、技能自訂條件）與觸發
import { SKILLS } from './skillDefs.js';
import { SKILL_BEHAVIORS } from './skillBehaviors.js';

export const SLOT_COUNT = 5;

export class ActiveSlots {
  constructor(game, owner, ids) {
    this.game = game;
    this.owner = owner;
    this.slots = Array.from({ length: SLOT_COUNT }, (_, i) => this.#createSlot(ids[i]));
  }

  #createSlot(id) {
    if (!id) return null;
    const def = SKILLS[id];
    if (!def) throw new Error(`Unknown skill: ${id}`);
    return { def, charges: def.mode === 'charges' ? def.charges : Infinity };
  }

  cdKey(index) {
    return `player.slot${index + 1}`;
  }

  canUse(index) {
    const slot = this.slots[index];
    if (!slot || slot.charges <= 0) return false;
    if (!this.game.cooldowns.isReady(this.cdKey(index))) return false;
    const behavior = SKILL_BEHAVIORS[slot.def.behavior];
    return behavior.canUse ? behavior.canUse(this.game, this.owner, slot.def) : true;
  }

  use(index) {
    if (!this.canUse(index)) return false;
    const slot = this.slots[index];
    SKILL_BEHAVIORS[slot.def.behavior].activate(this.game, this.owner, slot.def);
    if (slot.def.mode === 'charges') slot.charges--;
    const key = this.cdKey(index);
    this.game.cooldowns.start(key, slot.def.cooldown);
    this.game.events.emit('skill:used', { key, def: slot.def });
    return true;
  }

  // 無法使用時給 HUD 的回饋
  notifyBlocked(index) {
    if (this.slots[index]) this.game.events.emit('skill:onCooldown', { key: this.cdKey(index) });
  }
}
