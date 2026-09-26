class_name RouletteWheel
extends Control
## 돌림판. spin(target_index) 로 목표 칸에 멈추도록 감속 회전한다.
## 칸 크기는 확률(segments[i]["w"])에 비례한다 (보이는 크기 = 실제 확률).

signal stopped(index: int)

var segments: Array = []
var angle := 0.0
var spinning := false
var _from := 0.0
var _to := 0.0
var _t := 0.0
var _dur := 4.2
var _target := 0
var _last_seg := -1
var _glow := 0.0
var _result := -1


func spin(target: int) -> void:
	if spinning:
		return
	_target = target
	_result = -1
	var a0 := seg_start(target)
	var seg := seg_width(target)
	# 포인터는 위쪽(-PI/2). 목표 칸 가운데 + 약간의 흔들림이 포인터에 오도록
	var inside := randf_range(-0.35, 0.35) * seg
	var target_angle := -PI / 2 - (a0 + seg * 0.5) + inside
	var base := angle - fposmod(angle, TAU)
	_from = angle
	_to = base + TAU * 6 + fposmod(target_angle, TAU)
	_t = 0.0
	spinning = true


func _process(delta: float) -> void:
	if spinning:
		_t += delta
		var k := minf(1.0, _t / _dur)
		var e := 1.0 - pow(1.0 - k, 4.0)
		angle = lerpf(_from, _to, e)
		var seg := _pointer_segment()
		if seg != _last_seg:
			_last_seg = seg
			Sfx.play("tick")
		if k >= 1.0:
			spinning = false
			_result = _target
			_glow = 1.0
			stopped.emit(_target)
	_glow = maxf(0.0, _glow - delta * 0.6)
	queue_redraw()


func _total_w() -> float:
	var t := 0.0
	for sg in segments:
		t += float(sg.get("w", 1))
	return maxf(t, 0.001)


func seg_start(i: int) -> float:
	## i 번째 칸이 시작하는 각도 (바퀴 기준, 0 부터 시계 방향)
	var acc := 0.0
	for k in i:
		acc += float(segments[k].get("w", 1))
	return acc / _total_w() * TAU


func seg_width(i: int) -> float:
	return float(segments[i].get("w", 1)) / _total_w() * TAU


func _pointer_segment() -> int:
	var rel := fposmod(-PI / 2 - angle, TAU)
	for i in segments.size():
		if rel < seg_start(i) + seg_width(i):
			return i
	return segments.size() - 1


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	var n := segments.size()
	if n == 0:
		return
	draw_circle(c, r + 10, Color(0.95, 0.8, 0.3))
	draw_circle(c, r + 4, Color(0.2, 0.12, 0.05))
	var font := get_theme_font("font")
	for i in n:
		var a0 := angle + seg_start(i)
		var seg := seg_width(i)
		var pts := PackedVector2Array([c])
		var steps := maxi(3, int(seg / TAU * 64))
		for j in steps + 1:
			pts.append(c + Vector2.from_angle(a0 + seg * j / float(steps)) * r)
		var col: Color = segments[i]["color"]
		if i == _result and _glow > 0.0 and fmod(_glow * 6.0, 1.0) < 0.5:
			col = col.lightened(0.5)
		draw_colored_polygon(pts, col)
		draw_line(c, c + Vector2.from_angle(a0) * r, Color(0, 0, 0, 0.35), 2.0)
		var am := a0 + seg * 0.5
		var mid := c + Vector2.from_angle(am) * r * 0.66
		var rw: Dictionary = segments[i]
		if seg < 0.4:
			# 좁은 칸 (낮은 확률): 글자를 바깥쪽 방향으로 눕혀서
			var txt: String = str(rw["coins"]) if rw.has("coins") else GameData.shop_item(rw["item"])["name"]
			var fs := int(r * 0.1)
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_set_transform(c, am)
			var p := Vector2(r * 0.92 - w, fs * 0.36)
			draw_string_outline(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
			draw_string(font, p, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.95, 0.6) if rw.get("jackpot", false) else Color.WHITE)
			draw_set_transform(Vector2.ZERO)
		elif rw.has("item"):
			Glyphs.draw_icon(self, GameData.shop_item(rw["item"])["icon"], mid, r * 0.13, Color.WHITE)
		else:
			Glyphs.draw_icon(self, "coin", mid + Vector2(0, -r * 0.05), r * 0.1, Color.WHITE)
			var txt := str(rw["coins"])
			var fs := int(r * 0.11)
			var w := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			draw_string_outline(font, mid + Vector2(-w / 2, r * 0.16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color.BLACK)
			draw_string(font, mid + Vector2(-w / 2, r * 0.16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 0.9, 0.5) if rw.get("jackpot", false) else Color.WHITE)
	# 테두리 전구
	for k in 24:
		var on := (int(Time.get_ticks_msec() / 150) + k) % 2 == 0 or spinning
		draw_circle(c + Vector2.from_angle(k * TAU / 24.0) * (r + 7), 3.5, Color(1, 1, 0.8) if on else Color(0.6, 0.45, 0.2))
	draw_circle(c, r * 0.14, Color(0.95, 0.8, 0.3))
	draw_circle(c, r * 0.09, Color(0.25, 0.15, 0.05))
	# 포인터
	var tip := c + Vector2(0, -r + 18)
	draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-18, -40), tip + Vector2(18, -40)]), Color(0.95, 0.2, 0.25))
	draw_circle(tip + Vector2(0, -40), 12, Color(0.95, 0.2, 0.25))
