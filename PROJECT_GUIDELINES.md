# Cubeborn 專案開發守則

> 本文件是專案的**唯一事實來源**。任何與本文件衝突的程式碼都視為 bug；架構變更時必須同步更新本文件。

> **轉換期說明**：第 1~14 節描述網頁版（Three.js），網頁版已凍結（v0.8.0 起不修 bug、不更新版號）並於 v0.10.0 搬到 `legacy/`，只當玩法設計圖；**第 1~14 節的檔案路徑都相對於 `legacy/`**。正式開發改用 Godot 4.7.2（GDScript，專案在 `godot/`），架構與多人連線規範見**第 15 節**；第 15 節沒寫到的玩法規則（狀態機分段、CD key、事件名稱、資料格式）沿用第 4~9 節，只把語法換成 GDScript。

---

## 1. 專案概要

| 項目 | 內容 |
|---|---|
| 類型 | 3D 等距俯視角 Roguelike 動作遊戲（網頁版原型） |
| 美術風格 | 程式生成的低多邊形奇幻角色（不使用外部模型與貼圖），造型已定案為**暗黑幻想**（寫實比例、硬朗多面體、月夜墓地） |
| 目前階段 | Phase 1：核心戰鬥、5 波制（含 Boss 戰）的一局流程 |
| 不在 Phase 1 範圍 | 職業選擇、房間/關卡生成、升級、掉落、武器切換、存檔、背景音樂（試聽中） |

---

## 2. 技術棧

| 項目 | 選擇 | 理由 |
|---|---|---|
| 語言 | 原生 JavaScript（ES2022），ES6 Modules | 零建置、易讀 |
| 音效 | Web Audio API 即時合成，不使用音檔 | 免授權、零下載；瀏覽器規定使用者操作後才能出聲 |
| 3D 引擎 | Three.js `0.170.0`，透過 `importmap` 從 jsDelivr CDN 載入（含 `three/addons/` 內建工具） | 不需 npm |
| 建置工具 | 無。日後需要打包上線再導入 Vite | 降低初期複雜度 |
| 本機伺服器 | `tools/serve.ps1`（PowerShell 內建 HttpListener） | ES Modules 不能用 `file://` 開啟；遊戲執行不依賴 Node |
| 自動檢查 | Node 24 LTS + `check.js`（`node check.js`）；`package.json` 只為檢查安裝 `three@0.170.0`，`node_modules/` 不進版控 | 不開瀏覽器即可驗證資料與核心機制 |
| 物理 | 不用物理引擎，自寫圓形碰撞 | 俯視角動作遊戲只需 2D 平面碰撞 |
| UI | DOM + CSS 疊在 canvas 上 | 好排版、好除錯 |
| 版控 | git，每個版本一個 commit + tag | 可回溯 |

**啟動方式**：在專案根目錄執行 `powershell -ExecutionPolicy Bypass -File legacy/tools/serve.ps1`，瀏覽器開 `http://localhost:5173`。`.claude/launch.json` 也有同樣設定（名稱 `cubeborn-legacy`），可供 Claude 的瀏覽器預覽使用。

**AI 測試技巧**：瀏覽器分頁在背景時 `requestAnimationFrame` 會暫停。測試邏輯時可在 Console 透過 `__game.update(1/60)` 加 `__game.input.endStep()` 手動推進邏輯步。

---

## 3. 目錄結構

```
Cubeborn/
├─ CLAUDE.md                  AI 最高指導原則（自動載入）、檔案地圖
├─ PROJECT_GUIDELINES.md      本文件
├─ CHANGELOG.md               版本紀錄
├─ check.js                   自動檢查（資料完整性與核心機制）
├─ package.json               Node 設定（只用於檢查）
├─ docs/                      進度.md（跨對話交接）、設計方向.md（設計目標）、新電腦設定.md
├─ index.html                 遊戲頁面、importmap、HUD 容器
├─ preview.html               模型檢視頁（並排展示四個角色，可拖曳旋轉）
├─ css/style.css              HUD 與頁面樣式
├─ tools/serve.ps1            本機靜態伺服器
└─ src/
   ├─ main.js                 遊戲進入點：建立 Game 並啟動
   ├─ preview.js              模型檢視頁進入點
   ├─ Game.js                 遊戲主體（組合根）：持有所有系統、主迴圈、命中停頓、重新開始、通關
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
   │  ├─ rig.js               角色骨架 Rig、零件組 PartKit、幾何體工廠 G、材質工廠
   │  ├─ environment.js       低多邊形地面、邊界點位、裝飾散佈工具
   │  ├─ WeaponModels.js      依目前風格建立玩家武器外觀並同步姿勢
   │  ├─ Effects.js           粒子、揮砍弧光、衝擊環、圓形/直線預警
   │  └─ styles/              造型風格（介面見第 14 節）
   │     ├─ index.js          風格登錄、getStyle()
   │     └─ darkFantasy.js    暗黑幻想（定案）
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
   ├─ audio/
   │  └─ Sound.js           Web Audio 即時合成音效；訂閱事件播放、M 鍵靜音
   ├─ world/
   │  ├─ Arena.js             依風格建立場地；碰撞邊界固定
   │  ├─ waveDefs.js          波次表與波次數值成長
   │  └─ Spawner.js           分波生成、Boss 出場、召喚用 spawnAt
   └─ ui/
      └─ HUD.js               血條、技能欄、波次/時間、Boss 血條、橫幅、死亡/勝利畫面
```

規則：
- 新增、刪除、搬移檔案時，同步更新本節與 `CLAUDE.md` 第 4 節的檔案地圖。
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
| 空白鍵 | 跳躍（Godot 版，見 15.13；只有一段跳） |
| Shift | 翻滾（Godot 版，見 15.12；受次數與回充管理） |
| 1 ~ 5 | 主動欄位（受 CD 或次數管理） |
| F | 按住救援倒地的隊友（Godot 版 v0.21.0，見 15.18） |
| Tab | 屬性面板（Godot 版） |
| R | 死亡或通關後重新開始（連線時只有房主能按） |
| F1 | 除錯：切換劍盾 / 法杖（非正式武器切換系統；Godot 版 v0.21.0 起走 InputCmd，連線時也能用） |
| F2 | 除錯：顯示碰撞與命中範圍 |
| F3 | 除錯：移速 +50%（Godot 版；F3~F5 只有單機） |
| Esc | 暫停 / 繼續（視窗失去焦點時自動暫停；死亡或通關畫面不能暫停）；Godot 版選單裡有開房 / 加入，連線時 Esc 只開選單、遊戲不停 |
| M | 靜音切換（記在瀏覽器） |

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
- Godot 版 v0.21.0 起：玩家自己的動作途中發出的事件會被 World 加上 `actor`（peer id），客戶端用它丟掉自己已經本機預測播過的事件（15.18）；命中結果與盾反不加。
- 所有事件名稱必須列在本節下方的清單中：

| 事件 | payload | 發出者 |
|---|---|---|
| `entity:damaged` | `{ target, amount, source, knockback, isCrit }`（Godot 版：`isCrit` 拆成 `is_heavy` 重擊顯示（第三段、盾反、爆炸）與 `is_crit` 屬性擲出的爆擊，見 15.11；另帶 `hit_stop` 命中定格秒數，見 15.3） | Combat |
| `entity:healed` | `{ target, amount }` | skillBehaviors |
| `player:blocked` | `{ player_id, perfect }`（Godot 版 v0.18.0：格擋擋下攻擊；perfect = 完美格擋，下一步盾反） | Player.try_block |
| `entity:died` | `{ entity, source }` | Entity |
| `player:died` | `{ player }`（Godot 版 v0.21.0 起只代表這位玩家真的死亡；輸掉一局改看 `game:defeat`） | Player |
| `player:downed` | `{ player_id }`（僅 Godot 版 v0.21.0：多人時生命歸零先倒地假死，見 15.18） | Player |
| `player:revived` | `{ player_id }`（僅 Godot 版 v0.21.0：被隊友救起） | Player.revive |
| `game:defeat` | `{ stats }`（僅 Godot 版 v0.21.0：全員倒下 = 輸；單機和 `player:died` 同一步發出） | World |
| `item:added` | `{ player_id, item, uid }`（僅 Godot 版 v0.19.0：道具放進身上；item = 物品 id，uid = 實例 id，武器為空字串） | Player.add_item |
| `inventory:full` | `{ player_id, item }`（v0.25.0：背包放不下） | Player.add_item |
| `gold:gained` | `{ amount, pos, total }`（v0.25.0：殺怪得到共用的錢） | World.on_enemy_died |
| `chest:denied` | `{ chest_id, player_id, price }`（v0.25.0：錢不夠開寶箱） | Chest.try_open |
| `chest:opened` | `{ chest_id, player_id, item, rarity, pos }`（v0.25.0：開了寶箱，道具掉在地上） | Chest.try_open |
| `skill:used` | `{ key, def }` | playerStates / ActiveSlots |
| `skill:onCooldown` | `{ key }` | playerStates / ActiveSlots |
| `wave:started` | `{ wave, total, isBoss }` | Spawner |
| `boss:enraged` | `{ boss }` | Boss |
| `game:victory` | `{ stats }` | Game（Boss 死亡後延遲發出） |
| `game:restart` | `{}` | Game |
| `game:paused` | `{ paused }` | Game（Esc、失去焦點） |
| `audio:muted` | `{ muted }` | Game（M 鍵） |
| `sfx:cue` | `{ name }` | 各遊戲物件；`name` 必須是 `audio/Sound.js` 的 `CUES` 之一（check.js 會檢查）。Godot 版欄位為 `cue` |
| `camera:shake` | `{ amount, duration, player_id? }` | 僅 Godot 版：Combat、Player、Projectile、Enemy、Boss、World（模擬層不能直接震相機）；有 `player_id`（玩家被打）時只震那位玩家的畫面 |
| `fx:slash` | `{ pos, height, facing, range, arc, color, swing_dir }` | 僅 Godot 版（v0.20.0 起的特效事件，見 15.17）：劍盾揮砍 |
| `fx:muzzle` | `{ pos, height, color }` | 法杖魔彈發射 |
| `fx:telegraph` | `{ pos, height, radius, color, life }` | 奧術爆裂落點預警 |
| `fx:fizzle` | `{ pos, height, color }` | 投射物飛到盡頭、撞牆或被格擋 |
| `fx:explosion` | `{ pos, height, radius, color }` | 投射物爆炸 |
| `fx:parry` | `{ pos, height, radius, facing, arc, color }` | 盾反（畫出實際的扇形範圍） |
| `fx:heal` | `{ pos, height, color }` | 治療藥水 |
| `fx:sprint` | `{ pos, height, color }` | 疾跑 |
| `fx:boss_slam` | `{ pos, height, radius }` | Boss 砸地 |
| `fx:boss_wall` | `{ pos, height }` | Boss 衝鋒撞牆 |

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
- 版號必須三處一致：`CHANGELOG.md`、`godot/core/version.gd`、git tag（網頁版的 `legacy/src/core/version.js` 已凍結在 0.7.0）。
- HUD 角落顯示目前版號，方便確認瀏覽器載入的是最新版。

---

## 13. 開發工作流程

1. **開工**：`git pull --ff-only origin main`（失敗就停下來問使用者）→ 讀 `CLAUDE.md` → `docs/進度.md` → 本文件 → CHANGELOG 最新版本 → 相關模組。
2. **實作**：先列出預計修改的檔案並取得使用者同意；遵守本文件；若需要偏離規範，先更新本文件再寫程式。
3. **驗證**：執行 Godot `tests/check.gd`，全部通過；改到畫面或操作時，另外用離屏截圖驗證（見 15.10）。
4. **記錄**：更新 CHANGELOG 與 `godot/core/version.gd`；架構有變就更新本文件。
5. **提交**：`git commit -m "vX.Y.Z: 摘要"`，`git tag vX.Y.Z`。只有使用者當次明確要求時才 `git push`（見 `CLAUDE.md` 1.3）。
6. **回報**：告訴使用者新版號、變更內容、驗證結果與已知問題。

---

## 14. 造型風格與角色模型

- 所有角色都是 `render/rig.js` 的 **`Rig`**：統一關節階層 `root → body → head / armR / armL / legR / legL`，手掌掛點 `handR / handL`。角色面向 +Z、右側為 -X、四肢往 -Y 延伸。**動畫程式只轉動關節，不依賴任何特定造型**，因此改造型不需改動畫。
- 手臂、腿的關節旋轉順序為 `YXZ`：先用 `rotation.x` 前後抬起，再用 `rotation.y` 水平揮動。
- 零件用 `PartKit.add()` 建立、材質用 `kit.mat(color, { glow, metal })` 取得，才能統一受擊閃白、淡出與釋放資源。自發光部位（眼睛、寶石）用 `glow: true`，不受閃白影響。
- **零件數影響效能**：角色建好後呼叫 `rig.optimize()`，武器與場地呼叫 `kit.mergeStatic(根節點, [會動的節點], [不合併的零件])`，把一起動的零件合併成少數 mesh（使用 Three.js 內建 `mergeGeometries`）。會單獨動畫的零件（例如法杖寶石）要放進不合併清單。`check.js` 會檢查每個角色與場地的零件數上限。
- 風格是 `render/styles/` 下的一個模組（目前只有 `darkFantasy`），必須實作以下介面並在 `styles/index.js` 登錄：

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

- 新增職業或敵人時：先在 `darkFantasy.js` 補上對應的 `characters` 欄位，再新增資料定義。
- 新造型或新外觀的候選方案，依 `CLAUDE.md` 第 2.5 節先做對比頁給使用者挑選，選定後才做進遊戲。

---

## 15. Godot 版架構（正式版）

### 15.1 目標與已定案的方向
| 項目 | 決定 |
|---|---|
| 引擎 | Godot 4.7.2 普通版，GDScript（一律寫型別）；效能不夠的熱點才改 C++（GDExtension），判斷依據見 `docs/進度.md` 壓力測試 |
| 平台 | Windows 優先，目標 Steam 上架。能完整玩一局後加上**網頁匯出**取代試玩網站：網頁用 Compatibility 渲染器（`project.godot` 的 `.web` 覆寫），電腦版維持 Forward+；網頁版不支援 ENet / Steam 連線，只給朋友試玩單機 |
| 多人 | **合作 1~4 人**，不做對戰 |
| 連線架構 | **房主當伺服器**（listen server，房主即權威端）。開發期用 Godot 內建 ENet（本機 / 區網），上架前換成 Steam 連線（GodotSteam），只換傳輸層 |
| 美術 | 照網頁版**程式生成**低多邊形暗黑幻想造型（第 14 節），用 GDScript 重寫，不用外部模型 |
| 音效 | 照網頁版合成公式，用工具腳本預先產生 WAV 檔放進專案（不在遊戲中即時合成）；背景音樂為已選定的「B 哥德輓歌」 |
| 開發順序 | 階段一：單機 1:1 搬完網頁版並驗收手感；階段二：接上 1~4 人連線。**階段一就必須照本節分層**，階段二才不用重寫 |

### 15.2 三層分離（最重要的規則）
```
輸入層（本機）        模擬層（只在權威端跑）              畫面層（每台都跑）
InputCollector ──► InputCmd ──► World.step(cmds, dt) ──► 快照 + 事件 ──► WorldView / HUD / Sound
```
- **模擬層（`sim/`）**：遊戲的全部規則（移動、狀態機、命中、傷害、CD、生成、勝敗）。只用 `RefCounted` 類別與資料，**不繼承 Node、不碰場景樹**。
  - 禁止使用：`Input`、`get_node` / `$`、任何 `Node` 型別、`Engine.time_scale`、全域 `randf()` / `randi()`、`Time.get_ticks_*`、讀檔。`tests/check.gd` 會掃描 `sim/` 擋住這些字。
  - 時間只來自 `step()` 傳入的 `dt`；隨機只用 `world.rng`（`RandomNumberGenerator`，種子由權威端決定）。
  - 輸出只有兩種：可讀取的狀態（實體列表、CD、波次）與本步的事件列表 `world.events`。
- **輸入層（`input/`）**：把 Godot 的 `InputMap` 動作轉成一筆 `InputCmd`。螢幕方向的 WASD 在這裡轉成世界 XZ 向量、滑鼠在這裡投射到地面得到瞄準點，模擬層只看到世界座標。
- **畫面層（`view/`、`ui/`、`audio/`）**：依實體 id 建立 / 移除模型，每個渲染幀讀模擬狀態擺位置與姿勢；消化事件來播特效、音效、更新 HUD。**畫面層不得修改模擬狀態**。
- **單機 = 沒有連線的房主**：單機時本機同時當權威端與玩家，走的是跟連線房主完全相同的程式路徑，不另寫一套單機邏輯。

### 15.3 主迴圈與時間
- 模擬固定每秒 60 步：使用 Godot 內建 `_physics_process`，`physics/common/physics_ticks_per_second=60`、`max_physics_steps_per_frame=5`（對應網頁版 `FIXED_DT`、`MAX_STEPS_PER_FRAME`）。每秒 60 步與 Forward+ 渲染器都是 Godot 預設值，Godot 編輯器存檔時會把等於預設值的設定從 `project.godot` 刪掉，看不到是正常的。不使用 Godot 的物理引擎與物理節點，只借用它的固定步長。
- 組合根 `main.gd` 在 `_physics_process` 收集輸入 → `world.step()` → 分送事件；畫面在 `_process` 以 `Engine.get_physics_interpolation_fraction()` 在上一步與這一步的位置之間補間，高更新率螢幕也平順。
- 更新順序與網頁版第 4 節相同（CD → 玩家 → 敵人 → 投射物 → 位移 → 碰撞分離 → 場地限制 → 生成器 → 清除）。
- 「本步按下」由 `InputCollector` 鎖存：兩次 `step` 之間按過就算，送出後才清除，不漏按。
- **命中定格**（v0.18.3 使用者決定，取代網頁版的整體放慢）：打中時模擬時間照常走，`entity:damaged` 事件帶 `hit_stop` 秒數，畫面層（`world_view.gd`）讓攻擊者與目標的模型停住這麼久、之後跟上實際狀態。只是畫面效果，多人時不影響其他玩家。**v0.19.1 使用者試玩覺得怪，預設關閉**（`Config.FEEL.hit_freeze = false`），事件仍帶 `hit_stop`，要加回來只改開關。
- 整體放慢只剩打倒 Boss 的 0.25 秒慢動作：真實時間照走、邏輯時間放慢到 5%，**每步仍是 `FIXED_DT`**（只是少跑幾步）。模擬層用 `world.hit_stop(秒)` 記錄，`main.gd` 每個真實固定步呼叫 `world.consume_hit_stop()` 取得縮放；通關時所有人一起放慢。
- 畫面震動：玩家方的攻擊打中不震動（`Config.FEEL.player_attack_shake = false`，v0.18.3 使用者決定）；玩家被打、Boss 砸地 / 撞牆 / 狂暴 / 登場、通關照常震動。
- `InputCmd` 放在 `sim/`：它是模擬層的輸入格式（連線時原樣傳送），`input/` 只負責產生它。
- 實體與 `World` 互相參照（RefCounted 循環），移除實體、`reset()` 與結束遊戲時必須經過 `world.clear()` / 移除流程切斷參照，否則記憶體洩漏（`tests/check.gd` 有檢查）。
- 暫停：單機時 `Esc` 停止呼叫 `step()`，失去焦點自動暫停；連線時 `Esc` 只開選單，模擬不停。

### 15.4 實體與效能
- 實體是 `sim/` 裡的 `RefCounted` 物件，由 `world` 以**整數 id**（`world.next_id` 遞增，不重複使用）管理；連線同步、畫面對應、CD key（`enemy<id>.<招式>`）都用這個 id。
- 碰撞分離與投射物命中用格子切分（uniform grid，作法同 `godot/stress_test/`），集中在 `sim/physics.gd`（v0.8.0 碰撞分離已改用格子；投射物命中目前仍逐一比對，數量變多時再改）。
- 敵人與 Spawner 不持有 World 以外的循環參照：Spawner 不存 World（每次呼叫時傳入），敵人的 CD key 需要 id，所以在 `World.add_entity` 之後的 `on_added()` 才開始 CD。這兩段是之後改 C++ 的首選，介面要保持「輸入陣列 → 輸出陣列」，方便替換。
- 大量相同外觀的物件（投射物、未來的大量小怪）用 `MultiMeshInstance3D`；角色用節點樹 Rig。

### 15.5 動畫與姿勢
- 網頁版的武器行為在 `update` 裡同時做命中判定與擺姿勢；Godot 版**拆開**：模擬層只記錄動畫所需的資料 `anim`（動作名稱、階段 `windup` / `active` / `recovery`、階段進度 `k`、狀態經過秒數），畫面層的 `view/animator.gd` 依 `anim` 算出關節角度。
- 規則：姿勢公式從網頁版照搬到畫面層，模擬層不出現關節名稱。這樣連線時只要同步 `anim`，每台都能畫出同樣動作。

### 15.6 事件
- 模擬層每步把事件 append 到 `world.events`（`{ "name": String, ... }`，只放 id 與數值，不放物件參照，才能透過網路傳送），步驟結束後由組合根交給 `GameEvents`（autoload）以 Godot 訊號 `event_emitted(name, payload)` 發出。
- 事件名稱、payload 欄位與第 9 節相同（`entity:damaged`、`sfx:cue`…），物件欄位改為 id（例如 `target` → `target_id`）。新增事件時同樣要列進第 9 節的表。
- payload 的 `name` 欄位保留給事件名稱（`world.emit_event` 會寫入並擋下衝突），所以 `sfx:cue` 的音效名稱放在 `cue`。
- 網頁版直接呼叫畫面的地方（`renderer.shake`、`effects.*`）改成事件：震動是 `camera:shake`，特效是 `fx:*`（見 15.17）。
- 只有畫面層訂閱事件；模擬層內部流程用直接呼叫。

### 15.7 多人連線（階段二實作，階段一就要遵守資料形狀）
- **權威**：房主（peer id 1）跑唯一的 `world`。傷害、死亡、生成、掉落、隨機一律由房主決定；其他玩家不跑 `world.step()`。
- **InputCmd**：`{ tick, move: Vector2, aim: Vector2, buttons: int }`，`buttons` 為位元旗標（攻擊按住、右鍵按下、1~5 按下）。玩家每步送出，用 unreliable 通道並夾帶最近幾筆未確認的輸入以防掉包。
- **快照**：房主每 3 步（20 次/秒）送出所有實體的 `id、類型、x、z、height（v0.16.0 起）、facing、hp、anim`，加上該玩家自己的 CD 與欄位；unreliable 通道。事件走 reliable 通道。
- **其他玩家的畫面**：遠端實體保留約 100 ms 的快照緩衝，在兩次快照之間補間。
- **自己的角色**：移動先在本機預測（用同一份 `sim/` 移動程式），收到快照後以伺服器位置為準修正。實作方式見 15.18（v0.21.0 改成「誤差平移」，不倒帶重播）。
- **玩家對應**：`world.players` 以 peer id 為 key；單機的唯一玩家也是 peer id 1。
- **傳輸層**：`net/` 封裝建立房間 / 加入 / 斷線，對外只暴露 Godot 的 `MultiplayerPeer`；從 ENet 換 Steam 只改 `net/`。
- v0.21.0 已實作（C1~C4），使用者的決定與實際做法見 15.18。

### 15.8 目錄結構（`godot/`）
```
godot/
├─ project.godot
├─ main.tscn / main.gd        組合根：建立 world、輸入、畫面，主迴圈、重新開始
├─ core/                      與遊戲內容無關：config.gd、version.gd、math_util.gd、state_machine.gd、cooldowns.gd、
│                             game_events.gd（autoload GameEvents）
├─ defs/                      資料表：weapon_defs.gd、skill_defs.gd、enemy_defs.gd、wave_defs.gd、stat_defs.gd、item_defs.gd、map_defs.gd
├─ sim/                       模擬層：world.gd、input_cmd.gd、stats.gd、terrain.gd、nav.gd、hitbox.gd、entity.gd、player.gd、player_states.gd、enemy.gd、
│  │                          enemies/（melee_enemy、ranged_enemy、boss）、projectile.gd、combat.gd、
│  │                          physics.gd、spawner.gd、weapon_behaviors.gd、skill_behaviors.gd、active_slots.gd
├─ input/                     input_collector.gd（按鍵在程式中註冊，不寫在 project.godot）
├─ net/                       連線：net_session.gd（ENet 傳輸、RPC、大廳）、net_host.gd（輸入排隊、快照）、
│                             net_client.gd（鏡像 World、補間、預測修正）、net_codec.gd（快照編碼）
├─ view/                      world_view.gd、arena_view.gd、camera_rig.gd、animator.gd、enemy_animator.gd、rig.gd、part_kit.gd、effects.gd、
│  └─ styles/                 dark_fantasy.gd（第 14 節介面照搬）
├─ ui/                        hud.tscn / hud.gd、skill_bar.gd、stats_panel.gd、floaters.gd、ui_kit.gd、net_panel.gd、player_tags.gd
├─ audio/                     sound.gd、sfx/*.wav、music/
├─ tools/                     synth.gd（離線合成）、bake_sfx.gd / bake_music.gd（headless 產生音效 / 背景音樂 WAV）
├─ tests/                     check.gd（headless 自動檢查）、net_checks.gd（連線的檢查，check.gd 呼叫）、capture.tscn / capture.gd（離屏截圖）
└─ stress_test/               效能壓力測試（保留作為效能基準）
```
- 依賴方向：`core` ← `defs` ← `sim` ← `view` / `ui` / `audio` / `net` ← `main`。`sim` 不得引用 `view`、`ui`、`audio`、`input`、`net`。
- 單檔約 300 行就考慮拆分；新增、刪除、搬移檔案時同步更新本節與 `CLAUDE.md` 檔案地圖。
- 網頁版檔案對應：`Game.js → main.gd + sim/world.gd`、`Input.js → input/`、`Renderer.js → view/camera_rig.gd`、`render/rig.js → view/rig.gd + part_kit.gd`、`*Defs.js → defs/`、`EventBus.js → GameEvents autoload`、`HUD.js → ui/`、`Sound.js → audio/ + tools/bake_sfx.gd`，其餘同名改 snake_case。

### 15.9 命名與程式風格（GDScript）
| 對象 | 規則 | 範例 |
|---|---|---|
| 檔案 | snake_case | `cooldowns.gd`、`player_states.gd` |
| 類別（`class_name`） | PascalCase | `class_name CooldownManager` |
| 函式、變數 | snake_case | `apply_damage`、`move_speed_mul` |
| 常數、資料表 | UPPER_SNAKE_CASE | `FIXED_DT`、`WEAPONS` |
| 私有成員 | `_` 前綴 | `_accumulator` |
| 布林值 | `is_` / `has_` / `can_` 開頭 | `is_dead` |
| 訊號 | 過去式 | `event_emitted` |
| 狀態名稱 | StringName | `&"idle"`、`&"attack"` |
| 事件名稱、CD key、音效名稱 | 與網頁版相同字串 | `"entity:damaged"`、`"player.slot1"` |

- 一律寫靜態型別（`var hp: float`、`func step(cmds: Dictionary, dt: float) -> void`），型別錯誤在匯入時就會報出，也比較快。
- 資料表用 `const` Dictionary（不用 `.tres` Resource），欄位名稱照網頁版改 snake_case，方便逐欄對照網頁版數值。
- 可調數值放 `core/config.gd` 或 `defs/`，邏輯內不寫魔術數字。
- 每個檔案開頭一行註解說明職責；註解用繁體中文。
- 座標、單位、角度與第 4 節相同：Y 朝上、邏輯只用 XZ、`facing = atan2(dx, dz)`（0 = 面向 +Z），模型面向 +Z 建模，Godot 的 `rotation.y = facing` 可直接套用。

### 15.10 驗收
- `tests/check.gd`（作用等同 `check.js`），在 `godot/` 內執行：`<Godot console 執行檔> --headless --path . -s res://tests/check.gd`，全部通過才算完成。網頁版已凍結，只有動到網頁版時才跑 `node check.js`。
- 因為模擬層不依賴場景樹，檢查可以直接建立 `World`、餵假的 `InputCmd`、推進 N 步讀數值（例如移動 1 秒的距離、三段攻擊總時間、CD 是否到期）。
- 搬移時對照網頁版：同樣輸入下的移速、攻擊時間、傷害、CD、波次數量要與網頁版一致，數字寫進回報。資料表由 `check.gd` 對 `tests/web_defs.json`（`tools/dump_web_defs.mjs` 匯出）逐欄比對；對照結果整理在 `docs/手感對照.md`。
- 畫面用離屏截圖場景 `tests/capture.tscn` 驗證（用法與「開視窗前先問使用者」的規則見 `CLAUDE.md` 1.8），截圖存暫存資料夾，不進版控；手感與效能定案以使用者實際遊玩為準。
- 版號必須三處一致（`CHANGELOG.md`、`godot/core/version.gd`、git tag）；遊戲畫面角落顯示版號。

### 15.11 屬性系統（v0.14.0）
- 玩家與敵人共用一套屬性：名稱、基礎值、上下限、顯示方式在 `defs/stat_defs.gd`；計算在 `sim/stats.gd`，每個實體一個 `entity.stats`。
- **公式**：結果 = (基礎值 + Σadd) × (1 + Σpct) × Πmul，再取整（有 `round` 的屬性）、限制上下限。使用者決定：
  - 同類加成**相加**（兩個 +8% = +16%）。暫時效果（疾跑 ×1.6）、波次倍率、**冷卻縮減**用 `mul` **相乘**（−6% 與 −25% → ×0.94 × 0.75 = 0.705，疊再多也不會到 0）。
  - **護甲**：受到傷害 × 100 ÷ (100 + 護甲)（`StatDefs.ARMOR_SCALE`），護甲 100 減傷 50%。
  - **爆擊**：基礎爆擊率 0%、爆擊傷害 ×1.5；爆擊率 0 時不擲骰（不消耗 `world.rng`）。
- 加成以「來源」為單位整批設定 / 移除：`entity.set_stat_source(來源, [[屬性, Stats.ADD|PCT|MUL, 數值], …])`、`remove_stat_source(來源)`。來源名稱：增益用增益 id（`sprint`）、盾擊 `shieldBash`、敵人波次 `wave`、除錯 `debug`；之後的道具用道具實例的 id。
- 最大生命提高時目前生命增加同樣的量；降低時只截到上限。
- 套用位置：攻擊力由出招方乘進 `hit.damage`（投射物在發射時就乘好）；爆擊與擊退在 `Combat.apply_damage`；護甲與受到傷害在 `Entity.take_damage`；攻速只除普攻三階段時間；冷卻縮減套在特殊技與數字鍵欄位；每秒回血在 `Entity.integrate`。
- `Entity.max_hp`、`damage_mul`、`damage_taken_mul`、`knockback_mul`（受到擊退）與 `Enemy.speed` 是屬性的唯讀捷徑，不能直接賦值。
- 新增屬性時先加進 `stat_defs.gd`；對應系統還沒做的屬性設 `in_use = false`（屬性面板不顯示）。

### 15.12 翻滾（v0.15.0）
- 使用者決定：左 Shift；往移動方向翻（沒按方向鍵就往面對方向）；0.35 秒；前 0.2 秒無敵；1 次充能、回充 1.2 秒；**速度與距離隨移速屬性等比放大**（基礎移速 6.5 時 4 單位，移速 ×1.5 時 6 單位），時間與無敵不變。數值在 `core/config.gd` 的 `ROLL`。
- 動作層狀態 `roll`（`sim/player_states.gd`）。翻滾按鍵走 `InputCmd.BTN_ROLL` 與動作緩衝（0.25 秒）：普攻的前搖與後搖會被翻滾取消；揮下去（active）、特殊技、硬直、使用道具中先緩衝，結束後才翻。
- 無敵用 `player.dodge_timer`（`Entity.is_dodging()`）：不能被打中，投射物直接穿過；受傷後的無敵時間（`invuln_timer`）則照舊擋下投射物。
- 充能：`player.roll_charges`，上限是 `roll_charges` 屬性；回充計時用 CD key `player.roll`（乘 `roll_cooldown` 屬性），一次回 1 格，沒滿就接著回充。
- 移速只算屬性（含疾跑等暫時加成），動作本身的走路減速（攻擊、硬直）不算。

### 15.13 跳躍、高度與地形（v0.16.0）
- 使用者決定：空白鍵、最高 1.5、起跳到落地 0.6 秒、只有一段跳；空中可以攻擊、用技能與道具、翻滾（空中翻滾照常下墜）；命中照實際高度計算。數值在 `core/config.gd` 的 `JUMP` 與 `HEIGHT`。
- 高度是模擬層的資料：`entity.height`（腳底）、`vz`、`ground_height`、`body_height`（身高，依 kind 查 `HEIGHT.body`）。重力 = 8 × 高度 ÷ 時間²，所有實體共用；垂直移動在 `World.step` 的碰撞分離與地形推擠之後（`Entity.integrate_vertical`，用前後速度平均，60 步 / 秒時第 18 步最高 1.5、第 36 步落地）。
- 起跳：`InputCmd.BTN_JUMP`，站在地面上隨時可跳（攻擊、翻滾中也行），硬直與倒地不行；落地沒有硬直。
- **命中高度**：目標佔 [height, height + body_height]；攻擊用 `hit.band`（Vector2 下緣、上緣）。沒給 band 時用攻擊者身體往腳底下延伸 `reach_below`（近戰、碰撞、衝鋒）。投射物是飛行高度 ± `projectile_half`，高度不重疊就從頭頂 / 腳下穿過；爆炸是地面往上 `explosion_height`；Boss 砸地打得到上下各一層高台，但目標腳底離自己腳下地面超過 `slam_height` 就打不到（`hit.max_air`，見 15.19）。
- 投射物的 `height` 就是飛行高度：敵人箭矢 = 發射者腳底 + `arrow_altitude`，飛向目標的過程中線性變到「目標腳下地面 + `arrow_altitude`」（D1，打得到高台上的玩家；跳起來照樣躲得過），之後高度不變；玩家投射物 = 腳底 + `bolt_altitude`，飛出 `bolt_settle_distance` 內降到「min(發射時腳下地面, 目前位置的地面) + `bolt_altitude`」（只往下貼地，不會順著牆往上爬）。撞到比飛行高度高的石台就結束（會爆炸的照樣爆炸）。
- 碰撞分離：高度不重疊的兩個實體不互推。
- **地形**：`sim/terrain.gd`，石台資料在 `defs/map_defs.gd`（見 15.19）。腳底 ≥ 頂面 − `HEIGHT.step` 才能站上去，否則石台當牆、把實體推出去；圓心在石台範圍內時地面高度就是頂面。查詢用 4 單位的格子分桶。
- 連線：快照的實體欄位要加 `height`（15.7）。

### 15.14 通用攻擊判定（v0.17.0）
- 設計方向：怪物**沒有碰撞傷害**，每種怪物都靠自己的招式（預備 → 判定 → 收招）攻擊。貼著怪物不會扣血。
- `sim/hitbox.gd`：玩家與怪物共用。`Hitbox.strike(world, 攻擊者, 原點, 朝向, 形狀, hit, already)` 查詢形狀內的敵對目標並套用 `Combat.apply_damage`；`already`（id 字典）讓同一招每個目標只打一次。形狀：`{shape: &"sector", range, arc}`、`{shape: &"circle", radius}`。
- hit 欄位加上 `blockable`（能不能被格擋，B5 使用）：揮砍、箭、Boss 衝鋒（v0.18.2 起）= true；Boss 砸地、爆炸、盾反 = false。可另給 `block_knockback_mul` 指定擋下時的推退比例。數值寫在資料表（`enemy_defs` 的 `swing.blockable`、`slam.blockable`、`charge.blockable`、`projectile_blockable`）。
- 每次 `strike` 都記錄到 `world.hitboxes`（每步清空，只給畫面層 F2 畫形狀，不影響模擬）。
- 骷髏戰士揮砍（使用者選「中等」）：中心距離 1.3 內且冷卻好時舉刀 0.5 秒（站定，前 50% 轉向、之後鎖定）→ 揮下 0.1 秒（前方 100°、距離 1.5 的扇形，傷害 12）→ 收招 0.5 秒；冷卻 1.2 秒從舉刀算。舉刀中被打進入受擊硬直，揮砍中斷。
- 弓手與 Boss 拿掉碰撞傷害後不補新招（使用者決定）。
- 網頁版對照：`check.gd` 的 `WEB_DIVERGENCE`（欄位）與 `WEB_DIVERGENCE_PATHS`（整段）列出刻意不同的地方與原因，其他欄位照常逐欄比對。

### 15.15 劍盾格擋與盾反（v0.18.0）
- 使用者決定：劍盾右鍵從盾擊衝鋒改成格擋；按一下自動維持 3 秒；格擋時可以移動。其餘由 Claude 訂（數值在 `weapon_defs.gd` 的 `swordShield.special`）：
  - 移速 ×0.5、會轉向瞄準點；用翻滾或再按一次右鍵（v0.23.0 使用者決定，`press_cancel`：直接進入 0.15 秒收招）提前結束；冷卻 4 秒從按下算（取消不退冷卻）。
  - 擋得住：`blockable` 的攻擊（揮砍、箭），來向在正前方合計 120°（左右各 60°；v0.23.0 使用者決定，原本 75°）內。格擋中腳下前方顯示金色扇形（`WorldView` 的 BlockFan，半徑 2.2、角度同 `block_arc`）。擋下時不扣血、自己被推退 30% 擊退，發出 `player:blocked` 與音效；箭會消失。
  - Boss 衝鋒（v0.18.2 使用者決定）：擋得住、不扣血，但推退 100%（`charge.block_knockback_mul`）；同一次衝鋒擋下後不再判定。
  - 擋不住：砸地、爆炸（不是 blockable），或來自側面 / 背後。
  - 完美格擋：按下後 0.2 秒內擋下 → 下一步開頭盾反（前方 180°、距離 3.5；v0.23.0 使用者決定，原本 120° / 2.5；傷害 25 × 攻擊力，大擊退、重擊顯示），然後結束格擋。`fx:parry` 帶 facing 與 arc，畫面閃一下實際打得到的扇形。
  - 注意：`InputCmd.buttons` 是「這一步按下」，測試裡連續好幾步帶 `BTN_SPECIAL` 等於連按，格擋會被第二下取消。
- 實作：`ShieldBlock` 行為記錄 `player.block_time`（格擋開始後秒數，< 0 = 沒在格擋）；`Combat.apply_damage` 對 blockable 的攻擊先呼叫 `target.try_block(來源位置, hit)`；盾反延到下一步執行（`pending_parry`），避免在怪物出招的途中改動怪物狀態。

### 15.16 物品資料（v0.19.0）
- 使用者決定：資料放程式資料表 `defs/item_defs.gd`（`ItemDefs.ITEMS`）。武器與道具共用一種格式：`kind`（`item` / `weapon`）、`name`、`rarity`、`shape`、`desc`、`effects`；道具另有強度分數 `power`，武器另有 `weapon`（對應 `WeaponDefs`，武器數值仍在那邊）。
- 稀有度 `RARITIES`（名稱、顏色、效率）、占格形狀 `SHAPES`（格子座標，左上為 (0, 0)、上下左右相連）、背包 `BAG_SIZE` 8×6。**道具格數必須 = ceil(power ÷ 稀有度效率)**（`docs/道具清單.md`），新增道具時先估 power 再挑形狀。
- 效果四種寫法：
  - 屬性 `{stat, op, value}`：放進身上就生效。
  - 條件屬性 `{when, stat, op, value, …}`：條件見 `CONDITIONS`。
  - 觸發 `{on, do, chance?, …}`：時機見 `TRIGGERS`，動作見 `ACTIONS`。
  - 能力 `{ability, …}`：見 `ABILITIES`。
  - 各表的 `params` 是必填參數，`check.gd` 會檢查。新增條件、觸發、動作或能力時先加進表。
- **目前只接上屬性效果**（`ItemDefs.stat_mods`）；條件、觸發、能力等之後的里程碑再實作。
- 放進身上：`Player.add_item(id)` 建立實例 `{uid, id}`，以 `uid`（`item_N`）為屬性來源；`remove_item(uid)`、`clear_items()` 拿掉。武器道具直接 `equip_weapon`，不放進 `items`。還沒有背包介面，放進來就生效。
- 除錯：F4 依清單順序放入下一個道具，F5 清空；`--items=id,id`。

### 15.17 特效（v0.20.0）
- 畫面層 `view/effects.gd`（`WorldView.effects`）照搬網頁版 `Effects.js`：方塊粒子（`burst`、`mote`）、揮砍弧光（`slash`）、衝擊環（`ring`）、預警圈（`telegraph`）。Boss 招式的地面預警仍在 `enemy_animator.gd`。
- **一次性特效走事件**：模擬層發 `fx:*`（第 9 節的表），payload 只放位置（`pos` Vector2、`height`）、顏色與尺寸，不放實體參照。命中、死亡、狂暴直接用既有事件。新增特效事件時：模擬層 emit → `Effects.HANDLERS` 加處理函式 → 列進第 9 節；`check.gd` 會檢查三者一致。
- **持續性粒子由畫面層依狀態產生**（投射物拖尾、蓄力、爬出、拉弓、衝鋒、暈眩、召喚、疾跑殘影），不發事件，連線時不佔頻寬。網頁版「每步機率 p」換算成每秒 p × 60 顆，小數累積到下一幀（`_count`），和幀率無關。
- 上限：粒子 `MAX_PARTICLES` 600（一個 MultiMesh），弧光與環 `MAX_TRANSIENTS` 64。開場先畫一次透明的粒子與環來預先編譯著色器。暫停時停住、`game:restart` 時清空。

### 15.18 多人連線（v0.21.0，C1~C4）
- **使用者決定**（2026-10-23）：區網 ENet、1~4 人合作、房主即權威；誤傷開啟；敵人數量不變、血量每多 1 人 +50%；只能開局前加入（中途加入先不開放）；移動 / 翻滾 / 跳躍本機預測，攻擊與技能的動作、音效本機立即播，傷害一律由房主判定；倒下假死 10 秒、隊友按住 F 累積 5 秒救起、救起 30% 血、全員倒下就輸。數值在 `Config.NET`、`Config.REVIVE`。
- **三種模式**（`main.gd`）：單機 = 沒有連線的房主（同一條程式路徑）；房主跑唯一的 `World`，`NetHost` 收各玩家輸入排隊（每步取一筆，排超過 `input_queue_max` 筆就把最舊的併進下一筆，本步按下的按鈕保留）；客戶端不跑 `World.step()`，`NetClient` 用快照維護鏡像 `World`（`is_authority = false`）。
- **傳輸**（`net/net_session.gd`）：輸入（客戶端每步送最近 `input_redundancy` 筆）與快照（房主每 3 步）走 unreliable；事件每步一包走 reliable（`[run_id, tick, events]`）。RPC 的節點路徑以 `main` 為根（`get_tree().set_multiplayer(…, main 的路徑)`），直接執行與在 `capture.tscn` 裡執行的程序能互連。`--net-latency` / `--net-loss` 模擬延遲與掉包。
- **快照**（`net/net_codec.gd`）：`[run_id, tick, ack, 世界狀態, 實體…]`；實體網路格式 `[id, kind, 數值 PackedFloat32Array, is_dead, 動畫, extra]`，動畫欄位名稱換成 `ANIM_KEYS` 索引、玩家動畫和預設值相同的欄位不送。客戶端用同樣的類別建立鏡像實體（`Player`、`Spawner.create`、`Projectile`），畫面層不用分辨單機或連線。2 人 + 2 隻怪約 0.8~0.9 KB；4 人 + 十幾隻怪會超過 ENet 的 MTU（約 1.4 KB）而被分片，區網沒問題，換 Steam 前要做差量或量化（見 `docs/進度.md`）。
- **其他實體**：畫面時間 = 估計的房主 tick（最新快照 + 收到後經過的步數）− `interp_delay_ticks`（6 步 = 100 ms），在前後兩筆快照之間補間（位置、高度、朝向；動畫的狀態相同時數值欄位也補間）；連續掉包追上最新快照時，沿速度最多往前推 `max_extrapolate_ticks` 步。事件也依 tick 延到畫面時間才播，和畫面對得上。
- **自己的角色**：`World.step_predicted` 只推進自己（同 `step()` 的順序，但不扣血、不產生投射物，投射物等快照）。每筆快照帶 `ack`（房主最後套用的該玩家輸入編號），誤差 = 房主在 ack 時的位置 − 本機當時預測的位置，加到目前位置與之後的預測紀錄（不倒帶重播，狀態機與計時器不用存檔）；差超過 `snap_distance` 直接跳過去。血量、倒地 / 死亡、盾反、武器以房主最新快照為準；倒地 / 死亡時不預測，位置直接用房主的。被房主判定打中時本機立刻進入受擊硬直（`Player.net_hurt`）。
- **事件去重**：World 更新某位玩家時，事件標上 `actor`（peer id）；`Combat.apply_damage` 與盾反期間清掉（不是預測得到的）。客戶端丟掉 `actor` 是自己的房主事件。
- **CD**：每位玩家的 CD 實際存在 `Player.cd(key)`（`key@peer_id`）；事件與 HUD 仍用 `player.special` 這類名稱。
- **誤傷**：`Combat.hostiles_of(world, team, source_id)` 在 `Config.NET.friendly_fire` 時把其他玩家也當目標，但不含出招者自己（投射物用發射者 id）。
- **倒下與救援**（`Player.die` / `_go_down` / `revive`、`World._update_downed`、動作層 `revive` 狀態）：多人時生命歸零先倒地（`is_downed`，移動層 `downed`，不能被打、不被怪追、不接受輸入）；隊友按住 F（`InputCmd.BTN_INTERACT`）、中心距離 ≤ `REVIVE.range` 就進入 `revive` 動作（不能移動 / 攻擊 / 跳），倒地者救援進度 +1/秒、倒數暫停；放開時進度每秒 −`decay_rate`（Claude 暫定和累積同速）、倒數照走；沒有站著的玩家時所有倒地者直接死亡並發 `game:defeat`。單機倒下 = 死亡（和以前一樣）。
- **只有單機才有**：F3~F5 除錯鍵（直接改模擬狀態）、暫停（連線時 Esc 只開選單）、失去焦點自動暫停。F1 切武器改走 `InputCmd.BTN_SWAP_WEAPON`，連線時也能用。
- **斷線**：房主那邊有人斷線就移除他的角色；客戶端和房主斷線就回到單機。網頁版不支援 ENet，連線選單不顯示。

### 15.19 地圖與怪物尋路（v0.22.0，D1）
- **地圖資料**：`defs/map_defs.gd` 的 `MAPS`。地圖座標左上角 (0, 0)、x 往右、y 往下（= 世界 X、Z），世界座標 = 地圖座標 − `origin`（地圖中央在世界原點）；畫面是等距視角，所以地圖在畫面上轉 45°（菱形）。每張圖有 `size`、`spawn`（玩家出生點）、`dig`（挖墳點 = 出口，D6 使用）、`spawn_rule`、`blocks`（[x, y, 寬, 深, 頂面, 種類]）、`tomb_rows`（一排排墓碑）。
- **石台種類**：`wall`（牆 / 陵墓，頂面 3.0，跳不上去）、`tomb`（墓碑 1.2 × 0.5、高 1.3：擋箭與魔彈，玩家跳得上去）、`platform`（可以站的高台，0.5 / 1.0）。
- **地圖**：`graveyard_a`（A 環形墓園，96 × 96，使用者選定；遊戲用 `Config.WORLD.default_map`）、`test_arena`（舊的 32 × 32 測試場地，`check.gd` 大部分檢查用）。B、C、D 草圖在 `mockups/graveyard_map.html`，之後做成資料並隨機抽（使用者決定）；屆時房主要把地圖編號傳給客戶端（目前兩邊都用 default_map）。
- `World` 建立時載入地圖（`World.new(map_id)`、`load_map`）：`half_extents`（場地一半大小，限制實體與投射物）、`terrain`、`nav`、`spawn_point`；玩家出生在 `spawn_point`。
- **沒有安全區**（使用者決定）：玩家去得了的地方怪物都去得了，怪物只是比玩家多花一點時間上去。
  - 尋路（`sim/nav.gd`）：1 單位的格子，牆與墓碑往外擴 margin 的格子是障礙，高台可走；路徑用引擎內建的 `AStarGrid2D`（八方向、不切牆角），再拉直看得到的點。只在權威端算。依體型兩張：`World.nav`（小怪，`NAV.margin` 0.6 = 半徑 0.45 + 0.15）、`World.nav_large`（半徑 > `large_radius` 的 Boss，`margin_large` 1.15），用 `World.nav_for(radius)` 取。
  - 「看得到、直接走」是精確的線段判斷（`Terrain.segment_blocked`：線段與「牆 / 墓碑往外擴 margin」的長方形相交；起點已貼牆時往外走不算擋住）。v0.22.0 用格子取樣，直線會擦到牆角，怪物看起來一直撞牆（繞北門時 154 步被牆擋住變慢，v0.23.0 為 0 步）。
  - 怪物每 `NAV.repath_interval` 秒判斷一次：看得到就直接走向玩家（和以前一樣），否則照路徑點走（`Enemy.steer_point`）。
  - 跳上高台（`Enemy._update_jump`）：站在地上往前走、前方 `jump_lookahead` 的地面比腳下高出 `step` ~ `climb_height`（1.1）就先蹲 `jump_windup`（0.25 秒）再用玩家的起跳速度跳；空中往起跳方向至少 `jump_air_speed`（4.0），身體整個越過邊緣才落地（Boss 半徑 1.0、移速 2.2，v0.22.0 會掉回去）。1.3 的墓碑太高不跳，站在下面揮砍 / 射擊打得到。
  - Boss 衝鋒（v0.23.0）：前方是高低差 ≤ `climb_height` 的高台就在衝鋒途中直接跳上去、不停；更高的牆與墓碑、場地邊緣才撞停暈眩。衝鋒中不做一般的蹲跳。
  - Boss 砸地（v0.23.0）：範圍內站在任何地面上（含旁邊的高台）的目標都打得到；`hit.max_air` = `slam_height`，腳底離自己腳下地面超過 0.5（跳起來）才躲得過。
  - 弓手：看不到玩家或箭會撞到石台時先繞路靠近、不射擊；箭瞄準玩家腳下地面的高度。
  - 地圖規則（`check.gd` 檢查）：所有可走格連成一片、相鄰可走格高低差 ≤ `climb_height`、牆比最高的地面高出跳躍高度 + 0.3 以上。
- **生成**（`spawn_rule`）：`arena` 同以前（整個場地隨機、Boss 在玩家對面）；`around_player`（大地圖）小怪生在離玩家 `min_distance_from_player` ~ `max_distance_from_player`（8 ~ 18）、可走而且走得到玩家的格子；Boss 往地圖中央方向、離玩家 `boss_distance`；Boss 召喚的小怪落在障礙格時移到最近的空地。
- 畫面：`ArenaView.create_blocks` 把所有石台合併成一個網格（每個石台 5 面、頂點色依種類），地圖上有上百個石台也只畫 1 次。

### 15.20 角色視野（v0.24.0，D2）
- 使用者決定：前方 120°、18 單位；身邊 4 單位不管方向都看得到；牆（`wall` 種類）擋視線，墓碑與高台不擋；視野外的地面變暗。數值在 `Config.VISION`。
- **只影響畫面**：模擬照常進行（看不到的怪照樣會打你），沒有網路同步的改動；每個程序只依自己的本機玩家（`WorldView.local_peer`，`main.gd` 換 World 時設定）決定畫什麼。
- 判斷在 `sim/vision.gd`（純函式）：`Vision.point_visible(world, 看的人, 位置, 目標半徑)`：距離 ≤ 18（加目標半徑）、在身邊 4 單位內或扇形內（身體邊緣進入就算）、而且視線不被牆擋（`Terrain.sight_blocked`，身邊一圈也會被牆擋）。`Vision.entity_visible`：自己、自己發出的投射物一律看得到；怪物、隊友、別人的投射物照位置判斷；看的人不存在或已陣亡時全部看得到。
- 看不到時不畫：怪物與隊友的模型（Boss 地面預警是模型的子節點，一起隱藏）、別人的投射物、位置在視野外的 `fx:*` 特效事件、看不到的實體的持續性粒子（`Effects.hidden_ids`）、HUD 的傷害數字、隊友名牌。音效照常播（聽得到）。之後的寶箱等可互動物件也要接 `Vision`。
- 變暗：`WorldView` 的全畫面四邊形著色器，從深度貼圖還原每個像素的世界位置，在扇形與身邊一圈之外蓋 `darkness`（0.5）的黑色，邊緣漸層 `edge`（0.8）。牆擋住的區域不畫暗（只隱藏牆後的東西）。Compatibility（網頁版）用 `CURRENT_RENDERER` 換深度的換算方式，網頁版還沒實測。

### 15.21 金錢、寶箱與背包（v0.25.0，D3）
- 數值（Claude 暫定，使用者說先用建議值）在 `defs/loot_defs.gd`：殺怪金幣 `KILL_GOLD`（骷髏 5、Boss 50，Boss 召喚的小怪照樣給）、寶箱 `CHESTS`（價格、稀有度權重、半徑）、`INTERACT_RANGE`（身體邊緣距離 1.6）、`DROP_DISTANCE`（1.4）。寶箱位置在 `map_defs.gd` 每張地圖的 `chests`（地圖 A：4 小 1 大）。
- **金錢**：`World.gold`，多人共用；`World.on_enemy_died` 加錢並發 `gold:gained`；快照的世界欄位 `W_GOLD`。
- **寶箱**（`sim/chest.gd`，實體 kind `chest`，不擋路、不能被打）：`World.reset` 依地圖放好。`try_open`：錢不夠發 `chest:denied`；夠了扣錢、`LootDefs.roll_rarity` 用 `world.rng` 抽稀有度、再從該稀有度的道具（不含武器）抽一個，掉在寶箱往玩家方向 `DROP_DISTANCE`（`World.drop_item`，落在最近的可走格），發 `chest:opened`。快照 extra：`[tier, opened]`。
- **地上的道具**（`sim/item_pickup.gd`，kind `pickup`）：快照 extra `[item_id]`；畫面是稀有度顏色的發光寶石 + 光柱。
- **F 互動**（`Player._try_interact`，只在權威端、只在「剛按下」那一步）：附近有倒地隊友時讓給救援；否則先撿最近的道具（`World.nearest_interactable`），沒有道具才開最近的寶箱。多人同一步按，依玩家更新順序先到先得。
- **背包**（`sim/inventory.gd`）：`ItemDefs.BAG_SIZE` 8 × 6；形狀轉 rot 次 90 度（(x, y) → (−y, x) 後平移到左上）；`find_spot` 由上到下、左到右，每格依序試 0 / 90 / 180 / 270 度。`Player.add_item` 自動放進第一個空位才生效（屬性來源 = 實例 uid），放不下回傳 `&""` 並發 `inventory:full`。`Player.items` 與 `inventory` 同步。
- **背包操作走輸入**：`InputCmd.inv_ops`（`[OP_MOVE, uid, x, y, rot]`、`[OP_DROP, uid]`），房主合併輸入時接在一起；只在權威端執行（`Player._apply_inventory_ops`）。客戶端的背包以快照為準（玩家 extra 的 `P_INV`，`Player.sync_inventory` 依增減的道具加減屬性，本機預測的移速才對）。
- **介面**：`ui/inventory_panel.gd`（I 開關；滑鼠拖曳、拖著時按 R 旋轉、拖到面板外丟掉；下方顯示滑鼠停著的道具名稱與效果，效果還沒實作的標「效果尚未實作」）。開著時不暫停、WASD 照常，`InputCollector.mouse_captured` 讓滑鼠不攻擊、不格擋、瞄準點不動。`ui/world_labels.gd`：沒開的寶箱顯示名稱與價格（錢不夠紅色）、地上道具顯示名稱，按得到 F 的那一個加「[F] 開啟 / 撿起」；視野外不顯示。左上顯示金幣。
- 屍體裝背包、冤魂復活移到 D6。
