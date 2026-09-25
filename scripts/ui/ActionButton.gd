class_name ActionButton
extends Button
## 아이콘 중심 버튼: 큰 아이콘 + 하단 비용 뱃지 + 우상단 카운트 + 진행 링.
## 설명은 tooltip 으로. 글자 캡션은 설정(show_captions)이 켜졌을 때만 작게 표시.

static var show_captions := false

var icon_name := ""
var icon_color := Color.WHITE
var badge := ""              # 하단 값 (비용 등)
var badge_icon := ""         # 하단 값 앞 아이콘 (gold / gem / coin / ad)
var caption := ""            # 짧은 이름 (show_captions 가 켜진 경우만)
var count := 0               # 우상단 빨간 뱃지 (0 이면 숨김)
var progress := -1.0         # 0~1 게이지 링 (-1 이면 숨김)
var glow := false            # 사용 가능 강조
var selected := false
var tone := Color(0, 0, 0, 0)  # 설정하면 이 색의 입체 버튼으로 직접 그림 (강조 버튼)
var radius := 14.0
var font_px := 0               # 가운데 글자 크기 강제 (0 = 버튼 크기에 맞춤)
var _t := 0.0
var _hold := -1.0            # 누르고 있는 시간 (터치 길게 누르기 → 설명 말풍선)
const LONG_PRESS := 0.45
static var _bubble: Label


static func make(p_icon: String, p_color: Color, p_tip: String, cb: Callable, sz := Vector2(76, 76)) -> ActionButton:
	var b := ActionButton.new()
	b.icon_name = p_icon
	b.icon_color = p_color
	b.tooltip_text = p_tip
	b.caption = p_tip.split("\n")[0]
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	return b


func _ready() -> void:
	button_down.connect(_on_down)
	button_up.connect(_on_up)
	resized.connect(func(): pivot_offset = size * 0.5)
	pivot_offset = size * 0.5
	if tone.a > 0.0:
		set_tone(tone)


func set_tone(c: Color) -> void:
	tone = c
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(st, StyleBoxEmpty.new())
	queue_redraw()


func _on_down() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.94, 0.94), 0.06)


func _on_up() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if glow or progress >= 0.0:
		_t += delta
		queue_redraw()
	if _hold >= 0.0:
		_hold += delta
		if _hold >= LONG_PRESS:
			_hold = -1.0
			_long_press()


func _gui_input(event: InputEvent) -> void:
	## 마우스 오버가 없는 터치 화면용: 길게 누르면 설명(tooltip) 말풍선, 이때는 버튼이 눌리지 않음
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		_hold = 0.0 if event.pressed else -1.0
	elif event is InputEventMouseMotion and _hold >= 0.0 and (event as InputEventMouseMotion).relative.length() > 12.0:
		_hold = -1.0


func _long_press() -> void:
	if tooltip_text == "":
		return
	# 누르던 것을 취소 (손을 떼도 pressed 가 나가지 않음)
	if not disabled:
		disabled = true
		disabled = false
	Platform.vibrate(20)
	show_bubble(self, tooltip_text)


static func show_bubble(target: Control, text: String) -> void:
	if _bubble == null or not is_instance_valid(_bubble):
		var layer := CanvasLayer.new()
		layer.layer = 110
		target.get_tree().root.add_child(layer)
		_bubble = Label.new()
		_bubble.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_bubble.add_theme_font_size_override("font_size", 22)
		_bubble.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.06, 0.1, 0.95)
		sb.border_color = Color(1, 0.85, 0.4)
		sb.set_border_width_all(2)
		sb.set_corner_radius_all(12)
		sb.set_content_margin_all(12)
		_bubble.add_theme_stylebox_override("normal", sb)
		layer.add_child(_bubble)
	_bubble.text = text
	_bubble.size = Vector2(360, 0)
	_bubble.custom_minimum_size = Vector2(0, 0)
	_bubble.reset_size()
	_bubble.size.x = 360
	var r := target.get_global_rect()
	var h := _bubble.get_minimum_size().y
	var pos := Vector2(r.get_center().x - 180, r.position.y - h - 10)
	if pos.y < 10:
		pos.y = r.end.y + 10
	pos.x = clampf(pos.x, 10, 1600 - 370)
	_bubble.position = pos
	_bubble.modulate.a = 1.0
	_bubble.visible = true
	var tw := _bubble.create_tween()
	tw.tween_interval(2.2)
	tw.tween_property(_bubble, "modulate:a", 0.0, 0.3)


func set_state(p_badge: String, p_disabled: bool, p_glow := false, p_count := 0) -> void:
	if badge != p_badge or disabled != p_disabled or glow != p_glow or count != p_count:
		badge = p_badge
		disabled = p_disabled
		glow = p_glow
		count = p_count
		queue_redraw()


func _draw() -> void:
	var sz := size
	var font := get_theme_font("font")
	var a := 0.4 if disabled else 1.0
	var pressed_now := is_pressed() and not disabled and (button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and is_hovered()
	if tone.a > 0.0:
		var c := tone if not disabled else Color(0.32, 0.33, 0.38)
		if is_hovered() and not disabled:
			c = c.lightened(0.08)
		UIKit.draw_gloss(self, Rect2(Vector2.ZERO, sz), c, radius, 6.0, pressed_now)
	if glow and not disabled:
		var pulse := 0.5 + 0.5 * sin(_t * 6.0)
		var g := StyleBoxFlat.new()
		g.draw_center = false
		g.border_color = Color(1, 0.9, 0.35, 0.45 + 0.5 * pulse)
		g.set_border_width_all(3)
		g.set_corner_radius_all(int(radius) + 2)
		g.shadow_color = Color(1, 0.8, 0.2, 0.25 * pulse)
		g.shadow_size = 10
		g.draw(get_canvas_item(), Rect2(Vector2(-2, -2), sz + Vector2(4, 4)))
	if selected:
		var sb := StyleBoxFlat.new()
		sb.draw_center = false
		sb.border_color = Color(1, 0.88, 0.35)
		sb.set_border_width_all(3)
		sb.set_corner_radius_all(int(radius))
		sb.draw(get_canvas_item(), Rect2(Vector2(-1, -1), sz + Vector2(2, 2)))
	if tone.a > 0.0:
		# 입체 버튼: 윗면 가운데에 내용 (눌리면 같이 내려감)
		draw_set_transform(Vector2(0, (4.0 if pressed_now else 0.0) - 3.0))
	if icon_name == "":
		# 아이콘 없는 버튼: 뱃지를 크게 가운데
		_draw_center_badge(font, sz)
		return
	var has_bottom := badge != "" or (show_captions and caption != "")
	var icon_c := Vector2(sz.x * 0.5, sz.y * (0.42 if has_bottom else 0.5))
	var icon_r := minf(sz.x, sz.y) * (0.27 if has_bottom else 0.33)
	var col := icon_color
	col.a = a
	var t := Art.icon(icon_name)
	if t != null:
		draw_texture_rect(t, Rect2(icon_c - Vector2(icon_r, icon_r), Vector2(icon_r, icon_r) * 2.0), false, Color(1, 1, 1, a))
	else:
		Glyphs.draw(self, icon_name, icon_c, icon_r, col)
	if progress >= 0.0:
		draw_arc(icon_c, icon_r + 5, -PI / 2, -PI / 2 + TAU * clampf(progress, 0, 1), 32, Color(1, 0.85, 0.3, a), 3.0)
	# 하단: 비용 뱃지 또는 캡션
	var fs := int(clampf(sz.y * 0.19, 11, 18))
	if badge != "":
		var tw := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var iw := fs * 1.1 if badge_icon != "" else 0.0
		var x0 := (sz.x - tw - iw) * 0.5
		var y := sz.y - fs * 0.55
		if badge_icon != "":
			Glyphs.draw_icon(self, badge_icon, Vector2(x0 + fs * 0.45, y - fs * 0.35), fs * 0.45, Color.WHITE)
		UIKit.draw_text_outlined(self, font, Vector2(x0 + iw, y), badge, fs, Color(1, 1, 1, a), 4)
	elif show_captions and caption != "":
		var cs := fs - 2
		var tw := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x
		draw_string(font, Vector2((sz.x - tw) * 0.5, sz.y - cs * 0.5), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, Color(0.85, 0.88, 0.95, a))
	if count > 0:
		UIKit.draw_badge_dot(self, font, Vector2(sz.x - 6, 6), count)


func _draw_center_badge(font: Font, sz: Vector2) -> void:
	var a := 0.4 if disabled else 1.0
	var fs := font_px if font_px > 0 else int(clampf(sz.y * 0.36, 14, 30))
	var tw := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var iw := fs * 1.2 if badge_icon != "" else 0.0
	var x0 := (sz.x - tw - iw) * 0.5
	var y := sz.y * 0.5 + fs * 0.36
	if badge_icon != "":
		Glyphs.draw_icon(self, badge_icon, Vector2(x0 + fs * 0.5, sz.y * 0.5), fs * 0.5, Color.WHITE)
	UIKit.draw_text_outlined(self, font, Vector2(x0 + iw, y), badge, fs, Color(1, 1, 1, a), maxi(4, fs / 6))
