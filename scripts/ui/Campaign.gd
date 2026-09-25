class_name Campaign
extends Control
## 스토리 모드 지도: 장 선택 → 스테이지 길 → 정보/시작. 장별 ★ 상자.
## 이미지 교체: art/ui/chapter_<장 번호>.png (배경)

var _chapter := 1
var _stage := ""
var _map: Control
var _info_title: Label
var _info_desc: Label
var _info_mods: HBoxContainer
var _info_stars: HBoxContainer
var _start: ActionButton
var _coin_lbl: Label
var _chap_btns: Array = []
var _chest_row: HBoxContainer
var _bg: TextureRect


func _ready() -> void:
	theme = GameData.ui_theme()
	var base := ColorRect.new()
	base.color = Color(0.05, 0.06, 0.09)
	base.size = Vector2(1600, 900)
	add_child(base)
	_bg = TextureRect.new()
	_bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_bg.size = Vector2(1600, 900)
	_bg.modulate = Color(1, 1, 1, 0.5)
	add_child(_bg)
	var top := HBoxContainer.new()
	top.position = Vector2(30, 24)
	top.size = Vector2(1540, 70)
	top.add_theme_constant_override("separation", 14)
	add_child(top)
	top.add_child(ActionButton.make("back", Color(0.85, 0.9, 1.0), "뒤로", func(): get_tree().change_scene_to_file("res://scenes/Main.tscn"), Vector2(70, 64)))
	top.add_child(UIIcon.make("book", 50, Color(1, 0.8, 0.45)))
	var title := Label.new()
	title.text = "스토리 - 사각 결계 연대기"
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	top.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(UIIcon.make("star", 38, Color(1, 0.85, 0.3)))
	var st := Label.new()
	st.text = "%d / %d" % [Profile.total_stars(), Story.all_ids().size() * 3]
	st.add_theme_font_size_override("font_size", 26)
	top.add_child(st)
	top.add_child(UIIcon.make("coin", 40))
	_coin_lbl = Label.new()
	_coin_lbl.add_theme_font_size_override("font_size", 28)
	_coin_lbl.add_theme_color_override("font_color", Color(0.85, 0.72, 1.0))
	top.add_child(_coin_lbl)
	# 왼쪽: 장 목록
	var left := VBoxContainer.new()
	left.position = Vector2(30, 110)
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	for ch in Story.CHAPTERS:
		var n: int = ch["id"]
		var b := Button.new()
		b.custom_minimum_size = Vector2(330, 100)
		b.focus_mode = Control.FOCUS_NONE
		b.pressed.connect(func(): _select_chapter(n))
		b.add_theme_font_size_override("font_size", 18)
		left.add_child(b)
		_chap_btns.append(b)
	# 가운데: 스테이지 지도
	_map = _StageMap.new()
	_map.position = Vector2(390, 110)
	_map.size = Vector2(1180, 420)
	_map.menu = self
	add_child(_map)
	# 장별 ★ 상자
	_chest_row = HBoxContainer.new()
	_chest_row.position = Vector2(400, 470)
	_chest_row.add_theme_constant_override("separation", 14)
	add_child(_chest_row)
	# 아래: 스테이지 정보
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.1, 0.15, 0.95)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	p.position = Vector2(390, 580)
	p.size = Vector2(1180, 290)
	add_child(p)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 20)
	p.add_child(h)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	h.add_child(v)
	_info_title = Label.new()
	_info_title.add_theme_font_size_override("font_size", 30)
	v.add_child(_info_title)
	_info_stars = HBoxContainer.new()
	v.add_child(_info_stars)
	_info_desc = Label.new()
	_info_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_desc.custom_minimum_size = Vector2(760, 0)
	_info_desc.add_theme_font_size_override("font_size", 17)
	_info_desc.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	v.add_child(_info_desc)
	_info_mods = HBoxContainer.new()
	_info_mods.add_theme_constant_override("separation", 16)
	v.add_child(_info_mods)
	_start = ActionButton.make("play", Color(0.5, 1.0, 0.6), "출격!", _launch, Vector2(260, 220))
	_start.badge = "출격"
	h.add_child(_start)
	Profile.changed.connect(_refresh)
	# 처음엔 진행 중인 장/스테이지
	var cur := "1-1"
	for id in Story.all_ids():
		if Profile.stage_unlocked(id):
			cur = id
	_select_chapter(int(cur.split("-")[0]))
	_select_stage(cur)


func _select_chapter(n: int) -> void:
	if n > 1 and not Profile.stage_unlocked(Story.stage_id(n, 1)):
		return
	_chapter = n
	var t := Art.tex("ui/chapter_%d" % n)
	_bg.texture = t
	_select_stage(Story.stage_id(n, 1))


func _select_stage(id: String) -> void:
	_stage = id
	_refresh()


func _refresh() -> void:
	_coin_lbl.text = str(Profile.coins)
	for i in _chap_btns.size():
		var ch: Dictionary = Story.CHAPTERS[i]
		var open := i == 0 or Profile.stage_unlocked(Story.stage_id(i + 1, 1))
		_chap_btns[i].text = "%d장  %s\n★ %d / %d%s" % [ch["id"], ch["name"], Profile.chapter_stars(i + 1), ch["stages"].size() * 3, "" if open else "   (잠김)"]
		_chap_btns[i].disabled = not open
		_chap_btns[i].modulate = Color(1.2, 1.2, 1.2) if i + 1 == _chapter else Color(1, 1, 1)
	_map.set("chapter", _chapter)
	_map.set("selected", _stage)
	_map.queue_redraw()
	# 상자
	for c in _chest_row.get_children():
		c.queue_free()
	for k in Story.CHEST_STEPS.size():
		var step: Array = Story.CHEST_STEPS[k]
		var kk := k
		var got: bool = Profile.chests.get("%d-%d" % [_chapter, k], false)
		var b := ActionButton.make("chest", Color.WHITE, "★%d 상자: 코인 %d + %s" % [step[0], step[1] * _chapter, GameData.shop_item(step[2])["name"]], func(): _claim(kk), Vector2(96, 64))
		b.badge = "받음" if got else "★%d" % step[0]
		b.disabled = not Profile.chest_claimable(_chapter, k)
		b.glow = Profile.chest_claimable(_chapter, k)
		_chest_row.add_child(b)
	# 정보
	var st := Story.get_stage(_stage)
	var d: Dictionary = st["data"]
	var boss := d.has("boss")
	_info_title.text = "%s  %s%s" % [_stage, d["name"], "  (보스)" if boss else ""]
	_info_title.add_theme_color_override("font_color", Color(1, 0.5, 0.5) if boss else Color(1, 0.9, 0.6))
	for c in _info_stars.get_children():
		c.queue_free()
	var got_stars := Profile.stage_stars(_stage)
	for k in 3:
		_info_stars.add_child(UIIcon.make("star", 34, Color(1, 0.85, 0.3) if k < got_stars else Color(0.28, 0.3, 0.38)))
	var hint := Label.new()
	hint.text = "  ★1 클리어  ★2 최대 적 30 미만  ★3 최대 적 15 미만 + 부활 없이"
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	_info_stars.add_child(hint)
	_info_desc.text = "%s\n%d 라운드%s" % [st["chapter"]["desc"], d["rounds"], "  ·  마지막 라운드에 %s 등장" % Story.BOSS_NAMES[d["boss"]] if boss else "  ·  끝까지 버티면 클리어"]
	for c in _info_mods.get_children():
		c.queue_free()
	for m in d.get("mods", []):
		var info: Dictionary = Story.MOD_INFO[m]
		var mh := HBoxContainer.new()
		mh.add_child(UIIcon.make(info["icon"], 28, Color(1, 0.7, 0.4)))
		var ml := Label.new()
		ml.text = "%s: %s" % [info["name"], info["desc"]]
		mh.add_child(ml)
		_info_mods.add_child(mh)
	_start.disabled = not Profile.stage_unlocked(_stage)
	_start.glow = not _start.disabled
	_start.queue_redraw()


func _claim(k: int) -> void:
	if Profile.claim_chest(_chapter, k):
		Sfx.play("win")


func _launch() -> void:
	start_stage(_stage, get_tree())


static func start_stage(id: String, tree: SceneTree) -> void:
	Session.setup_local("solo", [{"name": Session.player_name, "kind": "human", "keys": 0}])
	Session.stage = id
	if id == "1-1" and not Profile.tutorial_done:
		Session.tutorial = true
	tree.change_scene_to_file("res://scenes/Match.tscn")


class _StageMap:
	extends Control
	## 스테이지 노드를 곡선 길로 잇는 지도
	var chapter := 1
	var selected := ""
	var menu: Node
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _nodes() -> Array:
		var n: int = Story.CHAPTERS[chapter - 1]["stages"].size()
		var out: Array = []
		for i in n:
			var x := 110.0 + i * (size.x - 220.0) / maxf(1.0, n - 1)
			var y := 170.0 + (-60.0 if i % 2 == 0 else 60.0)
			out.append(Vector2(x, y))
		return out

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var nodes := _nodes()
			for i in nodes.size():
				if nodes[i].distance_to(event.position) < 60:
					menu._select_stage(Story.stage_id(chapter, i + 1))
					accept_event()
					return

	func _draw() -> void:
		var ch: Dictionary = Story.CHAPTERS[chapter - 1]
		var col: Color = ch["color"]
		var nodes := _nodes()
		var font := get_theme_font("font")
		for i in nodes.size() - 1:
			var a: Vector2 = nodes[i]
			var b: Vector2 = nodes[i + 1]
			var open := Profile.stage_unlocked(Story.stage_id(chapter, i + 2))
			var pts := PackedVector2Array()
			for k in 21:
				var q := k / 20.0
				pts.append(a.lerp(b, q) + Vector2(0, sin(q * PI) * -30))
			draw_polyline(pts, Color(col, 0.9) if open else Color(0.3, 0.32, 0.4), 6.0)
			if open:
				var dot := pts[int(fmod(_t * 8.0, 20.0))]
				draw_circle(dot, 5, Color(1, 1, 1, 0.8))
		for i in nodes.size():
			var id := Story.stage_id(chapter, i + 1)
			var d: Dictionary = ch["stages"][i]
			var p: Vector2 = nodes[i]
			var open := Profile.stage_unlocked(id)
			var boss := d.has("boss")
			var r := 54.0 if boss else 44.0
			if id == selected:
				draw_circle(p, r + 14 + 4 * sin(_t * 4.0), Color(1, 0.9, 0.5, 0.25))
			draw_circle(p, r, col.darkened(0.45) if open else Color(0.15, 0.16, 0.2))
			draw_arc(p, r, 0, TAU, 40, col if open else Color(0.35, 0.37, 0.45), 5.0)
			if boss:
				Glyphs.draw_unit_glyph(self, Story.CHARACTERS[["ogre", "lich", "golem", "eye", "lord"][d["boss"]]]["glyph"], p, r * 0.55, Color(1, 0.5, 0.5) if open else Color(0.4, 0.4, 0.45))
			elif open:
				var label := "%d" % (i + 1)
				var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34).x
				draw_string(font, p + Vector2(-w / 2, 12), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 34, Color.WHITE)
			if not open:
				Glyphs.draw(self, "lock", p, 18, Color(0.55, 0.57, 0.65))
			var stars := Profile.stage_stars(id)
			for k in 3:
				Glyphs.draw(self, "star", p + Vector2((k - 1) * 26, r + 22), 11, Color(1, 0.85, 0.3) if k < stars else Color(0.28, 0.3, 0.38))
			var nm: String = d["name"]
			var w2 := font.get_string_size(nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16).x
			draw_string(font, p + Vector2(-w2 / 2, -r - 12), nm, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.85, 0.88, 0.95) if open else Color(0.45, 0.47, 0.55))
