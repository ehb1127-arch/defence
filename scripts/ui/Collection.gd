extends Control
## 도감: 획득한 유닛 모아보기 + 코인으로 유닛 영구 레벨업 (레벨당 공격력 +5%, 대전 제외)

var _coin_lbl: Label
var _count_lbl: Label
var _icons := {}
var _sel := ""
var _big: UnitIcon
var _name: Label
var _info: Label
var _stars: HBoxContainer
var _up: ActionButton


func _ready() -> void:
	theme = GameData.ui_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.1)
	bg.size = Vector2(1600, 900)
	add_child(bg)
	var top := HBoxContainer.new()
	top.position = Vector2(30, 24)
	top.size = Vector2(1540, 70)
	top.add_theme_constant_override("separation", 14)
	add_child(top)
	top.add_child(ActionButton.make("back", Color(0.85, 0.9, 1.0), "뒤로", func(): get_tree().change_scene_to_file("res://scenes/Main.tscn"), Vector2(70, 64)))
	top.add_child(UIIcon.make("book", 50, Color(0.6, 0.8, 1.0)))
	var title := Label.new()
	title.text = "도감"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	top.add_child(title)
	_count_lbl = Label.new()
	_count_lbl.add_theme_font_size_override("font_size", 22)
	_count_lbl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	top.add_child(_count_lbl)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(UIIcon.make("coin", 44))
	_coin_lbl = Label.new()
	_coin_lbl.add_theme_font_size_override("font_size", 32)
	_coin_lbl.add_theme_color_override("font_color", Color(0.85, 0.72, 1.0))
	top.add_child(_coin_lbl)
	# 왼쪽: 등급별 줄
	var left := VBoxContainer.new()
	left.position = Vector2(30, 110)
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	for r in 5:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var tag := Label.new()
		tag.text = GameData.RARITY_NAMES[r]
		tag.custom_minimum_size = Vector2(60, 0)
		tag.add_theme_color_override("font_color", GameData.RARITY_COLORS[r])
		row.add_child(tag)
		for id in GameData.units_of_rarity(r):
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(130, 138)
			btn.focus_mode = Control.FOCUS_NONE
			var uid: String = id
			btn.pressed.connect(func(): _select(uid))
			var ic := UnitIcon.make(id, 118)
			ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			ic.position = Vector2(6, 2)
			btn.add_child(ic)
			var lv := Label.new()
			lv.position = Vector2(8, 110)
			lv.size = Vector2(114, 24)
			lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			lv.add_theme_font_size_override("font_size", 15)
			btn.add_child(lv)
			row.add_child(btn)
			_icons[id] = [ic, lv, btn]
		left.add_child(row)
	# 오른쪽: 상세
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.16)
	sb.set_corner_radius_all(16)
	sb.set_content_margin_all(20)
	p.add_theme_stylebox_override("panel", sb)
	p.position = Vector2(1030, 110)
	p.size = Vector2(540, 760)
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	_big = UnitIcon.make("", 240)
	_big.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(_big)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", 30)
	v.add_child(_name)
	_stars = HBoxContainer.new()
	_stars.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(_stars)
	_info = Label.new()
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info.custom_minimum_size = Vector2(500, 0)
	_info.add_theme_font_size_override("font_size", 17)
	_info.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	_info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_info)
	_up = ActionButton.make("upgrade", Color(0.45, 0.95, 0.6), "레벨 업", _level_up, Vector2(500, 90))
	_up.badge_icon = "coin"
	v.add_child(_up)
	Profile.changed.connect(_refresh)
	_select(GameData.UNIT_ORDER[0])


func _select(id: String) -> void:
	_sel = id
	_refresh()


func _refresh() -> void:
	_coin_lbl.text = str(Profile.coins)
	_count_lbl.text = "수집 %d / %d" % [Profile.discovered.size(), GameData.UNIT_ORDER.size()]
	for id in _icons:
		var found := Profile.discovered.has(id)
		var e: Array = _icons[id]
		e[0].set_unit(id, not found)
		e[1].text = ("Lv.%d" % Profile.unit_level(id)) if found else "미발견"
		e[1].add_theme_color_override("font_color", Color(1, 0.85, 0.4) if found else Color(0.45, 0.47, 0.55))
		e[2].modulate = Color(1.25, 1.25, 1.25) if id == _sel else Color(1, 1, 1)
	var u: Dictionary = GameData.UNITS[_sel]
	var found := Profile.discovered.has(_sel)
	var lvl := Profile.unit_level(_sel)
	_big.set_unit(_sel, not found)
	_name.text = u["name"] if found else "???"
	_name.add_theme_color_override("font_color", GameData.RARITY_COLORS[u["rarity"]])
	for c in _stars.get_children():
		c.queue_free()
	for k in GameData.UNIT_MAX_LEVEL:
		_stars.add_child(UIIcon.make("star", 32, Color(1, 0.85, 0.3) if k < lvl else Color(0.28, 0.3, 0.38)))
	var lines: Array = ["[%s]  %s" % [GameData.RARITY_NAMES[u["rarity"]], u["desc"]]]
	var mult := 1.0 + GameData.UNIT_LEVEL_BONUS * lvl
	lines.append("공격력 %d → %d (도감 보너스 +%d%%)" % [int(u["dmg"]), int(u["dmg"] * mult), int(round((mult - 1.0) * 100))])
	lines.append("공격 간격 %.2f초 · 사거리 %d" % [u["cd"], int(u["range"])])
	var uses: Array = []
	for m in GameData.RECIPES:
		if _sel in GameData.RECIPES[m]:
			uses.append(GameData.UNITS[m]["name"])
	if not uses.is_empty():
		lines.append("신화 재료: " + ", ".join(uses))
	if u["rarity"] == 4:
		lines.append("조합식: " + GameData.recipe_text(_sel))
	if not found:
		lines = ["아직 만나지 못한 유닛입니다.", "게임에서 한 번 얻으면 도감에 등록되고 레벨업할 수 있어요."]
	lines.append("\n도감 레벨은 솔로·협동에 적용됩니다 (대전 제외).")
	_info.text = "\n".join(lines)
	var maxed := lvl >= GameData.UNIT_MAX_LEVEL
	var cost := GameData.unit_level_cost(_sel, lvl)
	_up.badge = "MAX" if maxed else str(cost)
	_up.disabled = not found or maxed or Profile.coins < cost
	_up.glow = not _up.disabled
	_up.queue_redraw()


func _level_up() -> void:
	if Profile.level_up_unit(_sel):
		Sfx.play("rare")
