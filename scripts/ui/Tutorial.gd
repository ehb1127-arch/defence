class_name Tutorial
extends Control
## 첫 플레이 안내. 게임을 멈춘 채 버튼을 하나씩 짚어준다 (강조 테두리 + 화살표 + 말풍선).
## 각 단계: {text, target: Callable -> Rect2, wait: Callable -> bool (없으면 [다음] 버튼)}

signal finished

var steps: Array = []
var _i := -1
var _panel: PanelContainer
var _label: Label
var _next: Button
var _t := 0.0
var _on_enter: Callable


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(1600, 900)
	theme = GameData.ui_theme()
	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.09, 0.14, 0.97)
	sb.border_color = Color(1, 0.85, 0.35)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(16)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 10
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.size = Vector2(430, 0)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_panel.add_child(v)
	var head := HBoxContainer.new()
	head.add_child(UIIcon.make("star", 26, Color(1, 0.85, 0.35)))
	var tl := Label.new()
	tl.text = "튜토리얼"
	tl.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
	head.add_child(tl)
	v.add_child(head)
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size = Vector2(398, 0)
	_label.add_theme_font_size_override("font_size", 19)
	v.add_child(_label)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var skip := Button.new()
	skip.text = "건너뛰기"
	skip.focus_mode = Control.FOCUS_NONE
	skip.pressed.connect(_finish)
	h.add_child(skip)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(sp)
	_next = Button.new()
	_next.text = "다음"
	_next.focus_mode = Control.FOCUS_NONE
	_next.custom_minimum_size = Vector2(120, 42)
	_next.pressed.connect(_advance)
	h.add_child(_next)
	_advance()


func _advance() -> void:
	_i += 1
	if _i >= steps.size():
		_finish()
		return
	var st: Dictionary = steps[_i]
	_label.text = "%s\n(%d / %d)" % [st["text"], _i + 1, steps.size()]
	if st.has("enter"):
		st["enter"].call()
	_next.visible = not st.has("wait")
	Sfx.play("tick")


func _finish() -> void:
	finished.emit()
	queue_free()


func _process(delta: float) -> void:
	_t += delta
	if _i < 0 or _i >= steps.size():
		return
	var st: Dictionary = steps[_i]
	if st.has("wait") and st["wait"].call():
		_advance()
		return
	# 말풍선은 대상 반대쪽에
	var r: Rect2 = st["target"].call()
	var px := r.get_center().x + 60 if r.get_center().x < 800 else r.get_center().x - 490
	var py := clampf(r.get_center().y - 60, 70, 900 - _panel.size.y - 20)
	_panel.position = Vector2(clampf(px, 20, 1600 - 450), py)
	queue_redraw()


func _draw() -> void:
	if _i < 0 or _i >= steps.size():
		return
	var r: Rect2 = steps[_i]["target"].call()
	var pulse := 0.5 + 0.5 * sin(_t * 6.0)
	var grow := r.grow(6 + 4 * pulse)
	draw_rect(grow, Color(1, 0.85, 0.3, 0.9), false, 4.0)
	draw_rect(grow.grow(6), Color(1, 0.85, 0.3, 0.25 * pulse), false, 6.0)
	# 말풍선 → 대상 화살표
	var from := _panel.position + Vector2(_panel.size.x * 0.5, _panel.size.y * 0.5)
	var to := r.get_center()
	var dir := (to - from).normalized()
	var tip := to - dir * (minf(r.size.x, r.size.y) * 0.5 + 18 + 6 * pulse)
	var start := tip - dir * 60
	draw_line(start, tip, Color(1, 0.85, 0.3), 6.0)
	var n := dir.orthogonal()
	draw_colored_polygon(PackedVector2Array([tip + dir * 12, tip - dir * 8 + n * 14, tip - dir * 8 - n * 14]), Color(1, 0.85, 0.3))
