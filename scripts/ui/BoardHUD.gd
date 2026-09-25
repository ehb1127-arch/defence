class_name BoardHUD
extends PanelContainer
## 전장 하나의 조작 패널. 아이콘 중심(이미지로 교체 가능), 글자는 숫자와 이름 정도만.
##  - 자원 칩 (골드 / 보석)
##  - 행동 버튼 줄: 소환 · 합성 · 도박 · 강화 · 조합 · 공격(대전)/협동 · 과제 · 광고
##  - 선택 유닛 카드: 초상화, 능력치 아이콘, 합성/판매/선물
##  - 도박/강화/조합/공격/협동/과제는 전장 위에 카드형 시트로 열림

signal ad_summon_requested(hud)
signal emote_requested(hud, emote)

var board: Board
var interactive := true
var keys_hint := ""
var tall := false
var sheet_parent: Node          # 시트를 띄울 레이어 (Match 가 지정)
var sheet_rect := Rect2()       # 시트를 띄울 화면 영역 (보통 전장 위)
var ad_available := false       # 이 판에서 광고 무료 소환 가능 여부
var emotes_enabled := false     # 온라인: 이모티콘 버튼

var _chip_gold: Label
var _chip_gems: Label
var _chip_extra: Label
var _btn := {}                   # 이름 -> ActionButton
var _sel_icon: UnitIcon
var _sel_name: Label
var _sel_stats: Label
var _sel_merge: ActionButton
var _sel_sell: ActionButton
var _sel_gift: ActionButton
var _sel_up: ActionButton
var _syn_row: HBoxContainer
var _syn_items := {}
var _recipe_rows: Array = []     # [mythic, [UnitIcon...], UnitIcon(result), ActionButton]
var _sheet: PanelContainer
var _sheet_kind := ""
var _sheet_refresh: Callable
var _info_rarity: Array = []
var _info_myth: Array = []
var _t := 0.0


func setup(b: Board, p_interactive: bool, p_keys_hint: String, p_tall := false) -> void:
	board = b
	interactive = p_interactive
	keys_hint = p_keys_hint
	tall = p_tall
	theme = GameData.ui_theme()
	var sb: StyleBox = Art.stylebox("hud_panel")
	if sb == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.09, 0.1, 0.14, 0.97)
		f.border_color = b.accent.darkened(0.25)
		f.set_border_width_all(2)
		f.set_corner_radius_all(10)
		f.set_content_margin_all(10 if tall else 8)
		sb = f
	add_theme_stylebox_override("panel", sb)
	if not interactive:
		_build_readonly()
	elif tall:
		_build_tall()
	else:
		_build_compact()


# ===========================================================================
# 구성
# ===========================================================================
func _chips(big: bool) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 18)
	var fs := 26 if big else 20
	var isz := 34.0 if big else 26.0
	for spec in [["gold", Color(1, 0.85, 0.3)], ["gem", Color(0.55, 0.85, 1.0)]]:
		var chip := HBoxContainer.new()
		chip.add_theme_constant_override("separation", 4)
		chip.add_child(UIIcon.make(spec[0], isz))
		var l := Label.new()
		l.add_theme_font_size_override("font_size", fs)
		l.add_theme_color_override("font_color", spec[1])
		l.add_theme_color_override("font_outline_color", Color.BLACK)
		l.add_theme_constant_override("outline_size", 4)
		chip.add_child(l)
		h.add_child(chip)
		if spec[0] == "gold":
			_chip_gold = l
		else:
			_chip_gems = l
	_chip_extra = Label.new()
	_chip_extra.add_theme_font_size_override("font_size", 14)
	_chip_extra.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	_chip_extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chip_extra.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	h.add_child(_chip_extra)
	return h


func _synergy_row(isz: float) -> HBoxContainer:
	_syn_row = HBoxContainer.new()
	_syn_row.add_theme_constant_override("separation", 6)
	for tag in GameData.SYNERGY_ORDER:
		var d: Dictionary = GameData.SYNERGIES[tag]
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 1)
		box.mouse_filter = Control.MOUSE_FILTER_PASS
		var tiers: Array = []
		for t in d["tiers"]:
			tiers.append("%d종: %s" % [t[0], d["desc"] % int(t[1] * 100 if tag != "lightning" else t[1])])
		box.tooltip_text = "%s 시너지\n%s" % [d["name"], "\n".join(tiers)]
		var ic := UIIcon.make(d["icon"], isz, d["color"])
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		ic.tooltip_text = box.tooltip_text
		box.add_child(ic)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", int(isz * 0.55))
		box.add_child(l)
		_syn_row.add_child(box)
		_syn_items[tag] = [ic, l, box]
	return _syn_row


func _refresh_synergy() -> void:
	if _syn_row == null:
		return
	for tag in _syn_items:
		var e: Array = _syn_items[tag]
		var n: int = board.syn_counts.get(tag, 0)
		var on: bool = board.syn.get(tag, 0.0) > 0.0
		var need: int = GameData.SYNERGIES[tag]["tiers"][0][0]
		for t in GameData.SYNERGIES[tag]["tiers"]:
			if n >= t[0]:
				continue
			need = t[0]
			break
		e[1].text = "%d/%d" % [n, need] if n < GameData.SYNERGIES[tag]["tiers"][-1][0] else "MAX"
		e[1].add_theme_color_override("font_color", GameData.SYNERGIES[tag]["color"] if on else Color(0.45, 0.47, 0.55))
		e[2].modulate = Color(1, 1, 1, 1.0 if on or n > 0 else 0.45)
		e[0].color = GameData.SYNERGIES[tag]["color"] if on else Color(0.4, 0.42, 0.5)
		e[0].queue_redraw()


func _action_buttons(sz: Vector2) -> Array:
	var list: Array = []
	var add := func(key: String, icon: String, col: Color, tip: String, cb: Callable):
		var ab := ActionButton.make(icon, col.lightened(0.45), tip, cb, sz)
		# 모바일 게임식 색 버튼: 버튼마다 고유 색 (소환/합성은 더 진하게 강조)
		ab.tone = col.darkened(0.25 if key in ["summon", "merge"] else 0.42)
		ab.radius = 16
		_btn[key] = ab
		list.append(ab)
	add.call("summon", "summon", Color(0.45, 0.9, 0.5), "소환 (Q)\n골드로 무작위 유닛 소환", func(): board.summon())
	_btn["summon"].badge_icon = "gold"
	add.call("merge", "merge", Color(1, 0.85, 0.4), "자동 합성 (E)\n같은 유닛 3마리 → 상위 등급", func(): board.auto_merge())
	add.call("gamble", "gamble", Color(0.75, 0.45, 1.0), "도박\n보석으로 영웅/전설 뽑기", func(): _toggle_sheet("gamble"))
	add.call("slot", "slot", Color(1, 0.35, 0.45), "럭키 슬롯\n골드를 걸고 한 판!", func(): _toggle_sheet("slot"))
	add.call("upgrade", "upgrade", Color(0.45, 0.95, 0.6), "강화\n등급별 공격력 / 소환 행운", func(): _toggle_sheet("upgrade"))
	add.call("recipe", "recipe", Color(1, 0.35, 0.4), "신화 조합표", func(): _toggle_sheet("recipe"))
	if board.mode == "pvp":
		add.call("special", "attack", Color(1, 0.5, 0.4), "공격\n상대에게 적/저주 보내기", func(): _toggle_sheet("attack"))
	elif board.mode == "coop":
		add.call("special", "gift", Color(0.5, 0.95, 0.8), "협동\n골드 선물 / 합동 폭격", func(): _toggle_sheet("coop"))
	add.call("mission", "mission", Color(0.5, 1.0, 0.6), "도전 과제 / 조작법", func(): _toggle_sheet("mission"))
	if emotes_enabled:
		add.call("emote", "emote", Color(1, 0.8, 0.2), "이모티콘", func(): _toggle_sheet("emote"))
	if ad_available:
		add.call("ad", "ad", Color(0.35, 0.6, 1.0), "광고 보고 무료 소환 3회 (판당 1회)", func(): ad_summon_requested.emit(self))
		_btn["ad"].badge_icon = ""
	return list


func _selected_card(portrait: float) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_sel_icon = UnitIcon.make("", portrait)
	h.add_child(_sel_icon)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 0)
	h.add_child(v)
	_sel_name = Label.new()
	_sel_name.add_theme_font_size_override("font_size", 18 if tall else 15)
	_sel_name.clip_text = true
	v.add_child(_sel_name)
	_sel_stats = Label.new()
	_sel_stats.add_theme_font_size_override("font_size", 14 if tall else 12)
	_sel_stats.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	if tall:
		_sel_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		_sel_stats.clip_text = true
	v.add_child(_sel_stats)
	var bsz := Vector2(56, 56) if tall else Vector2(52, 42)
	_sel_up = ActionButton.make("hammer", Color(1, 0.8, 0.4), "★ 강화 시도\n성공하면 공격력·공속 상승, ★3 각성\n높은 ★에서 실패하면 하락 위험", func(): board.enhance_try(board.selected), bsz * Vector2(1.5, 1))
	_sel_up.badge_icon = "gold"
	h.add_child(_sel_up)
	_sel_merge = ActionButton.make("merge", Color(1, 0.85, 0.4), "이 칸 합성", func(): board.merge_cell(board.selected), bsz)
	h.add_child(_sel_merge)
	_sel_sell = ActionButton.make("sell", Color(1, 0.85, 0.3), "1마리 판매 (X)", func(): board.sell_one(board.selected), bsz)
	h.add_child(_sel_sell)
	if board.mode == "coop":
		_sel_gift = ActionButton.make("gift", Color(0.5, 0.95, 0.8), "파트너에게 1마리 선물", func(): board.request_gift_unit(board.selected), bsz)
		h.add_child(_sel_gift)
	return h


func _build_compact() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 4)
	add_child(root)
	var top := _chips(false)
	_chip_extra.visible = false
	top.add_child(_synergy_row(22))
	root.add_child(top)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	root.add_child(row)
	for ab in _action_buttons(Vector2(56, 70)):
		ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(ab)
	var card := _selected_card(42)
	root.add_child(card)


func _build_tall() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	add_child(root)
	root.add_child(_chips(true))
	root.add_child(_synergy_row(30))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	root.add_child(grid)
	for ab in _action_buttons(Vector2(174, 84)):
		ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(ab)
	var card_panel := PanelContainer.new()
	card_panel.add_theme_stylebox_override("panel", _inner_box())
	card_panel.add_child(_selected_card(84))
	root.add_child(card_panel)
	# 신화 조합표 상시 표시 (재료 그림 나열)
	var head := HBoxContainer.new()
	head.add_child(UIIcon.make("recipe", 26, Color(1, 0.35, 0.4)))
	var hl := Label.new()
	hl.text = "신화 조합"
	hl.add_theme_font_size_override("font_size", 18)
	hl.add_theme_color_override("font_color", Color(1, 0.6, 0.6))
	head.add_child(hl)
	root.add_child(head)
	var rp := PanelContainer.new()
	rp.add_theme_stylebox_override("panel", _inner_box())
	rp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rp.add_child(_recipe_list(52, _recipe_rows))
	root.add_child(rp)


func _build_readonly() -> void:
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 6)
	add_child(root)
	root.add_child(_chips(false))
	root.add_child(_synergy_row(22))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	root.add_child(row)
	for r in 5:
		var chip := HBoxContainer.new()
		var ic := UIIcon.make("star", 24, GameData.RARITY_COLORS[r])
		ic.tooltip_text = GameData.RARITY_NAMES[r]
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_child(ic)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 18)
		l.add_theme_color_override("font_color", GameData.RARITY_COLORS[r])
		chip.add_child(l)
		row.add_child(chip)
		_info_rarity.append(l)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 10)
	root.add_child(mrow)
	for m in GameData.RECIPES:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var ic := UnitIcon.make(m, 56)
		v.add_child(ic)
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 13)
		v.add_child(l)
		mrow.add_child(v)
		_info_myth.append([m, ic, l])


func _inner_box() -> StyleBox:
	var sb: StyleBox = Art.stylebox("hud_inner")
	if sb != null:
		return sb
	var f := StyleBoxFlat.new()
	f.bg_color = Color(0.13, 0.14, 0.19)
	f.set_corner_radius_all(8)
	f.set_content_margin_all(8)
	return f


func _recipe_list(icon_sz: float, out: Array) -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	for m in GameData.RECIPES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 2)
		var icons: Array = []
		for ing in GameData.RECIPES[m]:
			var ic := UnitIcon.make(ing, icon_sz)
			row.add_child(ic)
			icons.append(ic)
		var arrow := UIIcon.make("play", icon_sz * 0.45, Color(0.6, 0.65, 0.75))
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(arrow)
		var res := UnitIcon.make(m, icon_sz * 1.2)
		row.add_child(res)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(spacer)
		var mm: String = m
		var btn := ActionButton.make("check", Color(1, 0.4, 0.45), "%s 조합 (T)\n%s" % [GameData.UNITS[m]["name"], GameData.UNITS[m]["desc"]], func(): board.combine(mm), Vector2(icon_sz * 1.3, icon_sz))
		row.add_child(btn)
		v.add_child(row)
		out.append([m, icons, res, btn])
	return v


# ===========================================================================
# 시트 (전장 위 카드 팝업)
# ===========================================================================
func close_sheet() -> void:
	if _sheet != null:
		_sheet.queue_free()
		_sheet = null
	_sheet_kind = ""
	_sheet_refresh = Callable()
	for k in _btn:
		_btn[k].selected = false
		_btn[k].queue_redraw()


func _toggle_sheet(kind: String) -> void:
	var same := _sheet_kind == kind
	close_sheet()
	if same or sheet_parent == null:
		return
	_sheet_kind = kind
	var key: String = {"emote": "emote", "slot": "slot", "gamble": "gamble", "upgrade": "upgrade", "recipe": "recipe", "attack": "special", "coop": "special", "mission": "mission"}[kind]
	if _btn.has(key):
		_btn[key].selected = true
	_sheet = PanelContainer.new()
	_sheet.theme = GameData.ui_theme()
	var sb: StyleBox = Art.stylebox("sheet_panel")
	if sb == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.06, 0.07, 0.1, 0.96)
		f.border_color = board.accent
		f.set_border_width_all(2)
		f.set_corner_radius_all(14)
		f.set_content_margin_all(16)
		f.shadow_color = Color(0, 0, 0, 0.5)
		f.shadow_size = 12
		sb = f
	_sheet.add_theme_stylebox_override("panel", sb)
	var w := minf(sheet_rect.size.x - 20, 720)
	_sheet.position = sheet_rect.position + Vector2((sheet_rect.size.x - w) / 2, 60)
	_sheet.size = Vector2(w, 0)
	sheet_parent.add_child(_sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_sheet.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var info: Array = {
		"slot": ["slot", "럭키 슬롯", Color(1, 0.35, 0.45)],
		"emote": ["emote", "이모티콘", Color(1, 0.8, 0.2)],
		"gamble": ["gamble", "도박", Color(0.75, 0.45, 1.0)], "upgrade": ["upgrade", "강화", Color(0.45, 0.95, 0.6)],
		"recipe": ["recipe", "신화 조합", Color(1, 0.35, 0.4)], "attack": ["attack", "공격", Color(1, 0.5, 0.4)],
		"coop": ["gift", "협동", Color(0.5, 0.95, 0.8)], "mission": ["mission", "도전 과제", Color(0.5, 1.0, 0.6)],
	}[kind]
	head.add_child(UIIcon.make(info[0], 34, info[2]))
	var tl := Label.new()
	tl.text = info[1]
	tl.add_theme_font_size_override("font_size", 22)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	head.add_child(ActionButton.make("close", Color(0.85, 0.85, 0.9), "닫기 (Esc)", close_sheet, Vector2(44, 44)))
	match kind:
		"slot":
			_slot_sheet(v)
		"emote":
			var cards: Array = []
			for spec in [["emote", Color(1, 0.8, 0.2)], ["heart", Color(1, 0.35, 0.45)], ["star", Color(1, 0.8, 0.2)], ["skull", Color(0.6, 0.6, 0.65)], ["attack", Color(0.9, 0.3, 0.3)], ["gift", Color(0.3, 0.8, 0.6)]]:
				var em: String = spec[0]
				var send := func():
					emote_requested.emit(self, em)
					close_sheet()
				var c := _card(em, spec[1], "", "보내기", send)
				c[1].custom_minimum_size = Vector2(80, 80)
				c[2].visible = false
				cards.append(c)
			_sheet_cards(v, cards)
		"gamble":
			_sheet_cards(v, _gamble_cards())
		"upgrade":
			_sheet_cards(v, _upgrade_cards())
		"attack":
			_sheet_cards(v, _attack_cards())
		"coop":
			_sheet_cards(v, _coop_cards())
		"recipe":
			var rows: Array = []
			v.add_child(_recipe_list(56, rows))
			_sheet_refresh = func(): _refresh_recipes(rows)
		"mission":
			_mission_sheet(v)
	if _sheet_refresh.is_valid():
		_sheet_refresh.call()


func _card(icon: String, col: Color, title: String, tip: String, cb: Callable) -> Array:
	## [VBox, ActionButton, Label]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var ab := ActionButton.make(icon, col, tip, cb, Vector2(118, 118))
	box.add_child(ab)
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 14)
	l.custom_minimum_size = Vector2(118, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return [box, ab, l]


func _sheet_cards(v: VBoxContainer, cards: Array) -> void:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	for c in cards:
		h.add_child(c[0])


func _slot_sheet(v: VBoxContainer) -> void:
	var reels := SlotReels.new()
	reels.board = board
	reels.custom_minimum_size = Vector2(0, 150)
	v.add_child(reels)
	var result := Label.new()
	result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result.add_theme_font_size_override("font_size", 22)
	v.add_child(result)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var bets: Array = []
	for i in GameData.SLOT_BETS.size():
		var bi := i
		var b := ActionButton.make("slot", Color(1, 0.35, 0.45) if i == 0 else Color(1, 0.75, 0.2), ["한 판", "크게 한 판"][i] + "\n세 개가 같으면 잭팟!", func(): board.slot_spin(bi), Vector2(170, 90))
		b.badge_icon = "gold"
		h.add_child(b)
		bets.append(b)
	var pay := Label.new()
	pay.text = "골드x3 = 8배   보석x3 · 소환x3 · 별x3 = 특별 보상   두 개 = 1.5배"
	pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pay.add_theme_font_size_override("font_size", 13)
	pay.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	v.add_child(pay)
	_sheet_refresh = func():
		var spinning := not board.pending_slot.is_empty()
		for i in bets.size():
			var bet := board.slot_bet(i)
			bets[i].set_state(str(bet), not board.alive or spinning or board.gold < bet, not spinning and board.gold >= bet * 3)
		if spinning:
			result.text = "두근두근..."
			result.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
		elif not board.last_slot.is_empty():
			result.text = board.last_slot["text"]
			result.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if board.last_slot["win"] > 0 else Color(0.65, 0.65, 0.7))
		else:
			result.text = "골드를 걸고 레버를 당기세요"


func _gamble_cards() -> Array:
	var cards: Array = []
	for i in GameData.GAMBLES.size():
		var g: Dictionary = GameData.GAMBLES[i]
		var gi := i
		var c := _card("gamble", GameData.RARITY_COLORS[g["rarity"]], "%s %d%%" % [GameData.RARITY_NAMES[g["rarity"]], int((g["chance"] + board.bonus_gamble) * 100)],
			"%s\n성공 시 %s 유닛 획득" % [g["name"], GameData.RARITY_NAMES[g["rarity"]]], func(): board.gamble(gi))
		c[1].badge_icon = "gem"
		c[1].badge = str(g["gems"])
		cards.append(c)
	_sheet_refresh = func():
		for i in cards.size():
			cards[i][1].set_state(str(GameData.GAMBLES[i]["gems"]), not board.alive or board.gems < GameData.GAMBLES[i]["gems"], board.gems >= GameData.GAMBLES[i]["gems"])
	return cards


func _upgrade_cards() -> Array:
	var cards: Array = []
	var cols := [Color(0.85, 0.85, 0.9), Color(0.75, 0.45, 1.0), Color(1, 0.65, 0.2), Color(0.45, 0.95, 0.5)]
	for i in GameData.UPGRADES.size():
		var u: Dictionary = GameData.UPGRADES[i]
		var ti := i
		var c := _card("upgrade" if i < 3 else "luck", cols[i], "", "%s 강화" % u["name"], func(): board.upgrade(ti))
		c[1].badge_icon = "gem" if u["cur"] == "gems" else "gold"
		cards.append(c)
	_sheet_refresh = func():
		for i in cards.size():
			var lvl: int = board.upgrades[i]
			var maxed: bool = lvl >= (GameData.MAX_LUCK if i == 3 else GameData.MAX_UPGRADE)
			var eff := ("+%d%%" % int(GameData.UPGRADE_DMG_PER_LEVEL * 100 * lvl)) if i < 3 else ""
			cards[i][2].text = "%s\nLv.%d %s" % [GameData.UPGRADES[i]["name"], lvl, eff]
			cards[i][1].set_state("MAX" if maxed else str(GameData.upgrade_cost(i, lvl)), not board.alive or not board.can_afford_upgrade(i), false)
	return cards


func _attack_cards() -> Array:
	var cards: Array = []
	var cols := {"swarm": Color(1, 0.75, 0.2), "elite": Color(0.9, 0.2, 0.2), "curse": Color(0.65, 0.35, 1.0)}
	for a in GameData.ATTACKS:
		var aid: String = a["id"]
		var c := _card(aid, cols[aid], a["name"], "%s\n%s" % [a["name"], a["desc"]], func(): board.request_attack(aid))
		c[1].badge_icon = "gold" if a["gold"] > 0 else "gem"
		c[1].badge = str(a["gold"] if a["gold"] > 0 else a["gems"])
		cards.append([c[0], c[1], c[2], a])
	_sheet_refresh = func():
		for c in cards:
			var a: Dictionary = c[3]
			c[1].set_state(c[1].badge, not board.alive or board.gold < a["gold"] or board.gems < a["gems"])
	return cards


func _coop_cards() -> Array:
	var gift := _card("gold", Color.WHITE, "골드 선물", "파트너에게 골드 100 선물", func(): board.request_gift_gold(100))
	gift[1].badge_icon = "gold"
	gift[1].badge = "100"
	var blast := _card("blast", Color(1, 0.55, 0.2), "합동 폭격", "두 전장의 모든 적에게 큰 피해\n처치할수록 게이지가 찹니다 (F)", func(): board.request_blast())
	_sheet_refresh = func():
		gift[1].set_state("100", not board.alive or board.gold < 100)
		blast[1].progress = float(board.gauge) / GameData.COOP_BLAST_NEED
		blast[1].set_state("%d%%" % int(100.0 * board.gauge / GameData.COOP_BLAST_NEED), not board.alive or board.gauge < GameData.COOP_BLAST_NEED, board.gauge >= GameData.COOP_BLAST_NEED)
	return [gift, blast]


func _mission_sheet(v: VBoxContainer) -> void:
	var labels: Array = []
	for m in GameData.MISSIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var ic := UIIcon.make("mission", 24)
		row.add_child(ic)
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.add_theme_font_size_override("font_size", 15)
		row.add_child(l)
		var rw := Label.new()
		var parts: Array = []
		if m["gold"] > 0:
			parts.append("%dG" % m["gold"])
		if m["gems"] > 0:
			parts.append("보석 %d" % m["gems"])
		rw.text = " + ".join(parts)
		rw.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		row.add_child(rw)
		v.add_child(row)
		labels.append([m, l, ic])
	if keys_hint != "":
		var k := Label.new()
		k.text = keys_hint
		k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		k.add_theme_font_size_override("font_size", 13)
		k.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
		v.add_child(k)
	_sheet_refresh = func():
		for e in labels:
			var done: bool = board.missions.has(e[0]["id"])
			e[1].text = "%s - %s" % [e[0]["name"], e[0]["desc"]]
			e[1].add_theme_color_override("font_color", Color(0.5, 1.0, 0.6) if done else Color(0.8, 0.82, 0.88))
			e[2].set_icon("check" if done else "mission", Color(0.4, 1.0, 0.5) if done else Color(0.6, 0.65, 0.75))


# ===========================================================================
# 갱신
# ===========================================================================
func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0 or board == null:
		return
	_t = 0.12
	_refresh()


func _refresh() -> void:
	var b := board
	_chip_gold.text = str(b.gold)
	_chip_gems.text = str(b.gems)
	if not interactive:
		_chip_extra.text = "%s  ·  처치 %d" % [b.player_name, b.kills]
		_refresh_readonly()
		if b.is_remote:
			b._recalc_synergy()
		_refresh_synergy()
		return
	_chip_extra.text = "처치 %d" % b.kills
	var ok := b.alive
	var free := b.free_summons > 0
	_btn["summon"].badge_icon = "summon" if free else "gold"
	_btn["summon"].set_state(("x%d" % b.free_summons) if free else str(b.summon_cost()), not ok or (not free and b.gold < b.summon_cost()), free)
	var merges := 0
	for i in b.cells.size():
		if b.mergeable(i):
			merges += 1
	_btn["merge"].set_state("", not ok or merges == 0, merges > 0, merges)
	_btn["gamble"].set_state("", not ok, b.gems >= GameData.GAMBLES[1]["gems"])
	_btn["slot"].set_state("", not ok, b.pending_slot.is_empty() and b.gold >= b.slot_bet(0) * 4)
	var can_up := false
	for i in 4:
		if b.can_afford_upgrade(i):
			can_up = true
	_btn["upgrade"].set_state("", not ok, can_up and b.gold > b.summon_cost() * 2)
	var combos := 0
	for m in GameData.RECIPES:
		if b.can_combine(m):
			combos += 1
	_btn["recipe"].set_state("", not ok, combos > 0, combos)
	if _btn.has("special"):
		if b.mode == "coop":
			_btn["special"].progress = float(b.gauge) / GameData.COOP_BLAST_NEED
			_btn["special"].set_state("", not ok, b.gauge >= GameData.COOP_BLAST_NEED)
		else:
			_btn["special"].set_state("", not ok, b.gold > 300)
	_btn["mission"].set_state("", false, false, 0)
	if _btn.has("ad"):
		_btn["ad"].visible = ad_available
		_btn["ad"].set_state("", not ok, ad_available)
	_refresh_selected()
	_refresh_synergy()
	if not _recipe_rows.is_empty():
		_refresh_recipes(_recipe_rows)
	if _sheet_refresh.is_valid():
		_sheet_refresh.call()


func _refresh_selected() -> void:
	var b := board
	var sel := b.selected
	var has_sel: bool = sel >= 0 and b.cells[sel]["id"] != ""
	if has_sel:
		var id: String = b.cells[sel]["id"]
		var u: Dictionary = GameData.UNITS[id]
		_sel_icon.set_unit(id)
		var star: int = b.cells[sel]["star"]
		_sel_name.text = "%s%s  x%d%s" % [u["name"], "  " + "★".repeat(star) if star > 0 else "", b.cells[sel]["n"], "  각성" if star >= GameData.AWAKEN_STAR else ""]
		_sel_name.add_theme_color_override("font_color", GameData.RARITY_COLORS[u["rarity"]])
		var cell: Dictionary = b.cells[sel]
		var stats := "공격 %d · %.2f초 · 사거리 %d" % [int(b.cell_damage(cell)), u["cd"] / b.cell_speed(cell), int(b.cell_range(cell))]
		if star < GameData.STAR_MAX:
			var ch := int(GameData.STAR_CHANCE[star] * 100)
			var down := int(GameData.STAR_DOWN_CHANCE[star] * 100)
			stats += "  |  ★%d 확률 %d%%%s" % [star + 1, ch, (" (실패 시 %d%% 하락)" % down) if down > 0 else ""]
		_sel_stats.text = (stats + "\n" + u["desc"]) if tall else (stats + " · " + u["desc"])
		var r: int = u["rarity"]
		var sell := ("+%dG" % GameData.SELL_GOLD[r]) if GameData.SELL_GOLD[r] > 0 else ("+%d" % GameData.SELL_GEMS[r] if GameData.SELL_GEMS[r] > 0 else "")
		_sel_sell.set_state(sell, not b.alive or r >= GameData.Rarity.MYTHIC)
		_sel_merge.set_state("", not b.alive or not b.mergeable(sel), b.mergeable(sel))
		if _sel_gift:
			_sel_gift.set_state("", not b.alive)
		var maxed: bool = star >= GameData.STAR_MAX
		var busy := not b.pending_enhance.is_empty()
		_sel_up.set_state("MAX" if maxed else ("..." if busy else str(b.enhance_cost_of(sel))), maxed or busy or not b.can_enhance(sel), not busy and b.can_enhance(sel) and star < 3)
	else:
		_sel_icon.set_unit("")
		_sel_name.text = "칸을 눌러 유닛 선택"
		_sel_name.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
		_sel_stats.text = "다른 칸을 누르면 이동 · 사거리 짧은 유닛은 바깥쪽"
		_sel_sell.set_state("", true)
		_sel_merge.set_state("", true)
		_sel_up.set_state("", true)
		if _sel_gift:
			_sel_gift.set_state("", true)


func _refresh_recipes(rows: Array) -> void:
	var have := board.unit_counts()
	for row in rows:
		var m: String = row[0]
		var used := {}
		for ic in row[1]:
			var id: String = ic.unit_id
			used[id] = used.get(id, 0) + 1
			var ok: bool = have.get(id, 0) >= used[id]
			ic.set_unit(id, not ok, ok)
		var can := board.can_combine(m)
		row[2].set_unit(m, not can)
		row[3].set_state("", not board.alive or not can, can)


func _refresh_readonly() -> void:
	var counts := [0, 0, 0, 0, 0]
	for c in board.cells:
		if c["id"] != "":
			counts[GameData.UNITS[c["id"]]["rarity"]] += c["n"]
	for r in 5:
		_info_rarity[r].text = str(counts[r])
	for e in _info_myth:
		var pr := board.recipe_progress(e[0])
		e[1].set_unit(e[0], pr[0] < pr[1])
		e[2].text = "%d/%d" % [pr[0], pr[1]]
