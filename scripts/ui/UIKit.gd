class_name UIKit
extends RefCounted
## 공통 모바일 게임 스타일: 두툼한 입체 버튼, 팝업 패널, 테두리 글자, 팝 애니메이션.
## 이미지로 덮을 때는 Art.stylebox("...") 가 우선한다 (art/ui/*.png).

const GOLD := Color(1.0, 0.8, 0.2)
const GREEN := Color(0.35, 0.8, 0.3)
const BLUE := Color(0.25, 0.55, 0.95)
const RED := Color(0.9, 0.3, 0.3)
const PURPLE := Color(0.6, 0.4, 0.95)
const NAVY := Color(0.2, 0.28, 0.5)
const PANEL := Color(0.12, 0.15, 0.27)
const INK := Color(0.05, 0.06, 0.12)   # 글자 테두리


static func bevel(col: Color, radius := 14, lip := 6, pressed := false) -> StyleBoxFlat:
	## 아래쪽이 두꺼운 입체 버튼 (눌리면 얇아지고 내용이 내려감)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = col.darkened(0.5)
	sb.set_border_width_all(2)
	sb.border_width_bottom = 2 if pressed else lip
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	sb.content_margin_top = 8 + (lip - 2 if pressed else 0)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 0 if pressed else 3
	sb.shadow_offset = Vector2(0, 3)
	sb.anti_aliasing_size = 1.0
	return sb


static func panel_box(col := PANEL, border := Color(0.36, 0.48, 0.85), radius := 22) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = border
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(18)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	return sb


static func inset(col := Color(0.06, 0.08, 0.15, 0.85), radius := 12) -> StyleBoxFlat:
	## 안쪽으로 파인 칸 (리스트, 입력칸, 게이지 바탕)
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color(0, 0, 0, 0.5)
	sb.border_width_top = 3
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(8)
	return sb


static func pill(col := Color(0.04, 0.05, 0.1, 0.72)) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.border_color = Color(1, 1, 1, 0.12)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(40)
	sb.content_margin_left = 8
	sb.content_margin_right = 14
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	return sb


static func outline(l: Label, size: int, col := Color.WHITE, thick := 0) -> Label:
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", thick if thick > 0 else maxi(4, size / 5))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	l.add_theme_constant_override("shadow_offset_y", maxi(2, size / 14))
	return l


static func label(text: String, size: int, col := Color.WHITE, thick := 0) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return outline(l, size, col, thick)


static func pop_in(c: Control, from := 0.82) -> void:
	c.pivot_offset = c.size * 0.5
	c.scale = Vector2(from, from)
	c.modulate.a = 0.0
	var tw := c.create_tween().set_parallel(true)
	tw.tween_property(c, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(c, "modulate:a", 1.0, 0.15)


static func draw_gloss(ci: CanvasItem, rect: Rect2, col: Color, radius := 14.0, lip := 6.0, pressed := false) -> void:
	## Control._draw 안에서 입체 버튼 그리기 (윗면 광택 포함)
	var sb := bevel(col, int(radius), int(lip), pressed)
	sb.shadow_size = 0
	var r := rect
	if pressed:
		r.position.y += lip - 2
		r.size.y -= lip - 2
	# 아랫면 (두께)
	var under := StyleBoxFlat.new()
	under.bg_color = col.darkened(0.45)
	under.set_corner_radius_all(int(radius))
	under.draw(ci.get_canvas_item(), Rect2(r.position + Vector2(0, 3), r.size))
	var top := Rect2(r.position, Vector2(r.size.x, r.size.y - (2.0 if pressed else lip)))
	var face := StyleBoxFlat.new()
	face.bg_color = col
	face.border_color = col.darkened(0.55)
	face.set_border_width_all(2)
	face.set_corner_radius_all(int(radius))
	face.draw(ci.get_canvas_item(), top)
	# 윗면 광택
	var gl := StyleBoxFlat.new()
	gl.bg_color = Color(1, 1, 1, 0.22)
	gl.corner_radius_top_left = int(radius - 3)
	gl.corner_radius_top_right = int(radius - 3)
	gl.corner_radius_bottom_left = int(radius * 0.6)
	gl.corner_radius_bottom_right = int(radius * 0.6)
	gl.draw(ci.get_canvas_item(), Rect2(top.position + Vector2(5, 4), Vector2(top.size.x - 10, top.size.y * 0.42)))


static func draw_badge_dot(ci: CanvasItem, font: Font, p: Vector2, n: int) -> void:
	## 빨간 알림 숫자 (흰 테두리)
	var s := str(n) if n < 100 else "99+"
	var fs := 15
	var w := maxf(24.0, font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 12)
	var r := Rect2(p - Vector2(w * 0.5, 12), Vector2(w, 24))
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.93, 0.18, 0.22)
	sb.border_color = Color.WHITE
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.draw(ci.get_canvas_item(), r)
	var tw := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
	ci.draw_string(font, Vector2(p.x - tw * 0.5, p.y + 5.5), s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color.WHITE)


static func draw_text_outlined(ci: CanvasItem, font: Font, pos: Vector2, text: String, fs: int, col := Color.WHITE, thick := 5) -> void:
	ci.draw_string_outline(font, pos + Vector2(0, 2), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, thick, Color(0, 0, 0, 0.5))
	ci.draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, thick, INK)
	ci.draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)


static func dress_screen(root: Control) -> void:
	## 하위 화면(상점·보상·도감·스토리) 공통 꾸밈: 배경, 상단 띠, 뒤로 버튼, 제목, 코인 알약.
	## 각 화면이 만든 기본 구성(맨 앞 ColorRect 배경 + (30,24) 위치의 상단 HBox)을 찾아 바꾼다.
	var first := root.get_child(0) if root.get_child_count() > 0 else null
	if first is ColorRect and first.size == Vector2(1600, 900):
		var bg := ScreenBG.new()
		bg.rays = false
		bg.track = false
		bg.center = Vector2(800, 120)
		bg.size = Vector2(1600, 900)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(bg)
		root.move_child(bg, 1)
		first.visible = false
	var top: HBoxContainer = null
	for c in root.get_children():
		if c is HBoxContainer and c.position == Vector2(30, 24):
			top = c
			break
	if top == null:
		return
	var band := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.03, 0.04, 0.1, 0.55)
	bsb.border_color = Color(0.4, 0.52, 0.95, 0.5)
	bsb.border_width_bottom = 2
	band.add_theme_stylebox_override("panel", bsb)
	band.size = Vector2(1600, 104)
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(band)
	root.move_child(band, top.get_index())
	top.position = Vector2(24, 18)
	var kids := top.get_children()
	for i in kids.size():
		var k: Node = kids[i]
		if k is ActionButton and k.icon_name == "back":
			k.tone = BLUE
			k.radius = 18
			k.custom_minimum_size = Vector2(76, 68)
		elif k is Label and int(k.get_theme_font_size("font_size")) >= 30 and not (i > 0 and kids[i - 1] is UIIcon and kids[i - 1].icon_name == "coin"):
			outline(k, 40, k.get_theme_color("font_color"))
		elif k is UIIcon and k.icon_name == "coin" and i + 1 < kids.size() and kids[i + 1] is Label:
			# 코인 아이콘 + 숫자 → 알약
			var lbl: Label = kids[i + 1]
			var pillc := PanelContainer.new()
			pillc.add_theme_stylebox_override("panel", pill())
			var h := HBoxContainer.new()
			h.add_theme_constant_override("separation", 6)
			pillc.add_child(h)
			top.add_child(pillc)
			top.move_child(pillc, k.get_index())
			k.reparent(h)
			lbl.reparent(h)
			lbl.custom_minimum_size = Vector2(100, 0)
			outline(lbl, 28, Color.WHITE)


class Shade:
	extends Control
	## 그림 배경 위 가독성용 그늘: 위·아래 진하게, 양옆 약하게
	func _draw() -> void:
		var d := Color(0.02, 0.03, 0.08, 0.78)
		var n := Color(0.02, 0.03, 0.08, 0.0)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1600, 0), Vector2(1600, 150), Vector2(0, 150)]), PackedColorArray([d, d, n, n]))
		draw_polygon(PackedVector2Array([Vector2(0, 540), Vector2(1600, 540), Vector2(1600, 900), Vector2(0, 900)]), PackedColorArray([n, n, d, d]))
		var side := Color(0.02, 0.03, 0.08, 0.55)
		draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(170, 0), Vector2(170, 900), Vector2(0, 900)]), PackedColorArray([side, n, n, side]))
		draw_polygon(PackedVector2Array([Vector2(1430, 0), Vector2(1600, 0), Vector2(1600, 900), Vector2(1430, 900)]), PackedColorArray([n, side, side, n]))
		draw_rect(Rect2(0, 0, 1600, 900), Color(0.02, 0.03, 0.08, 0.12))


static func coin_fly(from_pos: Vector2, target: Control, n := 8, icon := "coin") -> void:
	## 보상 연출: 동전이 흩어졌다가 재화 표시로 빨려 들어가고, 표시가 톡 튄다
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	var tree := target.get_tree()
	var layer := CanvasLayer.new()
	layer.layer = 115
	tree.root.add_child(layer)
	var to := target.get_global_rect().get_center()
	for i in n:
		var c := UIIcon.make(icon, 34)
		c.position = from_pos - Vector2(17, 17)
		layer.add_child(c)
		var spread := from_pos + Vector2.from_angle(i * TAU / n + randf() * 0.5) * randf_range(40, 90) - Vector2(17, 17)
		var tw := c.create_tween()
		tw.tween_property(c, "position", spread, 0.22).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_interval(0.05 + i * 0.035)
		tw.tween_property(c, "position", to - Vector2(17, 17), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			Sfx.play("coin")
			c.queue_free())
	var pop := target.create_tween()
	pop.tween_interval(0.62)
	target.pivot_offset = target.size * 0.5
	pop.tween_property(target, "scale", Vector2(1.25, 1.25), 0.08)
	pop.tween_property(target, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK)
	tree.create_timer(2.0).timeout.connect(layer.queue_free)
