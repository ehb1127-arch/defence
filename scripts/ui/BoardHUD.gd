class_name BoardHUD
extends PanelContainer
## 전장 하나에 붙는 조작 패널 (소환/합성/도박/강화/조합/대전·협동/과제).

var board: Board
var interactive := true
var keys_hint := ""

var _lbl_head: RichTextLabel
var _btn_summon: Button
var _btn_merge: Button
var _btn_gambles: Array = []
var _lbl_sel: Label
var _lbl_probs: Label
var _btn_sel_merge: Button
var _btn_sel_sell: Button
var _btn_sel_gift: Button
var _upg_btns: Array = []
var _recipe_rows: Array = []
var _attack_btns: Array = []
var _btn_gift_gold: Button
var _btn_blast: Button
var _blast_bar: ProgressBar
var _mission_list: VBoxContainer
var _t := 0.0


func setup(b: Board, p_interactive: bool, p_keys_hint: String, tall := false) -> void:
	board = b
	interactive = p_interactive
	keys_hint = p_keys_hint
	theme = GameData.ui_theme()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.11, 0.15, 0.95)
	sb.border_color = b.accent.darkened(0.2)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(8)
	add_theme_stylebox_override("panel", sb)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)

	_lbl_head = RichTextLabel.new()
	_lbl_head.bbcode_enabled = true
	_lbl_head.fit_content = true
	_lbl_head.scroll_active = false
	_lbl_head.custom_minimum_size = Vector2(0, 26)
	_lbl_head.add_theme_font_size_override("normal_font_size", 16)
	root.add_child(_lbl_head)

	if not interactive:
		var l := Label.new()
		l.text = "원격 플레이어의 전장입니다." if b.is_remote else "AI가 플레이 중입니다."
		l.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
		root.add_child(l)
		return

	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(tabs)
	tabs.add_child(_build_action_tab())
	tabs.add_child(_build_upgrade_tab())
	if b.mode == "pvp":
		tabs.add_child(_build_pvp_tab())
	elif b.mode == "coop":
		tabs.add_child(_build_coop_tab())
	if tall:
		# 세로로 긴 패널(솔로)은 조합표와 과제를 항상 펼쳐서 보여준다
		tabs.size_flags_vertical = Control.SIZE_FILL
		tabs.custom_minimum_size = Vector2(0, 230)
		for section in [["신화 조합표", _build_recipe_tab()], ["도전 과제", _build_mission_tab()]]:
			var h := Label.new()
			h.text = section[0]
			h.add_theme_font_size_override("font_size", 18)
			h.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
			root.add_child(h)
			var body: Control = section[1]
			body.size_flags_vertical = Control.SIZE_EXPAND_FILL
			root.add_child(body)
	else:
		tabs.add_child(_build_recipe_tab())
		tabs.add_child(_build_mission_tab())
	if keys_hint != "":
		var hint := Label.new()
		hint.text = keys_hint
		hint.add_theme_font_size_override("font_size", 11)
		hint.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		root.add_child(hint)


func _btn(text: String, cb: Callable, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(min_w, 44)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _build_action_tab() -> Control:
	var v := VBoxContainer.new()
	v.name = "행동"
	var g := GridContainer.new()
	g.columns = 4
	v.add_child(g)
	_btn_summon = _btn("소환", func(): board.summon())
	_btn_summon.add_theme_color_override("font_color", Color(0.6, 1.0, 0.6))
	g.add_child(_btn_summon)
	_btn_merge = _btn("자동 합성", func(): board.auto_merge())
	g.add_child(_btn_merge)
	for i in GameData.GAMBLES.size():
		var gi := i
		var b := _btn("", func(): board.gamble(gi))
		_btn_gambles.append(b)
		g.add_child(b)
	_lbl_probs = Label.new()
	_lbl_probs.add_theme_font_size_override("font_size", 13)
	_lbl_probs.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	v.add_child(_lbl_probs)
	var sel := HBoxContainer.new()
	v.add_child(sel)
	_lbl_sel = Label.new()
	_lbl_sel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_sel.clip_text = true
	sel.add_child(_lbl_sel)
	_btn_sel_merge = _btn("합성", func(): board.merge_cell(board.selected), 70)
	_btn_sel_merge.size_flags_horizontal = Control.SIZE_SHRINK_END
	sel.add_child(_btn_sel_merge)
	_btn_sel_sell = _btn("판매", func(): board.sell_one(board.selected), 70)
	_btn_sel_sell.size_flags_horizontal = Control.SIZE_SHRINK_END
	sel.add_child(_btn_sel_sell)
	if board.mode == "coop":
		_btn_sel_gift = _btn("선물", func(): board.request_gift_unit(board.selected), 70)
		_btn_sel_gift.size_flags_horizontal = Control.SIZE_SHRINK_END
		sel.add_child(_btn_sel_gift)
	return v


func _build_upgrade_tab() -> Control:
	var g := GridContainer.new()
	g.name = "강화"
	g.columns = 2
	for i in GameData.UPGRADES.size():
		var ti := i
		var b := _btn("", func(): board.upgrade(ti))
		_upg_btns.append(b)
		g.add_child(b)
	return g


func _build_recipe_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "신화 조합"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)
	for m in GameData.RECIPES:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 13)
		l.clip_text = true
		row.add_child(l)
		var mm: String = m
		var b := _btn("조합", func(): board.combine(mm), 70)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		b.custom_minimum_size = Vector2(70, 30)
		row.add_child(b)
		v.add_child(row)
		_recipe_rows.append([m, l, b])
	return scroll


func _build_pvp_tab() -> Control:
	var v := VBoxContainer.new()
	v.name = "공격"
	var g := GridContainer.new()
	g.columns = 3
	v.add_child(g)
	for a in GameData.ATTACKS:
		var aid: String = a["id"]
		var b := _btn("", func(): board.request_attack(aid))
		b.add_theme_color_override("font_color", Color(1.0, 0.6, 0.5))
		_attack_btns.append([a, b])
		g.add_child(b)
	var l := Label.new()
	l.text = "상대 전장으로 적을 보내거나 저주를 겁니다. 상대가 먼저 한도에 닿으면 승리!"
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	v.add_child(l)
	return v


func _build_coop_tab() -> Control:
	var v := VBoxContainer.new()
	v.name = "협동"
	var h := HBoxContainer.new()
	v.add_child(h)
	_btn_gift_gold = _btn("골드 100 선물", func(): board.request_gift_gold(100))
	h.add_child(_btn_gift_gold)
	_btn_blast = _btn("합동 폭격", func(): board.request_blast())
	_btn_blast.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	h.add_child(_btn_blast)
	_blast_bar = ProgressBar.new()
	_blast_bar.max_value = GameData.COOP_BLAST_NEED
	_blast_bar.custom_minimum_size = Vector2(0, 16)
	_blast_bar.show_percentage = false
	v.add_child(_blast_bar)
	var l := Label.new()
	l.text = "처치할수록 폭격 게이지가 찹니다. 폭격은 두 전장 모두를 강타! 유닛 선물은 [행동] 탭에서 칸 선택 후."
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 12)
	v.add_child(l)
	return v


func _build_mission_tab() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "과제"
	_mission_list = VBoxContainer.new()
	scroll.add_child(_mission_list)
	for m in GameData.MISSIONS:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 13)
		l.set_meta("mid", m["id"])
		_mission_list.add_child(l)
	return scroll


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or board == null:
		return
	_t = 0.12
	_refresh()


func _refresh() -> void:
	var b := board
	_lbl_head.text = "[b][color=#%s]%s[/color][/b]   [color=#ffd84d]골드 %d[/color]   [color=#8fd8ff]보석 %d[/color]   처치 %d   소환 비용 %d" % [
		b.accent.lightened(0.3).to_html(false), b.player_name, b.gold, b.gems, b.kills,
		b.summon_cost() if not b.is_remote else int(b.remote_stats.get("sc", 0))]
	if not interactive:
		return
	var ok := b.alive
	_btn_summon.text = "소환 (%s)" % ("무료 x%d" % b.free_summons if b.free_summons > 0 else "%dG" % b.summon_cost())
	_btn_summon.disabled = not ok or (b.free_summons <= 0 and b.gold < b.summon_cost())
	var any_merge := false
	for i in b.cells.size():
		if b.mergeable(i):
			any_merge = true
			break
	_btn_merge.disabled = not ok or not any_merge
	for i in _btn_gambles.size():
		var g: Dictionary = GameData.GAMBLES[i]
		_btn_gambles[i].text = "%s (%d보석 %d%%)" % [g["name"], g["gems"], int(g["chance"] * 100)]
		_btn_gambles[i].disabled = not ok or b.gems < g["gems"]
	var probs := GameData.summon_probs(b.upgrades[3])
	var ps: Array = []
	for i in probs.size():
		ps.append("%s %.1f%%" % [GameData.RARITY_NAMES[i], probs[i] * 100.0])
	_lbl_probs.text = "소환 확률: " + "  ".join(ps)
	# 선택 칸
	var sel := b.selected
	var has_sel: bool = sel >= 0 and b.cells[sel]["id"] != ""
	if has_sel:
		var u: Dictionary = GameData.UNITS[b.cells[sel]["id"]]
		_lbl_sel.text = "[%s] %s x%d - %s" % [GameData.RARITY_NAMES[u["rarity"]], u["name"], b.cells[sel]["n"], u["desc"]]
		_lbl_sel.add_theme_color_override("font_color", GameData.RARITY_COLORS[u["rarity"]])
	else:
		_lbl_sel.text = "칸을 클릭해 선택 → 다른 칸 클릭으로 이동/교체"
		_lbl_sel.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	_btn_sel_merge.disabled = not ok or not has_sel or not b.mergeable(sel)
	_btn_sel_sell.disabled = not ok or not has_sel
	if _btn_sel_gift:
		_btn_sel_gift.disabled = not ok or not has_sel
	# 강화
	for i in _upg_btns.size():
		var u: Dictionary = GameData.UPGRADES[i]
		var cost := GameData.upgrade_cost(i, b.upgrades[i])
		var maxed: bool = b.upgrades[i] >= (GameData.MAX_LUCK if i == 3 else GameData.MAX_UPGRADE)
		var cur := "보석" if u["cur"] == "gems" else "G"
		var effect := ("피해 +%d%%" % int(GameData.UPGRADE_DMG_PER_LEVEL * 100 * b.upgrades[i])) if i < 3 else "고등급 확률 UP"
		_upg_btns[i].text = "%s Lv.%d (%s)  %s" % [u["name"], b.upgrades[i], effect, "MAX" if maxed else "%d%s" % [cost, cur]]
		_upg_btns[i].disabled = not ok or not b.can_afford_upgrade(i)
	# 조합
	for row in _recipe_rows:
		var m: String = row[0]
		var prog := b.recipe_progress(m)
		var can := b.can_combine(m)
		row[1].text = "%s [%d/%d]  %s" % [GameData.UNITS[m]["name"], prog[0], prog[1], GameData.recipe_text(m)]
		row[1].tooltip_text = GameData.UNITS[m]["desc"]
		row[1].add_theme_color_override("font_color", GameData.RARITY_COLORS[4] if can else Color(0.8, 0.8, 0.85))
		row[2].disabled = not ok or not can
	# 대전
	for pair in _attack_btns:
		var a: Dictionary = pair[0]
		var cost_s := ("%dG" % a["gold"]) if a["gold"] > 0 else ("%d보석" % a["gems"])
		pair[1].text = "%s (%s)" % [a["name"], cost_s]
		pair[1].tooltip_text = a["desc"]
		pair[1].disabled = not ok or b.gold < a["gold"] or b.gems < a["gems"]
	# 협동
	if _btn_gift_gold:
		_btn_gift_gold.disabled = not ok or b.gold < 100
		_blast_bar.value = b.gauge
		_btn_blast.disabled = not ok or b.gauge < GameData.COOP_BLAST_NEED
		_btn_blast.text = "합동 폭격 (%d/%d)" % [b.gauge, GameData.COOP_BLAST_NEED]
	# 과제
	if _mission_list:
		for l in _mission_list.get_children():
			var mid: String = l.get_meta("mid")
			for m in GameData.MISSIONS:
				if m["id"] == mid:
					var done := b.missions.has(mid)
					l.text = "%s %s - %s" % ["[완료]" if done else "[  ]", m["name"], m["desc"]]
					l.add_theme_color_override("font_color", Color(0.5, 1.0, 0.6) if done else Color(0.8, 0.8, 0.85))
