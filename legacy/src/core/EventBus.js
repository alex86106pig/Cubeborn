// 發布/訂閱事件匯流排：用於通知 UI 與特效，不用於核心流程控制

export class EventBus {
  #handlers = new Map();

  on(name, handler) {
    if (!this.#handlers.has(name)) this.#handlers.set(name, new Set());
    this.#handlers.get(name).add(handler);
    return () => this.off(name, handler);
  }

  off(name, handler) {
    this.#handlers.get(name)?.delete(handler);
  }

  emit(name, payload = {}) {
    const set = this.#handlers.get(name);
    if (!set) return;
    for (const handler of [...set]) handler(payload);
  }
}
