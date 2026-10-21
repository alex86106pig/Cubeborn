// 平面圓形碰撞：存活實體依質量比例互相推開，並限制在場地內

export function separateEntities(entities) {
  for (let i = 0; i < entities.length; i++) {
    const a = entities[i];
    if (a.isDead) continue;
    for (let j = i + 1; j < entities.length; j++) {
      const b = entities[j];
      if (b.isDead) continue;
      let dx = b.position.x - a.position.x;
      let dz = b.position.z - a.position.z;
      const minDist = a.radius + b.radius;
      let distSq = dx * dx + dz * dz;
      if (distSq >= minDist * minDist) continue;
      if (distSq < 1e-8) {
        dx = Math.random() - 0.5;
        dz = Math.random() - 0.5;
        distSq = dx * dx + dz * dz;
      }
      const dist = Math.sqrt(distSq);
      const overlap = minDist - dist;
      const nx = dx / dist;
      const nz = dz / dist;
      const total = a.mass + b.mass;
      const pushA = overlap * (b.mass / total);
      const pushB = overlap * (a.mass / total);
      a.position.x -= nx * pushA;
      a.position.z -= nz * pushA;
      b.position.x += nx * pushB;
      b.position.z += nz * pushB;
    }
  }
}

export function clampToArena(entity, halfSize) {
  const limit = halfSize - entity.radius;
  const p = entity.position;
  if (p.x < -limit) p.x = -limit;
  else if (p.x > limit) p.x = limit;
  if (p.z < -limit) p.z = -limit;
  else if (p.z > limit) p.z = limit;
}
