// 音效：以 Web Audio API 即時合成（不使用音檔），訂閱 EventBus 播放；M 鍵靜音
// 遊戲程式以 events.emit('sfx:cue', { name }) 播放 CUES 中的音效，其他通知事件在 #bindEvents 對應
import { AUDIO } from '../core/config.js';

const MUTE_KEY = 'cubeborn.muted';

// ───────── 合成小工具（a = { ctx, out, t }）─────────

function tone(a, { type = 'sine', from, to = from, dur, vol = 0.3, attack = 0.005, delay = 0, filter = null }) {
  const { ctx } = a;
  const t = a.t + delay;
  const osc = ctx.createOscillator();
  osc.type = type;
  osc.frequency.setValueAtTime(from, t);
  osc.frequency.exponentialRampToValueAtTime(Math.max(1, to), t + dur);
  const gain = ctx.createGain();
  gain.gain.setValueAtTime(0.0001, t);
  gain.gain.exponentialRampToValueAtTime(vol, t + attack);
  gain.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  let node = osc;
  if (filter) {
    const f = ctx.createBiquadFilter();
    f.type = 'lowpass';
    f.frequency.value = filter;
    node.connect(f);
    node = f;
  }
  node.connect(gain).connect(a.out);
  osc.start(t);
  osc.stop(t + dur + 0.02);
}

function noise(a, { dur, vol = 0.3, type = 'bandpass', from = 1000, to = from, q = 1, attack = 0.003, delay = 0 }) {
  const { ctx } = a;
  const t = a.t + delay;
  const src = ctx.createBufferSource();
  src.buffer = a.noiseBuffer;
  src.loop = true;
  const f = ctx.createBiquadFilter();
  f.type = type;
  f.Q.value = q;
  f.frequency.setValueAtTime(from, t);
  f.frequency.exponentialRampToValueAtTime(Math.max(20, to), t + dur);
  const gain = ctx.createGain();
  gain.gain.setValueAtTime(0.0001, t);
  gain.gain.exponentialRampToValueAtTime(vol, t + attack);
  gain.gain.exponentialRampToValueAtTime(0.0001, t + dur);
  src.connect(f).connect(gain).connect(a.out);
  src.start(t, Math.random() * 1.5);
  src.stop(t + dur + 0.02);
}

// ───────── 音效表 ─────────

export const CUES = {
  // 玩家攻擊
  swing: (a) => noise(a, { dur: 0.13, vol: 0.32, from: 2200, to: 600, q: 1.5 }),
  swingHeavy: (a) => {
    noise(a, { dur: 0.2, vol: 0.3, from: 1500, to: 300, q: 1.2 });
    tone(a, { type: 'triangle', from: 140, to: 60, dur: 0.2, vol: 0.18 });
  },
  shieldBash: (a) => {
    noise(a, { dur: 0.25, vol: 0.28, type: 'lowpass', from: 1800, to: 200 });
    tone(a, { from: 110, to: 40, dur: 0.22, vol: 0.35 });
  },
  fireBolt: (a) => {
    tone(a, { type: 'sawtooth', from: 260, to: 900, dur: 0.14, vol: 0.12, filter: 1800 });
    noise(a, { dur: 0.18, vol: 0.12, type: 'highpass', from: 3000, to: 1500 });
  },
  arcaneCast: (a) => {
    tone(a, { type: 'triangle', from: 380, to: 1150, dur: 0.32, vol: 0.14 });
    tone(a, { type: 'sine', from: 760, to: 2300, dur: 0.32, vol: 0.06, delay: 0.03 });
  },
  explosion: (a) => {
    noise(a, { dur: 0.55, vol: 0.4, type: 'lowpass', from: 1600, to: 90 });
    tone(a, { from: 90, to: 30, dur: 0.45, vol: 0.4 });
  },

  // 命中
  hit: (a) => {
    noise(a, { dur: 0.06, vol: 0.25, type: 'highpass', from: 2500, to: 1200 });
    tone(a, { type: 'triangle', from: 200, to: 90, dur: 0.09, vol: 0.25 });
  },
  hitHeavy: (a) => {
    noise(a, { dur: 0.12, vol: 0.32, type: 'bandpass', from: 1800, to: 500, q: 0.8 });
    tone(a, { from: 150, to: 45, dur: 0.18, vol: 0.4 });
  },
  playerHurt: (a) => {
    tone(a, { type: 'square', from: 240, to: 110, dur: 0.16, vol: 0.14, filter: 1200 });
    noise(a, { dur: 0.1, vol: 0.18, type: 'lowpass', from: 900, to: 200 });
  },

  // 道具技能
  potion: (a) => {
    [523, 659, 784, 1047].forEach((f, i) => tone(a, { from: f, dur: 0.18, vol: 0.12, delay: i * 0.06 }));
    noise(a, { dur: 0.25, vol: 0.06, type: 'highpass', from: 4000, to: 6000 });
  },
  sprint: (a) => noise(a, { dur: 0.3, vol: 0.45, from: 400, to: 2400, q: 1.2 }),
  denied: (a) => {
    tone(a, { type: 'square', from: 150, dur: 0.06, vol: 0.08, filter: 900 });
    tone(a, { type: 'square', from: 120, dur: 0.07, vol: 0.08, filter: 900, delay: 0.08 });
  },

  // 敵人
  enemySpawn: (a) => noise(a, { dur: 0.45, vol: 0.25, type: 'lowpass', from: 400, to: 120, attack: 0.08 }),
  bowDraw: (a) => tone(a, { type: 'triangle', from: 180, to: 320, dur: 0.5, vol: 0.05, attack: 0.15, filter: 900 }),
  arrowShot: (a) => {
    noise(a, { dur: 0.09, vol: 0.18, from: 3500, to: 1400, q: 2 });
    tone(a, { type: 'triangle', from: 340, to: 240, dur: 0.12, vol: 0.12 });
  },
  enemyDeath: (a) => {
    for (let i = 0; i < 4; i++) {
      noise(a, { dur: 0.04, vol: 0.18, type: 'highpass', from: 2200 + i * 400, delay: i * 0.035 + Math.random() * 0.02 });
    }
    tone(a, { type: 'square', from: 260, to: 70, dur: 0.25, vol: 0.06, filter: 800 });
  },

  // Boss
  bossSlamWindup: (a) => tone(a, { type: 'sawtooth', from: 55, to: 110, dur: 0.6, vol: 0.12, attack: 0.3, filter: 400 }),
  bossSlam: (a) => {
    noise(a, { dur: 0.7, vol: 0.45, type: 'lowpass', from: 1200, to: 60 });
    tone(a, { from: 70, to: 25, dur: 0.6, vol: 0.5 });
  },
  bossChargeWindup: (a) => tone(a, { type: 'sawtooth', from: 70, to: 180, dur: 0.55, vol: 0.12, attack: 0.25, filter: 600 }),
  bossWallHit: (a) => {
    noise(a, { dur: 0.4, vol: 0.4, type: 'lowpass', from: 2000, to: 100 });
    tone(a, { from: 100, to: 35, dur: 0.35, vol: 0.4 });
  },
  bossSummon: (a) => {
    tone(a, { type: 'sine', from: 220, to: 660, dur: 0.9, vol: 0.1, attack: 0.3 });
    tone(a, { type: 'sine', from: 233, to: 700, dur: 0.9, vol: 0.08, attack: 0.3 });
  },
  enrage: (a) => {
    tone(a, { type: 'sawtooth', from: 65, to: 50, dur: 1.1, vol: 0.2, attack: 0.1, filter: 500 });
    noise(a, { dur: 1.0, vol: 0.2, type: 'lowpass', from: 700, to: 150, attack: 0.1 });
  },
  bossDeath: (a) => {
    noise(a, { dur: 1.6, vol: 0.4, type: 'lowpass', from: 900, to: 40, attack: 0.02 });
    tone(a, { type: 'sawtooth', from: 110, to: 30, dur: 1.5, vol: 0.18, filter: 400 });
  },

  // 流程
  waveStart: (a) => {
    tone(a, { from: 196, dur: 1.4, vol: 0.18 });
    tone(a, { from: 392, dur: 1.0, vol: 0.06 });
    tone(a, { from: 587, dur: 0.7, vol: 0.03 });
  },
  bossAppear: (a) => {
    tone(a, { from: 98, dur: 2.0, vol: 0.25 });
    tone(a, { from: 104, dur: 2.0, vol: 0.15 });
    tone(a, { type: 'sawtooth', from: 49, dur: 1.8, vol: 0.08, filter: 300 });
  },
  victory: (a) => {
    [262, 330, 392, 523].forEach((f, i) => tone(a, { type: 'triangle', from: f, dur: 0.9, vol: 0.13, delay: i * 0.14 }));
  },
  defeat: (a) => {
    [330, 262, 196, 131].forEach((f, i) => tone(a, { type: 'triangle', from: f, dur: 0.8, vol: 0.13, delay: i * 0.22 }));
  },
  pause: (a) => tone(a, { from: 660, to: 440, dur: 0.12, vol: 0.08 }),
  resume: (a) => tone(a, { from: 440, to: 660, dur: 0.12, vol: 0.08 }),
  restart: (a) => tone(a, { type: 'triangle', from: 330, to: 660, dur: 0.25, vol: 0.1 }),
};

// 同一音效的最短間隔（秒），避免一次打中多隻怪時爆音
const MIN_INTERVAL = { hit: 0.04, hitHeavy: 0.05, enemyDeath: 0.06, enemySpawn: 0.1, bowDraw: 0.15 };
const DEFAULT_INTERVAL = 0.03;

export class Sound {
  #ctx = null;
  #out = null;
  #noiseBuffer = null;
  #lastPlayed = new Map();

  constructor(game) {
    this.game = game;
    this.muted = false;
    try { this.muted = localStorage.getItem(MUTE_KEY) === '1'; } catch { /* 無法存取時預設有聲音 */ }

    // 瀏覽器規定必須在使用者操作後才能出聲（Node 的 check.js 沒有 window，略過）
    if (typeof window !== 'undefined') {
      const unlock = () => this.#ensureContext();
      window.addEventListener('pointerdown', unlock);
      window.addEventListener('keydown', unlock);
    }
    this.#bindEvents(game.events);
  }

  play(name) {
    const cue = CUES[name];
    if (!cue || this.muted || !this.#ctx || this.#ctx.state !== 'running') return;
    const now = this.#ctx.currentTime;
    const last = this.#lastPlayed.get(name) ?? -Infinity;
    if (now - last < (MIN_INTERVAL[name] ?? DEFAULT_INTERVAL)) return;
    this.#lastPlayed.set(name, now);
    cue({ ctx: this.#ctx, out: this.#out, t: now, noiseBuffer: this.#noiseBuffer });
  }

  toggleMute() {
    this.muted = !this.muted;
    try { localStorage.setItem(MUTE_KEY, this.muted ? '1' : '0'); } catch { /* 忽略 */ }
    if (this.#out) this.#out.gain.value = this.muted ? 0 : AUDIO.master * AUDIO.sfx;
    return this.muted;
  }

  #ensureContext() {
    if (!this.#ctx) {
      const Ctx = window.AudioContext ?? window.webkitAudioContext;
      if (!Ctx) return;
      this.#ctx = new Ctx();
      this.#out = this.#ctx.createGain();
      this.#out.gain.value = this.muted ? 0 : AUDIO.master * AUDIO.sfx;
      this.#out.connect(this.#ctx.destination);
      const len = this.#ctx.sampleRate * 2;
      this.#noiseBuffer = this.#ctx.createBuffer(1, len, this.#ctx.sampleRate);
      const data = this.#noiseBuffer.getChannelData(0);
      for (let i = 0; i < len; i++) data[i] = Math.random() * 2 - 1;
    }
    if (this.#ctx.state === 'suspended') this.#ctx.resume();
  }

  #bindEvents(ev) {
    ev.on('sfx:cue', ({ name }) => this.play(name));
    ev.on('entity:damaged', ({ target, isCrit }) => {
      if (target.team === 'player') this.play('playerHurt');
      else this.play(isCrit ? 'hitHeavy' : 'hit');
    });
    ev.on('entity:died', ({ entity }) => {
      if (entity.team !== 'enemy') return;
      this.play(entity === this.game.boss ? 'bossDeath' : 'enemyDeath');
    });
    ev.on('skill:used', ({ def }) => {
      if (def.id === 'heal') this.play('potion');
      else if (def.id === 'sprint') this.play('sprint');
    });
    ev.on('skill:onCooldown', () => this.play('denied'));
    ev.on('wave:started', ({ isBoss }) => this.play(isBoss ? 'bossAppear' : 'waveStart'));
    ev.on('boss:enraged', () => this.play('enrage'));
    ev.on('player:died', () => this.play('defeat'));
    ev.on('game:victory', () => this.play('victory'));
    ev.on('game:restart', () => this.play('restart'));
    ev.on('game:paused', ({ paused }) => this.play(paused ? 'pause' : 'resume'));
  }
}
