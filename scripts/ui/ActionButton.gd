class_name ActionButton
extends Button
## 아이콘 중심 버튼: 큰 아이콘 + 하단 비용 뱃지 + 우상단 카운트 + 진행 링.
## 설명은 tooltip 으로. 글자 캡션은 설정(show_captions)이 켜졌을 때만 작게 표시.

static var show_captions := true

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
var font_px := 0
var badge_px := 0              # 하단 값 글자 크기 (0 = 버튼 높이에 맞춰 자동)
var wide := false
var sub := ""                  # 가로형 버튼 오른쪽 위 작은 글 (예: "영웅 확정 7")
var locked := false            # 아직 열리지 않은 기능: 흐리게 + 자물쇠 (눌림은 그대로 → 누른 쪽에서 안내)
var new_tag := false           # 새로 열린 기능: 왼쪽 위 NEW 표시
var _t := 0.0
var _hold := -1.0            # 누르고 있는 시간 (터치 길게 누르기 → 설명 말풍선)
const LONG_PRESS := 0.45
static var _bubble: Label


static func make(p_icon: String, p_color: Color, p_tip: String, cb: Callable, sz := Vector2(76, 76)) -> ActionButton:
	var b := ActionButton.new()
	b.icon_name = p_icon
	b.icon_color = p_color
	b.tooltip_text = p_tip
	b.caption = short_caption(p_tip)
	b.custom_minimum_size = sz
	b.focus_mode = Control.FOCUS_NONE
	b.tone = UIKit.NAVY   # 기본: 코드로 그린 입체 버튼 (그림 버튼 스킨은 글자 버튼용)
	b.pressed.connect(cb)
	return b


static func short_caption(tip: String) -> String:
	## 설명 첫 줄에서 괄호(단축키 등)를 뗀 짧은 이름: "소환 (Q)\n..." → "소환"
	var c := tip.split("\n")[0]
	var i := c.find(" (")
	if i > 0:
		c = c.substr(0, i)
	return c


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
	if not disabled:
		Sfx.play("click")
		Platform.vibrate(8)
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2(0.94, 0.94), 0.06)


func _on_up() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if glow or progress >= 0.0 or new_tag:
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
	if Platform.is_mobile():
		# 휴대폰에는 키보드가 없으니 "(Q)" 같은 단축키 표시는 뺀다
		var re := RegEx.create_from_string(" ?\\((?:[A-Z]|Esc|Space|Enter)\\)")
		text = re.sub(text, "", true)
	# 폭을 먼저 정해야 줄바꿈 높이가 맞게 계산된다 (폭 0 으로 재면 글자마다 줄이 바뀌어 아주 길어짐)
	_bubble.custom_minimum_size = Vector2(360, 0)
	_bubble.size = Vector2(360, _bubble.size.y)
	_bubble.text = text
	# 높이는 글꼴로 직접 잰다 (처음 만든 Label 은 첫 측정이 틀릴 수 있음). 여백 12x2 + 테두리
	var font := _bubble.get_theme_font("font")
	var fs := _bubble.get_theme_font_size("font_size")
	var th := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, 360.0 - 24.0, fs, -1,
		TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND | TextServer.BREAK_ADAPTIVE).y
	var h := clampf(ceilf(th) + 28.0, 44.0, 400.0)
	_bubble.custom_minimum_size = Vector2(360, h)
	_bubble.size = Vector2(360, h)
	var r := target.get_global_rect()
	h = _bubble.size.y
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


static func hide_bubble() -> void:
	## 도움말 말풍선 바로 숨기기 (확인 팝업이 열릴 때)
	if _bubble != null and is_instance_valid(_bubble):
		_bubble.visible = false


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
	var a := 0.4 if disabled or locked else 1.0
	var pressed_now := is_pressed() and not disabled and (button_mask & MOUSE_BUTTON_MASK_LEFT) != 0 and is_hovered()
	if tone.a > 0.0:
		var c := tone if not disabled and not locked else Color(0.32, 0.33, 0.38)
		if is_hovered() and not disabled:
			c = c.lightened(0.08)
		UIKit.draw_gloss(self, Rect2(Vector2.ZERO, sz), c, radius, 6.0, pressed_now)
	if glow and not disabled and not locked:
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
	# 가로로 넉넉한 버튼에 이름과 비용이 둘 다 있으면 가로형 배치 (아이콘 | 이름 / 비용)
	if wide or (show_captions and caption != "" and badge != "" and icon_name != "" and sz.x >= sz.y * 1.6 \
			and font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, int(sz.y * 0.28)).x <= sz.x - sz.y - 12):
		_draw_wide(font, sz, a)
		if count > 0:
			UIKit.draw_badge_dot(self, font, Vector2(sz.x - 6, 6), count)
		_draw_marks(font, sz)
		return
	if icon_name == "":
		# 아이콘 없는 버튼: 뱃지를 크게 가운데
		_draw_center_badge(font, sz)
		_draw_marks(font, sz)
		return
	var has_bottom := badge != "" or (show_captions and caption != "")
	var icon_c := Vector2(sz.x * 0.5, sz.y * (0.42 if has_bottom else 0.5))
	var icon_r := minf(sz.x, sz.y) * (0.3 if has_bottom else 0.36)
	var col := icon_color
	col.a = a
	var t := Art.icon(icon_name)
	if t != null:
		draw_texture_rect(t, Rect2(icon_c - Vector2(icon_r, icon_r), Vector2(icon_r, icon_r) * 2.0), false, Glyphs.art_modulate(col))
	else:
		Glyphs.draw(self, icon_name, icon_c, icon_r, col)
	if progress >= 0.0:
		draw_arc(icon_c, icon_r + 5, -PI / 2, -PI / 2 + TAU * clampf(progress, 0, 1), 32, Color(1, 0.85, 0.3, a), 3.0)
	# 하단: 비용 뱃지 또는 캡션
	var fs := int(clampf(sz.y * 0.22, 14, 24))
	if badge != "":
		if badge_px > 0:
			fs = badge_px
		var tw := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var iw := fs * 1.1 if badge_icon != "" else 0.0
		var x0 := (sz.x - tw - iw) * 0.5
		var y := sz.y - fs * 0.55
		if badge_icon != "":
			Glyphs.draw_icon(self, badge_icon, Vector2(x0 + fs * 0.45, y - fs * 0.35), fs * 0.45, Color(1, 1, 1, a))
		UIKit.draw_text_outlined(self, font, Vector2(x0 + iw, y), badge, fs, Color(1, 1, 1, a), 4)
	elif show_captions and caption != "":
		var cs := fs
		var tw := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x
		while tw > sz.x - 8 and cs > 11:
			cs -= 1
			tw = font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x
		UIKit.draw_text_outlined(self, font, Vector2((sz.x - tw) * 0.5, sz.y - cs * 0.55), caption, cs, Color(1, 1, 1, a), 4)
	if count > 0:
		UIKit.draw_badge_dot(self, font, Vector2(sz.x - 6, 6), count)
	_draw_marks(font, sz)


func _draw_marks(font: Font, sz: Vector2) -> void:
	## 자물쇠(잠김) / NEW(새로 열림) 표시
	if locked:
		var r := clampf(minf(sz.x, sz.y) * 0.2, 12, 22)
		var p := Vector2(sz.x - r - 4, r + 4)
		draw_circle(p, r + 3, Color(0.05, 0.06, 0.12, 0.9))
		Glyphs.draw_icon(self, "lock", p, r, Color(1, 0.9, 0.6))
	elif new_tag:
		var fs := int(clampf(sz.y * 0.2, 14, 20))
		var tw := font.get_string_size("NEW", HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var pulse := 0.85 + 0.15 * sin(_t * 6.0)
		var rect := Rect2(Vector2(-6, -8), Vector2(tw + 14, fs + 8))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.95, 0.2, 0.25, pulse)
		sb.set_corner_radius_all(int(rect.size.y * 0.5))
		sb.draw(get_canvas_item(), rect)
		UIKit.draw_text_outlined(self, font, rect.position + Vector2(7, fs + 1), "NEW", fs, Color.WHITE, 3)


func _draw_center_badge(font: Font, sz: Vector2) -> void:
	var a := 0.4 if disabled else 1.0
	var fs := font_px if font_px > 0 else int(clampf(sz.y * 0.36, 14, 30))
	var tw := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var iw := fs * 1.2 if badge_icon != "" else 0.0
	var x0 := (sz.x - tw - iw) * 0.5
	var y := sz.y * 0.5 + fs * 0.36
	if badge_icon != "":
		Glyphs.draw_icon(self, badge_icon, Vector2(x0 + fs * 0.5, sz.y * 0.5), fs * 0.5, Color(1, 1, 1, a))
	UIKit.draw_text_outlined(self, font, Vector2(x0 + iw, y), badge, fs, Color(1, 1, 1, a), maxi(4, fs / 6))


func _draw_wide(font: Font, sz: Vector2, a: float) -> void:
	var h := sz.y
	var r := h * 0.3
	var ic := Vector2(h * 0.5 + 6, h * 0.5)
	var t := Art.icon(icon_name)
	if t != null:
		draw_texture_rect(t, Rect2(ic - Vector2(r, r) * 1.15, Vector2(r, r) * 2.3), false, Glyphs.art_modulate(Color(icon_color, a)))
	else:
		Glyphs.draw(self, icon_name, ic, r, Color(icon_color, a))
	var x := h + 4
	if sub != "":
		var ss := int(h * 0.15)
		var sw := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_LEFT, -1, ss).x
		UIKit.draw_text_outlined(self, font, Vector2(sz.x - sw - 16, h * 0.3), sub, ss, Color(0.85, 0.95, 1.0, a), 4)
	if progress >= 0.0:
		var bw := sz.x - x - 18
		var by := h - 20.0
		draw_rect(Rect2(x, by, bw, 7), Color(0, 0, 0, 0.45))
		draw_rect(Rect2(x, by, bw * clampf(progress, 0.0, 1.0), 7), Color(1, 0.85, 0.3, a))
	var title := caption
	var fs := int(h * 0.28)
	if badge == "":
		UIKit.draw_text_outlined(self, font, Vector2(x, h * 0.5 + fs * 0.36), title, fs, Color(1, 1, 1, a), 6)
		return
	UIKit.draw_text_outlined(self, font, Vector2(x, h * 0.44), title, fs, Color(1, 1, 1, a), 6)
	var bs := badge_px if badge_px > 0 else int(h * 0.2)
	var bx := x
	if badge_icon != "":
		Glyphs.draw_icon(self, badge_icon, Vector2(bx + bs * 0.5, h * 0.72 - bs * 0.32), bs * 0.5, Color(1, 1, 1, a))
		bx += bs * 1.2
	UIKit.draw_text_outlined(self, font, Vector2(bx, h * 0.72 + bs * 0.05), badge, bs, Color(1, 0.95, 0.7, a), 5)
