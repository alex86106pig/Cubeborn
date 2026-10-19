// 場地：方塊草地、石牆邊界、外圍泥土地
import * as THREE from 'three';
import { WORLD } from '../core/config.js';

const TILE_PX = 16;

function createGrassTexture(tiles) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = tiles * TILE_PX;
  const ctx = canvas.getContext('2d');
  for (let ty = 0; ty < tiles; ty++) {
    for (let tx = 0; tx < tiles; tx++) {
      const base = 0.36 + Math.random() * 0.06 + ((tx + ty) % 2) * 0.025;
      ctx.fillStyle = `hsl(100, 42%, ${base * 100}%)`;
      ctx.fillRect(tx * TILE_PX, ty * TILE_PX, TILE_PX, TILE_PX);
      // 方塊內的像素雜訊
      for (let i = 0; i < 10; i++) {
        const l = base + (Math.random() - 0.5) * 0.12;
        ctx.fillStyle = `hsl(${95 + Math.random() * 15}, 45%, ${l * 100}%)`;
        ctx.fillRect(tx * TILE_PX + Math.floor(Math.random() * 14), ty * TILE_PX + Math.floor(Math.random() * 14), 2, 2);
      }
    }
  }
  const texture = new THREE.CanvasTexture(canvas);
  texture.magFilter = THREE.NearestFilter;
  texture.minFilter = THREE.NearestMipmapLinearFilter;
  texture.colorSpace = THREE.SRGBColorSpace;
  return texture;
}

export class Arena {
  constructor(game) {
    this.halfSize = WORLD.arenaHalfSize;
    const scene = game.renderer.scene;
    const size = this.halfSize * 2;

    const ground = new THREE.Mesh(
      new THREE.PlaneGeometry(size, size),
      new THREE.MeshLambertMaterial({ map: createGrassTexture(size) }),
    );
    ground.rotation.x = -Math.PI / 2;
    ground.receiveShadow = true;
    scene.add(ground);

    const outside = new THREE.Mesh(
      new THREE.PlaneGeometry(200, 200),
      new THREE.MeshLambertMaterial({ color: 0x3b2f22 }),
    );
    outside.rotation.x = -Math.PI / 2;
    outside.position.y = -0.02;
    outside.receiveShadow = true;
    scene.add(outside);

    scene.add(this.#createWalls());
  }

  #createWalls() {
    const h = this.halfSize;
    const cells = [];
    for (let i = -h - 1; i <= h; i++) {
      cells.push([i + 0.5, -h - 0.5], [i + 0.5, h + 0.5]);
    }
    for (let i = -h; i < h; i++) {
      cells.push([-h - 0.5, i + 0.5], [h + 0.5, i + 0.5]);
    }

    const blocks = [];
    for (const [x, z] of cells) {
      const height = Math.random() < 0.35 ? 2 : 1;
      for (let y = 0; y < height; y++) blocks.push([x, y + 0.5, z]);
    }

    const mesh = new THREE.InstancedMesh(
      new THREE.BoxGeometry(1, 1, 1),
      new THREE.MeshLambertMaterial({ color: 0xffffff }),
      blocks.length,
    );
    const matrix = new THREE.Matrix4();
    const color = new THREE.Color();
    blocks.forEach(([x, y, z], i) => {
      matrix.makeTranslation(x, y, z);
      mesh.setMatrixAt(i, matrix);
      const mossy = Math.random() < 0.15;
      color.setHSL(mossy ? 0.28 : 0.6, mossy ? 0.2 : 0.04, 0.42 + Math.random() * 0.12);
      mesh.setColorAt(i, color);
    });
    mesh.castShadow = true;
    mesh.receiveShadow = true;
    return mesh;
  }
}
