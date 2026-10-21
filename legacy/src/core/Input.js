// 鍵盤/滑鼠狀態：提供「按住」與「本步按下」查詢，按下事件保留到下一個邏輯步才清除

const PREVENT_DEFAULT = new Set(['F1', 'F2', 'Space', 'Tab']);

export class Input {
  #down = new Set();
  #pressed = new Set();

  constructor(canvas) {
    this.canvas = canvas;
    this.mouse = { x: 0, y: 0, left: false, right: false, leftPressed: false, rightPressed: false };

    window.addEventListener('keydown', (e) => {
      if (PREVENT_DEFAULT.has(e.code)) e.preventDefault();
      if (!e.repeat) this.#pressed.add(e.code);
      this.#down.add(e.code);
    });
    window.addEventListener('keyup', (e) => this.#down.delete(e.code));
    window.addEventListener('blur', () => this.#releaseAll());

    canvas.addEventListener('mousedown', (e) => {
      if (e.button === 0) { this.mouse.left = true; this.mouse.leftPressed = true; }
      if (e.button === 2) { this.mouse.right = true; this.mouse.rightPressed = true; }
    });
    window.addEventListener('mouseup', (e) => {
      if (e.button === 0) this.mouse.left = false;
      if (e.button === 2) this.mouse.right = false;
    });
    window.addEventListener('mousemove', (e) => {
      const rect = canvas.getBoundingClientRect();
      this.mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      this.mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;
    });
    canvas.addEventListener('contextmenu', (e) => e.preventDefault());
  }

  isDown(code) {
    return this.#down.has(code);
  }

  wasPressed(code) {
    return this.#pressed.has(code);
  }

  // 讀取並清除「本步按下」：給每個渲染幀處理的系統鍵用（Esc、M），避免一次按鍵被處理兩次
  consumePressed(code) {
    return this.#pressed.delete(code);
  }

  // 每個固定邏輯步結束時呼叫
  endStep() {
    this.#pressed.clear();
    this.mouse.leftPressed = false;
    this.mouse.rightPressed = false;
  }

  #releaseAll() {
    this.#down.clear();
    this.mouse.left = false;
    this.mouse.right = false;
  }
}
