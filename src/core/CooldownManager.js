// 統一冷卻時間管理：全遊戲唯一實例，key 格式為 owner.purpose

export class CooldownManager {
  #timers = new Map(); // key -> { remaining, duration }

  start(key, duration) {
    if (duration <= 0) {
      this.#timers.delete(key);
      return;
    }
    this.#timers.set(key, { remaining: duration, duration });
  }

  tick(dt) {
    for (const [key, timer] of this.#timers) {
      timer.remaining -= dt;
      if (timer.remaining <= 0) this.#timers.delete(key);
    }
  }

  isReady(key) {
    return !this.#timers.has(key);
  }

  remaining(key) {
    return this.#timers.get(key)?.remaining ?? 0;
  }

  // 0~1，1 表示冷卻完成
  progress(key) {
    const timer = this.#timers.get(key);
    return timer ? 1 - timer.remaining / timer.duration : 1;
  }

  reset(key) {
    this.#timers.delete(key);
  }

  resetAll() {
    this.#timers.clear();
  }
}
