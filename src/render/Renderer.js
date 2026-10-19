// WebGLRenderer、場景、燈光、正交等距相機（平滑跟隨與畫面震動）
import * as THREE from 'three';
import { CAMERA } from '../core/config.js';

const UP = new THREE.Vector3(0, 1, 0);
const _ndc = new THREE.Vector2();
const _shake = new THREE.Vector3();
const _project = new THREE.Vector3();

export class Renderer {
  constructor(container) {
    this.webgl = new THREE.WebGLRenderer({ antialias: true });
    this.webgl.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.webgl.shadowMap.enabled = true;
    this.webgl.shadowMap.type = THREE.PCFSoftShadowMap;
    container.appendChild(this.webgl.domElement);
    this.domElement = this.webgl.domElement;

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x161c2b);

    this.camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 200);
    this.cameraTarget = new THREE.Vector3();
    this.cameraOffset = new THREE.Vector3(
      Math.cos(CAMERA.elevation) * Math.sin(CAMERA.azimuth),
      Math.sin(CAMERA.elevation),
      Math.cos(CAMERA.elevation) * Math.cos(CAMERA.azimuth),
    ).multiplyScalar(CAMERA.distance);

    // 螢幕方向在地面上的投影，供 WASD 以螢幕為準移動
    this.screenForward = this.cameraOffset.clone().setY(0).normalize().negate();
    this.screenRight = new THREE.Vector3().crossVectors(this.screenForward, UP).normalize();
    this.screenUp = new THREE.Vector3().crossVectors(this.screenRight, this.cameraOffset).normalize();

    this.raycaster = new THREE.Raycaster();
    this.aimPlane = new THREE.Plane(UP, -CAMERA.aimPlaneHeight);

    this.#setupLights();

    this.shakeStrength = 0;
    this.shakeTime = 0;
    this.shakeDuration = 0;

    window.addEventListener('resize', () => this.resize());
    this.resize();
  }

  #setupLights() {
    this.hemi = new THREE.HemisphereLight(0xcfe3ff, 0x4a3b28, 1.1);
    this.scene.add(this.hemi);
    const sun = new THREE.DirectionalLight(0xfff3dd, 1.8);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    const s = 24;
    Object.assign(sun.shadow.camera, { left: -s, right: s, top: s, bottom: -s, near: 1, far: 80 });
    sun.shadow.bias = -0.0005;
    this.sunOffset = new THREE.Vector3(-10, 22, 8);
    this.sun = sun;
    this.scene.add(sun, sun.target);
  }

  // 套用造型風格的背景與燈光
  applyEnvironment(env) {
    this.scene.background.set(env.background);
    this.hemi.color.set(env.hemiSky);
    this.hemi.groundColor.set(env.hemiGround);
    this.hemi.intensity = env.hemiIntensity;
    this.sun.color.set(env.sunColor);
    this.sun.intensity = env.sunIntensity;
  }

  resize() {
    const w = window.innerWidth;
    const h = window.innerHeight;
    const aspect = w / h;
    const H = CAMERA.viewHalfHeight;
    Object.assign(this.camera, { left: -H * aspect, right: H * aspect, top: H, bottom: -H });
    this.camera.updateProjectionMatrix();
    this.webgl.setSize(w, h);
  }

  shake(strength, duration = 0.2) {
    const current = this.shakeDuration > 0 ? this.shakeStrength * (this.shakeTime / this.shakeDuration) : 0;
    if (strength < current) return;
    this.shakeStrength = strength;
    this.shakeTime = duration;
    this.shakeDuration = duration;
  }

  follow(target, dt, snap = false) {
    if (snap) this.cameraTarget.copy(target);
    else this.cameraTarget.lerp(target, 1 - Math.exp(-CAMERA.followSharpness * dt));

    _shake.set(0, 0, 0);
    if (this.shakeTime > 0) {
      this.shakeTime = Math.max(0, this.shakeTime - dt);
      const k = this.shakeStrength * (this.shakeTime / this.shakeDuration);
      _shake.addScaledVector(this.screenRight, (Math.random() * 2 - 1) * k)
        .addScaledVector(this.screenUp, (Math.random() * 2 - 1) * k);
    }

    this.camera.position.copy(this.cameraTarget).add(this.cameraOffset).add(_shake);
    this.camera.lookAt(_project.copy(this.cameraTarget).add(_shake));

    this.sun.position.copy(this.cameraTarget).add(this.sunOffset);
    this.sun.target.position.copy(this.cameraTarget);
  }

  // 滑鼠 NDC 座標投射到瞄準平面；未命中時回傳 null
  screenToGround(ndcX, ndcY, out) {
    _ndc.set(ndcX, ndcY);
    this.raycaster.setFromCamera(_ndc, this.camera);
    return this.raycaster.ray.intersectPlane(this.aimPlane, out);
  }

  // 世界座標轉成 CSS 像素座標
  worldToScreen(position, out) {
    _project.copy(position).project(this.camera);
    out.x = (_project.x * 0.5 + 0.5) * window.innerWidth;
    out.y = (-_project.y * 0.5 + 0.5) * window.innerHeight;
    return out;
  }

  render() {
    this.webgl.render(this.scene, this.camera);
  }
}
