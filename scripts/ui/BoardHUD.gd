class_name BoardHUD
extends PanelContainer
## 전장 하나의 조작 패널. 아이콘 중심(이미지로 교체 가능), 글자는 숫자와 이름 정도만.
##  - 자원 칩 (골드 / 보석)
##  - 행동 버튼 줄: 소환 · 합성 · 운명 소환 · 강화 · 조합 · 공격(대전)/협동 · 과제 · 광고
##  - 선택 유닛 카드: 초상화, 능력치 아이콘, 합성/판매/선물
##  - 운명 소환/강화/조합/공격/협동/과제는 카드형 시트로 열림 (한 전장 화면은 오른쪽 조작 패널 위)
##  - 고급 버튼(강화 · 운명 소환 · 럭키 슬롯 · 지배 · ★ 강화)은 스토리 진행/계정 레벨로 하나씩 열림 (UIKit.UNLOCKS)

signal ad_summon_requested(hud)
signal emote_requested(hud, emote)

var board: Board
var interactive := true
var keys_hint := ""
var tall := false
var sheet_parent: Node          # 시트를 띄울 레이어 (Match 가 지정)
var sheet_rect := Rect2()       # 시트를 띄울 화면 영역 (보통 전장 위)
var sheet_top := 60.0           # sheet_rect 위쪽에서 시트까지 여백
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
var _pick_opened := false        # 이번 골라 뽑기를 자동으로 한 번 열었는지 (닫으면 다시 안 열고 배지로 알림)
var _pick_badge: ActionButton    # 소환 버튼 위 "골라 뽑기" 배지
var _marks: _CellMarks           # 전장 칸 위 "신화 재료 보호" 표시
const LOCK_KEYS := {"upgrade": "upgrade", "gamble": "gamble", "slot": "slot", "control": "control"}


func sheet_kind() -> String:
	## 지금 열린 시트 종류 ("" = 없음)
	return _sheet_kind


func setup(b: Board, p_interactive: bool, p_keys_hint: String, p_tall := false) -> void:
	board = b
	interactive = p_interactive
	keys_hint = p_keys_hint
	tall = p_tall
	theme = UIKit.theme()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.17, 0.94)
	sb.border_color = Color(0.4, 0.52, 0.95, 0.55) if interactive else b.accent.darkened(0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(20)
	sb.set_content_margin_all(14 if tall else 8)
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 10
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
	_chip_extra.add_theme_font_size_override("font_size", 22 if big else 19)
	_chip_extra.add_theme_color_override("font_color", Color(0.72, 0.77, 0.88))
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
		l.add_theme_font_size_override("font_size", maxi(18, int(isz * 0.6)))
		l.mouse_filter = Control.MOUSE_FILTER_PASS
		l.tooltip_text = box.tooltip_text
		l.gui_input.connect(func(e):
			if e is InputEventMouseButton and e.pressed:
				ActionButton.show_bubble(l, l.tooltip_text))
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
		e[2].modulate = Color(1, 1, 1, 1.0 if on else 0.8)
		e[2].visible = n > 0
		e[0].color = GameData.SYNERGIES[tag]["color"] if on else Color(0.4, 0.42, 0.5)
		e[0].queue_redraw()


func _action_buttons(sz: Vector2) -> Array:
	var list: Array = []
	var add := func(key: String, icon: String, col: Color, tip: String, cb: Callable):
		var ab := ActionButton.make(icon, col.lightened(0.45), tip, _gated(key, cb), sz)
		# 모바일 게임식 색 버튼: 버튼마다 고유 색 (소환/합성은 더 진하게 강조)
		ab.tone = col.darkened(0.25 if key in ["summon", "merge"] else 0.42)
		ab.radius = 16
		_btn[key] = ab
		list.append(ab)
	add.call("summon", "summon", Color(0.45, 0.9, 0.5), "소환 (Q)\n골드로 무작위 유닛 소환", func(): board.summon())
	_btn["summon"].badge_icon = "gold"
	add.call("merge", "merge", Color(1, 0.85, 0.4), "합성 (E)\n같은 유닛 3마리 → 상위 등급\n신화 재료(자물쇠 칸)는 아껴 둬요", func(): board.auto_merge())
	add.call("merge_all", "merge", Color(1, 0.7, 0.3), "모두 합성\n합성할 수 있는 칸을 한 번에\n(신화 재료는 남김)", _merge_all)
	add.call("gamble", "gamble", Color(0.75, 0.45, 1.0), "운명 소환\n보석으로 영웅·전설에 도전! 실패해도 3연속이면 위로 보상", func(): _toggle_sheet("gamble"))
	add.call("slot", "slot", Color(1, 0.35, 0.45), "럭키 슬롯\n골드를 걸고 한 판!", func(): _toggle_sheet("slot"))
	add.call("upgrade", "upgrade", Color(0.45, 0.95, 0.6), "강화\n등급별 공격력 / 소환 행운", func(): _toggle_sheet("upgrade"))
	add.call("recipe", "recipe", Color(1, 0.35, 0.4), "조합\n신화 조합표", func(): _toggle_sheet("recipe"))
	add.call("control", "curse", Color(0.8, 0.5, 1.0), "지배\n보석 %d개로 트랙 위 가장 강한 적을 내 유닛으로!\n중간보스는 보석 %d개, 전설 유닛이 돼요" % [GameData.MC_GEMS, GameData.MC_LEGEND_GEMS], func(): board.mind_control())
	_btn["control"].badge_icon = "gem"
	if board.mode == "pvp":
		add.call("special", "attack", Color(1, 0.5, 0.4), "공격\n상대에게 적/저주 보내기", func(): _toggle_sheet("attack"))
	elif board.mode == "coop":
		add.call("special", "gift", Color(0.5, 0.95, 0.8), "협동\n골드 선물 / 합동 폭격", func(): _toggle_sheet("coop"))
	add.call("mission", "mission", Color(0.5, 1.0, 0.6), "미션\n도전 과제 · 조작법", func(): _toggle_sheet("mission"))
	if emotes_enabled:
		add.call("emote", "emote", Color(1, 0.8, 0.2), "이모티콘", func(): _toggle_sheet("emote"))
	if ad_available:
		add.call("ad", "ad", Color(0.35, 0.6, 1.0), "무료 소환\n광고 보고 무료 소환 3회 (판당 1회)", func(): ad_summon_requested.emit(self))
		_btn["ad"].badge_icon = ""
	_btn["merge_all"].caption = "모두 합성"
	return list


func _gated(key: String, cb: Callable) -> Callable:
	## 아직 안 열린 기능이면 누를 때 안내만. 처음 눌러 본 새 기능은 NEW 표시를 지운다
	return func():
		var k: String = LOCK_KEYS.get(key, "")
		if k != "" and not UIKit.feature_unlocked(k):
			var ab: ActionButton = _btn.get(key)
			Sfx.play("fail")
			if ab != null:
				ActionButton.show_bubble(ab, "%s\n%s" % [ab.caption, UIKit.UNLOCKS[k][2]])
			return
		if k != "" and UIKit.feature_is_new(k):
			UIKit.mark_feature_seen(k)
			if _btn.has(key):
				_btn[key].new_tag = false
				_btn[key].queue_redraw()
		cb.call()


func _merge_all() -> void:
	var n := board.merge_all()
	if n <= 0:
		board.auto_merge()   # 남은 게 신화 재료뿐이면 하나라도


func _refresh_locks() -> void:
	for key in LOCK_KEYS:
		if not _btn.has(key):
			continue
		var ab: ActionButton = _btn[key]
		var k: String = LOCK_KEYS[key]
		var lk := not UIKit.feature_unlocked(k)
		var nw := not lk and UIKit.feature_is_new(k)
		if ab.locked != lk or ab.new_tag != nw:
			ab.locked = lk
			ab.new_tag = nw
			ab.queue_redraw()
	if _sel_up != null:
		var lk := not UIKit.feature_unlocked("enhance")
		if _sel_up.locked != lk:
			_sel_up.locked = lk
			_sel_up.queue_redraw()


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
	_sel_name.add_theme_font_size_override("font_size", 26 if tall else 20)
	_sel_name.clip_text = true
	v.add_child(_sel_name)
	_sel_stats = Label.new()
	_sel_stats.add_theme_font_size_override("font_size", 22 if tall else 18)
	_sel_stats.add_theme_color_override("font_color", Color(0.8, 0.84, 0.92))
	if tall:
		_sel_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		_sel_stats.clip_text = true
	v.add_child(_sel_stats)
	var bsz := Vector2(92, 92) if tall else Vector2(56, 48)
	var try_enhance := func():
		if not UIKit.feature_unlocked("enhance"):
			Sfx.play("fail")
			ActionButton.show_bubble(_sel_up, "★ 강화\n" + UIKit.UNLOCKS["enhance"][2])
			return
		board.enhance_try(board.selected)
	_sel_up = ActionButton.make("hammer", Color(1, 0.8, 0.4), "★ 강화 시도\n성공하면 공격력·공속 상승, ★3 각성\n높은 ★에서 실패하면 하락 위험", try_enhance, bsz * (Vector2(1.3, 1) if tall else Vector2(1, 1)))
	_sel_up.badge_icon = "gold"
	_sel_up.caption = "★ 강화"
	h.add_child(_sel_up)
	_sel_merge = ActionButton.make("merge", Color(1, 0.85, 0.4), "이 칸 합성", func(): board.merge_cell(board.selected), bsz)
	_sel_merge.caption = "합성"
	h.add_child(_sel_merge)
	_sel_sell = ActionButton.make("sell", Color(1, 0.85, 0.3), "1마리 판매 (X)", func(): board.sell_one(board.selected), bsz)
	_sel_sell.caption = "판매"
	h.add_child(_sel_sell)
	if board.mode == "coop":
		_sel_gift = ActionButton.make("gift", Color(0.5, 0.95, 0.8), "파트너에게 1마리 선물", func(): board.request_gift_unit(board.selected), bsz)
		_sel_gift.caption = "선물"
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
	var card := _selected_card(48)
	root.add_child(card)
	_add_pick_badge(Vector2(88, 44))


func _build_tall() -> void:
	## 한 전장 화면의 오른쪽 패널 (상위 디펜스 게임식):
	##  재화 → 시너지 → 선택한 유닛 → 보조 버튼(둥근 색 버튼) → 맨 아래 큰 [소환] [합성]
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	add_child(root)
	var res := PanelContainer.new()
	res.add_theme_stylebox_override("panel", _inner_box())
	res.add_child(_chips(true))
	root.add_child(res)
	root.add_child(_synergy_row(34))
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(sp)
	root.add_child(_preview_panel())
	var card_panel := PanelContainer.new()
	card_panel.add_theme_stylebox_override("panel", _inner_box())
	card_panel.custom_minimum_size = Vector2(0, 124)
	card_panel.add_child(_selected_card(100))
	root.add_child(card_panel)
	var buttons := _action_buttons(Vector2(150, 96))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	root.add_child(grid)
	for ab in buttons:
		if ab == _btn["summon"] or ab == _btn["merge"] or ab == _btn["merge_all"]:
			continue
		ab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ab.radius = 20
		grid.add_child(ab)
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	root.add_child(main)
	var sm: ActionButton = _btn["summon"]
	sm.custom_minimum_size = Vector2(0, 128)
	sm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sm.size_flags_stretch_ratio = 1.7
	sm.wide = true
	sm.radius = 24
	sm.tone = Color(0.2, 0.62, 0.28)
	main.add_child(sm)
	var mg: ActionButton = _btn["merge"]
	mg.custom_minimum_size = Vector2(0, 128)
	mg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mg.wide = true
	mg.radius = 24
	mg.tone = Color(0.85, 0.52, 0.1)
	main.add_child(mg)
	var ma: ActionButton = _btn["merge_all"]
	ma.custom_minimum_size = Vector2(112, 128)
	ma.radius = 24
	ma.tone = Color(0.72, 0.4, 0.08)
	main.add_child(ma)
	_add_pick_badge(Vector2(150, 60))


func _add_pick_badge(sz: Vector2) -> void:
	## 골라 뽑기 대기 중인데 시트를 닫았으면 소환 버튼 위에 반짝이는 배지 (누르면 다시 열기)
	var sm: ActionButton = _btn["summon"]
	_pick_badge = ActionButton.make("", Color.WHITE, "골라 뽑기\n눌러서 3장 중 하나 고르기", func(): _toggle_sheet("pick"), sz)
	_pick_badge.badge = "골라 뽑기!"
	_pick_badge.font_px = int(sz.y * 0.42)
	_pick_badge.tone = Color(0.2, 0.55, 0.95)
	_pick_badge.radius = sz.y * 0.5
	_pick_badge.glow = true
	_pick_badge.visible = false
	sm.add_child(_pick_badge)
	var place := func(): _pick_badge.position = Vector2(sm.size.x - sz.x + 6, -sz.y * 0.55)
	sm.resized.connect(place)
	place.call_deferred()


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
		var ic := UIIcon.make("star", 28, GameData.RARITY_COLORS[r])
		ic.tint = true
		ic.tooltip_text = GameData.RARITY_NAMES[r]
		ic.mouse_filter = Control.MOUSE_FILTER_PASS
		chip.add_child(ic)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 22)
		l.add_theme_color_override("font_color", GameData.RARITY_COLORS[r])
		chip.add_child(l)
		row.add_child(chip)
		_info_rarity.append(l)
	# 신화 진행도: 11종 → 아이콘을 줄여 한 줄에 (패널 높이를 넘지 않게)
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 4)
	root.add_child(mrow)
	for m in GameData.RECIPES:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", -4)
		var ic := UnitIcon.make(m, 46)
		v.add_child(ic)
		var l := Label.new()
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 18)
		v.add_child(l)
		mrow.add_child(v)
		_info_myth.append([m, ic, l])


var _preview_items: Array = []   # [[UIIcon, Label(이름), Label(남은 라운드)], ...]
var _preview_box: Control


func _preview_panel() -> Control:
	## 다가오는 특별 라운드 예고 (보스 · 중간보스 · 보너스) - 긴장감과 준비 시간을 준다
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", _inner_box())
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	var t := Label.new()
	t.text = "다가오는 라운드"
	t.add_theme_font_size_override("font_size", 20)
	t.add_theme_color_override("font_color", Color(0.7, 0.78, 0.95))
	v.add_child(t)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	for i in 3:
		var box := HBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 8)
		var ic := UIIcon.make("skull", 46)
		box.add_child(ic)
		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", -2)
		var nl := Label.new()
		nl.add_theme_font_size_override("font_size", 23)
		tv.add_child(nl)
		var rl := Label.new()
		rl.add_theme_font_size_override("font_size", 19)
		rl.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
		tv.add_child(rl)
		box.add_child(tv)
		h.add_child(box)
		_preview_items.append([ic, nl, rl, box])
	_preview_box = p
	return p


func _refresh_preview() -> void:
	if _preview_items.is_empty():
		return
	var b := board
	var list: Array = []
	var w := b.wave + 1
	while list.size() < 3 and w <= b.final_wave + 20:
		if b.is_boss_round(w):
			list.append([w, "skull", "보스" if w < b.final_wave else "최종 보스", Color(1, 0.4, 0.45)])
		elif b.is_bonus_round(w):
			list.append([w, "gold", "보너스", Color(1, 0.8, 0.4)])
		elif GameData.is_midboss_wave(w) and w < b.final_wave:
			list.append([w, "elite", "중간보스", Color(0.8, 0.55, 1.0)])
		if w >= b.final_wave and b.mode != "pvp":
			break
		w += 1
	if _preview_box != null:
		_preview_box.visible = not list.is_empty()   # 짧은 스테이지엔 특별 라운드가 없음 → 빈 칸 대신 숨김
	for i in _preview_items.size():
		var it: Array = _preview_items[i]
		it[3].visible = i < list.size()
		if i >= list.size():
			continue
		var e: Array = list[i]
		it[0].set_icon(e[1], e[3])
		it[1].text = e[2]
		it[1].add_theme_color_override("font_color", e[3])
		var left: int = e[0] - b.wave
		it[2].text = "R%d · %s" % [e[0], "다음!" if left == 1 else "%d판 뒤" % left]


func _inner_box() -> StyleBox:
	var f := StyleBoxFlat.new()
	f.bg_color = Color(0.02, 0.03, 0.09, 0.6)
	f.border_color = Color(1, 1, 1, 0.06)
	f.set_border_width_all(1)
	f.set_corner_radius_all(16)
	f.set_content_margin_all(10)
	return f


func _recipe_list(icon_sz: float, out: Array) -> Control:
	## 신화 조합표. 완성에 가까운 것부터 위에 (11종이라 스크롤). 결과 이름 + 모자란 재료 이름을 글로도 보여 줌
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for m in _recipes_by_progress():
		# [ 재료들 → 결과  이름 ]  [조합]
		# [ 필요: 모자란 재료 이름    ]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var left := VBoxContainer.new()
		left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		left.add_theme_constant_override("separation", -4)
		row.add_child(left)
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 0)
		left.add_child(line)
		var icons: Array = []
		for ing in GameData.RECIPES[m]:
			var ic := UnitIcon.make(ing, icon_sz)
			line.add_child(ic)
			icons.append(ic)
		var arrow := UIIcon.make("play", icon_sz * 0.4, Color(0.6, 0.65, 0.75))
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		line.add_child(arrow)
		var res := UnitIcon.make(m, icon_sz * 1.15)
		line.add_child(res)
		var nm := UIKit.label(GameData.UNITS[m]["name"], 23, GameData.RARITY_COLORS[4].lightened(0.35), 4)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		line.add_child(nm)
		var miss := UIKit.label("", 19, Color(1, 0.62, 0.55), 3)
		miss.clip_text = true
		miss.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		left.add_child(miss)
		var mm: String = m
		var btn := ActionButton.make("check", Color(1, 0.4, 0.45), "%s 조합 (T)\n%s" % [GameData.UNITS[m]["name"], GameData.UNITS[m]["desc"]], func(): board.combine(mm), Vector2(104, 68))
		btn.caption = "조합"
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(btn)
		v.add_child(row)
		out.append([m, icons, res, btn, miss])
	return v


func _recipes_by_progress() -> Array:
	var list: Array = GameData.RECIPES.keys()
	var score := {}
	for m in list:
		var pr := board.recipe_progress(m)
		score[m] = float(pr[0]) / maxf(1.0, pr[1])
	list.sort_custom(func(a, b): return score[a] > score[b])
	return list


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
	var key: String = {"pick": "summon", "emote": "emote", "slot": "slot", "gamble": "gamble", "upgrade": "upgrade", "recipe": "recipe", "attack": "special", "coop": "special", "mission": "mission"}[kind]
	if _btn.has(key):
		_btn[key].selected = true
	_sheet = PanelContainer.new()
	_sheet.theme = UIKit.theme()
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
	var w := minf(sheet_rect.size.x - 12, 720)
	_sheet.position = sheet_rect.position + Vector2((sheet_rect.size.x - w) / 2, sheet_top)
	_sheet.size = Vector2(w, 0)
	sheet_parent.add_child(_sheet)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_sheet.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var info: Array = {
		"pick": ["summon", "골라 뽑기 · 하나 고르기", Color(0.6, 0.9, 1.0)],
		"slot": ["slot", "럭키 슬롯", Color(1, 0.35, 0.45)],
		"emote": ["emote", "이모티콘", Color(1, 0.8, 0.2)],
		"gamble": ["gamble", "운명 소환", Color(0.75, 0.45, 1.0)], "upgrade": ["upgrade", "강화", Color(0.45, 0.95, 0.6)],
		"recipe": ["recipe", "신화 조합", Color(1, 0.35, 0.4)], "attack": ["attack", "공격", Color(1, 0.5, 0.4)],
		"coop": ["gift", "협동", Color(0.5, 0.95, 0.8)], "mission": ["mission", "도전 과제", Color(0.5, 1.0, 0.6)],
	}[kind]
	head.add_child(UIIcon.make(info[0], 44, info[2]))
	var tl := Label.new()
	tl.text = info[1]
	tl.add_theme_font_size_override("font_size", 28)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	head.add_child(tl)
	var xb := ActionButton.make("close", Color(0.85, 0.85, 0.9), "닫기 (Esc)", close_sheet, Vector2(76, 68))
	xb.caption = ""
	head.add_child(xb)
	match kind:
		"pick":
			var cards: Array = []
			for i in board.pending_pick.size():
				var pid: String = board.pending_pick[i]
				var pu: Dictionary = GameData.UNITS[pid]
				var ii := i
				var choose := func():
					if board.choose_pick(ii):
						close_sheet()
				var c := _card("", GameData.RARITY_COLORS[pu["rarity"]], "%s\n%s" % [GameData.RARITY_NAMES[pu["rarity"]], pu["name"]], "%s\n%s" % [pu["name"], pu["desc"]], choose)
				var ic := UnitIcon.make(pid, 110)
				ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
				ic.position = Vector2(4, 4)
				c[1].add_child(ic)
				c[1].tone = GameData.RARITY_COLORS[pu["rarity"]].darkened(0.55)
				c[2].add_theme_color_override("font_color", GameData.RARITY_COLORS[pu["rarity"]].lightened(0.3))
				cards.append(c)
			_sheet_cards(v, cards)
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
			var sc := ScrollContainer.new()
			sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			var avail := minf(sheet_rect.end.y, 900.0) - sheet_rect.position.y - sheet_top - 130.0
			sc.custom_minimum_size = Vector2(0, clampf(avail, 260, 640))
			v.add_child(sc)
			sc.add_child(_recipe_list(50, rows))
			_sheet.set_meta("scroll", sc)
			_sheet_refresh = func(): _refresh_recipes(rows)
		"mission":
			_mission_sheet(v)
	if _sheet_refresh.is_valid():
		_sheet_refresh.call()
	_fit_sheet.call_deferred()


func _fit_sheet() -> void:
	## 시트가 화면 아래로 넘치면 스크롤 영역을 줄이고, 그래도 넘치면 위로 올린다
	if _sheet == null or not is_instance_valid(_sheet):
		return
	var limit := minf(sheet_rect.end.y, 900.0) - 6.0
	var need := _sheet.get_combined_minimum_size().y
	var sc: ScrollContainer = _sheet.get_meta("scroll") if _sheet.has_meta("scroll") else null
	if sc != null and _sheet.position.y + need > limit:
		sc.custom_minimum_size.y = maxf(180.0, sc.custom_minimum_size.y - (_sheet.position.y + need - limit))
		need = _sheet.get_combined_minimum_size().y
	_sheet.size = Vector2(_sheet.size.x, need)
	if _sheet.position.y + need > limit:
		_sheet.position.y = maxf(8.0, limit - need)


func _card(icon: String, col: Color, title: String, tip: String, cb: Callable) -> Array:
	## [VBox, ActionButton, Label]
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var ab := ActionButton.make(icon, col, tip, cb, Vector2(124, 118))
	ab.caption = ""
	box.add_child(ab)
	var l := Label.new()
	l.text = title
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", 21)
	l.custom_minimum_size = Vector2(130, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(l)
	return [box, ab, l]


func _sheet_cards(v: VBoxContainer, cards: Array) -> void:
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 12)
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
	result.add_theme_font_size_override("font_size", 26)
	v.add_child(result)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var bets: Array = []
	for i in GameData.SLOT_BETS.size():
		var bi := i
		var b := ActionButton.make("slot", Color(1, 0.35, 0.45) if i == 0 else Color(1, 0.75, 0.2), ["한 판", "크게 한 판"][i] + "\n세 개가 같으면 잭팟!", func(): board.slot_spin(bi), Vector2(190, 100))
		b.badge_icon = "gold"
		h.add_child(b)
		bets.append(b)
	var pay := Label.new()
	pay.text = "골드 3개 = 8배 · 두 개 = 1.5배\n보석·소환·별 3개 = 특별 보상"
	pay.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pay.add_theme_font_size_override("font_size", 20)
	pay.add_theme_color_override("font_color", Color(0.78, 0.82, 0.92))
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
			var g: Dictionary = GameData.GAMBLES[i]
			cards[i][1].set_state(str(g["gems"]), not board.alive or board.gems < g["gems"], board.gems >= g["gems"])
			var t := "%s %d%%" % [GameData.RARITY_NAMES[g["rarity"]], int((g["chance"] + board.bonus_gamble) * 100)]
			var pity: int = g.get("pity", 0)
			if pity > 0 and i < board.gamble_fails.size():
				var fails := int(board.gamble_fails[i])
				t += "\n" + ("다음 확정!" if fails >= pity else "확정까지 %d" % (pity - fails))
				cards[i][2].add_theme_color_override("font_color", Color(1, 0.85, 0.35) if fails >= pity else Color(0.85, 0.88, 1.0))
			cards[i][2].text = t
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
		var ic := UIIcon.make("mission", 30)
		row.add_child(ic)
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 21)
		row.add_child(l)
		var rw := Label.new()
		var parts: Array = []
		if m["gold"] > 0:
			parts.append("%dG" % m["gold"])
		if m["gems"] > 0:
			parts.append("보석 %d" % m["gems"])
		rw.text = " + ".join(parts)
		rw.add_theme_font_size_override("font_size", 21)
		rw.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		row.add_child(rw)
		v.add_child(row)
		labels.append([m, l, ic])
	if keys_hint != "" and not Platform.is_mobile():
		var k := Label.new()
		k.text = keys_hint
		k.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		k.add_theme_font_size_override("font_size", 18)
		k.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
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
	_chip_extra.text = ""   # 처치 수는 전장 머리줄에 이미 있음
	var ok := b.alive
	var free := b.free_summons > 0
	_btn["summon"].badge_icon = "summon" if free else "gold"
	_btn["summon"].set_state(("x%d" % b.free_summons) if free else str(b.summon_cost()), not ok or (not free and b.gold < b.summon_cost()), free)
	# 천장 게이지 + 골라 뽑기까지 + 확률 공개 (길게 누르기)
	var to_pick := GameData.PICK_EVERY - b.summons_total % GameData.PICK_EVERY
	var sm: ActionButton = _btn["summon"]
	sm.sub = "영웅 확정 %d" % (GameData.PITY_EPIC - b.pity_epic) if to_pick > 1 else "다음: 골라 뽑기!"
	sm.progress = float(b.pity_epic) / GameData.PITY_EPIC
	var probs := GameData.summon_probs(b.upgrades[3])
	var tot := 0.0
	for pv in probs:
		tot += pv
	var rates: Array = []
	for r in probs.size():
		rates.append("%s %.1f%%" % [GameData.RARITY_NAMES[r], probs[r] / tot * 100.0])
	sm.tooltip_text = "소환 (Q)\n%s\n영웅 이상 %d회 · 전설 %d회 안에 확정\n%d번째 소환마다 3장 중 골라 뽑기" % ["  ".join(rates), GameData.PITY_EPIC, GameData.PITY_LEGEND, GameData.PICK_EVERY]
	# 골라 뽑기: 처음 한 번만 자동으로 열고, 닫으면 소환 버튼 위 배지로 알린다 (싸움 중 계속 가리지 않게)
	var picking := not b.pending_pick.is_empty()
	if not picking:
		_pick_opened = false
	elif not _pick_opened and _sheet_kind == "" and sheet_parent != null:
		_pick_opened = true
		_toggle_sheet("pick")
	if _pick_badge != null:
		_pick_badge.visible = picking and _sheet_kind != "pick"
	var merges := 0
	var protected: Array = []
	for i in b.cells.size():
		if b.mergeable(i):
			if b.merge_protected(i):
				protected.append(i)
			else:
				merges += 1
	# 합성: 보호된 신화 재료만 남았으면 그것도 (auto_merge 는 그때 재료를 씀)
	_btn["merge"].set_state("", not ok or merges + protected.size() == 0, merges > 0, merges if merges > 0 else protected.size())
	# 모두 합성: 2곳 이상이거나, 신화 재료만 남았을 때 (그때는 auto_merge 로 하나)
	_btn["merge_all"].set_state("", not ok or (merges < 2 and protected.is_empty()), false, merges if merges >= 2 else 0)
	_update_marks(protected)
	_refresh_locks()
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
	var mc_ready := b.can_mind_control()
	var strong := false
	if mc_ready:
		var tgt := b._mc_target()
		strong = tgt != null and tgt.kind in ["midboss", "hero", "elite"]
	_btn["control"].progress = (1.0 - b.mc_cd / GameData.MC_COOLDOWN) if b.mc_cd > 0.0 else -1.0
	_btn["control"].set_state(str(board.mc_cost()), not mc_ready, strong)
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
	_refresh_preview()
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
		var stats := "공격 %d · %.2f초\n사거리 %d" % [int(b.cell_damage(cell)), u["cd"] / b.cell_speed(cell), int(b.cell_range(cell))]
		if star < GameData.STAR_MAX:
			var ch := int(GameData.STAR_CHANCE[star] * 100)
			var down := int(GameData.STAR_DOWN_CHANCE[star] * 100)
			stats += "\n★%d 강화 %d%%%s" % [star + 1, ch, (" · 실패 시 %d%% 하락" % down) if down > 0 else ""]
		if b.mergeable(sel) and b.merge_protected(sel):
			stats += "\n신화 재료라 합성 버튼은 건너뛰어요"
		_sel_stats.text = stats
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
		_sel_name.text = "유닛을 눌러 선택"
		_sel_name.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
		_sel_stats.text = "빈 칸을 누르면 이동"
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
		var missing: Array = []
		for ic in row[1]:
			var id: String = ic.unit_id
			used[id] = used.get(id, 0) + 1
			var ok: bool = have.get(id, 0) >= used[id]
			ic.set_unit(id, not ok, ok)
			if not ok:
				missing.append(GameData.UNITS[id]["name"])
		var can := board.can_combine(m)
		row[2].set_unit(m, not can)
		row[3].set_state("", not board.alive or not can, can)
		if row.size() > 4:
			row[4].text = "조합 가능!" if can else "필요: " + ", ".join(missing)
			row[4].add_theme_color_override("font_color", Color(0.5, 1, 0.6) if can else Color(1, 0.62, 0.55))


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


# ===========================================================================
# 전장 칸 표시: 합성 버튼이 아껴 두는 신화 재료 칸 (자물쇠)
# ===========================================================================
class _CellMarks:
	extends Node2D
	var cells: Array = []

	func _draw() -> void:
		for i in cells:
			var c: Vector2 = Board.cell_center(i) + Vector2(-Board.CELL * 0.34, -Board.CELL * 0.34)
			draw_circle(c, 11, Color(0.08, 0.06, 0.16, 0.9))
			draw_arc(c, 11, 0, TAU, 20, Color(0.85, 0.6, 1.0), 2.0)
			Glyphs.draw_icon(self, "lock", c, 8, Color(1, 0.9, 0.6))


func _update_marks(protected: Array) -> void:
	if not interactive or board == null:
		return
	if _marks == null:
		_marks = _CellMarks.new()
		_marks.z_index = 1
		board.add_child(_marks)
	if _marks.cells != protected:
		_marks.cells = protected
		_marks.queue_redraw()
