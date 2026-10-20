// 模型檢視頁：並排展示目前風格的騎士、近戰怪、遠程怪、Boss，不必進遊戲即可檢查模型
import * as THREE from 'three';
import { STYLES } from './render/styles/index.js';

const DESCRIPTIONS = {
  darkFantasy: '寫實比例、硬朗多面體、月夜墓地。',
};
const KINDS = ['knight', 'melee', 'ranged', 'boss'];

const renderer = new THREE.WebGLRenderer({ antialias: true });
renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
renderer.shadowMap.enabled = true;
renderer.setScissorTest(true);
document.getElementById('canvas-host').appendChild(renderer.domElement);

const labels = document.getElementById('labels');
const rows = STYLES.map((style) => {
  const scene = new THREE.Scene();
  scene.background = new THREE.Color(style.environment.background);
  const env = style.environment;
  scene.add(new THREE.HemisphereLight(env.hemiSky, env.hemiGround, env.hemiIntensity));
  const sun = new THREE.DirectionalLight(env.sunColor, env.sunIntensity);
  sun.position.set(-6, 12, 8);
  sun.castShadow = true;
  sun.shadow.mapSize.set(1024, 1024);
  Object.assign(sun.shadow.camera, { left: -12, right: 12, top: 8, bottom: -8 });
  scene.add(sun);

  const arena = style.buildArena(11);
  arena.group.position.x = 6;
  scene.add(arena.group);

  const rigs = KINDS.map((kind, i) => {
    const rig = style.characters[kind]();
    rig.root.position.set(i * 4, 0, 0);
    if (kind === 'knight') {
      const weapon = style.weapons.swordShield();
      rig.handR.add(weapon.main);
      if (weapon.offhand) rig.armL.add(weapon.offhand);
    }
    scene.add(rig.root);
    return rig;
  });

  const camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 100);

  const row = document.createElement('div');
  row.className = 'row';
  row.innerHTML = `<div class="row-title">${style.name}</div><div class="row-desc">${DESCRIPTIONS[style.id]}</div>`;
  const cells = document.createElement('div');
  cells.className = 'cells';
  for (const kind of KINDS) {
    const label = document.createElement('div');
    label.className = 'cell-label';
    label.textContent = style.names[kind];
    cells.appendChild(label);
  }
  row.appendChild(cells);
  labels.appendChild(row);

  return { style, scene, camera, rigs };
});

let yaw = 0.6;
let dragging = false;
let lastX = 0;
window.addEventListener('mousedown', (e) => { dragging = true; lastX = e.clientX; });
window.addEventListener('mouseup', () => { dragging = false; });
window.addEventListener('mousemove', (e) => {
  if (!dragging) return;
  yaw += (e.clientX - lastX) * 0.01;
  lastX = e.clientX;
});

function resize() {
  renderer.setSize(window.innerWidth, window.innerHeight);
}
window.addEventListener('resize', resize);
resize();

const clock = new THREE.Clock();
let lastT = 0;
function frame() {
  const t = clock.getElapsedTime();
  if (!dragging) yaw += (t - lastT) * 0.3;
  lastT = t;
  const w = window.innerWidth;
  const h = window.innerHeight;
  const rowH = h / rows.length;
  const halfH = 2.6;
  const halfW = halfH * (w / rowH);

  rows.forEach((row, r) => {
    row.rigs.forEach((rig, i) => {
      // 依視窗寬度平均分配四欄，對齊 DOM 標籤
      rig.root.position.x = 6 + (i - 1.5) * (halfW / 2);
      rig.root.rotation.y = yaw;
      const phase = t * 4 + i;
      rig.legR.rotation.x = Math.sin(phase) * 0.5;
      rig.legL.rotation.x = -Math.sin(phase) * 0.5;
      rig.armR.rotation.x = -0.4 - Math.sin(phase) * 0.3;
      rig.armL.rotation.x = -0.2 + Math.sin(phase) * 0.3;
    });

    const cam = row.camera;
    Object.assign(cam, { left: -halfW, right: halfW, top: halfH, bottom: -halfH });
    cam.updateProjectionMatrix();
    cam.position.set(6, 5.5, 14);
    cam.lookAt(6, 1.8, 0);

    const y = h - (r + 1) * rowH; // WebGL 視窗原點在左下
    renderer.setViewport(0, y, w, rowH);
    renderer.setScissor(0, y, w, rowH);
    renderer.render(row.scene, cam);
  });
  requestAnimationFrame(frame);
}
frame();
