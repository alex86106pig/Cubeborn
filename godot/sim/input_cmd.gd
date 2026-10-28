# 一位玩家一個模擬步的輸入：模擬層唯一的輸入來源，連線時原樣送給房主
class_name InputCmd
extends RefCounted

const BTN_ATTACK := 1 << 0       # 左鍵（按住）
const BTN_SPECIAL := 1 << 1      # 右鍵（本步按下）
const BTN_SLOT_FIRST := 1 << 2   # 數字鍵 1（本步按下），2~5 依序左移
const SLOT_COUNT := 5
const BTN_ROLL := 1 << 7         # 左 Shift 翻滾（本步按下）；數字鍵占用 1 << 2 ~ 1 << 6
const BTN_JUMP := 1 << 8         # 空白鍵跳躍（本步按下）
const BTN_INTERACT := 1 << 9     # F 互動（按住）：救援倒地的隊友
const BTN_SWAP_WEAPON := 1 << 10 # Q / 滑鼠滾輪：換到另一格裝備欄的武器（本步按下；D4 起取代 F1 除錯切換）
const BTN_SPECIAL_HELD := 1 << 11  # 右鍵（按住）：劍盾按住格擋（v0.41.0）；BTN_SPECIAL 仍是「本步按下」，法杖用它
const BTN_RUN := 1 << 12         # Ctrl 切換跑步（本步按下；2026-10-27 取代數字鍵 2 的疾跑）
const BTN_VOTE_YES := 1 << 13    # Enter：同意前往下一層（本步按下；只在投票中送出）
const BTN_VOTE_NO := 1 << 14     # Esc：反對前往下一層（本步按下；只在投票中送出，這時 Esc 不開選單）
const HELD_BUTTONS := BTN_ATTACK | BTN_INTERACT | BTN_SPECIAL_HELD   # 按住類的按鈕：沿用上一筆輸入時保留，其餘「本步按下」的不重複觸發

const OP_MOVE := 0   # 背包操作（D3）：[OP_MOVE, uid, x, y, rot] 搬到 (x, y)、轉 rot 次 90 度
const OP_DROP := 1   # [OP_DROP, uid] 丟到面前的地上
const OP_EQUIP := 2  # [OP_EQUIP, uid, slot] 武器放進裝備欄 slot（D4）
const OP_MERGE := 3  # [OP_MERGE, uid_a, uid_b] 把武器 a 拖到 b 上合成（D4）

var tick := 0
var move := Vector2.ZERO   # 世界 XZ 方向，長度 ≤ 1
var aim := Vector2.ZERO    # 世界 XZ 瞄準點
var buttons := 0
var inv_ops: Array = []    # 本步的背包操作（同「本步按下」：只執行一次，合併輸入時接在一起）
var view_tick := 0         # 連線：客戶端這一步畫面上其他實體的時間（房主 tick），房主做延遲補償用；0 = 不補償（v0.38.0）
var spectate := 0          # 連線：陣亡後觀戰的隊友 peer id（0 = 沒在觀戰）；房主改用他的位置挑快照裡的實體，模擬層不用


static func slot_bit(index: int) -> int:
	return BTN_SLOT_FIRST << index


func has(bit: int) -> bool:
	return buttons & bit != 0


func to_array() -> Array:
	return [tick, move.x, move.y, aim.x, aim.y, buttons, inv_ops, view_tick, spectate]


static func from_array(a: Array) -> InputCmd:
	var cmd := InputCmd.new()
	cmd.tick = a[0]
	cmd.move = Vector2(a[1], a[2])
	cmd.aim = Vector2(a[3], a[4])
	cmd.buttons = a[5]
	if a.size() > 6:
		cmd.inv_ops = a[6]
	if a.size() > 7:
		cmd.view_tick = a[7]
	if a.size() > 8:
		cmd.spectate = a[8]
	return cmd
