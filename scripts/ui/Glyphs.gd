class_name Glyphs
extends RefCounted
## 이미지가 오기 전까지 쓰는 벡터 임시 아이콘.
## 모든 그림은 중심 c, 반지름 s 인 정사각형 안에 그린다.
## Art 에 같은 이름의 이미지가 있으면 draw_icon() 이 이미지를 우선 사용한다.


static func draw_icon(ci: CanvasItem, name: String, c: Vector2, s: float, col: Color) -> void:
	var t := Art.icon(name)
	if t != null:
		ci.draw_texture_rect(t, Rect2(c - Vector2(s, s), Vector2(s, s) * 2.0), false)
		return
	draw(ci, name, c, s, col)


static func draw(ci: CanvasItem, name: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(1.5, s * 0.16)
	var dark := Color(0, 0, 0, 0.35)
	match name:
		# ---------------- 재화 ----------------
		"gold":
			ci.draw_circle(c, s * 0.9, Color(0.75, 0.55, 0.1))
			ci.draw_circle(c, s * 0.75, Color(1.0, 0.8, 0.2))
			ci.draw_arc(c, s * 0.5, 0, TAU, 20, Color(0.8, 0.55, 0.1), w * 0.7)
			ci.draw_circle(c + Vector2(-s * 0.3, -s * 0.3), s * 0.15, Color(1, 1, 0.8, 0.8))
		"gem":
			var pts := PackedVector2Array([c + Vector2(0, -s * 0.9), c + Vector2(s * 0.8, -s * 0.2), c + Vector2(0, s * 0.95), c + Vector2(-s * 0.8, -s * 0.2)])
			ci.draw_colored_polygon(pts, Color(0.35, 0.8, 1.0))
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.9), c + Vector2(s * 0.8, -s * 0.2), c + Vector2(0, -s * 0.05)]), Color(0.7, 0.95, 1.0))
			ci.draw_line(c + Vector2(-s * 0.8, -s * 0.2), c + Vector2(s * 0.8, -s * 0.2), Color(1, 1, 1, 0.5), w * 0.5)
		"coin":
			ci.draw_circle(c, s * 0.9, Color(0.55, 0.35, 0.8))
			ci.draw_circle(c, s * 0.72, Color(0.78, 0.55, 1.0))
			_star(ci, c, s * 0.42, Color(1, 0.95, 0.6))
		# ---------------- 행동 ----------------
		"summon":
			_star(ci, c, s * 0.95, col)
			ci.draw_line(c + Vector2(0, -s * 0.35), c + Vector2(0, s * 0.35), Color.WHITE, w)
			ci.draw_line(c + Vector2(-s * 0.35, 0), c + Vector2(s * 0.35, 0), Color.WHITE, w)
		"merge":
			for k in 3:
				var a := -PI / 2 + (k - 1) * 0.8
				var p := c + Vector2.from_angle(a + PI) * s * 0.85
				ci.draw_circle(p, s * 0.2, col)
				ci.draw_line(p, c + Vector2(0, s * 0.1), col, w)
			_arrow(ci, c + Vector2(0, s * 0.1), c + Vector2(0, -s * 0.9), Color.WHITE, w * 1.2, s * 0.3)
		"gamble":
			var r := Rect2(c - Vector2(s, s) * 0.75, Vector2(s, s) * 1.5)
			ci.draw_rect(r, col)
			ci.draw_rect(r, Color.WHITE, false, w)
			for d in [Vector2(-0.4, -0.4), Vector2(0.4, 0.4), Vector2(0, 0), Vector2(0.4, -0.4), Vector2(-0.4, 0.4)]:
				ci.draw_circle(c + d * s, s * 0.12, Color.WHITE)
		"upgrade":
			_arrow(ci, c + Vector2(0, s * 0.9), c + Vector2(0, -s * 0.9), col, w * 2.2, s * 0.6)
			ci.draw_line(c + Vector2(-s * 0.7, s * 0.9), c + Vector2(s * 0.7, s * 0.9), col, w)
		"recipe":
			ci.draw_rect(Rect2(c - Vector2(s * 0.8, s * 0.9), Vector2(s * 1.6, s * 1.8)), col)
			ci.draw_line(c + Vector2(0, -s * 0.9), c + Vector2(0, s * 0.9), dark, w)
			_star(ci, c + Vector2(s * 0.4, -s * 0.2), s * 0.3, Color(1, 0.9, 0.4))
		"attack":
			ci.draw_line(c + Vector2(-s * 0.8, s * 0.8), c + Vector2(s * 0.8, -s * 0.8), col, w * 1.4)
			ci.draw_line(c + Vector2(s * 0.8, s * 0.8), c + Vector2(-s * 0.8, -s * 0.8), col, w * 1.4)
			ci.draw_line(c + Vector2(-s * 0.75, s * 0.35), c + Vector2(-s * 0.35, s * 0.75), Color.WHITE, w)
			ci.draw_line(c + Vector2(s * 0.75, s * 0.35), c + Vector2(s * 0.35, s * 0.75), Color.WHITE, w)
		"gift":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.2), Vector2(s * 1.6, s * 1.05)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.9, -s * 0.5), Vector2(s * 1.8, s * 0.35)), col.lightened(0.2))
			ci.draw_line(c + Vector2(0, -s * 0.5), c + Vector2(0, s * 0.85), Color.WHITE, w * 1.2)
			ci.draw_arc(c + Vector2(-s * 0.25, -s * 0.65), s * 0.25, 0, TAU, 12, Color.WHITE, w)
			ci.draw_arc(c + Vector2(s * 0.25, -s * 0.65), s * 0.25, 0, TAU, 12, Color.WHITE, w)
		"blast":
			ci.draw_circle(c + Vector2(0, s * 0.15), s * 0.7, col)
			ci.draw_line(c + Vector2(s * 0.35, -s * 0.4), c + Vector2(s * 0.7, -s * 0.85), Color(0.9, 0.8, 0.6), w)
			_star(ci, c + Vector2(s * 0.75, -s * 0.9), s * 0.25, Color(1, 0.8, 0.2))
		"mission":
			ci.draw_line(c + Vector2(-s * 0.6, s * 0.95), c + Vector2(-s * 0.6, -s * 0.9), Color.WHITE, w)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.6, -s * 0.9), c + Vector2(s * 0.8, -s * 0.55), c + Vector2(-s * 0.6, -s * 0.15)]), col)
		"shop":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.8, -s * 0.3), Vector2(s * 1.6, s * 1.2)), col)
			ci.draw_arc(c + Vector2(0, -s * 0.3), s * 0.45, PI, TAU, 16, Color.WHITE, w)
			ci.draw_circle(c + Vector2(0, s * 0.3), s * 0.15, Color.WHITE)
		"ad":
			ci.draw_rect(Rect2(c - Vector2(s * 0.95, s * 0.7), Vector2(s * 1.9, s * 1.4)), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.3, -s * 0.4), c + Vector2(s * 0.45, 0), c + Vector2(-s * 0.3, s * 0.4)]), Color.WHITE)
		"pause":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.6, -s * 0.75), Vector2(s * 0.4, s * 1.5)), col)
			ci.draw_rect(Rect2(c + Vector2(s * 0.2, -s * 0.75), Vector2(s * 0.4, s * 1.5)), col)
		"play":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.5, -s * 0.8), c + Vector2(s * 0.8, 0), c + Vector2(-s * 0.5, s * 0.8)]), col)
		"speed":
			for dx in [-0.55, 0.25]:
				ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * dx, -s * 0.7), c + Vector2(s * (dx + 0.7), 0), c + Vector2(s * dx, s * 0.7)]), col)
		"menu", "home":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.9), c + Vector2(s * 0.9, -s * 0.1), c + Vector2(-s * 0.9, -s * 0.1)]), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.6, -s * 0.15), Vector2(s * 1.2, s * 0.95)), col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.15, s * 0.3), Vector2(s * 0.3, s * 0.5)), dark)
		"sound":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.8, -s * 0.3), c + Vector2(-s * 0.4, -s * 0.3), c + Vector2(0, -s * 0.75), c + Vector2(0, s * 0.75), c + Vector2(-s * 0.4, s * 0.3), c + Vector2(-s * 0.8, s * 0.3)]), col)
			ci.draw_arc(c, s * 0.45, -0.8, 0.8, 10, col, w)
			ci.draw_arc(c, s * 0.8, -0.8, 0.8, 10, col, w)
		"mute":
			draw(ci, "sound", c, s, col)
			ci.draw_line(c + Vector2(-s * 0.9, -s * 0.9), c + Vector2(s * 0.9, s * 0.9), Color(1, 0.3, 0.3), w * 1.3)
		"revive", "heart":
			ci.draw_circle(c + Vector2(-s * 0.38, -s * 0.2), s * 0.45, col)
			ci.draw_circle(c + Vector2(s * 0.38, -s * 0.2), s * 0.45, col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.82, 0), c + Vector2(s * 0.82, 0), c + Vector2(0, s * 0.9)]), col)
		"sell":
			draw(ci, "gold", c + Vector2(-s * 0.15, s * 0.1), s * 0.75, col)
			_arrow(ci, c + Vector2(s * 0.55, s * 0.6), c + Vector2(s * 0.55, -s * 0.9), Color(0.5, 1, 0.5), w, s * 0.3)
		"close":
			ci.draw_line(c + Vector2(-s * 0.6, -s * 0.6), c + Vector2(s * 0.6, s * 0.6), col, w * 1.4)
			ci.draw_line(c + Vector2(s * 0.6, -s * 0.6), c + Vector2(-s * 0.6, s * 0.6), col, w * 1.4)
		"back":
			_arrow(ci, c + Vector2(s * 0.8, 0), c + Vector2(-s * 0.8, 0), col, w * 1.5, s * 0.5)
		"check":
			ci.draw_polyline(PackedVector2Array([c + Vector2(-s * 0.7, 0), c + Vector2(-s * 0.2, s * 0.55), c + Vector2(s * 0.75, -s * 0.6)]), col, w * 1.5)
		"lock":
			ci.draw_arc(c + Vector2(0, -s * 0.2), s * 0.4, PI, TAU, 12, col, w * 1.2)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.6, -s * 0.2), Vector2(s * 1.2, s * 1.0)), col)
		"chest":
			ci.draw_rect(Rect2(c + Vector2(-s * 0.9, -s * 0.2), Vector2(s * 1.8, s * 0.95)), Color(0.6, 0.38, 0.15))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.9, -s * 0.65), Vector2(s * 1.8, s * 0.5)), Color(0.8, 0.5, 0.2))
			ci.draw_rect(Rect2(c + Vector2(-s * 0.15, -s * 0.3), Vector2(s * 0.3, s * 0.35)), Color(1, 0.85, 0.3))
		"luck":
			for k in 4:
				ci.draw_circle(c + Vector2.from_angle(PI / 4 + k * PI / 2) * s * 0.42, s * 0.36, col)
			ci.draw_line(c, c + Vector2(s * 0.3, s * 0.95), col.darkened(0.3), w)
		"swarm":
			for p in [Vector2(-0.45, 0.3), Vector2(0.45, 0.3), Vector2(0, -0.35)]:
				ci.draw_circle(c + p * s, s * 0.35, col)
				ci.draw_circle(c + p * s + Vector2(-s * 0.1, -s * 0.05), s * 0.07, Color.WHITE)
				ci.draw_circle(c + p * s + Vector2(s * 0.1, -s * 0.05), s * 0.07, Color.WHITE)
		"elite":
			ci.draw_rect(Rect2(c - Vector2(s, s) * 0.7, Vector2(s, s) * 1.4), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.7, -s * 0.7), c + Vector2(-s * 0.4, -s * 1.0), c + Vector2(-s * 0.3, -s * 0.7)]), col)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.7, -s * 0.7), c + Vector2(s * 0.4, -s * 1.0), c + Vector2(s * 0.3, -s * 0.7)]), col)
			ci.draw_circle(c + Vector2(-s * 0.3, -s * 0.1), s * 0.14, Color(1, 1, 0.5))
			ci.draw_circle(c + Vector2(s * 0.3, -s * 0.1), s * 0.14, Color(1, 1, 0.5))
		"curse":
			ci.draw_circle(c, s * 0.8, col)
			ci.draw_arc(c, s * 0.5, 0.3, PI * 1.6, 16, Color(0, 0, 0, 0.5), w)
			ci.draw_arc(c, s * 0.25, 0.3, PI * 1.6, 12, Color(0, 0, 0, 0.5), w)
		"star":
			_star(ci, c, s, col)
		"gear":
			for k in 8:
				var d := Vector2.from_angle(k * PI / 4)
				ci.draw_line(c + d * s * 0.5, c + d * s * 0.95, col, w * 1.8)
			ci.draw_circle(c, s * 0.62, col)
			ci.draw_circle(c, s * 0.26, Color(0, 0, 0, 0.45))
		"spawn":
			ci.draw_circle(c, s, Color(col, 0.35))
			ci.draw_circle(c, s * 0.7, col.darkened(0.4))
			ci.draw_arc(c, s * 0.7, 0, TAU, 20, col, w)
		"defeat":
			draw_unit_glyph(ci, "skull", c, s, col)
		# ---------------- 유닛 문양 ----------------
		_:
			draw_unit_glyph(ci, name, c, s, col)


## 유닛 종류별 문양 (등급 모양 안쪽에 그림)
static func draw_unit_glyph(ci: CanvasItem, name: String, c: Vector2, s: float, col: Color) -> void:
	var w := maxf(1.5, s * 0.18)
	match name:
		"blade", "dagger":
			var len := 0.9 if name == "blade" else 0.6
			ci.draw_line(c + Vector2(-s * len, s * len), c + Vector2(s * len, -s * len), col, w * 1.2)
			ci.draw_line(c + Vector2(-s * 0.5, s * 0.0), c + Vector2(s * 0.0, s * 0.5), col, w)
		"bow":
			ci.draw_arc(c + Vector2(-s * 0.3, 0), s * 0.85, -1.1, 1.1, 12, col, w)
			ci.draw_line(c + Vector2(s * 0.08, -s * 0.75), c + Vector2(s * 0.08, s * 0.75), col, w * 0.6)
			_arrow(ci, c + Vector2(-s * 0.8, 0), c + Vector2(s * 0.8, 0), col, w * 0.7, s * 0.25)
		"orb":
			ci.draw_arc(c, s * 0.7, 0, TAU, 18, col, w)
			ci.draw_circle(c, s * 0.3, col)
		"spear":
			ci.draw_line(c + Vector2(-s * 0.8, s * 0.8), c + Vector2(s * 0.5, -s * 0.5), col, w)
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(s * 0.9, -s * 0.9), c + Vector2(s * 0.3, -s * 0.6), c + Vector2(s * 0.6, -s * 0.3)]), col)
		"rock":
			ci.draw_circle(c + Vector2(s * 0.2, -s * 0.1), s * 0.45, col)
			ci.draw_arc(c, s * 0.85, PI * 0.6, PI * 1.2, 8, col, w * 0.7)
		"shield":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.7, -s * 0.7), c + Vector2(s * 0.7, -s * 0.7), c + Vector2(s * 0.6, s * 0.2), c + Vector2(0, s * 0.9), c + Vector2(-s * 0.6, s * 0.2)]), col)
		"scope":
			ci.draw_arc(c, s * 0.7, 0, TAU, 18, col, w)
			ci.draw_line(c + Vector2(-s * 0.95, 0), c + Vector2(s * 0.95, 0), col, w * 0.7)
			ci.draw_line(c + Vector2(0, -s * 0.95), c + Vector2(0, s * 0.95), col, w * 0.7)
		"snow":
			for k in 3:
				var d := Vector2.from_angle(k * PI / 3) * s * 0.85
				ci.draw_line(c - d, c + d, col, w)
		"flame":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -s * 0.95), c + Vector2(s * 0.6, s * 0.1), c + Vector2(s * 0.4, s * 0.7), c + Vector2(0, s * 0.85), c + Vector2(-s * 0.4, s * 0.7), c + Vector2(-s * 0.6, s * 0.1)]), col)
		"coin":
			ci.draw_arc(c, s * 0.7, 0, TAU, 18, col, w)
			ci.draw_line(c + Vector2(0, -s * 0.45), c + Vector2(0, s * 0.45), col, w)
		"bolt", "bolt2":
			var off := [0.0] if name == "bolt" else [-0.3, 0.3]
			for o in off:
				var p := c + Vector2(s * o, 0)
				ci.draw_polyline(PackedVector2Array([p + Vector2(s * 0.3, -s * 0.9), p + Vector2(-s * 0.25, 0), p + Vector2(s * 0.25, 0), p + Vector2(-s * 0.3, s * 0.9)]), col, w)
		"axe":
			ci.draw_line(c + Vector2(-s * 0.6, s * 0.9), c + Vector2(s * 0.3, -s * 0.6), col, w)
			ci.draw_arc(c + Vector2(s * 0.25, -s * 0.5), s * 0.5, -PI * 0.9, PI * 0.1, 10, col, w * 1.5)
		"flask":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.2, -s * 0.8), c + Vector2(s * 0.2, -s * 0.8), c + Vector2(s * 0.2, -s * 0.2), c + Vector2(s * 0.75, s * 0.8), c + Vector2(-s * 0.75, s * 0.8), c + Vector2(-s * 0.2, -s * 0.2)]), col)
		"note":
			ci.draw_circle(c + Vector2(-s * 0.3, s * 0.5), s * 0.3, col)
			ci.draw_line(c + Vector2(-s * 0.02, s * 0.5), c + Vector2(-s * 0.02, -s * 0.8), col, w)
			ci.draw_line(c + Vector2(-s * 0.02, -s * 0.8), c + Vector2(s * 0.6, -s * 0.5), col, w)
		"arrows":
			for dy in [-0.5, 0.0, 0.5]:
				_arrow(ci, c + Vector2(-s * 0.8, s * dy), c + Vector2(s * 0.8, s * dy), col, w * 0.8, s * 0.25)
		"wing":
			for sgn in [-1.0, 1.0]:
				ci.draw_colored_polygon(PackedVector2Array([c, c + Vector2(sgn * s * 0.95, -s * 0.7), c + Vector2(sgn * s * 0.7, s * 0.1), c + Vector2(sgn * s * 0.3, s * 0.3)]), col)
		"meteor":
			ci.draw_circle(c + Vector2(s * 0.3, s * 0.3), s * 0.45, col)
			for k in 3:
				ci.draw_line(c + Vector2(s * 0.1 - k * s * 0.25, s * 0.0 - k * s * 0.05), c + Vector2(-s * 0.8 - k * s * 0.05, -s * 0.8 + k * s * 0.3), col, w * 0.7)
		"halo":
			ci.draw_arc(c + Vector2(0, -s * 0.55), s * 0.45, 0, TAU, 14, col, w)
			draw_unit_glyph(ci, "wing", c + Vector2(0, s * 0.25), s * 0.8, col)
		"phoenix":
			draw_unit_glyph(ci, "wing", c, s, col)
			draw_unit_glyph(ci, "flame", c + Vector2(0, -s * 0.1), s * 0.55, Color(1, 0.95, 0.6))
		"clock":
			ci.draw_arc(c, s * 0.8, 0, TAU, 20, col, w)
			ci.draw_line(c, c + Vector2(0, -s * 0.55), col, w)
			ci.draw_line(c, c + Vector2(s * 0.4, s * 0.1), col, w)
		"crown":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-s * 0.85, s * 0.6), c + Vector2(-s * 0.85, -s * 0.5), c + Vector2(-s * 0.4, 0), c + Vector2(0, -s * 0.8), c + Vector2(s * 0.4, 0), c + Vector2(s * 0.85, -s * 0.5), c + Vector2(s * 0.85, s * 0.6)]), col)
		"skull":
			ci.draw_circle(c + Vector2(0, -s * 0.15), s * 0.7, col)
			ci.draw_rect(Rect2(c + Vector2(-s * 0.4, s * 0.3), Vector2(s * 0.8, s * 0.5)), col)
			ci.draw_circle(c + Vector2(-s * 0.28, -s * 0.15), s * 0.2, Color(0, 0, 0, 0.7))
			ci.draw_circle(c + Vector2(s * 0.28, -s * 0.15), s * 0.2, Color(0, 0, 0, 0.7))
		_:
			ci.draw_circle(c, s * 0.4, col)


static func _star(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var r := s if k % 2 == 0 else s * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2 + k * PI / 5) * r)
	ci.draw_colored_polygon(pts, col)


static func _arrow(ci: CanvasItem, from: Vector2, to: Vector2, col: Color, w: float, head: float) -> void:
	var dir := (to - from).normalized()
	var n := dir.orthogonal()
	ci.draw_line(from, to - dir * head * 0.6, col, w)
	ci.draw_colored_polygon(PackedVector2Array([to, to - dir * head + n * head * 0.6, to - dir * head - n * head * 0.6]), col)


## 유닛 토큰: art/units/<id>.png 가 있으면 이미지, 없으면 등급 모양 + 종류 문양
static func draw_unit_token(ci: CanvasItem, id: String, c: Vector2, r: float, anim := 0.0, alpha := 1.0) -> void:
	var t := Art.unit(id)
	if t != null:
		ci.draw_texture_rect(t, Rect2(c - Vector2(r, r) * 1.3, Vector2(r, r) * 2.6), false, Color(1, 1, 1, alpha))
		return
	var u: Dictionary = GameData.UNITS[id]
	var rarity: int = u["rarity"]
	var col: Color = u["color"]
	var rc: Color = GameData.RARITY_COLORS[rarity]
	col.a = alpha
	rc.a = alpha
	var pts := PackedVector2Array()
	match rarity:
		0:
			for k in 24:
				pts.append(c + Vector2.from_angle(TAU * k / 24.0) * r)
		1:
			pts = PackedVector2Array([c + Vector2(0, -r * 1.2), c + Vector2(r * 1.2, 0), c + Vector2(0, r * 1.2), c + Vector2(-r * 1.2, 0)])
		2:
			for k in 6:
				pts.append(c + Vector2.from_angle(TAU * k / 6.0 - PI / 2) * r * 1.12)
		_:
			var spikes := 5 if rarity == 3 else 8
			var rot := anim * 0.8 if rarity == 4 else 0.0
			for k in spikes * 2:
				var rr := r * (1.3 if k % 2 == 0 else 0.85)
				pts.append(c + Vector2.from_angle(TAU * k / (spikes * 2.0) - PI / 2 + rot) * rr)
			if rarity == 4:
				ci.draw_circle(c, r * 1.45, Color(rc, (0.2 + 0.12 * sin(anim * 5.0)) * alpha))
	ci.draw_colored_polygon(pts, col.darkened(0.15))
	var inner := PackedVector2Array()
	for p in pts:
		inner.append(c + (p - c) * 0.82)
	ci.draw_colored_polygon(inner, col)
	pts.append(pts[0])
	ci.draw_polyline(pts, rc, maxf(2.0, r * 0.12))
	var lum := col.r * 0.3 + col.g * 0.59 + col.b * 0.11
	var gcol := Color(0.1, 0.1, 0.15, 0.85 * alpha) if lum > 0.62 else Color(1, 1, 1, 0.92 * alpha)
	draw_unit_glyph(ci, u.get("glyph", ""), c, r * 0.55, gcol)
