# Cubeborn — AI 最高指導原則

Three.js 等距視角 Roguelike 動作遊戲原型（暫定名 Cubeborn）。
本文件在每次新對話開始時自動載入，**所有規則優先於 AI 的預設行為**。技術細節（架構、命名、狀態機、CD、事件、資料格式）以 [`PROJECT_GUIDELINES.md`](PROJECT_GUIDELINES.md) 為準。

---

## 0. 開工順序

1. **同步**：新對話的第一件事執行 `git pull --ff-only origin main`，取得其他電腦推上去的內容。
   - 成功（含「已是最新」）→ 繼續下一步。
   - 失敗（兩台電腦改出不同版本、有未 commit 的修改、連不上網路）→ **停下來告訴使用者原因**，不自己合併、不丟棄任何修改，等使用者決定。
   - 為什麼：使用者在三台電腦輪流開發，聊天紀錄不會同步，忘了同步就會在舊版本上修改。
2. 讀 [`docs/進度.md`](docs/進度.md)：上一輪卡在哪、下一步是什麼。
3. 讀 [`PROJECT_GUIDELINES.md`](PROJECT_GUIDELINES.md) 中與本次任務相關的章節。
4. 讀 [`CHANGELOG.md`](CHANGELOG.md) 最上面一個版本。
5. 用本文件第 4 節的「檔案地圖」定位要動的模組，只讀那幾段。

---

## 1. 專案核心守則

### 1.1 語言
- 回覆預設使用**繁體中文**。程式識別名稱用英文，註解與文件用繁體中文。

### 1.2 行動確認
- 動手修改任何檔案前，先列出「預計要改哪些檔案、各改什麼」，**等使用者明確同意後才開始改**。
- 判斷：使用者在同一則訊息裡已經說「直接做」「可以開始執行」，視為已同意，不必再問一次。
- 例外：只讀取、搜尋、跑本機伺服器、在瀏覽器測試，不需要事先同意。
- 為什麼：避免改到使用者不想動的地方，修改範圍由使用者掌控。

### 1.3 權限
- 平常**不執行 `git push`**。只有使用者在**當次對話明確說要推送**（例如「推上去」「上傳」「更新網站」）時，才可以推送到 `origin`。
- 判斷：每次推送都要有當次的明確同意，不沿用之前對話或之前那次的同意。完成修改不等於可以推送。
- 推送前必須：`node check.js` 全部通過、工作目錄已 commit 並打 tag。推送指令用 `git push origin main --tags`。
- **絕對不准** `git push --force`、刪除遠端分支或 tag。
- 為什麼：推送後 GitHub Pages 會更新朋友試玩的網站（見 1.7），推送就是對外發布。
- `git commit` 與 `git tag` 依第 1.5 節流程照常執行。

### 1.4 驗收
- 驗收指令：`node check.js`（或 `npm run check`）。**全部通過才算完成**。
- 改到畫面、操作、動畫等 `check.js` 測不到的部分時，另外要在瀏覽器實測（`.claude/launch.json` 的 `cubeborn`），並確認 Console 無錯誤。需要驗證邏輯時，在 Console 用 `__game.update(1/60)` + `__game.input.endStep()` 手動推進並讀數值。
- 新增機制或修好 bug 時，能寫成檢查就補進 `check.js`，避免同樣問題再發生。
- 若 PowerShell 找不到 `node`，用完整路徑 `C:\Program Files\nodejs\node.exe`（安裝後尚未重開的終端機不會有新的 PATH）。
- 檢查沒過時的處理順序：
  1. 先查遊戲本體邏輯，拿程式碼與實測數值證明「遊戲機制是對的」。
  2. 證明之後，才可以修改測試腳本，並在回報中寫明「為什麼是測試錯、不是遊戲錯」。
  3. **嚴禁為了讓測試通過而改測試**（放寬門檻、刪斷言、跳過案例都算）。

### 1.5 每次修改完成後
1. 完成第 1.4 節的驗收。
2. 依 `PROJECT_GUIDELINES.md` 第 12 節升版號，同步更新 `CHANGELOG.md` 與 `src/core/version.js`。
3. `git commit -m "vX.Y.Z: 摘要"`，並 `git tag vX.Y.Z`（不 push）。
4. 新增、刪除、搬移檔案時更新第 4 節「檔案地圖」；架構或核心規則有變時更新 `PROJECT_GUIDELINES.md`。
5. 回覆使用者：新版號、變更摘要、驗證證據、已知問題。

### 1.6 重大修改
- 修改任何**核心玩法**（戰鬥手感、敵人行為、波次節奏、數值平衡、操作方式）前，必須先讀 [`docs/設計方向.md`](docs/設計方向.md)，確認符合設計目標與平衡品味。
- 判斷：只是修 bug 讓行為回到原本設計、或純美術/UI/重構，不算核心玩法。
- 例外：`docs/設計方向.md` 不存在或沒有涵蓋這次要改的部分時，先停下來問使用者設計意圖，不要自己腦補。

### 1.7 試玩網站（GitHub Pages）
- 遊戲以 GitHub Pages 發布給朋友試玩，來源為 `main` 分支根目錄，推送後約 1 分鐘更新。
- 網址：https://alex86106pig.github.io/Cubeborn/ （repo：https://github.com/alex86106pig/Cubeborn ，公開）
- 遊戲必須維持「純靜態檔案、相對路徑」，不能依賴 `node_modules/` 或本機伺服器才能執行，否則網站會壞掉。

### 1.8 轉換期：網頁版 → Godot
- 最終目標是 Steam 上架、多人連線，因此改用 **Godot 4.7.2 普通版（GDScript）** 開發，專案在 `godot/`。
- **網頁版（根目錄）只修 bug、不加新功能**，作為「玩法已驗證的設計圖」：數值、手感、Boss 招式、波次照著搬到 Godot。網頁版的規則（1.4 驗收、1.7 網站）在轉換期間仍適用。
- **Godot 執行檔**：這台電腦是 `E:\Godot\Godot_v4.7.2-stable_win64_console.exe`（指令列用 `_console` 版）。其他電腦路徑可能不同：先找常見位置，找不到就問使用者，不要自己下載安裝。
- 常用指令（在 `godot/` 內）：匯入 `--headless --import --path .`；執行主場景 `--path . -- 參數`。
- 驗證方式：邏輯用 `--headless` 執行並讀輸出；畫面用視窗模式執行並存截圖（目前由壓力測試的 `--screenshot=路徑` 參數提供），截圖存在暫存資料夾、不進版控。
- **多人連線從第一天就設計進架構**（權威端、同步方式），正式規範寫進 `PROJECT_GUIDELINES.md` 後才開始寫遊戲本體。
- 效能判斷依據見 `docs/進度.md` 的壓力測試數字；GDScript 不夠快的部分，才改用 C++（GDExtension）。

---

## 2. AI 效能與開發習慣

### 2.1 精準讀取（省 Token）
- **嚴禁整包讀取 `src/` 或整份大檔案。**
- 平常做法：先查第 4 節檔案地圖 → 用 `Grep` 找變數/函式/事件名稱 → 只用 `offset` + `limit` 讀需要修改的那段。
- 例外：檔案小於約 100 行，或這次要大範圍重構該檔，可以整檔讀。

### 2.2 除錯與驗證
- 提出 Bug 原因時**必須附程式碼證據**（`檔案:行號` 與相關片段），或實測數值。不能只給「可能是…」的假設。
- 同一個方法失敗約 **3 次**，必須強制停下：寫下試過什麼、為什麼失敗，換一條完全不同的路，或向使用者說明卡在哪。嚴禁反覆嘗試同一條錯誤路線。

### 2.3 引擎原生優先
- 實作新功能前，先評估「Three.js（或瀏覽器原生 API）本來就做得到嗎？」。做得到就用原生，不自己重寫一套。
- 例外：原生做法明顯不符合專案規範時（例如需要物理引擎，但規範是自寫 2D 圓形碰撞），照 `PROJECT_GUIDELINES.md` 走，並在回報中說明原因。

### 2.4 量化測試
- 調整手感與平衡時，一律用**具體數字**描述：速度（單位/秒）、幀數、秒數、傷害、存活時間、勝率等。禁止用「感覺比較順」「好像太難」這種描述。
- 數值必須**實際執行量測後**才能定案，並在回報中附上修改前後的數字。
- 可調數值放在 `src/core/config.js` 或 `*Defs.js`，不寫死在邏輯裡。

### 2.5 給使用者挑選的候選方案
- 使用者要「產出幾種不同風格/種類給我挑」時，**不要直接做進遊戲**。
- 平常做法：做成**一頁獨立的對比網頁**（`mockups/<主題>.html`，單一 HTML 檔，用 SVG / CSS 畫示意，不 import 遊戲程式），各方案並排、標上編號與一句特色說明，給使用者看完選定後，才把選中的那一個做進遊戲。
- 判斷：只要結果是「多選一」或「先看看長怎樣」，就走這條。使用者已經明確選定、只差實作時，直接做進遊戲。
- 例外：SVG 示意畫不出重點時（例如 3D 模型的立體比例），先說明限制並問使用者要不要改做獨立 3D 預覽頁，不要自己決定直接做進遊戲。
- 選定並做進遊戲後，刪除該對比頁（git 歷史仍保留），選擇結果記在 CHANGELOG。
- 為什麼：把多個方案都做成遊戲能用的完整版本（角色、敵人、武器、場地、整合測試）會消耗大量 token，而沒選上的全部要再拆掉。

---

## 3. 記憶、交接與規則更新機制

### 3.1 自我更新規則
- 同一個錯誤犯第**兩次**，就必須把防範規則寫進本文件第 5 節「從錯誤學到的規則」。口頭說「下次會注意」無效。
- 規則寫法：**平常怎麼做 ＋ 怎麼判斷 ＋ 例外 ＋ 為什麼**。避免寫死「一律」，以免在不適用的地方硬套。
- 規則過時（相關程式已移除、做法已改變）就**刪除**，不要留著。

### 3.2 進度交接（`docs/進度.md`）
- 換對話接手時，**第一件事讀 `docs/進度.md`**。
- 只記錄四件事：
  1. 卡在哪
  2. 下一步
  3. 試過哪條路、為什麼不走
  4. 哪些結論還沒驗證
- **不寫流水帳**（做過什麼由 CHANGELOG 與 git log 記錄）。
- 問題解決 → 刪除該段落；屬於通則 → 搬進本文件；能用測試擋住 → 寫成測試。
- 長度必須保持在**一個螢幕內能看完**（約 40 行內）。
- 每次結束一個任務前，更新這份檔案。
- 收工前（使用者說要結束、或一個段落完成時）：更新本檔並 commit，然後提醒使用者「要換電腦的話記得叫我推上去」。沒推送的內容，其他電腦看不到。

---

## 4. 檔案地圖

新增、刪除、搬移檔案時必須同步維護此表。

| 檔案 | 職責 |
|---|---|
| `index.html` | 遊戲頁面、importmap、HUD 容器 |
| `preview.html` | 模型檢視頁（並排展示四個角色，可拖曳旋轉） |
| `css/style.css` | HUD 與頁面樣式 |
| `tools/serve.ps1` | 本機靜態伺服器（`http://localhost:5173`） |
| `check.js` | 自動檢查：資料完整性、核心機制、零件合併、音效對應（`node check.js`） |
| `package.json` | Node 設定：檢查指令與檢查用的 three 套件（遊戲本身不需要） |
| `docs/進度.md` | 跨對話交接檔 |
| `docs/設計方向.md` | 設計目標與平衡品味（改核心玩法前必讀） |
| `docs/新電腦設定.md` | 新電腦第一次使用本專案的設定步驟 |
| `mockups/` | 給使用者挑選的對比頁（選定後刪除，見 2.5） |
| `mockups/背景音樂.html` | 背景音樂試聽頁：已選定 B 哥德輓歌，做進 Godot 版時作為參考，完成後刪除 |
| `godot/project.godot` | Godot 專案設定（4.7、Forward+、1920×1080） |
| `godot/stress_test/` | 效能壓力測試：大量敵人與投射物（資料導向 + MultiMesh + 格子碰撞），印出 FPS 與各段邏輯耗時 |
| `src/main.js` | 遊戲進入點：建立 Game 並啟動 |
| `src/preview.js` | 模型檢視頁進入點 |
| `src/Game.js` | 組合根：持有所有系統、主迴圈、命中停頓、暫停、靜音鍵、重新開始、通關 |
| `src/core/config.js` | 全域可調參數（迴圈、世界、相機、玩家、生成、音量、除錯開關） |
| `src/core/version.js` | VERSION 常數（與 CHANGELOG、git tag 同步） |
| `src/core/math.js` | 角度、插值、緩動等數學工具 |
| `src/core/EventBus.js` | 發布/訂閱事件匯流排 |
| `src/core/StateMachine.js` | 通用有限狀態機 |
| `src/core/CooldownManager.js` | 統一冷卻時間管理 |
| `src/core/Input.js` | 鍵盤/滑鼠狀態，「本步按下」查詢 |
| `src/render/Renderer.js` | WebGLRenderer、場景、燈光、正交相機與跟隨 |
| `src/render/rig.js` | 角色骨架 Rig、零件組 PartKit（含零件合併 mergeStatic / optimize）、幾何體工廠、材質工廠 |
| `src/render/environment.js` | 低多邊形地面、邊界點位、裝飾散佈 |
| `src/render/WeaponModels.js` | 玩家武器外觀與姿勢同步 |
| `src/render/Effects.js` | 粒子、揮砍弧光、衝擊環、地面預警 |
| `src/render/styles/index.js` | 風格登錄、getStyle() |
| `src/render/styles/darkFantasy.js` | 暗黑幻想造型（定案）：角色、武器、場地、環境光 |
| `src/entities/Entity.js` | 實體基底：位置、速度、血量、擊退、受傷/死亡 |
| `src/entities/Player.js` | 玩家：雙層狀態機、武器、主動欄位 |
| `src/entities/playerStates.js` | 玩家移動層與動作層狀態 |
| `src/entities/Enemy.js` | 敵人基底：波次倍率、共用狀態、接觸傷害 |
| `src/entities/enemyDefs.js` | 敵人資料（grunt / archer / boss） |
| `src/entities/enemies/MeleeEnemy.js` | 近戰小怪 |
| `src/entities/enemies/RangedEnemy.js` | 遠程小怪 |
| `src/entities/enemies/Boss.js` | Boss：重砸、衝鋒、召喚、狂暴 |
| `src/entities/Projectile.js` | 投射物 |
| `src/combat/Combat.js` | 傷害結算、命中判定、擊退 |
| `src/combat/Physics.js` | 圓形碰撞分離、場地邊界 |
| `src/weapons/weaponDefs.js` | 武器資料（劍盾、法杖） |
| `src/weapons/weaponBehaviors.js` | 武器攻擊/特殊技行為 |
| `src/skills/skillDefs.js` | 主動技能/道具資料 |
| `src/skills/skillBehaviors.js` | 技能行為 canUse / activate |
| `src/skills/ActiveSlots.js` | 數字鍵 1~5 主動欄位 |
| `src/world/Arena.js` | 依風格建立場地 |
| `src/world/waveDefs.js` | 波次表與數值成長 |
| `src/world/Spawner.js` | 分波生成、Boss 出場、召喚 |
| `src/ui/HUD.js` | 血條、技能欄、波次、FPS、靜音提示、Boss 血條、橫幅、暫停與結算畫面 |
| `src/audio/Sound.js` | 音效：Web Audio 即時合成，CUES 音效表，訂閱事件播放 |

---

## 5. 從錯誤學到的規則

依第 3.1 節的寫法新增；過時就刪除。

### 5.1 含反斜線的文字不用 perl / sed 寫入
- 平常做法：文件或程式中要寫入含 `\` 的內容（Windows 路徑如 `E:\Godot\`、正規表示式），用 Edit / Write 工具直接寫，不要放進 perl 或 sed 的替換字串。
- 判斷：替換內容出現 `\` 就算；寫完後用 Grep 搜尋該路徑確認反斜線還在。
- 例外：不含反斜線的大量機械式替換，仍可用 perl / sed。
- 為什麼：perl 與 sed 會把 `\G`、`\n` 等當成跳脫字元吃掉，已發生兩次（v0.3.1 的 Node 路徑、v0.5.0 的 Godot 路徑），而且不會報錯。
