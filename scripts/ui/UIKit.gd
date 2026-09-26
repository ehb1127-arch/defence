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


# ===========================================================================
# 공통 테마 (글자 크기를 휴대폰에 맞게 키운 판)
# ===========================================================================
const FONT_BODY := 22       # 기본 글자 (라벨·버튼·목록)
static var _theme: Theme


static func theme() -> Theme:
	## GameData.ui_theme() 를 바탕으로 기본 글자만 키운 테마 (6인치 휴대폰에서 읽히는 크기)
	if _theme == null:
		_theme = GameData.ui_theme().duplicate()
		_theme.default_font_size = FONT_BODY
		# 켜기/끄기 줄: 굵은 그림 버튼(모서리 장식)에 글자가 겹치지 않게 코드로 그린 납작한 줄
		var row := func(col: Color) -> StyleBoxFlat:
			var f := StyleBoxFlat.new()
			f.bg_color = col
			f.border_color = Color(0.4, 0.52, 0.95, 0.5)
			f.set_border_width_all(2)
			f.set_corner_radius_all(14)
			f.content_margin_left = 20
			f.content_margin_right = 16
			f.content_margin_top = 8
			f.content_margin_bottom = 8
			return f
		for st in ["normal", "pressed"]:
			_theme.set_stylebox(st, "CheckButton", row.call(Color(0.1, 0.13, 0.28, 0.95)))
		for st in ["hover", "hover_pressed"]:
			_theme.set_stylebox(st, "CheckButton", row.call(Color(0.14, 0.18, 0.36, 0.95)))
		_theme.set_stylebox("disabled", "CheckButton", row.call(Color(0.12, 0.13, 0.18, 0.8)))
		_theme.set_stylebox("focus", "CheckButton", StyleBoxEmpty.new())
	return _theme


# ===========================================================================
# 이 기기에만 남기는 화면 상태 (NEW 표시 확인, 본 공지, 개발자 메뉴 등)
# ===========================================================================
const UI_STATE_PATH := "user://ui_state.cfg"
static var _state: ConfigFile


static func ui_get(key: String, default: Variant = null) -> Variant:
	if _state == null:
		_state = ConfigFile.new()
		_state.load(UI_STATE_PATH)
	return _state.get_value("ui", key, default)


static func ui_set(key: String, value: Variant) -> void:
	ui_get(key)
	_state.set_value("ui", key, value)
	_state.save(UI_STATE_PATH)


# ===========================================================================
# 기능 단계별 열림 (처음엔 소환·합성만, 스토리 진행/계정 레벨에 따라 버튼이 하나씩 열림)
# ===========================================================================
## 기능 -> [열리는 스테이지(여기까지 오면 열림), 또는 이 계정 레벨 이상, 안내 문구]
const UNLOCKS := {
	"upgrade": ["1-2", 3, "스토리 1-2 에서 열려요"],
	"enhance": ["1-3", 4, "스토리 1-3 에서 열려요"],
	"gamble": ["1-4", 5, "스토리 1-4 에서 열려요"],
	"slot": ["2-1", 6, "스토리 2장에서 열려요"],
	"control": ["3-1", 8, "스토리 3장에서 열려요"],
}


static func feature_unlocked(key: String) -> bool:
	if not UNLOCKS.has(key) or Session.online:
		return true
	var u: Array = UNLOCKS[key]
	if Profile.level >= int(u[1]):
		return true
	var sid: String = u[0]
	if Session.stage == sid or Session.stage == "H" + sid:
		return true
	return Profile.stage_unlocked(sid)


static func feature_is_new(key: String) -> bool:
	## 새로 열렸는데 아직 한 번도 안 눌러 본 기능 (버튼에 NEW 표시)
	_init_seen()
	return UNLOCKS.has(key) and feature_unlocked(key) and not bool(ui_get("seen_" + key, false))


static func _init_seen() -> void:
	## 처음 한 번: 이미 열려 있던 기능은 본 것으로 (업데이트한 기존 플레이어에게 NEW 가 잔뜩 뜨지 않게)
	if bool(ui_get("seen_init", false)):
		return
	_state.set_value("ui", "seen_init", true)
	for key in UNLOCKS:
		var u: Array = UNLOCKS[key]
		if Profile.level >= int(u[1]) or Profile.stage_unlocked(u[0]):
			_state.set_value("ui", "seen_" + key, true)
	_state.save(UI_STATE_PATH)


static func mark_feature_seen(key: String) -> void:
	if UNLOCKS.has(key) and not bool(ui_get("seen_" + key, false)):
		ui_set("seen_" + key, true)


# ===========================================================================
# 확인 창 (구매 확인 · 나가기 확인 등)
# ===========================================================================
static func confirm(parent: Node, title: String, body: String, ok_text: String, on_ok: Callable, cancel_text := "취소", on_cancel := Callable(), extra: Control = null) -> Control:
	## 화면 전체를 어둡게 덮고 가운데 창을 띄운다. 바깥을 누르면 취소.
	ActionButton.hide_bubble()   # 도움말 말풍선이 창 위에 남지 않게
	var root := Control.new()
	root.theme = theme()
	root.size = Vector2(1600, 900)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.62)
	dim.size = Vector2(1600, 900)
	root.add_child(dim)
	var p := PanelContainer.new()
	var sb := panel_box(Color(0.09, 0.11, 0.23, 0.98), Color(1, 0.8, 0.35), 24)
	sb.set_content_margin_all(28)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(720, 0)
	root.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	p.add_child(v)
	var t := label(title, 34, Color(1, 0.88, 0.45))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	if body != "":
		var b := label(body, 24, Color(0.9, 0.93, 1.0), 4)
		b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size = Vector2(660, 0)
		v.add_child(b)
	if extra != null:
		v.add_child(extra)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	var close := func(): root.queue_free()
	var done := [false]
	var cancel := func():
		if done[0]:
			return
		done[0] = true
		close.call()
		if on_cancel.is_valid():
			on_cancel.call()
	if cancel_text != "":
		var cb := ActionButton.make("", Color.WHITE, cancel_text, cancel, Vector2(260, 92))
		cb.badge = cancel_text
		cb.font_px = 28
		cb.tone = NAVY
		h.add_child(cb)
	var ok := func():
		if done[0]:
			return
		done[0] = true
		close.call()
		on_ok.call()
	var ob := ActionButton.make("", Color.WHITE, ok_text, ok, Vector2(260, 92))
	ob.badge = ok_text
	ob.font_px = 28
	ob.tone = Color(0.95, 0.62, 0.12)
	h.add_child(ob)
	dim.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and cancel_text != "":
			cancel.call())
	root.set_meta("cancel", cancel)
	parent.add_child(root)
	var place := func():
		p.size = p.get_combined_minimum_size()
		p.position = (Vector2(1600, 900) - p.size) * 0.5
		pop_in(p)
	place.call_deferred()
	return root


static func keep_words(text: String) -> String:
	## 한글은 글자마다 줄이 바뀔 수 있어 "있\n어요" 처럼 잘린다 → 띄어쓰기에서만 줄을 바꾸도록
	## 글자 사이에 WORD JOINER(U+2060, 보이지 않음)를 넣는다
	var out := ""
	var prev := " "
	for ch in text:
		if ch != " " and ch != "\n" and prev != " " and prev != "\n":
			out += "⁠"
		out += ch
		prev = ch
	return out
