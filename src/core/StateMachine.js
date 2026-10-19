// 通用有限狀態機：狀態物件提供 enter / update / exit / canExit，皆為選用

export class StateMachine {
  constructor(ctx, states, initial) {
    this.ctx = ctx;
    this.states = states;
    this.current = null;
    this.currentName = null;
    this.previousName = null;
    this.time = 0;      // 進入目前狀態後經過的秒數
    this.data = {};     // 每次進入狀態時重建，供狀態存放本次執行的暫存資料
    if (initial) this.change(initial);
  }

  change(name, data) {
    const next = this.states[name];
    if (!next) throw new Error(`Unknown state: ${name}`);
    const prev = this.current;
    if (prev?.canExit && !prev.canExit(this.ctx, name, this)) return false;
    prev?.exit?.(this.ctx, this);
    this.previousName = this.currentName;
    this.current = next;
    this.currentName = name;
    this.time = 0;
    this.data = { ...(data ?? {}) };
    next.enter?.(this.ctx, this.data, this);
    return true;
  }

  update(dt) {
    this.time += dt;
    this.current?.update?.(this.ctx, dt, this);
  }

  is(name) {
    return this.currentName === name;
  }
}
