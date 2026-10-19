// 玩家：輸入轉換、雙層狀態機、武器裝備、主動欄位與增益效果
import * as THREE from 'three';
import { PLAYER } from '../core/config.js';
import { turnTowards } from '../core/math.js';
import { StateMachine } from '../core/StateMachine.js';
import { getStyle } from '../render/styles/index.js';
import { createWeaponModel } from '../render/WeaponModels.js';
import { ActiveSlots, SLOT_COUNT } from '../skills/ActiveSlots.js';
import { WEAPONS } from '../weapons/weaponDefs.js';
import { Entity } from './Entity.js';
import { ACTION_STATES, LOCOMOTION_STATES } from './playerStates.js';

const SLOT_KEYS = Array.from({ length: SLOT_COUNT }, (_, i) => `Digit${i + 1}`);

export class Player extends Entity {
  constructor(game) {
    super(game, { radius: PLAYER.radius, maxHp: PLAYER.maxHp, mass: PLAYER.mass, team: 'player' });
    this.attachModel(this.createModel());

    this.moveInput = new THREE.Vector3();
    this.aimPoint = new THREE.Vector3(0, 0, 5);
    this.forcedVelocity = new THREE.Vector3();
    this.hasForcedVelocity = false;
    this.walkPhase = 0;
    this.walkAmount = 0;
    this.weaponTilt = 0;
    this.comboStep = 0;
    this.comboTimer = 0;
    this.bufferedAction = null;   // { type: 'special' | 'slot', index?, time }
    this.buffs = new Map();       // id -> { remaining, speedMul, trailColor }
    this.trailTimer = 0;

    this.weapon = null;
    this.weaponModel = null;
    this.slots = new ActiveSlots(game, this, PLAYER.slots);
    this.locomotion = new StateMachine(this, LOCOMOTION_STATES, 'idle');
    this.action = new StateMachine(this, ACTION_STATES, null);
    this.equipWeapon(PLAYER.startWeapon);
  }

  createModel() {
    return getStyle().characters.knight();
  }

  rebuildModel() {
    this.weaponModel?.dispose();
    this.weaponModel = null;
    super.rebuildModel();
    this.#attachWeaponModel();
  }

  equipWeapon(id) {
    const def = WEAPONS[id];
    if (!def) throw new Error(`Unknown weapon: ${id}`);
    this.weapon = def;
    this.#attachWeaponModel();
    this.comboStep = 0;
    this.comboTimer = 0;
    this.action.change('ready');
  }

  #attachWeaponModel() {
    this.weaponModel?.dispose();
    this.weaponModel = createWeaponModel(this.weapon.model);
    this.model.handR.add(this.weaponModel.main);
    if (this.weaponModel.offhand) this.model.armL.add(this.weaponModel.offhand);
    this.model.accessories = [this.weaponModel.kit];
  }

  addBuff(id, duration, mods) {
    this.buffs.set(id, { remaining: duration, ...mods });
  }

  get speedMul() {
    let mul = 1;
    for (const buff of this.buffs.values()) mul *= buff.speedMul ?? 1;
    return mul;
  }

  update(dt) {
    this.#tickTimers(dt);
    if (this.isDead) {
      this.locomotion.update(dt);
      return;
    }

    this.#readInput();
    this.action.update(dt);

    const data = this.action.data;
    if (this.hasForcedVelocity) {
      this.velocity.copy(this.forcedVelocity);
    } else {
      const speed = PLAYER.moveSpeed * (data.moveSpeedMul ?? 1) * this.speedMul;
      this.velocity.copy(this.moveInput).multiplyScalar(speed);
    }

    if (!data.lockFacing) {
      const target = Math.atan2(this.aimPoint.x - this.position.x, this.aimPoint.z - this.position.z);
      this.facing = turnTowards(this.facing, target, PLAYER.turnSpeed * dt);
    }

    this.locomotion.update(dt);
    this.#emitTrail(dt);
  }

  #tickTimers(dt) {
    this.comboTimer = Math.max(0, this.comboTimer - dt);
    for (const [id, buff] of this.buffs) {
      buff.remaining -= dt;
      if (buff.remaining <= 0) this.buffs.delete(id);
    }
    if (this.bufferedAction) {
      this.bufferedAction.time -= dt;
      if (this.bufferedAction.time <= 0) this.bufferedAction = null;
    }
  }

  #readInput() {
    const input = this.game.input;
    const r = this.game.renderer;
    const x = (input.isDown('KeyD') ? 1 : 0) - (input.isDown('KeyA') ? 1 : 0);
    const y = (input.isDown('KeyW') ? 1 : 0) - (input.isDown('KeyS') ? 1 : 0);
    this.moveInput.set(0, 0, 0)
      .addScaledVector(r.screenRight, x)
      .addScaledVector(r.screenForward, y);
    if (this.moveInput.lengthSq() > 1) this.moveInput.normalize();

    r.screenToGround(input.mouse.x, input.mouse.y, this.aimPoint);

    if (input.mouse.rightPressed) this.#buffer({ type: 'special' });
    SLOT_KEYS.forEach((code, index) => {
      if (input.wasPressed(code)) this.#buffer({ type: 'slot', index });
    });
  }

  #buffer(action) {
    this.bufferedAction = { ...action, time: PLAYER.actionBufferTime };
  }

  #emitTrail(dt) {
    let color = null;
    for (const buff of this.buffs.values()) if (buff.trailColor) color = buff.trailColor;
    if (color === null || this.velocity.lengthSq() < 1) return;
    this.trailTimer -= dt;
    if (this.trailTimer > 0) return;
    this.trailTimer = 0.04;
    this.game.effects.burst(this.position, { color, count: 1, speed: 0.5, up: 0.5, gravity: 0, y: 0.3, size: 0.18, life: 0.35 });
  }

  onDamaged(amount) {
    if (this.isDead || amount <= 0) return;
    this.invulnTimer = PLAYER.invulnTime;
    this.game.renderer.shake(0.25, 0.2);
    // 特殊技期間有霸體，不會被打斷
    if (!this.action.is('special')) this.action.change('stagger');
  }

  onDied() {
    this.action.change('ready'); // 讓進行中的動作執行 exit 清理
    this.hasForcedVelocity = false;
    this.locomotion.change('dead');
    this.game.events.emit('player:died', { player: this });
  }

  syncModel() {
    super.syncModel();
    this.weaponModel?.sync(this);
    // 無敵時間閃爍
    this.model.root.visible = this.isDead || this.invulnTimer <= 0 || Math.floor(this.invulnTimer * 20) % 2 === 0;
  }
}
