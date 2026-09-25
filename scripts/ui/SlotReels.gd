class_name SlotReels
extends Control
## 슬롯머신 릴 3개. Board.pending_slot 이 있는 동안 빠르게 돌다가 하나씩 멈춘다.

var board: Board
var _scroll := [0.0, 0.0, 0.0]
var _stopped := [true, true, true]
var _tick_t := 0.0
var _flash := 0.0
var _last_key := ""


func _process(delta: float) -> void:
	if board == null:
		return
	var ps: Dictionary = board.pending_slot
	if not ps.is_empty():
		var total := GameData.SLOT_SPIN_TIME
		var elapsed: float = total - ps["t"]
		for i in 3:
			var stop_at := total * (0.45 + 0.25 * i)
			var was: bool = _stopped[i]
			_stopped[i] = elapsed >= stop_at
			if not _stopped[i]:
				_scroll[i] += delta * (14.0 + i * 3.0)
			elif not was:
				Sfx.play("summon")
		_tick_t -= delta
		if _tick_t <= 0.0:
			_tick_t = 0.07
			Sfx.play("tick")
	else:
		_stopped = [true, true, true]
	var key := str(board.last_slot)
	if key != _last_key:
		_last_key = key
		if board.last_slot.get("win", 0) > 0:
			_flash = 1.0
	_flash = maxf(0.0, _flash - delta * 1.5)
	queue_redraw()


func _symbols() -> Array:
	if not board.pending_slot.is_empty():
		return board.pending_slot["reels"]
	if not board.last_slot.is_empty():
		return board.last_slot["reels"]
	return ["star", "star", "star"]


func _draw() -> void:
	var w := size.x / 3.0
	var h := size.y
	var final := _symbols()
	var col_of := {"gold": Color(1, 0.85, 0.3), "gem": Color(0.5, 0.85, 1.0), "summon": Color(0.5, 1.0, 0.6), "star": Color(1, 0.6, 0.2), "skull": Color(0.75, 0.75, 0.8)}
	var frame := Color(1, 0.85, 0.3).lerp(Color.WHITE, _flash)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.04, 0.04, 0.06))
	for i in 3:
		var r := Rect2(i * w + 6, 6, w - 12, h - 12)
		draw_rect(r, Color(0.12, 0.12, 0.17))
		var c := r.get_center()
		if _stopped[i]:
			var sym: String = final[i]
			Glyphs.draw_icon(self, sym, c, h * 0.3, col_of.get(sym, Color.WHITE))
		else:
			# 돌아가는 중: 위아래로 흐르는 심볼
			var off: float = fmod(_scroll[i], 1.0)
			for k in [-1, 0, 1]:
				var idx: int = (int(_scroll[i]) + k + i * 2) % GameData.SLOT_SYMBOLS.size()
				var sym: String = GameData.SLOT_SYMBOLS[idx]
				var p := c + Vector2(0, (k + off - 0.5) * h * 0.55)
				if absf(p.y - c.y) < h * 0.45:
					Glyphs.draw_icon(self, sym, p, h * 0.22, Color(col_of[sym], 0.7))
		draw_rect(r, frame, false, 2.0)
	draw_line(Vector2(0, h / 2), Vector2(size.x, h / 2), Color(1, 0.3, 0.3, 0.35), 2.0)
	draw_rect(Rect2(Vector2.ZERO, size), frame, false, 3.0)
