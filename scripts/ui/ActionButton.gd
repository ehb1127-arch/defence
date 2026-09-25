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
var _t := 0.0


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


func _process(delta: float) -> void:
	if glow or progress >= 0.0:
		_t += delta
		queue_redraw()


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
	if glow and not disabled:
		var pulse := 0.5 + 0.5 * sin(_t * 6.0)
		draw_rect(Rect2(Vector2(2, 2), sz - Vector2(4, 4)), Color(1, 0.9, 0.4, 0.35 + 0.45 * pulse), false, 3.0)
	if selected:
		draw_rect(Rect2(Vector2(1, 1), sz - Vector2(2, 2)), Color(1, 1, 1, 0.9), false, 2.0)
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
		draw_string_outline(font, Vector2(x0 + iw, y), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(0, 0, 0, 0.8 * a))
		draw_string(font, Vector2(x0 + iw, y), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
	elif show_captions and caption != "":
		var cs := fs - 2
		var tw := font.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs).x
		draw_string(font, Vector2((sz.x - tw) * 0.5, sz.y - cs * 0.5), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, cs, Color(0.85, 0.88, 0.95, a))
	if count > 0:
		var p := Vector2(sz.x - 12, 12)
		draw_circle(p, 10, Color(0.9, 0.2, 0.25))
		var s := str(count) if count < 100 else "!"
		var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
		draw_string(font, p + Vector2(-w / 2, 4.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)


func _draw_center_badge(font: Font, sz: Vector2) -> void:
	var a := 0.4 if disabled else 1.0
	var fs := int(clampf(sz.y * 0.36, 14, 30))
	var tw := font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	var iw := fs * 1.2 if badge_icon != "" else 0.0
	var x0 := (sz.x - tw - iw) * 0.5
	var y := sz.y * 0.5 + fs * 0.36
	if badge_icon != "":
		Glyphs.draw_icon(self, badge_icon, Vector2(x0 + fs * 0.5, sz.y * 0.5), fs * 0.5, Color.WHITE)
	draw_string_outline(font, Vector2(x0 + iw, y), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.8 * a))
	draw_string(font, Vector2(x0 + iw, y), badge, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, a))
