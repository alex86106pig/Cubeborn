// 主動欄位（數字鍵 1~5）技能/道具資料定義；邏輯在 skillBehaviors.js
// mode: 'cooldown' 只受 CD 限制；'charges' 另有使用次數（CD 作為防連按間隔）

export const SKILLS = {
  heal: {
    id: 'heal',
    name: '治療藥水',
    icon: '✚',
    mode: 'charges',
    charges: 3,
    cooldown: 1.5,
    behavior: 'heal',
    amount: 35,
    color: 0x5dff7a,
  },
  sprint: {
    id: 'sprint',
    name: '疾跑',
    icon: '»',
    mode: 'cooldown',
    cooldown: 8,
    behavior: 'speedBuff',
    duration: 3,
    speedMul: 1.6,
    color: 0x6fe3ff,
  },
};
