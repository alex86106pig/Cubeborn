// 武器外觀：依目前造型風格建立劍盾、法杖，並提供每幀姿勢同步
import { getStyle } from './styles/index.js';

export function createWeaponModel(kind) {
  const build = getStyle().weapons[kind];
  if (!build) throw new Error(`Unknown weapon model: ${kind}`);
  const parts = build(); // { kit, main, offhand, gem? }

  return {
    ...parts,
    // 法杖的世界傾角由 player.weaponTilt 決定，與手臂角度脫鉤
    sync(player) {
      if (kind !== 'staff') return;
      parts.main.rotation.x = player.weaponTilt - player.model.armR.rotation.x;
      if (parts.gem) parts.gem.rotation.y += 0.05;
    },
    dispose() {
      parts.main.removeFromParent();
      parts.offhand?.removeFromParent();
      parts.kit.dispose();
    },
  };
}
