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
- 推送前必須：Godot 檢查 `check.gd` 全部通過（動到 `legacy/` 時另外在 `legacy/` 內跑 `node check.js`）、工作目錄已 commit 並打 tag。推送指令用 `git push origin main --tags`。推送後 GitHub Actions 會自動匯出 Godot 網頁版並發布（見 1.7）。
- **絕對不准** `git push --force`、刪除遠端分支或 tag。
- 為什麼：推送後 GitHub Pages 會更新朋友試玩的網站（見 1.7），推送就是對外發布。
- `git commit` 與 `git tag` 依第 1.5 節流程照常執行。

### 1.4 驗收
- 驗收指令：Godot 自動檢查（在 `godot/` 內）`<Godot console 執行檔> --headless --path . -s res://tests/check.gd`。**全部通過才算完成**。
- 改到畫面、操作、動畫等 `check.gd` 測不到的部分時，另外用離屏截圖驗證（見 1.8，開視窗前先問使用者）。
- 新增機制或修好 bug 時，能寫成檢查就補進 `check.gd`，避免同樣問題再發生。
- 網頁版已凍結並搬到 `legacy/`（見 1.8），平常不跑 `node check.js`；只有動到 `legacy/` 時才在該資料夾內跑。若 PowerShell 找不到 `node`，用完整路徑 `C:\Program Files\nodejs\node.exe`。
- 檢查沒過時的處理順序：
  1. 先查遊戲本體邏輯，拿程式碼與實測數值證明「遊戲機制是對的」。
  2. 證明之後，才可以修改測試腳本，並在回報中寫明「為什麼是測試錯、不是遊戲錯」。
  3. **嚴禁為了讓測試通過而改測試**（放寬門檻、刪斷言、跳過案例都算）。

### 1.5 每次修改完成後
1. 完成第 1.4 節的驗收。
2. 依 `PROJECT_GUIDELINES.md` 第 12 節升版號，同步更新 `CHANGELOG.md` 與 `godot/core/version.gd`（網頁版的 `legacy/src/core/version.js` 已凍結，不再更新）。
3. `git commit -m "vX.Y.Z: 摘要"`，並 `git tag vX.Y.Z`（不 push）。
4. 新增、刪除、搬移檔案時更新第 4 節「檔案地圖」；架構或核心規則有變時更新 `PROJECT_GUIDELINES.md`。
5. 回覆使用者：新版號、變更摘要、驗證證據、已知問題。

### 1.6 重大修改
- 修改任何**核心玩法**（戰鬥手感、敵人行為、波次節奏、數值平衡、操作方式）前，必須先讀 [`docs/設計方向.md`](docs/設計方向.md)，確認符合設計目標與平衡品味。
- 判斷：只是修 bug 讓行為回到原本設計、或純美術/UI/重構，不算核心玩法。
- 例外：`docs/設計方向.md` 不存在或沒有涵蓋這次要改的部分時，先停下來問使用者設計意圖，不要自己腦補。

### 1.7 試玩網站（GitHub Pages）
- 遊戲以 GitHub Pages 發布給朋友試玩。v0.10.0 起由 **GitHub Actions**（`.github/workflows/pages.yml`）在推送 `main` 後自動匯出 Godot 網頁版並發布，約數分鐘更新；repo 不存匯出檔。
- 網址：https://alex86106pig.github.io/Cubeborn/ （Godot 版）；舊網頁版：https://alex86106pig.github.io/Cubeborn/legacy/ （repo：https://github.com/alex86106pig/Cubeborn ，公開）
- repo 的 Settings → Pages → Source 必須是「GitHub Actions」（使用者設定）；如果還是「Deploy from a branch」，推送後網站會變成找不到首頁。
- 網頁版用 Compatibility 渲染器、單執行緒（GitHub Pages 不能設定多執行緒需要的 COOP / COEP 標頭）；介面文字只能用打包的字型（`godot/assets/fonts/`），瀏覽器裡沒有系統字型。
- 網站上的遊戲必須維持「純靜態檔案、相對路徑」，不能依賴本機伺服器才能執行。

### 1.8 轉換期：網頁版 → Godot
- 最終目標是 Steam 上架、多人連線，因此改用 **Godot 4.7.2 普通版（GDScript）** 開發，專案在 `godot/`。
- **網頁版已凍結並搬到 `legacy/`**（使用者決定，v0.8.0 凍結、v0.10.0 搬移）：不修 bug、不加功能、不更新版號，只當「玩法已驗證的設計圖」，數值、手感、Boss 招式、波次照著搬到 Godot；網站的 `/legacy/` 仍可玩。
- **Godot 執行檔**：每台電腦路徑不同，寫在該電腦的 `CLAUDE.local.md`（見 3.3），指令列用 `_console` 版。不要自己下載安裝。
- 常用指令（在 `godot/` 內）：匯入 `--headless --import --path .`；執行主場景 `--path . -- 參數`。
- 驗證方式：邏輯用 `--headless` 執行並讀輸出（不開視窗，隨時可跑）。畫面用離屏截圖場景 `tests/capture.tscn`：`--path . --resolution 64x64 res://tests/capture.tscn -- --seconds=S --screenshot=路徑`（可加 `--auto-move=x,y` 模擬移動）。遊戲畫在看不見的 1920×1080 畫布，截圖是完整解析度；實際視窗只有右下角 64×64、不搶焦點。截圖存在暫存資料夾、不進版控。
- **開 Godot 視窗前先問使用者**（含離屏截圖、壓力測試、任何非 `--headless` 的執行）：
  - 平常做法：先在對話說明要開視窗做什麼，等使用者回答可以才執行；同一次工作需要的截圖集中在最後一次跑完，不中途反覆開。
  - 判斷：使用者在當次對話、針對這次工作已經說「可以開視窗」就不必再問；之前的同意不沿用。使用者沒回應就停在這一步等，改做其他不需要視窗的工作或先回報。
  - 例外：`--headless` 的檢查與匯入不開視窗，不需要問。
  - 禁止直接開一般視窗模式（1920×1080 會蓋滿整個螢幕）；`--position` 開到螢幕外無效，Windows 會拉回畫面內。
  - 為什麼：使用者可能正在玩其他遊戲，突然跳出視窗會害他被打斷；直接開視窗曾經蓋住使用者整個螢幕。
  - 離屏截圖的 FPS 只能參考，效能定案以使用者實際全螢幕遊玩為準。
- **多人連線從第一天就設計進架構**（權威端、同步方式），正式規範寫進 `PROJECT_GUIDELINES.md` 後才開始寫遊戲本體。
- 效能判斷依據見 `docs/進度.md` 的壓力測試數字；GDScript 不夠快的部分，才改用 C++（GDExtension）。

---

## 2. AI 效能與開發習慣

### 2.1 精準讀取（省 Token）
- **嚴禁整包讀取 `godot/`、`legacy/src/` 或整份大檔案。**
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
- 可調數值放在 `godot/core/config.gd` 或 `godot/defs/`，不寫死在邏輯裡。

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

### 3.3 每台電腦的本機設定（`CLAUDE.local.md`）
- 使用者在三台電腦輪流開發，各台的專案路徑、Godot 路徑、硬體不同。這些寫在專案根目錄的 `CLAUDE.local.md`：會自動載入，但不進版控，每台各一份。
- 內容：電腦名稱（使用者自取，只供辨識）、專案路徑、Godot 與 Node 執行檔路徑、硬體、該台壓力測試數字。
- 判斷：開工時沒看到 `CLAUDE.local.md` 的內容 → 這台還沒設定，先問使用者電腦名稱與 Godot 路徑，再建立（建立本檔不需另外同意）。
- 本檔（`CLAUDE.md`）與其他進版控的檔案不寫任何單一電腦的絕對路徑。
- 為什麼：寫死在共用檔案的路徑換到別台就錯，而且三台會互相改來改去。

---

## 4. 檔案地圖

新增、刪除、搬移檔案時必須同步維護此表。

| 檔案 | 職責 |
|---|---|
| `.github/workflows/pages.yml` | 推送 main 後自動：下載 Godot 與網頁模板 → 跑 `check.gd` → 匯出網頁版 → 加上 `/legacy/` → 發布 GitHub Pages |
| `tools/serve_web.ps1` | 本機測試網頁匯出（`build/web`，`http://localhost:8060`）；檔案須維持純 ASCII |
| `build/web/` | 本機網頁匯出輸出（不進版控） |
| `legacy/` | **已凍結的網頁版（Three.js）**，網站 `/legacy/` 仍可玩；以下 `legacy/` 開頭的都是它 |
| `legacy/index.html` | 遊戲頁面、importmap、HUD 容器 |
| `legacy/preview.html` | 模型檢視頁（並排展示四個角色，可拖曳旋轉） |
| `legacy/css/style.css` | HUD 與頁面樣式 |
| `legacy/tools/serve.ps1` | 本機靜態伺服器（`http://localhost:5173`） |
| `legacy/check.js` | 自動檢查：資料完整性、核心機制、零件合併、音效對應（`node check.js`） |
| `legacy/package.json` | Node 設定：檢查指令與檢查用的 three 套件（遊戲本身不需要） |
| `CLAUDE.local.md` | 本機設定：電腦名稱、路徑、硬體（每台各一份，不進版控，見 3.3） |
| `docs/進度.md` | 跨對話交接檔 |
| `docs/設計方向.md` | 設計目標與平衡品味（改核心玩法前必讀） |
| `docs/新電腦設定.md` | 新電腦第一次使用本專案的設定步驟 |
| `docs/道具清單.md` | 道具草稿（白綠藍紫橘 45 個）、背包大小、強度與格數的平衡做法 |
| `docs/想法清單.md` | 使用者隨時提出、還沒定案的點子與 Claude 的評估（定案後移到設計方向或進度） |
| `docs/製作計畫.md` | 階段 A~E 的里程碑：每步做出什麼、使用者怎麼驗證、補什麼檢查、開工前要問什麼 |
| `docs/手感對照.md` | 網頁版 vs Godot 版的數值與手感對照表（第 7 步的結果） |
| `tools/dump_web_defs.mjs` | 把網頁版的設定與資料表匯出成 `godot/tests/web_defs.json`（`node tools/dump_web_defs.mjs`） |
| `mockups/` | 給使用者挑選的對比頁（選定後刪除，見 2.5） |
| `godot/project.godot` | Godot 專案設定（4.7、Forward+、1920×1080、預設字型 `hud_font.tres`） |
| `godot/export_presets.cfg` | 匯出設定：「Web」（單執行緒、輸出到 `../build/web/index.html`，排除 tests / stress_test） |
| `godot/assets/fonts/` | 打包字型 Noto Sans TC（OFL 授權，見該資料夾 README）與字重 700 的 `hud_font.tres` |
| `godot/main.tscn` / `main.gd` | Godot 組合根：單機 / 房主 / 客戶端三種模式、大廳（開房、加入、開始、離開連線）、主迴圈（每秒 60 步）、通關慢動作、暫停 / 選單、重新開始、離開遊戲、畫面震動、特效與命中定格事件轉給畫面層、Tab 屬性面板、F3 除錯移速 +50%、F4 / F5 除錯放入 / 清空道具（F3~F5 單機才有）、自動驗證參數（`--seconds`、`--screenshot`、`--auto-move`、`--auto-move-seconds`、`--auto-attack`、`--auto-special`、`--auto-interact`、`--weapon`、`--wave`、`--player-hp`、`--items`、`--no-spawn`、`--host`、`--join=IP`、`--net-port`、`--net-autostart=N`、`--net-latency`、`--net-loss`） |
| `godot/net/` | 多人連線（15.18）：net_session（ENet 傳輸、RPC、大廳、模擬延遲 / 掉包）、net_host（房主：輸入排隊、ack、快照）、net_client（客戶端：鏡像 World、補間與外推、自己角色的預測修正、事件延到畫面時間）、net_codec（快照編碼 / 套用） |
| `godot/core/` | config、version、math_util、state_machine、cooldowns、game_events（autoload `GameEvents`） |
| `godot/defs/` | 資料表：weapon_defs（劍盾、法杖）、enemy_defs（grunt / archer / boss）、wave_defs（5 波與成長倍率）、skill_defs（治療藥水、疾跑）、stat_defs（屬性名稱、基礎值、上下限、顯示格式、護甲公式）、terrain_defs（地形石台，目前是角落的測試石台）、item_defs（武器與 45 個道具：稀有度、占格形狀、效果列表） |
| `godot/sim/` | 模擬層（不碰場景樹）：world（含通關流程、倒下與救援、客戶端的本機預測 step_predicted）、input_cmd、stats（屬性計算：加值 / 百分比 / 相乘、依來源加入移除）、terrain（地面高度、石台當牆、投射物撞牆）、hitbox（通用攻擊判定：扇形 / 圓形、只打一次、能否格擋、記錄給 F2）、entity（含高度、重力、落地）、player（含翻滾充能）、player_states（雙層狀態機，含翻滾）、weapon_behaviors、combat、projectile、enemy（敵人基底與共用狀態）、spawner（分波生成）、physics（格子碰撞分離）、active_slots（數字鍵欄位）、skill_behaviors |
| `godot/sim/enemies/` | melee_enemy（追擊、舉刀揮砍）、ranged_enemy、boss；v0.17.0 起沒有碰撞傷害 |
| `godot/input/input_collector.gd` | 按鍵註冊、InputMap → InputCmd（螢幕方向轉世界、滑鼠投射地面、鎖存按下） |
| `godot/view/` | 畫面層：camera_rig（正交等距相機）、world_view（依 id 建模型、補間、命中定格（預設關）、F2 碰撞圈與攻擊判定形狀）、effects（特效：粒子、揮砍弧光、衝擊環、預警圈；fx:* 事件與持續性粒子）、rig（關節階層、換武器、閃白、同種角色共用合併好的零件）、part_kit（形狀工廠、材質、零件合併與平面法線）、animator（玩家姿勢）、enemy_animator（敵人姿勢、Boss 地面預警）、arena_view（場地、地形石台、地面 / 散佈工具） |
| `godot/view/styles/dark_fantasy.gd` | 暗黑幻想造型（照搬 `darkFantasy.js`）：騎士、骷髏戰士、骷髏弓手、亡骸騎士、劍盾、法杖、箭矢、墓地場地 |
| `godot/ui/hud.tscn` / `hud.gd` | Godot HUD：血條、波次 / 擊殺 / 時間、Boss 血條、屬性面板、橫幅、受擊暗角、暫停（含離開遊戲按鈕）與結算畫面 |
| `godot/ui/skill_bar.gd` / `floaters.gd` / `ui_kit.gd` | 技能欄（左鍵、右鍵、Shift 翻滾、1~5；CD 遮罩、次數）、浮動數字、HUD 共用的文字 / 色塊 / 顏色 |
| `godot/ui/stats_panel.gd` | 屬性面板（Tab 開關），有加成的數值以金色標示 |
| `godot/ui/net_panel.gd` / `player_tags.gd` | 選單裡的連線面板（開房、IP 加入、大廳名單、開始、離開連線）；多人時頭上的 P1~P4 名牌與倒地倒數 / 救援進度條 |
| `godot/ui/skill_icons.gd` | 字型沒有的圖示（⚔ 🛡 ✦ ✺、翻滾 ⟳）改用向量圖畫 |
| `godot/audio/sound.gd` | 音效與背景音樂：事件 → 音效（照網頁版）、多音播放、M 鍵靜音（存 `user://settings.cfg`）、一般 / Boss 曲切換與淡出 |
| `godot/audio/sfx/`、`godot/audio/music/` | 預先產生的 WAV（30 個音效、B 哥德輓歌一般 / Boss 兩首循環曲）；由 `godot/tools/` 產生，不要手改 |
| `godot/tools/synth.gd` | 離線合成：振盪器、指數漸變、Web Audio 公式的濾波器、白噪音、寫 WAV（含循環點） |
| `godot/tools/bake_sfx.gd` / `bake_music.gd` | 產生音效 / 背景音樂 WAV（headless：`--headless --path . -s res://tools/bake_sfx.gd`），之後要 `--import` |
| `godot/tests/web_defs.json` | 網頁版數值的存檔，`check.gd` 逐欄比對用（由 `tools/dump_web_defs.mjs` 產生，不要手改） |
| `godot/tests/check.gd` | Godot 自動檢查（headless：`--headless --path . -s res://tests/check.gd`） |
| `godot/tests/net_checks.gd` | 連線（C1~C4）的檢查，由 check.gd 呼叫：同程序假網路（延遲 / 掉包）比對房主與客戶端、開兩個 headless 程序實際連線 |
| `godot/tests/capture.tscn` / `capture.gd` | 畫面測試專用：離屏 1920×1080 繪製＋右下角 64×64 不搶焦點視窗，供截圖驗證（見 1.8） |
| `godot/stress_test/` | 效能壓力測試：大量敵人與投射物（資料導向 + MultiMesh + 格子碰撞），印出 FPS 與各段邏輯耗時 |
| `legacy/src/main.js` | 遊戲進入點：建立 Game 並啟動 |
| `legacy/src/preview.js` | 模型檢視頁進入點 |
| `legacy/src/Game.js` | 組合根：持有所有系統、主迴圈、命中停頓、暫停、靜音鍵、重新開始、通關 |
| `legacy/src/core/config.js` | 全域可調參數（迴圈、世界、相機、玩家、生成、音量、除錯開關） |
| `legacy/src/core/version.js` | VERSION 常數（網頁版已凍結於 0.7.0，不再更新） |
| `legacy/src/core/math.js` | 角度、插值、緩動等數學工具 |
| `legacy/src/core/EventBus.js` | 發布/訂閱事件匯流排 |
| `legacy/src/core/StateMachine.js` | 通用有限狀態機 |
| `legacy/src/core/CooldownManager.js` | 統一冷卻時間管理 |
| `legacy/src/core/Input.js` | 鍵盤/滑鼠狀態，「本步按下」查詢 |
| `legacy/src/render/Renderer.js` | WebGLRenderer、場景、燈光、正交相機與跟隨 |
| `legacy/src/render/rig.js` | 角色骨架 Rig、零件組 PartKit（含零件合併 mergeStatic / optimize）、幾何體工廠、材質工廠 |
| `legacy/src/render/environment.js` | 低多邊形地面、邊界點位、裝飾散佈 |
| `legacy/src/render/WeaponModels.js` | 玩家武器外觀與姿勢同步 |
| `legacy/src/render/Effects.js` | 粒子、揮砍弧光、衝擊環、地面預警 |
| `legacy/src/render/styles/index.js` | 風格登錄、getStyle() |
| `legacy/src/render/styles/darkFantasy.js` | 暗黑幻想造型（定案）：角色、武器、場地、環境光 |
| `legacy/src/entities/Entity.js` | 實體基底：位置、速度、血量、擊退、受傷/死亡 |
| `legacy/src/entities/Player.js` | 玩家：雙層狀態機、武器、主動欄位 |
| `legacy/src/entities/playerStates.js` | 玩家移動層與動作層狀態 |
| `legacy/src/entities/Enemy.js` | 敵人基底：波次倍率、共用狀態、接觸傷害 |
| `legacy/src/entities/enemyDefs.js` | 敵人資料（grunt / archer / boss） |
| `legacy/src/entities/enemies/MeleeEnemy.js` | 近戰小怪 |
| `legacy/src/entities/enemies/RangedEnemy.js` | 遠程小怪 |
| `legacy/src/entities/enemies/Boss.js` | Boss：重砸、衝鋒、召喚、狂暴 |
| `legacy/src/entities/Projectile.js` | 投射物 |
| `legacy/src/combat/Combat.js` | 傷害結算、命中判定、擊退 |
| `legacy/src/combat/Physics.js` | 圓形碰撞分離、場地邊界 |
| `legacy/src/weapons/weaponDefs.js` | 武器資料（劍盾、法杖） |
| `legacy/src/weapons/weaponBehaviors.js` | 武器攻擊/特殊技行為 |
| `legacy/src/skills/skillDefs.js` | 主動技能/道具資料 |
| `legacy/src/skills/skillBehaviors.js` | 技能行為 canUse / activate |
| `legacy/src/skills/ActiveSlots.js` | 數字鍵 1~5 主動欄位 |
| `legacy/src/world/Arena.js` | 依風格建立場地 |
| `legacy/src/world/waveDefs.js` | 波次表與數值成長 |
| `legacy/src/world/Spawner.js` | 分波生成、Boss 出場、召喚 |
| `legacy/src/ui/HUD.js` | 血條、技能欄、波次、FPS、靜音提示、Boss 血條、橫幅、暫停與結算畫面 |
| `legacy/src/audio/Sound.js` | 音效：Web Audio 即時合成，CUES 音效表，訂閱事件播放 |

---

## 5. 從錯誤學到的規則

依第 3.1 節的寫法新增；過時就刪除。

### 5.1 含反斜線的文字不用 perl / sed 寫入
- 平常做法：文件或程式中要寫入含 `\` 的內容（Windows 路徑如 `E:\Godot\`、正規表示式），用 Edit / Write 工具直接寫，不要放進 perl 或 sed 的替換字串。
- 判斷：替換內容出現 `\` 就算；寫完後用 Grep 搜尋該路徑確認反斜線還在。
- 例外：不含反斜線的大量機械式替換，仍可用 perl / sed。
- 為什麼：perl 與 sed 會把 `\G`、`\n` 等當成跳脫字元吃掉，已發生兩次（v0.3.1 的 Node 路徑、v0.5.0 的 Godot 路徑），而且不會報錯。

### 5.2 headless 執行 Godot 腳本要設逾時，輸出不要接 `head`
- 平常做法：`-s` 腳本、`--import` 用 PowerShell `Start-Process … -RedirectStandardOutput/-RedirectStandardError -PassThru`，再 `WaitForExit(毫秒)`，逾時就 `Kill()` 並讀錯誤檔。不要把 Godot 輸出接到 `head`、`Select-Object -First`。
- 判斷：新寫或剛改過的 `-s` 腳本（`extends SceneTree`）一定照做；已經穩定跑過的 `check.gd` 也建議照做。
- 例外：只有一行、確定不會卡住的指令（例如 `--version`）。
- 為什麼：`-s` 腳本有編譯錯誤時 `_initialize` 不會呼叫 `quit()`，Godot 會閒置到天荒地老；輸出接 `head` 提早關閉管線也會讓 Godot 卡住。v0.12.0 兩種各發生一次，各浪費 5~10 分鐘。
