# 一位玩家一個模擬步的輸入：模擬層唯一的輸入來源，連線時原樣送給房主
class_name InputCmd
extends RefCounted

const BTN_ATTACK := 1 << 0       # 左鍵（按住）
const BTN_SPECIAL := 1 << 1      # 右鍵（本步按下）
const BTN_SLOT_FIRST := 1 << 2   # 數字鍵 1（本步按下），2~5 依序左移
const SLOT_COUNT := 5
const BTN_ROLL := 1 << 7         # 左 Shift 翻滾（本步按下）；數字鍵占用 1 << 2 ~ 1 << 6
const BTN_JUMP := 1 << 8         # 空白鍵跳躍（本步按下）

var tick := 0
var move := Vector2.ZERO   # 世界 XZ 方向，長度 ≤ 1
var aim := Vector2.ZERO    # 世界 XZ 瞄準點
var buttons := 0


static func slot_bit(index: int) -> int:
	return BTN_SLOT_FIRST << index


func has(bit: int) -> bool:
	return buttons & bit != 0


func to_array() -> Array:
	return [tick, move.x, move.y, aim.x, aim.y, buttons]


static func from_array(a: Array) -> InputCmd:
	var cmd := InputCmd.new()
	cmd.tick = a[0]
	cmd.move = Vector2(a[1], a[2])
	cmd.aim = Vector2(a[3], a[4])
	cmd.buttons = a[5]
	return cmd
