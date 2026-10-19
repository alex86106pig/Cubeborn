# Cubeborn 專案開發守則

> 本文件是專案的**唯一事實來源**。任何與本文件衝突的程式碼都視為 bug；架構變更時必須同步更新本文件。

---

## 1. 專案概要

| 項目 | 內容 |
|---|---|
| 類型 | 3D 等距俯視角 Roguelike 動作遊戲（網頁版原型） |
| 美術風格 | 程式生成的低多邊形奇幻角色（不使用外部模型與貼圖），目前有三種候選造型可用 F3 切換 |
| 目前階段 | Phase 1：核心戰鬥、5 波制（含 Boss 戰）的一局流程、造型選定 |
| 不在 Phase 1 範圍 | 職業選擇、房間/關卡生成、升級、掉落、武器切換、存檔、音效 |

---

## 2. 技術棧

| 項目 | 選擇 | 理由 |
|---|---|---|
| 語言 | 原生 JavaScript（ES2022），ES6 Modules | 零建置、易讀 |
| 3D 引擎 | Three.js `0.170.0`，透過 `importmap` 從 jsDelivr CDN 載入 | 不需 npm |
| 建置工具 | 無。日後需要打包上線再導入 Vite | 降低初期複雜度 |
| 本機伺服器 | `tools/serve.ps1`（PowerShell 內建 HttpListener） | ES Modules 不能用 `file://` 開啟；本機未安裝 Node/Python |
| 物理 | 不用物理引擎，自寫圓形碰撞 | 俯視角動作遊戲只需 2D 平面碰撞 |
| UI | DOM + CSS 疊在 canvas 上 | 好排版、好除錯 |
| 版控 | git，每個版本一個 commit + tag | 可回溯 |

**啟動方式**：在專案根目錄執行 `powershell -ExecutionPolicy Bypass -File tools/serve.ps1`，瀏覽器開 `http://localhost:5173`。`.claude/launch.json` 也有同樣設定（名稱 `cubeborn`），可供 Claude 的瀏覽器預覽使用。

**AI 測試技巧**：瀏覽器分頁在背景時 `requestAnimationFrame` 會暫停。測試邏輯時可在 Console 透過 `__game.update(1/60)` 加 `__game.input.endStep()` 手動推進邏輯步。

---

## 3. 目錄結構

```
Cubeborn/
├─ CLAUDE.md                  AI 開工入口（自動載入）
├─ PROJECT_GUIDELINES.md      本文件
├─ CHANGELOG.md               版本紀錄
├─ index.html                 遊戲頁面、importmap、HUD 容器
├─ preview.html               造型比較頁（三種風格並排）
├─ css/style.css              HUD 與頁面樣式
├─ tools/serve.ps1            本機靜態伺服器
└─ src/
   ├─ main.js                 遊戲進入點：建立 Game 並啟動
   ├─ preview.js              造型比較頁進入點
   ├─ Game.js                 遊戲主體（組合根）：持有所有系統、主迴圈、命中停頓、重新開始、造型切換、通關
   ├─ core/                   與遊戲內容無關的底層機制
   │  ├─ config.js            全域可調參數（迴圈、世界、相機、玩家、生成、除錯開關）
   │  ├─ version.js           VERSION 常數（與 CHANGELOG 同步）
   │  ├─ math.js              角度、插值、緩動等數學小工具
   │  ├─ EventBus.js          發布/訂閱事件匯流排
   │  ├─ StateMachine.js      通用有限狀態機
   │  ├─ CooldownManager.js   統一冷卻時間管理
   │  └─ Input.js             鍵盤/滑鼠狀態，提供「本步按下」查詢
   ├─ render/
   │  ├─ Renderer.js          WebGLRenderer、場景、燈光、正交相機與跟隨、套用環境
   │  ├─ rig.js               角色骨架 Rig、零件組 PartKit、幾何體工廠 G、各風格材質工廠
   │  ├─ environment.js       低多邊形地面、邊界點位、裝飾散佈工具
   │  ├─ WeaponModels.js      依目前風格建立玩家武器外觀並同步姿勢
   │  ├─ Effects.js           粒子、揮砍弧光、衝擊環、圓形/直線預警
   │  └─ styles/              造型風格（介面見第 14 節）
   │     ├─ index.js          風格登錄、目前風格、切換（記在 localStorage）
   │     ├─ storybook.js      A 童話繪本
   │     ├─ darkFantasy.js    B 暗黑幻想
   │     └─ heroic.js         C 英雄卡通
   ├─ entities/
   │  ├─ Entity.js            實體基底：位置、速度、半徑、血量、擊退、受傷/死亡、模型重建
   │  ├─ Player.js            玩家：雙層狀態機、武器、主動欄位
   │  ├─ playerStates.js      玩家的移動層與動作層狀態定義
   │  ├─ Enemy.js             敵人基底：波次倍率、共用狀態（spawn/hurt/dead）、接觸傷害
   │  ├─ enemyDefs.js         敵人資料定義（grunt / archer / boss）
   │  ├─ enemies/
   │  │  ├─ MeleeEnemy.js     近戰小怪：追擊、接觸傷害
   │  │  ├─ RangedEnemy.js    遠程小怪：保持距離、瞄準預備、發射投射物
   │  │  └─ Boss.js           Boss：重砸、衝鋒、召喚、狂暴
   │  └─ Projectile.js        投射物（可自訂外觀；可設定範圍爆炸）
   ├─ combat/
   │  ├─ Combat.js            傷害結算、命中判定查詢（扇形、圓形）、擊退計算
   │  └─ Physics.js           圓形碰撞分離、場地邊界
   ├─ weapons/
   │  ├─ weaponDefs.js        武器資料定義（劍盾、法杖）
   │  └─ weaponBehaviors.js   武器攻擊/特殊技的行為函式
   ├─ skills/
   │  ├─ skillDefs.js         主動技能/道具資料定義（治療藥水、疾跑）
   │  ├─ skillBehaviors.js    技能行為：canUse（選用條件）與 activate（效果）
   │  └─ ActiveSlots.js       數字鍵 1~5 主動欄位：裝備、觸發、CD 或次數
   ├─ world/
   │  ├─ Arena.js             依風格建立場地；碰撞邊界固定
   │  ├─ waveDefs.js          波次表與波次數值成長
   │  └─ Spawner.js           分波生成、Boss 出場、召喚用 spawnAt
   └─ ui/
      └─ HUD.js               血條、技能欄、波次/時間、Boss 血條、橫幅、死亡/勝利畫面
```

規則：
- **一個檔案一個主要職責**，單檔超過約 300 行就該考慮拆分。
- `core/` 不得 import 任何其他目錄（依賴只能由上往下：內容 → core）。`src/Game.js` 是唯一的組合根，負責建立並串接所有系統。
- 模組之間優先透過 **建構時注入**（傳入 `game`）或 **EventBus** 溝通，禁止使用全域變數（除錯用的 `window.__game` 例外）。

---

## 4. 座標、單位與時間

- **單位**：1 單位 = 1 個方塊 ≈ 1 公尺。人形高約 2 單位。
- **座標**：Y 軸朝上，地面 `y = 0`。遊戲邏輯只在 XZ 平面運算（`x`、`z`），Y 只用於視覺。
- **角度**：弧度。角色朝向 `facing` 以 XZ 平面角度表示。
- **時間**：秒。所有速度、CD、持續時間都以秒為單位。
- **主迴圈**：固定步長 `FIXED_DT = 1/60` 更新邏輯（累加器模式，單幀最多補 5 步），渲染每幀一次。遊戲邏輯一律使用傳入的 `dt`，禁止直接讀 `performance.now()`。
- **命中停頓**：呼叫 `game.hitStop(秒)`。期間 `Game` 以真實時間倒數並把邏輯時間縮放到 5%，所有系統自動受影響，不需各自處理。
- **輸入**：`Input` 的「本步按下」狀態保留到下一個邏輯步執行完才清除，高更新率螢幕也不會漏按。
- **更新順序**（`Game.update`）：系統按鍵 → CD tick → 玩家 → 敵人 → 投射物 → 位移積分 → 碰撞分離 → 場地限制 → 生成器 → 特效 → 清除已移除物件。模型同步與 HUD 在每個渲染幀執行。

---

## 5. 操作對應

| 輸入 | 功能 |
|---|---|
| WASD | 移動，**以螢幕方向為準**（W = 畫面上方，世界座標為斜向） |
| 滑鼠游標 | 射線投射到地面平面得到瞄準點，角色面朝該點 |
| 滑鼠左鍵 | 普通攻擊（按住可連續攻擊） |
| 滑鼠右鍵 | 武器特殊技（受 CD 管理） |
| 1 ~ 5 | 主動欄位（受 CD 或次數管理） |
| R | 死亡或通關後重新開始 |
| F1 | 除錯：切換劍盾 / 法杖（非正式武器切換系統） |
| F2 | 除錯：顯示碰撞與命中範圍 |
| F3 | 切換造型風格（A / B / C，記在瀏覽器） |

右鍵選單在 canvas 上一律停用。

---

## 6. 狀態機規範

### 6.1 通用 StateMachine
- 狀態是一個物件：`{ enter(ctx, data), update(ctx, dt), exit(ctx), canExit?(ctx, next) }`，皆為選用。
- 只能透過 `fsm.change(name, data)` 切換；**禁止**直接改 `fsm.current`。
- 每個狀態可讀 `fsm.time`（進入此狀態後經過的秒數）。
- 狀態名稱用 camelCase 字串，例如 `'idle'`、`'attack'`。

### 6.2 玩家雙層狀態機
| 層 | 狀態 | 說明 |
|---|---|---|
| 移動層 `locomotion` | `idle` / `move` / `dead` | 只處理位移與腿部動畫 |
| 動作層 `action` | `ready` / `attack` / `special` / `useItem` / `stagger` | 處理攻擊、技能、受擊硬直與上半身動畫 |

- 兩層各自 update，**動作層可以限制移動層**：每個動作狀態宣告 `moveSpeedMul`（例如劍攻擊 0.3、法杖 0.8、硬直 0）。
- 攻擊類動作固定分三段：**`windup`（前搖） → `active`（判定） → `recovery`（後搖）**。命中判定只在 `active` 期間生效，每次出手同一目標只命中一次。
- 時間長度一律來自武器/技能的資料定義，狀態本身不寫死數值。
- `dead` 為終止狀態，進入後兩層都不再接受輸入。

- 動作層輸入有 **緩衝**（`PLAYER.actionBufferTime`）：右鍵與數字鍵先存入 `player.bufferedAction`，由 `ready` 狀態消化；攻擊後搖期間若有緩衝會直接取消後搖。
- 動作狀態可在 `fsm.data.lockFacing = true` 時鎖定轉向。

### 6.3 敵人
敵人使用同一個 `StateMachine`。`Enemy.js` 提供共用狀態 `spawn`（從地底爬出）/ `hurt`（硬直）/ `dead`（倒地沉沒後移除），子類別以 `static STATES` 合併自己的狀態，並以 `mainState` 指定爬出與硬直結束後回到哪個狀態。

| 類別 | 狀態 | 說明 |
|---|---|---|
| `MeleeEnemy` | `chase` | 追擊、接觸傷害（命中時播放揮擊動畫） |
| `RangedEnemy` | `kite` / `aim` | 保持 `preferredRange` 距離並橫移；冷卻好時停下瞄準，前 75% 追蹤玩家、最後鎖定方向再發射 |
| `Boss` | `chase` / `slam` / `charge` / `summon` | 霸體（不使用 `hurt`，擊退大幅減免）；招式都有地面預警；血量低於門檻進入狂暴（移速提升、冷卻縮短） |

- 敵人的招式冷卻同樣使用 `CooldownManager`，key 為 `enemy<id>.<招式>`，敵人移除時需 `reset`。
- 波次倍率（血量 / 傷害 / 移速）在建構時套用，Boss 不套用。

### 6.4 武器行為介面
`weaponBehaviors.js` 的每個行為物件可實作以下選用函式，由 `attack` / `special` 狀態呼叫：

| 函式 | 呼叫時機 |
|---|---|
| `enter(p, def, data)` | 進入動作時（可修改 `data.durations` 調整三段時間） |
| `phase(p, def, data, name)` | 每個階段開始時（`windup` / `active` / `recovery`），產生投射物、特效 |
| `update(p, def, data, name, k, dt)` | 每步呼叫，`k` 為階段進度 0~1；負責命中判定與姿勢 |
| `exit(p, def, data)` | 離開動作時（含被打斷），負責還原暫時狀態 |

---

## 7. 冷卻時間（CD）管理

- 全遊戲只有 **一個** `CooldownManager` 實例，由 `Game` 持有，於固定步長中 `tick(dt)`。
- Key 命名規則：`<擁有者>.<用途>`，例如 `player.special`、`player.slot1`。
- API：
  - `start(key, duration)`：開始冷卻
  - `isReady(key)` → boolean
  - `remaining(key)` → 剩餘秒數
  - `progress(key)` → 0~1（1 = 冷卻完成，給 HUD 畫遮罩用）
  - `reset(key)` / `resetAll()`
- **適用範圍**：右鍵特殊技、數字鍵 1~5、敵人招式。左鍵普攻不使用 CD Manager，攻擊頻率由動作狀態的前搖/後搖時間自然決定。
- 嘗試在冷卻中觸發時，發出 `skill:onCooldown` 事件（HUD 閃爍提示），不做其他事。

---

## 8. 資料驅動的內容定義

武器與技能都是「資料 + 行為」分離：數值放在 `*Defs.js`，邏輯放在行為函式。新增內容時優先只加一份資料。

### 8.1 武器定義格式（`weaponDefs.js`）
```js
export const WEAPONS = {
  swordShield: {
    id: 'swordShield',
    name: '劍盾',
    type: 'melee',                 // 'melee' | 'ranged'
    model: 'swordShield',          // 對應造型風格的 weapons 欄位
    idle: { armR: -0.35, armL: -0.1, tilt: 0 }, // 待機姿勢
    attack: {                      // 左鍵
      behavior: 'meleeSwing',      // 對應 weaponBehaviors.js 的行為名稱
      damage: 12, range: 2.3, arc: Math.PI * 0.65,
      windup: 0.07, active: 0.09, recovery: 0.2,
      knockback: 7, moveSpeedMul: 0.35,
    },
    special: {                     // 右鍵
      behavior: 'shieldBash',
      cooldown: 4, /* ...其他參數 */
    },
  },
};
```

### 8.2 主動欄位定義格式（`skillDefs.js`）
```js
export const SKILLS = {
  heal: {
    id: 'heal', name: '治療', icon: '✚',
    mode: 'cooldown',              // 'cooldown'（只有 CD）| 'charges'（有使用次數）
    cooldown: 8, charges: null,
    behavior: 'heal', amount: 30,
  },
};
```

### 8.3 敵人與波次（`enemyDefs.js`、`waveDefs.js`）
- `ENEMIES` 每個類型有 `visual`（對應造型風格的 `characters.melee / ranged / boss`）與數值；行為類別由 `Spawner` 的 `ENEMY_CLASSES` 對應（`grunt → MeleeEnemy`、`archer → RangedEnemy`、`boss → Boss`）。
- `WAVES` 是陣列，每波 `{ spawns: { 類型: 數量 }, isBoss? }`；最後一波打倒 Boss 即通關。
- `WAVE_SCALING` 定義每多一波小怪的血量 / 傷害 / 移速成長比例。

---

## 9. 事件（EventBus）

- 事件名稱格式：`<領域>:<動作>`，全小寫駝峰，例如 `entity:damaged`、`entity:died`、`player:died`、`skill:used`、`skill:onCooldown`、`game:restart`。
- payload 一律為單一物件，例如 `{ target, amount, source }`。
- 事件用於**通知**（UI、特效、音效），不用於核心流程控制；核心流程用直接呼叫。
- 所有事件名稱必須列在本節下方的清單中：

| 事件 | payload | 發出者 |
|---|---|---|
| `entity:damaged` | `{ target, amount, source, knockback, isCrit }` | Combat |
| `entity:healed` | `{ target, amount }` | skillBehaviors |
| `entity:died` | `{ entity, source }` | Entity |
| `player:died` | `{ player }` | Player |
| `skill:used` | `{ key, def }` | playerStates / ActiveSlots |
| `skill:onCooldown` | `{ key }` | playerStates / ActiveSlots |
| `wave:started` | `{ wave, total, isBoss }` | Spawner |
| `boss:enraged` | `{ boss }` | Boss |
| `style:changed` | `{ style }` | Game |
| `game:victory` | `{ stats }` | Game（Boss 死亡後延遲發出） |
| `game:restart` | `{}` | Game |

---

## 10. 命名慣例

| 對象 | 規則 | 範例 |
|---|---|---|
| Class 檔案 | PascalCase，與 class 同名 | `CooldownManager.js` |
| 非 class 模組 | camelCase | `weaponDefs.js`、`playerStates.js` |
| Class | PascalCase | `class Zombie` |
| 函式、變數、物件屬性 | camelCase | `applyDamage`、`moveSpeedMul` |
| 常數 | UPPER_SNAKE_CASE | `FIXED_DT`、`WEAPONS` |
| 私有成員 | `#` 前綴（原生私有欄位） | `#accumulator` |
| 布林值 | `is` / `has` / `can` 開頭 | `isDead`、`canMove` |
| 事件名稱 | `domain:action` | `entity:damaged` |
| CD key | `owner.purpose` | `player.slot1` |

- 程式碼的識別名稱一律英文；**註解與文件使用繁體中文**。
- 每個檔案開頭用一行註解說明職責。
- 只在「為什麼這樣做」不明顯時才寫註解，不寫重述程式碼的註解。

---

## 11. 程式風格

- 使用 `const` / `let`，禁止 `var`。
- 每個模組使用具名匯出（`export class` / `export const`），不使用 default export。
- 重用 Three.js 物件：每幀運算用的 `Vector3` 等暫存物件放在模組層級重複使用，避免 GC 卡頓。
- 共用幾何體與材質；受擊閃爍透過切換 `emissive`，不在每次受擊時建立新材質。
- 實體移除時必須從場景移除 mesh 並 `dispose()` 專屬資源。
- 可調數值集中放在 `config.js` 或 `*Defs.js`，邏輯程式內不出現魔術數字。

---

## 12. 版號與 CHANGELOG 規則

採用語意化版本 `MAJOR.MINOR.PATCH`：

| 變更類型 | 升級 | 範例 |
|---|---|---|
| 新功能、新系統、新內容（武器、敵人、技能） | MINOR | 0.1.0 → 0.2.0 |
| 修 bug、調數值、重構、改文件 | PATCH | 0.2.0 → 0.2.1 |
| 正式版或存檔不相容的大改 | MAJOR | 1.0 之前不使用 |

- **一次使用者請求 = 一個版號**，同一請求內的多項修改合併在同一版記錄。
- CHANGELOG 分類：`新增` / `修改` / `修復` / `移除`。
- 版號必須三處一致：`CHANGELOG.md`、`src/core/version.js`、git tag。
- HUD 角落顯示目前版號，方便確認瀏覽器載入的是最新版。

---

## 13. 開發工作流程

1. **開工**：讀 `CLAUDE.md` → 本文件 → CHANGELOG 最新版本 → 相關模組。
2. **實作**：遵守本文件；若需要偏離規範，先更新本文件再寫程式。
3. **驗證**：啟動本機伺服器，在瀏覽器實測新功能與既有功能，確認 Console 無錯誤。
4. **記錄**：更新 CHANGELOG 與 `version.js`；架構有變就更新本文件。
5. **提交**：`git commit -m "vX.Y.Z: 摘要"`，`git tag vX.Y.Z`。
6. **回報**：告訴使用者新版號、變更內容、驗證結果與已知問題。

---

## 14. 造型風格與角色模型

- 所有角色都是 `render/rig.js` 的 **`Rig`**：統一關節階層 `root → body → head / armR / armL / legR / legL`，手掌掛點 `handR / handL`。角色面向 +Z、右側為 -X、四肢往 -Y 延伸。**動畫程式只轉動關節，不依賴任何特定造型**，因此換造型不需改動畫。
- 手臂、腿的關節旋轉順序為 `YXZ`：先用 `rotation.x` 前後抬起，再用 `rotation.y` 水平揮動。
- 零件用 `PartKit.add()` 建立、材質用 `kit.mat(color, { glow, metal })` 取得，才能統一受擊閃白、淡出與釋放資源。自發光部位（眼睛、寶石）用 `glow: true`，不受閃白影響。
- 每種風格是 `render/styles/` 下的一個模組，必須實作以下介面並在 `styles/index.js` 登錄：

| 欄位 | 內容 |
|---|---|
| `id`, `name` | 識別碼與顯示名稱 |
| `names` | `{ knight, melee, ranged, boss }` 角色顯示名稱（Boss 血條使用） |
| `environment` | `{ background, hemiSky, hemiGround, hemiIntensity, sunColor, sunIntensity }` |
| `colors` | `{ blood, bossBlood, enemyProjectile, hitSpark }` |
| `characters` | `{ knight, melee, ranged, boss }`，各為 `() => Rig` |
| `weapons` | `{ swordShield, staff }`，各為 `() => { kit, main, offhand, gem? }`；`main` 掛在右手，`offhand` 掛在左臂 |
| `enemyProjectile()` | `→ { kit, mesh }`，沿 +Z 建模 |
| `buildArena(halfSize)` | `→ { kit, group }`；只負責外觀，碰撞邊界固定 |

- 新增職業或敵人時：先在每個風格補上對應的 `characters` 欄位，再新增資料定義。造型定案後，可以只保留選定的風格。
