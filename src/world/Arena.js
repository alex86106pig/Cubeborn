// 場地：依造型風格建立地面、邊界與裝飾；碰撞邊界固定為 WORLD.arenaHalfSize 的正方形
import { WORLD } from '../core/config.js';

export class Arena {
  constructor(game) {
    this.game = game;
    this.halfSize = WORLD.arenaHalfSize;
    this.current = null;
  }

  applyStyle(style) {
    const scene = this.game.renderer.scene;
    if (this.current) {
      scene.remove(this.current.group);
      this.current.kit.dispose();
    }
    this.current = style.buildArena(this.halfSize);
    scene.add(this.current.group);
  }
}
