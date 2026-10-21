// 進入點：建立 Game 並啟動
import { Game } from './Game.js';

const game = new Game(document.getElementById('game'), document.getElementById('hud'));
game.start();

// 除錯用：在 Console 可透過 __game 檢查狀態
window.__game = game;
