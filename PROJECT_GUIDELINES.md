# Cubeborn 專案開發守則

> 本文件是專案的**唯一事實來源**。任何與本文件衝突的程式碼都視為 bug；架構變更時必須同步更新本文件。

> 本文件只放**現行、共通**的規則（Godot 4.7.2，GDScript，專案在 `godot/`）。各系統的細節與使用者做過的決定（屬性、翻滾、連線、地圖、背包、怪群、挖墳…）在 [`docs/系統說明.md`](docs/系統說明.md)，要動那個系統時讀對應的一節。凍結的網頁版（`legacy/`）規則在 [`legacy/GUIDELINES.md`](legacy/GUIDELINES.md)。
> 節號（2026-10-26 整理）：第 4~14 節沿用舊版節號；舊的 15.1~15.10 分到第 1~3、15~17 節，15.11~15.26 = 系統說明 §1~§16。

---

## 1. 目標與已定案的方向

| 項目 | 決定 |
|---|---|
| 類型 | 3D 等距俯視角 Roguelike 動作遊戲，目標 Steam 上架 |
| 引擎 | Godot 4.7.2 普通版，GDScript（一律寫型別）；效能不夠的熱點才改 C++（GDExtension），判斷依據見 `docs/效能.md` |
| 平台 | Windows 優先。網頁匯出（GitHub Pages）給朋友試玩：網頁用 Compatibility 渲染器（`project.godot` 的 `.web` 覆寫），電腦版維持 Forward+；網頁版只能用房號連線（WebRTC） |
| 多人 | **合作 1~4 人**，不做對戰 |
| 連線架構 | **房主當伺服器**（listen server，房主即權威端）。開發期用 Godot 內建 ENet / WebRTC，上架前換成 Steam 連線（GodotSteam），只換傳輸層 |
| 美術 | **程式生成**低多邊形暗黑幻想造型（寫實比例、硬朗多面體、月夜墓地，第 14 節），不用外部模型與貼圖 |
| 音效 | 合成公式寫在工具腳本，預先產生 WAV 檔放進專案（不在遊戲中即時合成）；背景音樂為已選定的「B 哥德輓歌」 |
| 設計目標 | 見 `docs/設計方向.md`；改核心玩法前先讀（`CLAUDE.md` 1.6） |

## 2. 三層分離（最重要的規則）
```
輸入層（本機）        模擬層（只在權威端跑）              畫面層（每台都跑）
InputCollector ──► InputCmd ──► World.step(cmds, dt) ──► 快照 + 事件 ──► WorldView / HUD / Sound
```
- **模擬層（`sim/`）**：遊戲的全部規則（移動、狀態機、命中、傷害、CD、生成、勝敗）。只用 `RefCounted` 類別與資料，**不繼承 Node、不碰場景樹**。
  - 禁止使用：`Input`、`get_node` / `$`、任何 `Node` 型別、`Engine.time_scale`、全域 `randf()` / `randi()`、`Time.get_ticks_*`、讀檔。`tests/check.gd` 會掃描 `sim/` 擋住這些字。
  - 時間只來自 `step()` 傳入的 `dt`；隨機只用 `world.rng`（`RandomNumberGenerator`，種子由權威端決定）。
  - 輸出只有兩種：可讀取的狀態（實體列表、CD、波次）與本步的事件列表 `world.events`。
- **輸入層（`input/`）**：把 Godot 的 `InputMap` 動作轉成一筆 `InputCmd`。螢幕方向的 WASD 在這裡轉成世界 XZ 向量、滑鼠在這裡投射到地面得到瞄準點，模擬層只看到世界座標。`InputCmd` 本身放在 `sim/`：它是模擬層的輸入格式（連線時原樣傳送），`input/` 只負責產生它。
- **畫面層（`view/`、`ui/`、`audio/`）**：依實體 id 建立 / 移除模型，每個渲染幀讀模擬狀態擺位置與姿勢；消化事件來播特效、音效、更新 HUD。**畫面層不得修改模擬狀態**。
- **單機 = 沒有連線的房主**：單機時本機同時當權威端與玩家，走的是跟連線房主完全相同的程式路徑，不另寫一套單機邏輯。

## 3. 目錄結構（`godot/`）
```
godot/
├─ project.godot
├─ main.tscn / main.gd        組合根：建立 world、輸入、畫面，主迴圈、三種模式（單機 / 房主 / 客戶端）、重新開始
├─ core/                      與遊戲內容無關：config.gd、version.gd、math_util.gd、state_machine.gd、cooldowns.gd、
│                             game_events.gd（autoload GameEvents）
├─ defs/                      資料表（第 8 節）：weapon / skill / enemy / wave / stat / item / map / loot / weapon_drop /
│                             monster_rarity / event / hint_defs.gd
├─ sim/                       模擬層：world、input_cmd、stats、terrain、nav、vision、hitbox、entity、player、player_states、
│  │                          loadout、inventory、item_effects、enemy、projectile、combat、physics、spawner、chest、item_pickup、
│  │                          dig_event、weapon_behaviors、skill_behaviors、active_slots
│  └─ enemies/                melee_enemy、ranged_enemy、boss
├─ input/                     input_collector.gd（按鍵在程式中註冊，不寫在 project.godot）
├─ net/                       連線：net_session（ENet / WebRTC 傳輸、RPC、大廳）、peerjs_signaling（房號配對）、net_host（輸入排隊、快照）、
│                             net_client（鏡像 World、補間、預測修正）、net_codec（快照二進位編碼）
├─ view/                      world_view、arena_view、camera_rig、animator、enemy_animator、rig、skinned_rig、part_kit、effects
│  └─ styles/                 dark_fantasy.gd（第 14 節）
├─ ui/                        hud.tscn / hud.gd、skill_bar、stats_panel、inventory_panel、floaters、world_labels、health_bars、hints、
│                             main_menu、net_panel、player_tags、run_log、skill_icons、ui_kit
├─ audio/                     sound.gd、sfx/*.wav、music/
├─ debug/                     launch_args（指令列參數）、perf_meter（--perf）、debug_tools（F3~F5、--items 等）
├─ tools/                     synth.gd（離線合成）、bake_sfx.gd / bake_music.gd（headless 產生音效 / 背景音樂 WAV）
├─ tests/                     check.gd（headless 自動檢查的執行器）、check_kit.gd（共用工具）、*_checks.gd（依主題分檔的檢查）、
│                             capture.tscn / capture.gd（離屏截圖）
└─ stress_test/               效能壓力測試（保留作為效能基準）
```
- 依賴方向：`core` ← `defs` ← `sim` ← `view` / `ui` / `audio` / `net` / `debug` ← `main`。`sim` 不得引用 `view`、`ui`、`audio`、`input`、`net`、`debug`。
- `main.gd` 是唯一的組合根，負責建立並串接所有系統；模組之間透過建構時注入或事件溝通，不用全域變數（autoload 只有 `GameEvents`）。
- **一個檔案一個主要職責**，單檔約 300 行就考慮拆分。新增、刪除、搬移檔案時同步更新本節與 `docs/檔案地圖.md`。
- 網頁版檔案對應：`Game.js → main.gd + sim/world.gd`、`Input.js → input/`、`Renderer.js → view/camera_rig.gd`、`render/rig.js → view/rig.gd + part_kit.gd`、`*Defs.js → defs/`、`EventBus.js → GameEvents autoload`、`HUD.js → ui/`、`Sound.js → audio/ + tools/bake_sfx.gd`，其餘同名改 snake_case。

---

## 4. 座標、單位與時間

- **單位**：1 單位 = 1 個方塊 ≈ 1 公尺。人形高約 2 單位。
- **座標**：Y 軸朝上，地面 `y = 0`。邏輯在 XZ 平面運算（模擬層用 `Vector2(x, z)`），高度另外記在 `entity.height`（系統說明 §3）。
- **角度**：弧度。`facing = atan2(dx, dz)`（0 = 面向 +Z）；模型面向 +Z 建模，`rotation.y = facing` 可直接套用。
- **時間**：秒。所有速度、CD、持續時間都以秒為單位。
- **主迴圈**：模擬固定每秒 60 步，用 Godot 內建 `_physics_process`（`physics_ticks_per_second=60`、`max_physics_steps_per_frame=5`；等於預設值的設定 Godot 存檔時會從 `project.godot` 刪掉，看不到是正常的）。不使用 Godot 的物理引擎與物理節點，只借用它的固定步長。
- `main.gd` 在 `_physics_process` 收集輸入 → `world.step()` → 分送事件；畫面在 `_process` 以 `Engine.get_physics_interpolation_fraction()` 在上一步與這一步的位置之間補間。
- **更新順序**（`World.step`）：CD → 玩家 → 敵人 → 投射物 → 位移積分 → 碰撞分離 → 場地與地形限制 → 垂直移動 → 生成器 / 事件 → 清除已移除物件。
- **輸入**：「本步按下」由 `InputCollector` 鎖存：兩次 `step` 之間按過就算，送出後才清除，高更新率螢幕也不漏按。
- **命中定格**（v0.18.3 使用者決定，取代網頁版的整體放慢）：模擬時間照常走，`entity:damaged` 帶 `hit_stop` 秒數，畫面層（`world_view.gd`）讓攻擊者與目標的模型停住、之後跟上。只是畫面效果。**v0.19.1 起預設關閉**（`Config.FEEL.hit_freeze = false`），事件仍帶 `hit_stop`，要加回來只改開關。
- 整體放慢只剩打倒 Boss 的 0.25 秒慢動作：邏輯時間放慢到 5%，**每步仍是 `FIXED_DT`**（只是少跑幾步）。模擬層用 `world.hit_stop(秒)` 記錄，`main.gd` 每個真實固定步呼叫 `world.consume_hit_stop()` 取得縮放。
- 畫面震動：玩家方的攻擊打中不震動（`Config.FEEL.player_attack_shake = false`，v0.18.3 使用者決定）；玩家被打、Boss 砸地 / 撞牆 / 狂暴 / 登場、通關照常震動。
- 實體與 `World` 互相參照（RefCounted 循環），移除實體、`reset()` 與結束遊戲時必須經過 `world.clear()` / 移除流程切斷參照，否則記憶體洩漏（`check.gd` 有檢查）。
- 暫停：單機時 `Esc` 停止呼叫 `step()`，失去焦點自動暫停；連線時 `Esc` 只開選單，模擬不停。

---

## 5. 操作對應

按鍵在 `input/input_collector.gd` 註冊。

| 輸入 | 功能 |
|---|---|
| WASD | 移動，**以螢幕方向為準**（W = 畫面上方，世界座標為斜向） |
| 滑鼠游標 | 投射到地面得到瞄準點，角色面朝該點 |
| 滑鼠左鍵 | 普通攻擊（按住可連續攻擊）；拿盾格擋中按 = 招架 |
| 滑鼠右鍵 | 武器特殊技：有副手時是副手的（木盾：按住格擋；副手匕首：影步），沒有副手時是主手的（長劍：蓄力突刺；法杖：奧術爆裂） |
| 空白鍵 | 跳躍（系統說明 §3） |
| Shift | 翻滾（系統說明 §2；受次數與回充管理） |
| 1 ~ 5 | 主動欄位（受 CD 或次數管理） |
| F | 撿道具、開寶箱；按住救援倒地的隊友、挖墳 |
| Tab | 背包與屬性面板 |
| R | 死亡或通關後重新開始（連線時只有房主能按）；拖著背包道具時旋轉 |
| Esc | 暫停 / 選單（失去焦點時自動暫停；死亡或通關畫面不能暫停）；連線時只開選單、遊戲不停 |
| M | 靜音切換 |
| F2 | 除錯：顯示碰撞與命中範圍 |
| F3 / F4 / F5 | 除錯（只有單機）：移速 +50% / 放入下一個道具 / 清空道具 |

---

## 6. 狀態機

### 6.1 通用 StateMachine（`core/state_machine.gd`）
- 狀態是一個物件，可實作 `enter(ctx, data, fsm)`、`update(ctx, dt, fsm)`、`exit(ctx, fsm)`、`can_exit(ctx, next, fsm) -> bool`，皆為選用。
- 只能透過 `fsm.change(name, data)` 切換（`can_exit` 拒絕時回傳 false）；**禁止**直接改 `fsm.current`。
- 可讀：`fsm.current_name`、`previous_name`、`time`（進入此狀態後經過的秒數）、`data`（每次進入時重建，放這次執行的暫存資料）；`fsm.is_in(name)`。
- 狀態名稱用 StringName、camelCase，例如 `&"idle"`、`&"useItem"`。

### 6.2 玩家雙層狀態機（`sim/player_states.gd`）
| 層 | 狀態 | 說明 |
|---|---|---|
| 移動層 | `idle` / `move` / `downed` / `dead` | 只處理位移 |
| 動作層 | `ready` / `attack` / `special` / `useItem` / `stagger` / `roll` / `revive` / `dig` | 攻擊、技能、硬直、翻滾、救援、挖墳 |

- 兩層各自 update，**動作層可以限制移動層**：每個動作在 `data.move_speed_mul` 宣告移速倍率（例如硬直 0）；`data.lock_facing = true` 鎖定轉向。
- 攻擊類動作固定分三段：**`windup`（前搖）→ `active`（判定）→ `recovery`（後搖）**（`PlayerStates.PHASES`）。命中判定只在 `active` 期間生效，每次出手同一目標只命中一次。時間長度一律來自武器 / 技能的資料，狀態本身不寫死數值。
- 動作層輸入有**緩衝**（`Config.PLAYER.action_buffer_time`）：先存入 `player.buffered_action`，由 `ready` 狀態消化；攻擊後搖期間若有緩衝會直接取消後搖。
- `dead` 為終止狀態，進入後兩層都不再接受輸入。多人時生命歸零先進 `downed`（系統說明 §8）。
- 模擬層只記錄動畫所需的資料 `player.anim`，姿勢在畫面層算（第 11 節）。

### 6.3 敵人（`sim/enemy.gd`、`sim/enemies/`）
敵人使用同一個 `StateMachine`。`Enemy.base_states()` 提供共用狀態 `dormant`（怪群休眠）/ `spawn`（從地底爬出）/ `hurt`（硬直）/ `dead`，子類別把自己的狀態合併進去，並以 `main_state` 指定爬出、醒來與硬直結束後回到哪個狀態。

| 類別 | 狀態 | 說明 |
|---|---|---|
| `MeleeEnemy` | `chase` / `swing` / `rush` | 追擊、舉刀揮砍（系統說明 §4）、狂暴 Boss 召喚的衝撞 |
| `RangedEnemy` | `kite` / `aim` | 保持距離並橫移；冷卻好時停下瞄準再發射 |
| `Boss` | `chase` / `cleave` / `slam` / `charge` / `summon` | 霸體（拿掉 `hurt`）；招式見系統說明 §13 |

- 行為類別由資料表的 `behavior` 欄位決定（`Spawner.behavior_class`），流程只看 `behavior`、`is_boss` 等欄位，不寫死怪物種類。
- 敵人的招式冷卻同樣用 `CooldownManager`，key 由 `Enemy.cd(招式)` 產生（`enemy<id>.<招式>`），在 `on_added()` 之後才開始；敵人移除時 `reset`。

### 6.4 武器行為介面（`sim/weapon_behaviors.gd`）
每個行為類別（繼承 `Behavior`）可實作以下函式，由 `attack` / `special` 狀態呼叫：

| 函式 | 呼叫時機 |
|---|---|
| `enter(p, def, data)` | 進入動作時（可修改 `data.durations` 調整三段時間） |
| `phase(p, def, data, name)` | 每個階段開始時（`windup` / `active` / `recovery`），產生投射物、發特效事件 |
| `update(p, def, data, name, k, dt)` | 每步呼叫，`k` 為階段進度 0~1；負責命中判定 |
| `exit(p, def, data)` | 離開動作時（含被打斷），負責還原暫時狀態 |

---

## 7. 冷卻時間（CD）管理

- 全遊戲只有**一個** `CooldownManager`（`core/cooldowns.gd`），由 `world.cooldowns` 持有，於 `World.step` 中 `tick(dt)`。
- Key 命名規則：`<擁有者>.<用途>`，例如 `player.special`、`player.slot1`、`player.roll`。多人時每位玩家實際存在 `Player.cd(key)`（`key@peer_id`）；事件與 HUD 仍用 `player.special` 這類名稱。
- API：`start(key, duration)`、`tick(dt)`、`is_ready(key)`、`remaining(key)`（剩餘秒數）、`progress(key)`（0~1，1 = 冷卻完成，給 HUD 畫遮罩）、`reset(key)`、`reset_all()`。
- **適用範圍**：右鍵特殊技、數字鍵 1~5、翻滾回充、敵人招式。左鍵普攻不使用 CD，攻擊頻率由動作的前搖 / 後搖時間決定。
- 冷卻縮減屬性乘在 `start` 的時間上（系統說明 §1）。
- 嘗試在冷卻中觸發時，發出 `skill:onCooldown` 事件（HUD 閃爍提示），不做其他事。

---

## 8. 資料驅動的內容定義

- 內容都是「資料 + 行為」分離：數值放在 `defs/*.gd` 的 `const` Dictionary（不用 `.tres` Resource），邏輯放在 `sim/` 的行為類別。新增內容時優先只加一份資料。
- Key 用 StringName（`&"swordShield"`），欄位名稱 snake_case（從網頁版搬來的照原名改 snake_case，方便對照）。
- 資料表與對應的行為：

| 資料表 | 內容 | 行為 / 使用者 |
|---|---|---|
| `weapon_defs.gd` `WEAPONS` | 武器的 `attack`（左鍵）、`special`（右鍵）：`behavior`、傷害、範圍、三段時間、`move_speed_mul` | `WeaponBehaviors`（`behavior` 對應類別） |
| `skill_defs.gd` `SKILLS` | 主動欄位：`mode`（`&"cooldown"` / `&"charges"`）、`cooldown`、`charges`、`behavior` | `SkillBehaviors`、`ActiveSlots` |
| `enemy_defs.gd` `ENEMIES` | 每種怪的 `visual`、`behavior`（melee / ranged / boss）、`is_boss`、`freeze_immune`、數值與招式 | `Spawner.behavior_class`、`sim/enemies/` |
| `wave_defs.gd` | 波次表（每波 `spawns`、`is_boss`）、波次成長 | `Spawner` |
| `stat_defs.gd` | 屬性名稱、基礎值、上下限、顯示方式 | `Stats`（系統說明 §1） |
| `item_defs.gd` | 道具與武器、稀有度、形狀、效果（屬性 / 條件 / 觸發 / 能力） | `ItemEffects`（系統說明 §6、§16） |
| `map_defs.gd` | 地圖、石台、寶箱、生成規則 | `World.load_map`（系統說明 §9） |
| `loot_defs.gd`、`weapon_drop_defs.gd` | 金幣、寶箱、武器掉落與詞條 | 系統說明 §11、§12 |
| `monster_rarity_defs.gd` | 怪物稀有度、詞條、怪群 | 系統說明 §14 |
| `event_defs.gd` | 挖墳事件、難度 | 系統說明 §15 |
| `hint_defs.gd` | 新手提示文字 | `ui/hints.gd` |
| `class_defs.gd` | 職業：基礎數值、起始武器、被動、模型配色 | `Player.apply_class`（系統說明 §18） |

- 道具效果的條件與動作是 `ItemEffects` 的類別，用 `CONDITIONS` / `ACTIONS` 查表；新增時加一個類別並登錄，再把名稱加進 `ItemDefs.IMPLEMENTED_*`（`check.gd` 會比對兩邊一致）。
- 可調數值放 `core/config.gd` 或 `defs/`，邏輯內不寫魔術數字。

---

## 9. 事件

- 模擬層每步把事件 append 到 `world.events`（`world.emit_event(name, payload)`；`{ "name": String, ... }`，**只放 id 與數值，不放物件參照**，才能透過網路傳送），步驟結束後由組合根交給 `GameEvents`（autoload）以訊號 `event_emitted(name, payload)` 發出。
- 事件名稱格式：`<領域>:<動作>`，例如 `entity:damaged`、`player:died`、`skill:onCooldown`。payload 一律為單一 Dictionary。
- payload 的 `name` 欄位保留給事件名稱（`emit_event` 會擋下衝突），所以 `sfx:cue` 的音效名稱放在 `cue`（必須是 `audio/sound.gd` 的 `CUE_NAMES` 之一，`check.gd` 會檢查）。
- 事件用於**通知**（UI、特效、音效），只有畫面層訂閱；模擬層內部流程用直接呼叫。震動是 `camera:shake`，特效是 `fx:*`（系統說明 §7），模擬層不能直接呼叫畫面。
- 玩家自己的動作途中發出的事件會被 World 加上 `actor`（peer id），客戶端用它丟掉自己已經本機預測播過的事件（系統說明 §8）；命中結果與盾反不加。
- 所有事件名稱必須列在下表（`check.gd` 會檢查 `fx:*`）。下表的 payload 欄位沿用網頁版的名稱，物件欄位在 Godot 版改成 id（例如 `target` → `target_id`）：

| 事件 | payload | 發出者 |
|---|---|---|
| `entity:damaged` | `{ target, amount, source, knockback, isCrit }`（Godot 版：`isCrit` 拆成 `is_heavy` 重擊顯示（第三段、盾反、爆炸）與 `is_crit` 屬性擲出的爆擊，見系統說明 §1；另帶 `hit_stop` 命中定格秒數，見第 4 節；目標是玩家時再帶 `source_kind`、`origin`、`lethal` 給遊玩紀錄，v0.34.0；不是物理時帶 `damage_type`，傷害數字依屬性上色） | Combat |
| `entity:healed` | `{ target, amount }` | SkillBehaviors、ItemEffects |
| `entity:dodged` | `{ target_id, source_id }`（F1：閃避率擲中，整下沒打到；HUD 飄「閃避」） | Combat |
| `player:blocked` | `{ player_id, perfect }`（v0.18.0：格擋擋下攻擊；perfect = 招架成功（v0.41.0 起），下一步盾反） | Player.try_block |
| `entity:died` | `{ entity, source, kind }`（`kind` 給 v0.34.0 遊玩紀錄） | Entity |
| `player:died` | `{ player }`（v0.21.0 起只代表這位玩家真的死亡；輸掉一局看 `game:defeat`） | Player |
| `player:downed` | `{ player_id }`（v0.21.0：多人時生命歸零先倒地假死，見系統說明 §8） | Player |
| `player:revived` | `{ player_id }`（v0.21.0：被隊友救起） | Player.revive |
| `player:stunned` | `{ player_id, duration, grabbed }`（v0.27.0：被 Boss 衝鋒撞到暈眩；grabbed = 被腐屍抓住） | Player.stun |
| `player:grab_escaped` | `{ player_id }`（被腐屍抓住時按翻滾掙脫） | Player.update |
| `game:defeat` | `{ stats }`（v0.21.0：全員倒下 = 輸；單機和 `player:died` 同一步發出） | World |
| `item:added` | `{ player_id, item, uid }`（v0.19.0：道具放進身上；item = 物品 id，uid = 實例 id，武器為空字串） | Player.add_item |
| `inventory:full` | `{ player_id, item, pickup_id }`（v0.25.0：背包放不下；pickup_id = 地上道具的實體 id，不是從地上撿的為 0） | Loadout.add_item / add_weapon / add_corpse |
| `weapon:dropped` | `{ uid, base, rarity, pos }`（v0.26.0：殺怪掉武器） | World.on_enemy_died |
| `weapon:added` | `{ player_id, uid, slot }`（v0.26.0：撿到武器；slot = 主手 0 / 副手 1（Loadout.MAIN / OFF），-1 = 背包） | Player.add_weapon |
| `weapon:merged` | `{ player_id, uid, base, rarity }`（v0.26.0：合成成功） | Loadout |
| `weapon:merge_denied` | `{ player_id }`（v0.26.0：不能合成） | Loadout |
| `souls:gained` | `{ amount, pos, total }`（v0.25.0：殺怪得到共用的靈魂；v0.45 前叫 `gold:gained`） | World.on_enemy_died |
| `coins:gained` | `{ amount, total, reason, floor, pos }`（v0.45：局外金幣；reason `floor` 過關、`pickup` 撿到地上的；main.gd 收到就存檔） | World.gain_coins |
| `chest:denied` | `{ chest_id, player_id, price }`（v0.25.0：靈魂不夠開祭壇 / 石棺） | Chest.try_open |
| `chest:opened` | `{ chest_id, player_id, relic_id, pos }`（v0.25.0：開了祭壇 / 石棺；Build 改版第 6 步起開出遺物） | Chest.try_open |
| `relic:opened` | `{ relic_id, player_id }`（Build 改版第 6 步：打開自己的 N 選 1） | Relic.open_for |
| `relic:rerolled` | `{ relic_id, player_id, dice }`（用掉 1 顆骰子重擲，dice 是剩下的） | Relic.reroll |
| `relic:picked` | `{ relic_id, player_id, item }`（選了一個；拿到的道具照樣發 item:added） | Relic.pick |
| `skill:leveled` | `{ player_id, skill, level }`（Build 改版第 7 步：技能遺物選到已經有的技能，升到 level 級） | Relic.pick |
| `skill:used` | `{ key, def }` | PlayerStates / ActiveSlots |
| `skill:onCooldown` | `{ key }` | PlayerStates / ActiveSlots |
| `wave:started` | `{ wave, total, isBoss }` | Spawner |
| `boss:enraged` | `{ boss }` | Boss |
| `boss:transforming` | `{ boss_id }`（Boss 半血開始轉型態） | Gravekeeper |
| `boss:transformed` | `{ boss_id, form, pos }`（轉型態完成：畫面層換模型、HUD 換名字與提示） | Gravekeeper |
| `boss:revealed` | `{ boss_id, spoke }`（假裝 NPC 的守墓人露出真面目；spoke = 被說話觸發、頭上冒台詞） | Gravekeeper |
| `game:victory` | `{ stats }` | World（Boss 死亡後延遲發出） |
| `game:restart` | `{}` | World.reset |
| `game:paused` | `{ paused }` | main.gd（Esc、失去焦點） |
| `audio:muted` | `{ muted }` | main.gd（M 鍵） |
| `sfx:cue` | `{ cue, pos? }` | 各遊戲物件；`cue` 必須是 `audio/sound.gd` 的 `CUE_NAMES` 之一 |
| `camera:shake` | `{ amount, duration, player_id? }` | Combat、Player、Projectile、Enemy、Boss、World（模擬層不能直接震相機）；有 `player_id`（玩家被打）時只震那位玩家的畫面 |
| `fx:slash` | `{ pos, height, facing, range, arc, color, swing_dir }` | 近戰揮砍（`fx:*` 是 v0.20.0 起的特效事件，見系統說明 §7） |
| `fx:muzzle` | `{ pos, height, color }` | 法杖魔彈發射 |
| `fx:telegraph` | `{ pos, height, radius, color, life, fill? }`（fill：圈內鋪半透明的圓，聖光圈用） | 聖光圈、玩家道具。**怪物攻擊不用**（設計方向「怪物攻擊不畫紅圈」，檢查會擋 `sim/` 其他檔案發這個事件） |
| `fx:fizzle` | `{ pos, height, color }` | 投射物飛到盡頭、撞牆或被格擋 |
| `fx:explosion` | `{ pos, height, radius, color }` | 投射物爆炸 |
| `fx:parry` | `{ pos, height, radius, facing, arc, color }` | 盾反（畫出實際的扇形範圍） |
| `fx:heal` | `{ pos, height, color }` | 治療藥水 |
| `fx:boss_slam` | `{ pos, height, radius }` | Boss 砸地 |
| `fx:boss_wall` | `{ pos, height }` | Boss 衝鋒撞牆 |
| `fx:boss_teleport` | `{ pos, height, to }` | 狂暴 Boss 瞬移砸地（v0.27.0）：原地與目的地的紫色煙霧 |
| `fx:boss_teleport_warn` | `{ pos, height, life }` | 狂暴 Boss 瞬移前：目的地冒出越來越濃的紫煙（取代預警圈） |
| `fx:dirt_lob` | `{ pos, height, targets, flight, radius, shadow_only? }` | 守墓人鏟土拋擲（shadow_only：狼人飛撲只畫影子）：土塊沿拋物線飛到每個落點、地上的影子越來越大（看影子躲，不畫圈） |
| `fx:gas_cloud` | `{ pos, height, radius, color, life }` | 怪物的毒氣區（膨脹屍的腐氣，GroundZones `visual = &"gas"`）：範圍內一直冒低低的煙，不畫圈 |
| `fx:erupt_warn` | `{ pos, height, radius, life }` | 挖墳點噴怪前：墳土隆起、裂開、冒出白骨手（取代預警圈） |
| `fx:lightning` | `{ pos, height, points, color }` | 道具連鎖閃電（v0.33.0）：points 依序連成的閃電線 |
| `fx:status` | `{ pos, height, color }` | 道具讓怪中毒 / 冰凍（v0.33.0）：一小團該顏色的粒子 |

其他系統的事件（`event:*`、`floor:started`、`boss:reward`、`hit:predicted` 等）寫在系統說明對應的一節。

---

## 10. 命名與程式風格（GDScript）

| 對象 | 規則 | 範例 |
|---|---|---|
| 檔案 | snake_case | `cooldowns.gd`、`player_states.gd` |
| 類別（`class_name`） | PascalCase | `class_name CooldownManager` |
| 函式、變數 | snake_case | `apply_damage`、`move_speed_mul` |
| 常數、資料表 | UPPER_SNAKE_CASE | `FIXED_DT`、`WEAPONS` |
| 私有成員 | `_` 前綴 | `_accumulator` |
| 布林值 | `is_` / `has_` / `can_` 開頭 | `is_dead` |
| 訊號 | 過去式 | `event_emitted` |
| 狀態名稱 | StringName、camelCase | `&"idle"`、`&"useItem"` |
| 事件名稱 | `domain:action` | `"entity:damaged"` |
| CD key | `owner.purpose` | `"player.slot1"` |

- 程式碼的識別名稱一律英文；**註解與文件使用繁體中文**。
- 每個檔案開頭用一行註解說明職責；只在「為什麼這樣做」不明顯時才寫註解，不寫重述程式碼的註解。
  - 註解只寫現在的情況（這段做什麼、為什麼這樣做）與調整時要注意的地方（例如「往右長會超出舞台」「改這個值要一起改 X」）；不寫日期、誰回報 / 決定、以前怎樣、在哪次發現，這些記在 CHANGELOG 與 git。
- 一律寫靜態型別（`var hp: float`、`func step(cmds: Dictionary, dt: float) -> void`），型別錯誤在匯入時就會報出，也比較快。
- GDScript 的 `const` Dictionary 不能放類別參照（會報 "isn't a constant expression"）：要用表對應類別時用 `match` 或 `static var`。
- 每幀執行的程式避免配置新物件（重複使用 Dictionary / 陣列）；共用網格與材質，受擊閃白改材質參數，不在每次受擊時建立新材質。
- 實體移除時從場景移除節點並釋放專屬資源。
- **介面的按鈕與字級**（2026-10-27）：按鈕一律 `UiKit.button(文字, UiKit.BUTTON_L / BUTTON_M / BUTTON_S)`（選單 280×60 / 面板操作 200×52 / 一排很多顆 120×44），不自己 `Button.new()` 設大小與字；選單類畫面的文字用 `UiKit.FONT_TITLE / FONT_HEADING / FONT_BODY / FONT_NOTE`（52 / 32 / 28 / 20）。檢查「按鈕」會擋 `ui/` 裡的 `Button.new()`。

---

## 11. 動畫與姿勢

- 網頁版的武器行為在 `update` 裡同時做命中判定與擺姿勢；Godot 版**拆開**：模擬層只記錄動畫所需的資料 `anim`（動作名稱、階段 `windup` / `active` / `recovery`、階段進度 `k`、狀態經過秒數），畫面層的 `view/animator.gd`（玩家）、`view/enemy_animator.gd`（敵人）依 `anim` 算出關節角度。
- 規則：模擬層不出現關節名稱。連線時只要同步 `anim`，每台都能畫出同樣動作。
- **握武器用掛點**：`Rig` / `SkinnedRig` 的手掌掛點 `hand_r / hand_l` 在拳頭中心（關節資料的 `grip` = 肩膀到拳頭中心），拳頭模型掛在手掌掛點上。每把武器（玩家與怪物）在自己的模型座標標掛點：`grip` 必有（拳頭握的位置），弓另有 `string`（弓弦勾弦點）、鐵鏟另有 `hold`（托舉點），用 `DarkFantasy._hold` 掛上去，`grip` 就落在拳頭中心；`Rig.mount_point` 取掛點的世界座標。
  - 動畫要讓武器轉向（直立、弓面朝前）時轉手掌掛點，不轉武器模型：拳頭和武器一起轉，握的位置不會滑出拳頭。檢查「握武器」會擋。
  - 身上的掛點 `Rig.mount_nodes`（關節資料的 `mounts`，騎士是 `DarkFantasy.KNIGHT_MOUNTS`：`forearm_l` 盾、`back` 箭袋，`hip_l` / `hip_r` / `head` 預留）也用 `_hold` 掛；要掛新東西先找現成的掛點，沒有再加，不在 `Rig` 裡寫死位置。

---

## 12. 版號與 CHANGELOG 規則

採用語意化版本 `MAJOR.MINOR.PATCH`，**只在推送時升版號**（2026-10-25 起；之前是每次請求一版）：

| 這次推送「未發布」裡有 | 升級 | 範例 |
|---|---|---|
| `### 新增`（新功能、新系統、新內容：武器、敵人、技能） | MINOR | 0.42.0 → 0.43.0 |
| 只有修改 / 修復 / 移除（修 bug、調數值、重構、工具、文件；除錯場景、啟動參數也算工具，記在「修改」） | PATCH | 0.42.0 → 0.42.1 |
| 正式版或存檔不相容的大改 | MAJOR | 1.0 之前不使用 |

- **平常**：改動記在 CHANGELOG 最上面的 `## [未發布]`，分類 `新增` / `修改` / `修復` / `移除`；commit 不升版號、不改 `version.gd`、不打 tag。
  - CHANGELOG 會跟著版本發布出去：只寫改了什麼、原因、量到的數字。「還沒人看過 / 聽過」「可能…」這種確認狀態不寫，放 `docs/試玩清單.md`（未試玩）或 `docs/進度.md`（未驗證）。
- **推送**：`node tools/release.mjs --summary "摘要"`（流程見 `CLAUDE.md` 1.3）把「未發布」換成 `## [X.Y.Z] - 日期`、同步 `version.gd`、打 tag，一次推送 = 一個版號。「未發布」是空的（例如只改進度交接）就直接推、不升版號。自動判斷不對時用 `--bump=minor|patch` 蓋過。
  - 對方先推過時，rebase 的 union 合併會把自己的「未發布」接在對方的版號後面；推送時腳本換版號前會自動把「未發布」搬回最上面（有好幾段就合成一段、同分類合併）；推送前跑 `--check` 會被「版號」檢查擋下，要手動搬到最上面。
- 為什麼：兩位作者同時開發，各自先升版號會撞號；版號在推送前更新之後才決定就不會。每次推送最多一個 tag，Release 也一定會觸發。
- 版號在已發布的部分三處一致：CHANGELOG 最新的已發布版本、`godot/core/version.gd`、git tag（`check.gd` 會檢查前兩者；網頁版的 `legacy/src/core/version.js` 已凍結在 0.7.0）。
- HUD 角落顯示目前版號，方便確認載入的是最新版。

---

## 13. 開發工作流程

1. **開工**：`git pull --ff-only origin main`（失敗就停下來問使用者；有新 commit 就向使用者簡報）→ 讀 `CLAUDE.md` → `docs/進度.md`（先看「通知」）→ 本文件與 `docs/系統說明.md` 相關的節 → CHANGELOG 最上面 → 相關模組。
2. **實作**：先列出預計修改的檔案並取得使用者同意；遵守本文件；若需要偏離規範，先更新本文件再寫程式。
3. **驗證**：`node tools/release.mjs --check`，全部通過；改到畫面或操作時，另外用離屏截圖驗證（見第 17 節）。
4. **記錄**：改動記進 CHANGELOG 的「未發布」；架構有變就更新本文件，系統細節有變就更新 `docs/系統說明.md`；兩位作者都要知道的流程變更在 `docs/進度.md` 加「通知」。
5. **提交**：`git commit -m "摘要"`（不升版號、不打 tag）。只有使用者當次明確要求時才用 `node tools/release.mjs --summary "摘要"` 推送（見 `CLAUDE.md` 1.3）。
6. **回報**：告訴使用者變更內容、驗證結果與已知問題；推送時另外報新版號。

---

## 14. 造型風格與角色模型

- 所有角色都是 `view/rig.gd` 的 **`Rig`**（Node3D）：統一關節階層 `root → body → head / arm_r / arm_l / leg_r / leg_l`，手掌掛點 `hand_r / hand_l`。角色面向 +Z、右側為 -X、四肢往 -Y 延伸。**動畫程式只轉動關節，不依賴任何特定造型**，因此改造型不需改動畫。
- 關節旋轉順序為 Godot 預設的 `YXZ`：先用 `rotation.x` 前後抬起，再用 `rotation.y` 水平揮動。
- 零件用 `PartKit.add(parent, mesh, material, t)` 建立、材質用 `kit.mat(color, glow)` 取得（同色共用），才能統一受擊閃白（`set_flash`）與釋放資源。自發光部位（眼睛、寶石）用 `glow = true`，不受閃白影響。網格用 `PartKit.box / cyl / cone / sphere / ico…`。
- **零件數影響效能**：角色建好後呼叫 `rig.optimize()`，武器與場地呼叫 `kit.merge_static(根節點, [會動的節點], [不合併的零件])`，把一起動的零件合併成少數網格。會單獨動畫的零件（例如法杖寶石）要放進不合併清單。`check.gd` 會檢查每個角色與場地的零件數上限。
- 大量的小怪用蒙皮版 `view/skinned_rig.gd`（系統說明 §14）；大量相同外觀的物件（投射物、粒子）用 `MultiMeshInstance3D`。
- 造型在 `view/styles/dark_fantasy.gd`（`DarkFantasy`，已定案的暗黑幻想）：

| 函式 | 內容 |
|---|---|
| `character(kind)` | 依實體種類（player / grunt / archer / boss…）建立 `Rig`；同種第二次起用合併好的模板 |
| `skinned_character(kind)` | 小怪的蒙皮版本 |
| `weapon(model)` | 武器外觀 `{ kit, main, offhand, gem? }`；`main` 掛在右手，`offhand` 掛在左臂 |
| `enemy_projectile(color)` | 敵人投射物，沿 +Z 建模 |
| `build_arena(half, rng)` | 測試場地外觀；地圖的石台由 `ArenaView` 畫 |

- 新增職業或敵人時：先在 `DarkFantasy` 補上外觀，再新增資料定義。
- 新造型或新外觀的候選方案，依 `CLAUDE.md` 第 2.5 節先做對比頁給使用者挑選，選定後才做進遊戲。

---

## 15. 實體與效能

- 實體是 `sim/` 裡的 `RefCounted` 物件，由 `world` 以**整數 id**（`world.next_id` 遞增，不重複使用）管理；連線同步、畫面對應、CD key（`enemy<id>.<招式>`）都用這個 id。
- 碰撞分離與投射物命中用格子切分（uniform grid，作法同 `godot/stress_test/`），集中在 `sim/physics.gd`（碰撞分離已改用格子；投射物命中目前仍逐一比對，數量變多時再改）。
- 敵人與 Spawner 不持有 World 以外的循環參照：Spawner 不存 World（每次呼叫時傳入），敵人的 CD key 需要 id，所以在 `World.add_entity` 之後的 `on_added()` 才開始 CD。這兩段是之後改 C++ 的首選，介面要保持「輸入陣列 → 輸出陣列」，方便替換。
- 角色用節點樹 Rig（小怪用蒙皮網格），大量相同外觀的物件用 `MultiMeshInstance3D`。
- **新的實體種類**（2026-10-31 使用者要求：牆後的物件與獎勵也要看得到）：
  - 平常做法：模型一律從 `WorldView._create_view` 建（它會掛牆後剪影，顏色看 `WorldView.xray_color`，沒列的歸「物件」灰白）；材質從共用的工廠拿（`_flat_material` / `_glow_material` / `_beam` / `PartKit.mat`），不要自己 `StandardMaterial3D.new()`；在 `WorldView.warm_up` 各建一個。
  - 判斷：檢查「牆後剪影」會找出所有繼承 `Entity`、沒有子類別的 class_name，沒在預熱建過、模型沒剪影、或有網格沒寫模板值就失敗。
  - 例外：真的不要剪影的列進 `WorldView.XRAY_EXEMPT`（class_name → 原因）；地上的圈、光柱這類子節點用 `XRAY_SKIP`。
  - 為什麼：剪影原本是「列出來的種類才有」，後來加的寶箱、遺物、鍛造祭壇、金幣、插地火把被牆擋住就看不到，預熱也漏了遺物與火把。每個實體各自建材質的話，寫模板值後網頁版每份都要編一次著色器（系統說明 §16）。
- 效能目標、量測方法與數字在 `docs/效能.md`；怪群的效能做法見系統說明 §14。

---

## 16. 多人連線

規格如下，實際做法與使用者的決定見系統說明 §8。
- **權威**：房主（peer id 1）跑唯一的 `world`。傷害、死亡、生成、掉落、隨機一律由房主決定；其他玩家不跑 `world.step()`。
- **InputCmd**：`{ tick, move: Vector2, aim: Vector2, buttons: int, … }`，`buttons` 為位元旗標（攻擊按住、右鍵按下、1~5 按下…）。玩家每步送出，用 unreliable 通道並夾帶最近幾筆輸入以防掉包。
- **快照**：房主每 3 步（20 次/秒）送出附近實體的 `id、類型、x、z、height、facing、hp、anim`，加上該玩家自己的 CD 與欄位；unreliable 通道。事件走 reliable 通道。
- **其他玩家的畫面**：遠端實體保留約 100 ms 的快照緩衝，在兩次快照之間補間。
- **自己的角色**：移動先在本機預測（用同一份 `sim/` 移動程式），收到快照後以伺服器位置為準修正（誤差平移，不倒帶重播）。
- **玩家對應**：`world.players` 以 peer id 為 key；單機的唯一玩家也是 peer id 1。
- **傳輸層**：`net/` 封裝建立房間 / 加入 / 斷線，對外只暴露 Godot 的 `MultiplayerPeer`；從 ENet / WebRTC 換 Steam 只改 `net/`。
- 新增會影響畫面的模擬狀態時，同時想好它怎麼進快照（`net/net_codec.gd`）；只有房主知道的狀態，客戶端要能接受「以房主為準」。

---

## 17. 驗收

- `tests/check.gd`（headless 自動檢查），平常在專案根目錄用 `node tools/release.mjs --check --godot <路徑>` 跑（先匯入、有逾時），全部通過才算完成；CI 直接在 `godot/` 內跑 `<Godot console 執行檔> --headless --path . -s res://tests/check.gd`。畫面只印沒過的項目與總數，每項結果、`CheckKit._note()` 記的數字、手感量測（`CheckKit._feel()`）寫進 `tests/check_last.log`（不進版控）。網頁版已凍結，只有動到網頁版時才在 `legacy/` 跑 `node check.js`。
- 因為模擬層不依賴場景樹，檢查可以直接建立 `World`、餵假的 `InputCmd`、推進 N 步讀數值（例如移動 1 秒的距離、三段攻擊總時間、CD 是否到期）。
- 檢查分檔：`check.gd` 只放檢查清單（標題 + 函式），本體依主題放在 `core / player / combat / boss / map / loot / view / monster / event / net_checks.gd`，共用工具在 `check_kit.gd`（各檔 `extends CheckKit`）。新增檢查放進對應主題的檔案，再到 `check.gd` 加一行。
- **清單依種類分組、子檢查各自獨立**（2026-10-27 使用者要求，同日把全部檢查整理過一遍：158 → 120 項）：
  - 平常做法：`check.gd` 的一項 = 一種機制（例如道具依效果種類分「屬性 / 條件 / 觸發 / 能力」、玩家的「翻滾」、武器一把一項）。新增檢查前先找同種類的項目，有就寫成新的子檢查函式、用 `CheckKit.all_of.bind([…])` 加進那一項並在標題補一句；沒有才新開一項。不照批次或里程碑分（不要「道具第二批 G4」這種項目）。
  - 每個子檢查自己建 World、自己擺好前置，不依賴前一個子檢查或前一項留下的狀態（擊殺數、無敵時間、地上的東西、靜態快取）。**合起來會壞 = 測試有共享狀態，改測試**，不是在後面的段落把狀態清掉了事。
  - 檢查建的實體一定要加進 World（`add_entity` / `add_enemy`）、World 要登錄（`_new_world` 或各檔的 `_made`）：結束時才會 `clear()` 切斷循環參照。沒做會在結束時洩漏，`release.mjs --check` 會判失敗；要找是哪一項用 `-- --only=標題開頭` 逐項單獨跑。
  - 驗證：改動檢查後除了照常跑，再用 `--shuffle=種子` 打亂順序跑（在 `godot/` 內 `<Godot> --headless --path . -s res://tests/check.gd -- --shuffle=1`），換幾個種子都要全過。
  - 判斷：同一種機制、失敗訊息看得出是哪裡（`all_of` 會標出子檢查的函式名）→ 同一項；檢查的系統不同 → 分開。
  - 例外：開程序、跑很久的檢查（兩個程序連線、截圖）只有在情境的前提相容時才合併，否則分開並在函式註解寫原因。例：C1 驗「停下後兩邊收斂」，道具的兩程序檢查要一直打怪，結束那一刻還在被推、客戶端畫別人的角色本來就晚約 100 ms，前提不成立（2026-10-27 實測：兩邊同在 tick 479，遠端玩家差 0.22），所以分開。
  - 會隨機消失的東西（僕從會被打死、投射物會飛走）判斷「有沒有出現過」，不是「結束那一刻還在不在」。
  - 為什麼：檢查一直變多、照批次加的項目看不出哪些是同一件事；同程序的檢查每項不到一秒，分組主要是讓清單好讀（整份仍約 35 秒）。
- **平衡數字**：調了武器、技能、怪物的數值（`defs/`）後跑 `node tools/release.mjs --balance`，看 `docs/平衡數字.md` 有沒有招式跑出目標（標偏低 / 偏高），新的表跟著 commit。刻意不照目標的招式寫進 `tests/balance_report.gd` 的 `KEEP` 並附原因。
- 檢查機制、不檢查數值快照（v0.37.3）：預期值從資料表（`Config`、`defs/`）讀或算出來，例如「三段傷害 = 資料的 damage、damage、damage × finisher_mul」，不寫死 12 / 12 / 22；標題寫規則（「持續 stagger_time」），不寫數字。這樣調數值不用改檢查，只有機制改了才要改。
  - 例外：公式本身（護甲減傷曲線）、效能上限（零件數）、素材屬性（音樂長度）可以寫死數字，因為那就是要守住的規則。
  - `monster / event / net_checks.gd` 還有寫死的數值，之後動到時順便改。
- 量介面尺寸（塞不塞得進畫面）要等畫面更新再量：`await ViewChecks._settled_min_size(節點)`（等兩幀）。檢查函式可以 `await`（`check.gd` 會等它跑完）。
  - 判斷：剛建好、或剛換過文字 / 加過子節點的介面都算；立刻 `get_combined_minimum_size()` 拿到的是預設字級、舊快取，偏小約 15%。
  - 為什麼：2026-10-27 選角畫面四人大廳實際 2184 寬，立刻量是 1850，檢查沒擋到，截圖才發現。主選單各頁、暫停畫面、設定頁的尺寸檢查還是立刻量，之後動到時改掉。
- 網頁版對照（v0.37.3 退役）：搬移時曾用 `tests/web_defs.json` 逐欄比對，結果留在 `docs/手感對照.md`。
- 會影響畫面或幀率的改動，推送前用 `node tools/release.mjs --perf`（效能）在本機確認網頁版；`--web`（給使用者看）只在使用者要求時開（`CLAUDE.md` 1.4）。
- 畫面用離屏截圖場景 `tests/capture.tscn` 驗證（用法與「開視窗前先問使用者」的規則見 `CLAUDE.md` 1.8），截圖存暫存資料夾，不進版控；手感與效能定案以使用者實際遊玩為準。
- 版號三處一致見第 12 節；遊戲畫面角落顯示版號。
