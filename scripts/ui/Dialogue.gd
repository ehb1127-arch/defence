class_name Dialogue
extends Control
## 스토리 대화 장면: 아래쪽 대화창 + 초상화 + 한 글자씩 나오는 글. 클릭/Space 로 넘김.
## 초상화 이미지: art/portraits/<인물 id>.png (없으면 문양 임시 그림)

signal finished

var lines: Array = []            # [[인물 id, 대사], ...]
var _i := -1
var _shown := 0.0
var _text := ""
var _name: Label
var _title: Label
var _body: Label
var _portrait: Control
var _speaker := ""
var _t := 0.0


func _ready() -> void:
	size = Vector2(1600, 900)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UIKit.theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.size = size
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	_portrait = _Portrait.new()
	_portrait.position = Vector2(80, 360)
	_portrait.size = Vector2(320, 360)
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_portrait)
	var box := PanelContainer.new()
	var sb: StyleBox = Art.stylebox("dialogue_panel")
	if sb == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.06, 0.07, 0.11, 0.96)
		f.border_color = Color(0.85, 0.75, 0.45)
		f.set_border_width_all(3)
		f.set_corner_radius_all(16)
		f.set_content_margin_all(22)
		sb = f
	else:
		# 그림 틀: 이름·대사가 테두리 장식에 붙지 않게 안쪽 여백
		sb = sb.duplicate()
		sb.content_margin_left = 44
		sb.content_margin_right = 44
		sb.content_margin_top = 26
		sb.content_margin_bottom = 22
	box.add_theme_stylebox_override("panel", sb)
	box.position = Vector2(60, 640)
	box.size = Vector2(1480, 230)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 8)
	box.add_child(v)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(head)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 30)
	head.add_child(_name)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.72, 0.77, 0.88))
	_title.size_flags_vertical = Control.SIZE_SHRINK_END
	head.add_child(_title)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(1380, 110)
	_body.add_theme_font_size_override("font_size", 27)
	v.add_child(_body)
	var skip := ActionButton.make("", Color.WHITE, "대사 건너뛰기", _finish, Vector2(220, 84))
	skip.badge = "건너뛰기 ▶▶"
	skip.font_px = 26
	skip.tone = Color(0.2, 0.24, 0.42)
	skip.position = Vector2(1320, 548)
	add_child(skip)
	_next()


func _next() -> void:
	_i += 1
	if _i >= lines.size():
		_finish()
		return
	var line: Array = lines[_i]
	var who: Dictionary = Story.CHARACTERS.get(line[0], Story.CHARACTERS["narr"])
	_speaker = line[0]
	_name.text = who["name"] if who["name"] != "" else "..."
	_name.add_theme_color_override("font_color", who["color"])
	_title.text = "  " + who["title"]
	_text = str(line[1]).replace("{player}", Session.player_name)
	_shown = 0.0
	_body.text = ""
	_portrait.set("who", line[0])
	_portrait.queue_redraw()
	Sfx.play("tick")


func _finish() -> void:
	finished.emit()
	queue_free()


func _process(delta: float) -> void:
	_t += delta
	if _shown < _text.length():
		_shown += delta * 38.0
		_body.text = _text.substr(0, int(_shown))
	_portrait.set("t", _t)
	_portrait.queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_advance()
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		_advance()
		get_viewport().set_input_as_handled()


func _advance() -> void:
	if _shown < _text.length():
		_shown = _text.length()
		_body.text = _text
	else:
		_next()


class _Portrait:
	extends Control
	var who := "narr"
	var t := 0.0

	func _draw() -> void:
		var tex := Art.tex("portraits/" + who)
		if tex != null:
			draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
			return
		if who == "narr":
			return
		var d: Dictionary = Story.CHARACTERS.get(who, Story.CHARACTERS["narr"])
		var col: Color = d["color"]
		var c := Vector2(size.x * 0.5, size.y * 0.55 + sin(t * 2.0) * 4.0)
		draw_circle(c, 140, Color(col, 0.18))
		draw_circle(c, 115, col.darkened(0.55))
		draw_arc(c, 115, 0, TAU, 48, col, 5.0)
		Glyphs.draw_unit_glyph(self, d["glyph"], c, 70, col.lightened(0.2))
