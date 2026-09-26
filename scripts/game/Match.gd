extends Node2D
## 한 판의 게임. 전장(Board)들을 만들고, 모드 규칙(승패), 입력, 전장 간 상호작용,
## 봇, 네트워크 동기화를 담당한다.

const KEYS := [
	{
		"up": [KEY_W], "down": [KEY_S], "left": [KEY_A], "right": [KEY_D], "select": [KEY_SPACE],
		"summon": [KEY_Q], "merge": [KEY_E], "gamble": [KEY_R], "combine": [KEY_T], "special": [KEY_F], "sell": [KEY_X],
	},
	{
		"up": [KEY_UP], "down": [KEY_DOWN], "left": [KEY_LEFT], "right": [KEY_RIGHT], "select": [KEY_ENTER, KEY_KP_ENTER],
		"summon": [KEY_U, KEY_KP_1], "merge": [KEY_I, KEY_KP_2], "gamble": [KEY_O, KEY_KP_3], "combine": [KEY_P, KEY_KP_4],
		"special": [KEY_L, KEY_KP_5], "sell": [KEY_K, KEY_KP_0],
	},
]
const KEY_HINTS := [
	"키보드: WASD 이동 / Space 선택 / Q 소환 / E 합성 / R 영웅도박 / T 신화조합 / F %s / X 판매",
	"키보드: 방향키 이동 / Enter 선택 / U 소환 / I 합성 / O 영웅도박 / P 신화조합 / L %s / K 판매",
]

var mode := "solo"
var boards: Array = []
var huds: Array = []
var bots: Array = []
var key_sets: Array = []
var speed := 1.0
var paused := false
var over := false
var _snap_t := 0.0
var _time := 0.0

var _lbl_center: Label
var _lbl_left: Label
var _btn_sound: ActionButton
var _pending_coins := 0
var _coins_given := false
var _ad_revive_used := false
var _ad_double_used := false
var _ach_t := 1.0
var _match_achs: Array = []       # 이번 판에 달성한 업적
var _toasts: Array = []
var _toast_box: VBoxContainer
var _lbl_round: Label
var _coop_bar: ProgressBar
var _btn_speed: Button
var _btn_pause: Button
var _over_panel: PanelContainer
var _pause_label: Label


func _ready() -> void:
	mode = Session.mode
	if Session.players.is_empty():
		Session.setup_local("solo", [{"name": "플레이어", "kind": "human", "keys": 0}])
		mode = "solo"
	var ui := CanvasLayer.new()
	ui.name = "UI"
	add_child(ui)
	var n := Session.players.size()
	for i in n:
		var p: Dictionary = Session.players[i]
		var b := Board.new()
		b.name = "Board%d" % i
		b.setup(i, p["name"], mode, Session.seed_value, p["kind"] == "remote", p["kind"] == "bot")
		b.sfx = p["kind"] == "human"
		add_child(b)
		boards.append(b)
		key_sets.append(p.get("keys", -1))
		b.action_attack.connect(_on_attack)
		b.action_gift_gold.connect(_on_gift_gold)
		b.action_gift_unit.connect(_on_gift_unit)
		b.action_blast.connect(_on_blast)
	for i in n:
		var other: Board = boards[1 - i] if n > 1 else null
		bots.append(BotBrain.new(boards[i], other, Session.bot_level) if boards[i].is_bot else null)
	if Session.stage != "":
		boards[0].apply_stage(Session.stage)
	_layout(ui)
	_apply_loadout()
	var st := Story.get_stage(Session.stage) if Session.stage != "" else {}
	if not st.is_empty() and not st["data"].get("intro", []).is_empty() and not Profile.story_seen.has(Session.stage):
		paused = true
		var dlg := Dialogue.new()
		dlg.lines = st["data"]["intro"]
		dlg.finished.connect(_after_intro)
		ui.add_child(dlg)
	elif Session.tutorial and mode == "solo":
		_start_tutorial(ui)
	if Session.online:
		Net.event_received.connect(_on_net_event)
		Net.snapshot_received.connect(_on_net_snapshot)
		Net.disconnected.connect(_on_net_disconnected)


const TOP_BAR := 66.0
## 한 전장 화면: 전장이 화면 높이를 가득 채우는 배율 (상단 바를 오른쪽으로 옮김)
const BIG_SCALE := (900.0 - 12.0) / (Board.SIZE + Board.HEADER)
var _top_bar: PanelContainer


func _dock_top_bar(x: float) -> void:
	## 상단 바를 오른쪽 조작 패널 위로만 (전장이 위쪽까지 쓰도록)
	_top_bar.position = Vector2(x, 0)
	_top_bar.size = Vector2(1600 - x, TOP_BAR)
	_lbl_left.visible = false
	_top_right.custom_minimum_size = Vector2.ZERO
	var sb: StyleBoxFlat = _top_bar.get_theme_stylebox("panel").duplicate()
	sb.corner_radius_bottom_left = 16
	sb.border_width_left = 3
	_top_bar.add_theme_stylebox_override("panel", sb)
	# 레이아웃 정리 뒤에 폭이 다시 늘어나는 것을 막기 위해 한 번 더 맞춘다
	(func(): _top_bar.size = Vector2(1600 - x, TOP_BAR); _top_bar.position = Vector2(x, 0)).call_deferred()


func _layout(ui: CanvasLayer) -> void:
	## 화면(1600x900)을 빈틈 없이: 상단 바 / 전장(최대 크기) / 조작 패널
	var n := boards.size()
	var human_count := 0
	for p in Session.players:
		if p["kind"] == "human":
			human_count += 1
	_build_top_bar(ui)
	if n == 2 and human_count == 1 and (Platform.is_mobile() or Profile.settings.get("focus_layout", false)):
		_layout_focus(ui)
	elif n == 1:
		# 전장을 화면 높이 가득 (상단 바는 오른쪽 조작 패널 위로만)
		var s := BIG_SCALE
		var b: Board = boards[0]
		b.scale = Vector2(s, s)
		b.position = Vector2(10, 6 + Board.HEADER * s)
		var hud := _make_hud(0, human_count)
		hud.sheet_rect = Rect2(b.position, Vector2(Board.SIZE, Board.SIZE) * s)
		var x := 10 + Board.SIZE * s + 10
		_dock_top_bar(x)
		hud.position = Vector2(x, TOP_BAR + 8)
		hud.size = Vector2(1600 - x - 10, 900 - TOP_BAR - 16)
		ui.add_child(hud)
	else:
		var s := 1.08
		var bw := Board.SIZE * s
		var board_bottom := TOP_BAR + 6 + Board.HEADER * s + bw
		for i in n:
			var b: Board = boards[i]
			b.scale = Vector2(s, s)
			b.position = Vector2(800 * i + (800 - bw) / 2.0, TOP_BAR + 6 + Board.HEADER * s)
			var hud := _make_hud(i, human_count)
			hud.sheet_rect = Rect2(b.position, Vector2(bw, bw))
			hud.position = Vector2(800 * i + 8, board_bottom + 6)
			hud.size = Vector2(784, 900 - board_bottom - 12)
			ui.add_child(hud)
		var gap_x := (800 - bw) / 2.0 + bw
		_build_center_column(ui, Rect2(gap_x + 6, TOP_BAR + 10, 1600 - 2 * gap_x - 12, board_bottom - TOP_BAR - 10))
	_pause_label = Label.new()
	_pause_label.text = "일시정지"
	_pause_label.add_theme_font_size_override("font_size", 64)
	_pause_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_pause_label.add_theme_constant_override("outline_size", 12)
	_pause_label.position = Vector2(500, 380)
	_pause_label.size = Vector2(600, 100)
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.visible = false
	ui.add_child(_pause_label)


func _layout_focus(ui: CanvasLayer) -> void:
	## 휴대폰: 사람 1명 vs 봇/원격 → 내 전장을 크게. 상대 전장은 위쪽 [상대 보기] 버튼으로 같은 자리에 바꿔 보기
	var me := 0 if not (boards[0].is_bot or boards[0].is_remote) else 1
	_peek_me = me
	var s := BIG_SCALE
	var x := 10 + Board.SIZE * s + 10
	_dock_top_bar(x)
	for i in 2:
		var b: Board = boards[i]
		b.scale = Vector2(s, s)
		b.position = Vector2(10, 6 + Board.HEADER * s)
		b.visible = i == me
		var hud := _make_hud(i, 1, i == me)
		if i == me:
			hud.sheet_rect = Rect2(b.position, Vector2(Board.SIZE, Board.SIZE) * s)
			hud.position = Vector2(x, TOP_BAR + 8)
			hud.size = Vector2(1600 - x - 10, 900 - TOP_BAR - 16)
		else:
			hud.visible = false
		ui.add_child(hud)
	_btn_peek = ActionButton.make("attack", Color(1, 0.55, 0.45), "상대 전장 보기 (필드 적 수)", _toggle_peek, Vector2(96, 58))
	_btn_peek.tone = Color(0.7, 0.25, 0.22)
	_btn_peek.radius = 10
	_top_right.add_child(_btn_peek)
	_top_right.move_child(_btn_peek, 0)


var _peek_me := -1
var _btn_peek: ActionButton
var _top_right: HBoxContainer


func _toggle_peek() -> void:
	var mine: Board = boards[_peek_me]
	var other: Board = boards[1 - _peek_me]
	other.visible = mine.visible
	mine.visible = not other.visible
	_btn_peek.selected = other.visible
	_btn_peek.queue_redraw()


func _update_peek() -> void:
	if _btn_peek == null:
		return
	var n: int = boards[1 - _peek_me].field_count()
	var txt := str(n)
	if _btn_peek.badge != txt:
		_btn_peek.badge = txt
		_btn_peek.glow = n >= GameData.ENEMY_LIMIT * 0.7
		_btn_peek.queue_redraw()


func _make_hud(i: int, human_count: int, tall := false) -> BoardHUD:
	var b: Board = boards[i]
	var hud := BoardHUD.new()
	var interactive := not b.is_bot and not b.is_remote
	var hint := ""
	if interactive and key_sets[i] >= 0:
		var special: String = {"pvp": "잡몹 보내기", "coop": "합동 폭격", "solo": ""}[mode]
		hint = KEY_HINTS[key_sets[i]] % special
		if special == "":
			hint = hint.replace(" / F ", "").replace(" / L ", "")
		if human_count == 1 and not Session.online:
			hint += "   (마우스 조작 가능)"
	hud.sheet_parent = ui_layer()
	hud.ad_available = interactive and not Session.online and mode != "pvp" and _ad_ok()
	hud.ad_summon_requested.connect(_on_ad_summon)
	hud.emote_requested.connect(_on_emote)
	hud.emotes_enabled = interactive and Session.online
	hud.setup(b, interactive, hint, boards.size() == 1 or tall)
	huds.append(hud)
	return hud


func ui_layer() -> CanvasLayer:
	return get_node("UI")


func _ad_ok() -> bool:
	return true


func _on_ad_summon(hud: BoardHUD) -> void:
	if not hud.ad_available:
		return
	Ads.show_rewarded("match_summon", _grant_ad_summon.bind(hud))


func _on_emote(hud: BoardHUD, emote: String) -> void:
	hud.board.show_emote(emote)
	Net.send_event("emote", emote)


func _after_intro() -> void:
	Profile.mark_story_seen(Session.stage)
	paused = false
	if Session.tutorial and mode == "solo":
		_start_tutorial(ui_layer())


func _start_tutorial(ui: CanvasLayer) -> void:
	var b: Board = boards[0]
	var hud: BoardHUD = huds[0]
	paused = true
	var board_rect := func() -> Rect2:
		return Rect2(b.position + Board.GRID_ORIGIN * b.scale, Vector2(448, 448) * b.scale)
	var btn_rect := func(key: String) -> Rect2:
		return hud._btn[key].get_global_rect()
	var units := func() -> int:
		var n := 0
		for c in b.cells:
			n += c["n"]
		return n
	var header_rect := func() -> Rect2:
		return Rect2(b.position + Vector2(165, -31) * b.scale, Vector2(215, 21) * b.scale)
	var round_rect := func() -> Rect2:
		return _lbl_round.get_global_rect()
	var give_free := func():
		b.free_summons += 8
	var three_units := func() -> bool:
		return units.call() >= 3
	var merged := func() -> bool:
		return b.merges_done >= 1 or (b.free_summons == 0 and b.gold < b.summon_cost())
	var done := func():
		paused = false
		Session.tutorial = false
		Profile.mark_tutorial_done()
	var tut := Tutorial.new()
	tut.steps = [
		{"text": "적은 사각형 테두리 길을 계속 돕니다.\n필드에 적이 100마리 쌓이면 패배!", "target": header_rect},
		{"text": "소환 버튼을 눌러 유닛을 3번 뽑아보세요.\n(튜토리얼 동안 무료!)", "target": btn_rect.bind("summon"), "enter": give_free, "wait": three_units},
		{"text": "유닛은 사각형 안 칸에서 사거리 안의 적을 자동 공격해요.\n칸을 눌러 선택 → 다른 칸을 눌러 이동!", "target": board_rect},
		{"text": "같은 유닛 3마리가 한 칸에 모이면 반짝여요.\n합성 버튼으로 한 단계 높은 등급을 얻으세요!", "target": btn_rect.bind("merge"), "wait": merged},
		{"text": "보석으로 도박, 골드로 럭키 슬롯!\n잭팟이 터지면 대박 보상이 쏟아집니다.", "target": btn_rect.bind("slot")},
		{"text": "강화로 공격력을 올리고,\n재료를 모아 신화 유닛을 조합하세요.", "target": btn_rect.bind("recipe")},
		{"text": "10라운드마다 보스! 제한시간 안에 못 잡으면 바로 패배.\n남은 시간은 여기 상단에 표시됩니다.", "target": round_rect},
	]
	tut.finished.connect(done)
	ui.add_child(tut)


func _toast_achievement(e: Dictionary) -> void:
	## 화면 위쪽 업적 달성 알림 (차례로 쌓였다 사라짐)
	if _toast_box == null:
		_toast_box = VBoxContainer.new()
		_toast_box.position = Vector2(560, TOP_BAR + 60)
		_toast_box.size = Vector2(480, 0)
		_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_toast_box.add_theme_constant_override("separation", 6)
		ui_layer().add_child(_toast_box)
	var a: Dictionary = e["a"]
	var p := PanelContainer.new()
	p.theme = GameData.ui_theme()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.08, 0.02, 0.95)
	sb.border_color = Color(1, 0.8, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	p.add_child(h)
	h.add_child(UIIcon.make("trophy", 40, Color(1, 0.8, 0.3)))
	var v := VBoxContainer.new()
	var t1 := Label.new()
	t1.text = "업적 달성!  %s %s" % [a["name"], ["I", "II", "III", "IV"][e["tier"]]]
	t1.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
	t1.add_theme_font_size_override("font_size", 18)
	v.add_child(t1)
	var t2 := Label.new()
	t2.text = "%s  ·  코인 +%d" % [a["desc"] % a["goals"][e["tier"]], a["coins"][e["tier"]]]
	t2.add_theme_font_size_override("font_size", 14)
	v.add_child(t2)
	h.add_child(v)
	_toast_box.add_child(p)
	Sfx.play("win")
	var tw := create_tween()
	p.modulate.a = 0.0
	tw.tween_property(p, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.0)
	tw.tween_property(p, "modulate:a", 0.0, 0.5)
	tw.tween_callback(p.queue_free)


func _grant_ad_summon(hud: BoardHUD) -> void:
	hud.ad_available = false
	hud.board.free_summons += 3
	hud.board.show_banner("광고 보상!", "무료 소환 3회", Color(0.5, 0.8, 1.0))


func _apply_loadout() -> void:
	## 상점 아이템/영구 강화 (대전·온라인 대전 제외, 로컬 첫 번째 사람 전장에만)
	if mode == "pvp":
		return
	var target: Board = null
	for b in boards:
		if not b.is_bot and not b.is_remote:
			target = b
			break
	if target == null:
		return
	var items := Profile.take_loadout(mode)
	var notes := target.apply_loadout(items, Profile.perks, Profile.unit_levels)
	if not notes.is_empty():
		var names: Array = []
		for id in notes:
			names.append(GameData.shop_item(id)["name"])
		target.show_banner("아이템 사용", ", ".join(names), Color(0.8, 0.6, 1.0))


func _build_top_bar(ui: CanvasLayer) -> void:
	## 유즈맵 스타일 상단 바: [모드·경과시간] [ROUND · 남은 시간] [배속/일시정지/메뉴]
	var bar := PanelContainer.new()
	_top_bar = bar
	bar.theme = GameData.ui_theme()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.08, 0.18, 0.97)
	sb.border_color = Color(0.4, 0.52, 0.95, 0.7)
	sb.border_width_bottom = 3
	sb.shadow_color = Color(0, 0, 0, 0.4)
	sb.shadow_size = 6
	sb.content_margin_left = 14
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	bar.add_theme_stylebox_override("panel", sb)
	bar.position = Vector2.ZERO
	bar.size = Vector2(1600, TOP_BAR)
	ui.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	bar.add_child(h)
	_lbl_left = Label.new()
	_lbl_left.custom_minimum_size = Vector2(380, 0)
	_lbl_left.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_left.add_theme_font_size_override("font_size", 17)
	_lbl_left.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	h.add_child(_lbl_left)
	_lbl_round = Label.new()
	_lbl_round.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_round.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_lbl_round.add_theme_font_size_override("font_size", 28)
	_lbl_round.clip_text = true
	_lbl_round.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_lbl_round.add_theme_color_override("font_outline_color", Color.BLACK)
	_lbl_round.add_theme_constant_override("outline_size", 6)
	h.add_child(_lbl_round)
	var right := HBoxContainer.new()
	_top_right = right
	right.custom_minimum_size = Vector2(380, 0)
	right.alignment = BoxContainer.ALIGNMENT_END
	h.add_child(right)
	right.add_theme_constant_override("separation", 6)
	if not Session.online:
		_btn_speed = ActionButton.make("speed", Color(0.85, 0.9, 1.0), "배속", _cycle_speed, Vector2(84, 58))
		_btn_speed.badge = "x1"
		right.add_child(_btn_speed)
		_btn_pause = ActionButton.make("pause", Color(0.85, 0.9, 1.0), "일시정지 (Esc)", _toggle_pause, Vector2(70, 58))
		right.add_child(_btn_pause)
	_btn_sound = ActionButton.make("sound" if Profile.settings["sound"] else "mute", Color(0.85, 0.9, 1.0), "소리 켜기/끄기", _toggle_sound, Vector2(70, 58))
	right.add_child(_btn_sound)
	right.add_child(ActionButton.make("home", Color(0.85, 0.9, 1.0), "메인 메뉴", _to_menu, Vector2(70, 58)))
	for c in right.get_children():
		if c is ActionButton:
			c.caption = ""
			c.tone = UIKit.NAVY
			c.radius = 14


func _toggle_sound() -> void:
	Profile.set_setting("sound", not Profile.settings["sound"])
	_btn_sound.icon_name = "sound" if Profile.settings["sound"] else "mute"
	_btn_sound.queue_redraw()


func _build_center_column(ui: CanvasLayer, rect: Rect2) -> void:
	## 두 전장 사이: VS / 협동 합산 게이지 + 규칙 요약
	var v := VBoxContainer.new()
	v.theme = GameData.ui_theme()
	v.position = rect.position
	v.size = rect.size
	v.add_theme_constant_override("separation", 12)
	ui.add_child(v)
	_lbl_center = Label.new()
	_lbl_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_center.add_theme_font_size_override("font_size", 40 if mode == "pvp" else 22)
	_lbl_center.add_theme_color_override("font_color", Color(1, 0.55, 0.45) if mode == "pvp" else Color(0.6, 0.9, 1.0))
	v.add_child(_lbl_center)
	if mode == "coop":
		_coop_bar = ProgressBar.new()
		_coop_bar.max_value = GameData.COOP_ENEMY_LIMIT
		_coop_bar.show_percentage = false
		_coop_bar.custom_minimum_size = Vector2(0, 14)
		v.add_child(_coop_bar)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.size_flags_vertical = Control.SIZE_EXPAND_FILL
	help.add_theme_font_size_override("font_size", 13)
	help.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	help.text = {
		"pvp": "대전 규칙\n\n필드 적 %d마리 또는 보스 시간 초과 시 패배\n\n[공격] 탭으로 적·저주 보내기\n\n40라운드 이후 적 급성장" % GameData.ENEMY_LIMIT,
		"coop": "협동 규칙\n\n적 수 합계 %d 도달 또는 한 명이라도 보스 시간 초과 시 패배\n\n골드·유닛 선물, 합동 폭격!\n\n%d라운드 최종 보스를 둘 다 잡으면 승리" % [GameData.COOP_ENEMY_LIMIT, GameData.FINAL_WAVE],
	}.get(mode, "")
	v.add_child(help)


# ===========================================================================
# 루프
# ===========================================================================
func _process(delta: float) -> void:
	var run := not paused and not over
	var dt := delta * speed if run else 0.0
	if run:
		_time += dt
	# 고정 간격으로 쪼개서 시뮬레이션 (배속에서도 안정적)
	var steps := maxi(1, int(ceil(dt / 0.034)))
	var sdt := dt / steps
	for s in steps:
		for i in boards.size():
			boards[i].step(sdt)
			if bots[i] != null and run:
				bots[i].update(sdt)
		if run:
			_check_rules()
	if dt == 0.0:
		for b in boards:
			b.queue_redraw()
	if boards.size() == 2:
		boards[0].partner_count = boards[1].field_count() if mode == "coop" else 0
		boards[1].partner_count = boards[0].field_count() if mode == "coop" else 0
	if Session.online and not over:
		_snap_t -= delta
		if _snap_t <= 0.0:
			_snap_t = 0.1
			Net.send_snapshot(boards[Session.local_index].snapshot())
	_update_center_label()
	_update_peek()
	if not over and not paused:
		_ach_t -= delta
		if _ach_t <= 0.0:
			_ach_t = 1.0
			var me := _local_board()
			if not me.is_bot and not me.is_remote:
				for e in Profile.preview_achievements(me):
					_match_achs.append(e)
					_toast_achievement(e)


func _update_center_label() -> void:
	if _lbl_round == null:
		return
	var tsec := int(_time)
	var elapsed := "%02d:%02d" % [tsec / 60, tsec % 60]
	var total := 0
	for b in boards:
		total += b.field_count()
	match mode:
		"pvp":
			_lbl_left.text = "대전  ·  경과 %s" % elapsed
		"coop":
			_lbl_left.text = "협동  ·  경과 %s  ·  합산 %d/%d" % [elapsed, total, GameData.COOP_ENEMY_LIMIT]
		_:
			if Session.stage != "":
				var st := Story.get_stage(Session.stage)
				_lbl_left.text = "스토리 %s %s  ·  %s" % [Session.stage, st["data"]["name"], elapsed]
			else:
				_lbl_left.text = "무한 모드  ·  경과 %s" % elapsed
	if _lbl_center != null:
		_lbl_center.text = "VS" if mode == "pvp" else "합산 적\n%d / %d" % [total, GameData.COOP_ENEMY_LIMIT]
	if _coop_bar != null:
		_coop_bar.value = total
	# 라운드 / 남은 시간 (내 전장 기준)
	var b: Board = _local_board()
	var t := maxi(0, int(ceil(b.wave_timer)))
	var ts := "%02d:%02d" % [t / 60, t % 60]
	var text := ""
	var col := Color(0.95, 0.95, 1.0)
	if b.wave == 0:
		text = "게임 시작까지  %s" % ts
	elif mode != "pvp" and b.final_cleared_flag:
		text = "ROUND %s  ·  %s" % [_round_str(b), "스테이지 클리어!" if b.stage_id != "" else "최종 보스 격파!"]
		col = Color(1, 0.85, 0.35)
	elif b.is_boss_round(b.wave):
		text = "ROUND %s  ·  보스 제한시간  %s" % [_round_str(b), ts]
		col = Color(1, 0.4, 0.45)
	elif b.is_bonus_round(b.wave):
		text = "ROUND %s  ·  보너스 라운드  %s" % [_round_str(b), ts]
		col = Color(1, 0.72, 0.8)
	else:
		text = "ROUND %s  ·  %s  %s" % [_round_str(b), "남은 시간" if b.stage_id != "" and b.wave >= b.final_wave else "다음 라운드", ts]
	if b.wave_timer <= 5.0 and b.wave_timer > 0.0 and not (mode != "pvp" and b.final_cleared_flag):
		if fmod(b.wave_timer, 0.5) < 0.25:
			col = Color(1, 1, 0.4) if not b.is_boss_round(b.wave) else Color(1, 0.15, 0.15)
	if not _lbl_left.visible:
		# 좁은 상단 바(전장 옆): 짧게
		for pair in [["ROUND ", "R"], ["보스 제한시간", "보스"], ["보너스 라운드", "보너스"], ["다음 라운드  ", ""], ["남은 시간  ", ""], ["게임 시작까지", "시작"], ["  ·  ", "  "]]:
			text = text.replace(pair[0], pair[1])
	_lbl_round.text = text
	_lbl_round.add_theme_color_override("font_color", col)


func _finish_stage_win() -> void:
	## 스테이지 클리어: 보스 스테이지면 마무리 대화 후 결과
	if over:
		return
	var st := Story.get_stage(Session.stage)
	var outro: Array = st["data"].get("outro", [])
	var key := Session.stage + "_end"
	if outro.is_empty() or Profile.story_seen.has(key):
		_finish(0, "스테이지 클리어!  %s" % st["data"]["name"], false)
		return
	over = true
	var dlg := Dialogue.new()
	dlg.lines = outro
	dlg.finished.connect(_after_outro.bind(key, st["data"]["name"]))
	ui_layer().add_child(dlg)


func _after_outro(key: String, stage_name: String) -> void:
	Profile.mark_story_seen(key)
	over = false
	_finish(0, "스테이지 클리어!  %s" % stage_name, false)


func _round_str(b: Board) -> String:
	return ("%d / %d" % [b.wave, b.final_wave]) if b.stage_id != "" else str(b.wave)


func _check_rules() -> void:
	if over:
		return
	match mode:
		"coop":
			var total := 0
			for b in boards:
				total += b.field_count()
			if total >= GameData.COOP_ENEMY_LIMIT:
				for b in boards:
					b.alive = false
				_finish(-1, "패배... 합산 적 수가 한도에 도달했습니다", true)
				return
			for b in boards:
				if b.boss_failed:
					for bb in boards:
						bb.alive = false
					_finish(-1, "패배... %s 쪽 보스를 제한시간 안에 잡지 못했습니다" % b.player_name, true)
					return
			var all_clear := true
			for b in boards:
				if not b.final_cleared_flag:
					all_clear = false
			if all_clear:
				_finish(-2, "협동 승리! %d라운드 보스를 모두 격파했습니다" % GameData.FINAL_WAVE, true)
		"pvp":
			for b in boards:
				if b.alive and not b.is_remote and (b.field_count() >= b.enemy_limit or b.boss_failed):
					b.alive = false
					b.defeated.emit(b)
					if Session.online:
						Net.send_event("defeat", b.index)
			var alive_boards := boards.filter(func(b): return b.alive)
			if alive_boards.size() <= 1:
				if alive_boards.size() == 1:
					var w: Board = alive_boards[0]
					_finish(w.index, "%s 승리!" % w.player_name, true)
				else:
					_finish(-1, "무승부!", true)
		_:
			var b: Board = boards[0]
			if b.boss_failed:
				b.alive = false
				_finish(-1, "패배... ROUND %d 보스를 제한시간 안에 잡지 못했습니다" % b.wave, false)
			elif b.field_count() >= b.enemy_limit:
				b.alive = false
				_finish(-1, "패배... ROUND %d 에서 무너졌습니다" % b.wave, false)
			elif b.final_cleared_flag:
				if b.stage_id != "":
					_finish_stage_win()
				else:
					_finish(0, "승리! %d라운드를 모두 막아냈습니다" % GameData.FINAL_WAVE, false)


# ===========================================================================
# 전장 간 상호작용
# ===========================================================================
func _other(b: Board) -> Board:
	if boards.size() < 2:
		return null
	return boards[1 - b.index]


func _on_attack(b: Board, attack_id: String) -> void:
	var o := _other(b)
	if o == null:
		return
	if o.is_remote:
		Net.send_event("attack", attack_id)
	else:
		o.receive_attack(attack_id)


func _on_gift_gold(b: Board, amount: int) -> void:
	var o := _other(b)
	if o == null:
		b.gold += amount
		return
	if o.is_remote:
		Net.send_event("gold", amount)
	else:
		o.receive_gold(amount)


func _on_gift_unit(b: Board, unit_id: String) -> void:
	var o := _other(b)
	if o == null:
		b.add_unit(unit_id)
		return
	if o.is_remote:
		Net.send_event("unit", unit_id)
	else:
		o.receive_unit(unit_id)


func _on_blast(b: Board) -> void:
	b.receive_blast()
	var o := _other(b)
	if o == null:
		return
	if o.is_remote:
		Net.send_event("blast", 0)
	else:
		o.receive_blast()


func _local_board() -> Board:
	return boards[Session.local_index if Session.online else 0]


func _on_net_event(kind: String, data: Variant) -> void:
	var me := _local_board()
	match kind:
		"attack":
			me.receive_attack(str(data))
		"gold":
			me.receive_gold(int(data))
		"unit":
			me.receive_unit(str(data))
		"blast":
			me.receive_blast()
		"emote":
			for b in boards:
				if b.is_remote:
					b.show_emote(str(data))
		"defeat":
			var idx := int(data)
			if idx >= 0 and idx < boards.size():
				boards[idx].alive = false
		"gameover":
			if not over:
				var d: Dictionary = data
				_finish(int(d.get("winner", -1)), str(d.get("text", "게임 종료")), false)


func _on_net_snapshot(d: Dictionary) -> void:
	for b in boards:
		if b.is_remote:
			b.apply_snapshot(d)


func _on_net_disconnected() -> void:
	if not over:
		_finish(Session.local_index, "상대와의 연결이 끊겼습니다", false)


# ===========================================================================
# 입력
# ===========================================================================
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		for b in boards:
			var local: Vector2 = b.get_global_transform().affine_inverse() * (event as InputEventMouseMotion).position
			b.hover = Board.cell_at(local) if Rect2(0, 0, Board.SIZE, Board.SIZE).has_point(local) else -1
		return
	if event is InputEventMouseButton and event.pressed and not over:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		for b in boards:
			if b.is_bot or b.is_remote or not b.visible:
				continue
			var local: Vector2 = b.get_global_transform().affine_inverse() * mb.position
			if b.handle_click(local, mb.button_index == MOUSE_BUTTON_RIGHT):
				b.show_cursor = false
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
			for h in huds:
				if h._sheet != null:
					h.close_sheet()
					return
			_toggle_pause()
			return
		if over or paused:
			return
		for i in boards.size():
			var b: Board = boards[i]
			if b.is_bot or b.is_remote or key_sets[i] < 0:
				continue
			var sets: Array = [key_sets[i]]
			if _human_count() == 1:
				sets = [0, 1]
			for s in sets:
				if _handle_key(b, KEYS[s], key):
					get_viewport().set_input_as_handled()
					return


func _human_count() -> int:
	var c := 0
	for b in boards:
		if not b.is_bot and not b.is_remote:
			c += 1
	return c


func _handle_key(b: Board, ks: Dictionary, key: int) -> bool:
	var action := ""
	for a in ks:
		if key in ks[a]:
			action = a
			break
	if action == "":
		return false
	var c := b.cursor % Board.COLS
	var r := b.cursor / Board.COLS
	match action:
		"up":
			r = maxi(0, r - 1)
		"down":
			r = mini(Board.ROWS - 1, r + 1)
		"left":
			c = maxi(0, c - 1)
		"right":
			c = mini(Board.COLS - 1, c + 1)
		"select":
			b.select_cell(b.cursor)
		"summon":
			b.summon()
		"merge":
			if b.selected >= 0 and b.mergeable(b.selected):
				b.merge_cell(b.selected)
			else:
				b.auto_merge()
		"gamble":
			b.gamble(0)
		"combine":
			var m := b.first_combinable()
			if m != "":
				b.combine(m)
		"special":
			if mode == "pvp":
				b.request_attack("swarm")
			elif mode == "coop":
				b.request_blast()
		"sell":
			b.sell_one(b.selected)
	if action in ["up", "down", "left", "right", "select"]:
		b.cursor = r * Board.COLS + c
		b.show_cursor = true
	return true


func _cycle_speed() -> void:
	speed = {1.0: 2.0, 2.0: 3.0, 3.0: 1.0}[speed]
	_btn_speed.badge = "x%d" % int(speed)
	_btn_speed.queue_redraw()


# ---- 모바일: 뒤로 가기 / 앱 전환 (Platform 이 부름) ----
func on_back() -> bool:
	for h in huds:
		if h._sheet != null:
			h.close_sheet()
			return true
	if over:
		_to_menu()
		return true
	if Session.online:
		Platform.show_toast("대전 중에는 위쪽 메뉴 버튼으로 나갈 수 있어요")
		return true
	if not paused:
		_toggle_pause()
		Platform.show_toast("한 번 더 누르면 메인 메뉴로")
		return true
	_to_menu()
	return true


func on_app_paused() -> void:
	if not paused and not over and not Session.online:
		_toggle_pause()


func _enter_tree() -> void:
	Platform.keep_screen_on(true)


func _exit_tree() -> void:
	Platform.keep_screen_on(false)


func _toggle_pause() -> void:
	if Session.online or over:
		return
	paused = not paused
	_pause_label.visible = paused
	_btn_pause.icon_name = "play" if paused else "pause"
	_btn_pause.queue_redraw()


func _to_menu() -> void:
	_give_coins(1)
	if Session.online:
		# 매치 도중 나가면 방에서도 나가서 상대에게 알린다. 끝난 뒤라면 방에 남아 재대결 가능
		if Net.in_match:
			Net.leave_room()
	if Session.stage != "":
		get_tree().change_scene_to_file("res://scenes/Campaign.tscn")
		return
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


# ===========================================================================
# 종료 화면
# ===========================================================================
func _finish(winner: int, text: String, broadcast: bool) -> void:
	## winner: 보드 인덱스, -1 = 모두 패배, -2 = 모두 승리
	if over:
		return
	over = true
	for h in huds:
		h.close_sheet()
	if Session.online:
		if broadcast:
			Net.send_event("gameover", {"winner": winner, "text": text})
		Net.report_result(winner, _local_board().wave)
		Net.end_match()
	var won := winner == -2 or (winner >= 0 and (not Session.online or winner == Session.local_index))
	if mode == "solo":
		won = winner == 0
	_last_won = won
	Sfx.play("win" if won else "lose")
	var me := _local_board()
	var mc := Profile.match_coins_preview(_match_summary())
	_pending_coins = mc["coins"]
	_streak_bonus = mc["streak_bonus"]
	_stage_result = {}
	if Session.stage != "" and won:
		_stage_result = Profile.preview_stage(Session.stage, me.stage_stars())
	_coins_given = false
	var can_revive := not won and not Session.online and mode != "pvp"
	_build_over_panel(text, won, can_revive)


var _last_won := false
var _streak_bonus := 0.0
var _stage_result := {}


func _build_over_panel(text: String, won: bool, can_revive: bool) -> void:
	if _over_panel != null:
		_over_panel.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.size = Vector2(1600, 900)
	_over_panel = PanelContainer.new()
	_over_panel.theme = GameData.ui_theme()
	var sb: StyleBox = Art.stylebox("result_panel")
	if sb == null:
		var f := UIKit.panel_box(Color(0.08, 0.1, 0.2, 0.97), Color(1, 0.8, 0.25) if won else Color(0.9, 0.3, 0.3), 26)
		f.set_content_margin_all(26)
		f.content_margin_top = 56
		sb = f
	_over_panel.add_theme_stylebox_override("panel", sb)
	_over_panel.position = Vector2(420, 170)
	_over_panel.size = Vector2(760, 0)
	var holder := Control.new()
	holder.size = Vector2(1600, 900)
	holder.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(dim)
	if won:
		var rays := _ResultRays.new()
		rays.size = Vector2(1600, 900)
		rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(rays)
	holder.add_child(_over_panel)
	# 승리/패배 리본 (패널 위 가장자리에 걸침)
	var ribbon := PanelContainer.new()
	var rsb := UIKit.bevel(Color(1.0, 0.72, 0.12) if won else Color(0.8, 0.22, 0.25), 18, 7)
	rsb.content_margin_left = 60
	rsb.content_margin_right = 60
	ribbon.add_theme_stylebox_override("panel", rsb)
	ribbon.theme = GameData.ui_theme()
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ribbon.add_child(UIKit.label("승리!" if won else "패배", 46))
	holder.add_child(ribbon)
	var place := func():
		if not is_instance_valid(ribbon) or not is_instance_valid(_over_panel):
			return
		ribbon.size = ribbon.get_combined_minimum_size()
		ribbon.position = Vector2(800 - ribbon.size.x * 0.5, _over_panel.position.y - ribbon.size.y * 0.55)
		UIKit.pop_in(_over_panel, 0.7)
		UIKit.pop_in(ribbon, 0.4)
	place.call_deferred()
	ui_layer().add_child(holder)
	_over_panel.set_meta("holder", holder)
	# 글자가 잘 보이도록 안쪽은 어두운 판 (결과 패널 그림이 밝아도 가독성 유지)
	var inner := PanelContainer.new()
	var isb := StyleBoxFlat.new()
	isb.bg_color = Color(0.04, 0.06, 0.14, 0.86)
	isb.set_corner_radius_all(16)
	isb.set_content_margin_all(16)
	inner.add_theme_stylebox_override("panel", isb)
	_over_panel.add_child(inner)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	inner.add_child(v)
	var top := HBoxContainer.new()
	top.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(top)
	top.add_child(UIIcon.make("star" if won else "skull", 54, Color(1, 0.85, 0.3) if won else Color(1, 0.4, 0.4)))
	var title := Label.new()
	title.text = text
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.custom_minimum_size = Vector2(560, 0)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if won else Color(1, 0.5, 0.5))
	top.add_child(title)
	for b in boards:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var nm := Label.new()
		nm.text = b.player_name
		nm.custom_minimum_size = Vector2(150, 0)
		nm.add_theme_color_override("font_color", b.accent.lightened(0.3))
		nm.add_theme_font_size_override("font_size", 18)
		row.add_child(nm)
		var st := Label.new()
		st.text = "ROUND %d   처치 %d" % [b.wave, b.kills]
		st.custom_minimum_size = Vector2(190, 0)
		st.add_theme_font_size_override("font_size", 18)
		row.add_child(st)
		# MVP 유닛 초상화 3개
		for id in _mvp_ids(b):
			var ic := UnitIcon.make(id, 46)
			ic.tooltip_text = "%s  피해 %s" % [GameData.UNITS[id]["name"], _fmt(b.dmg_by_unit[id])]
			row.add_child(ic)
		v.add_child(row)
	var me := _local_board()
	if Session.stage != "":
		if won:
			var srow := HBoxContainer.new()
			srow.alignment = BoxContainer.ALIGNMENT_CENTER
			srow.add_theme_constant_override("separation", 18)
			var got: int = _stage_result.get("stars", 1)
			for k in 3:
				var ic := UIIcon.make("star", 70, Color(1, 0.85, 0.3) if k < got else Color(0.25, 0.27, 0.35))
				ic.scale = Vector2.ZERO
				ic.pivot_offset = Vector2(35, 35)
				srow.add_child(ic)
				var tw := create_tween()
				tw.tween_interval(0.25 + k * 0.35)
				tw.tween_property(ic, "scale", Vector2(1.25, 1.25), 0.15)
				tw.tween_property(ic, "scale", Vector2.ONE, 0.1)
				if k < got:
					tw.tween_callback(Sfx.play.bind("rare"))
			v.add_child(srow)
			var sr := Label.new()
			var parts: Array = []
			if _stage_result.get("first", false):
				parts.append("첫 클리어!")
			if _stage_result.get("new_stars", 0) > 0:
				parts.append("새 ★ +%d" % _stage_result["new_stars"])
			if _stage_result.get("coins", 0) > 0:
				parts.append("스테이지 보상 코인 +%d" % _stage_result["coins"])
			sr.text = "   ".join(parts) if not parts.is_empty() else "최대 적 수 %d (★2: 30 미만, ★3: 15 미만)" % me.peak_field
			sr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sr.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
			v.add_child(sr)
		else:
			v.add_child(_near_miss_label(me))
	elif not won and mode == "solo":
		v.add_child(_near_miss_label(me))
	if _streak_bonus > 0.0:
		var sk := Label.new()
		sk.text = "연승 x%d  코인 +%d%%" % [Profile.streak + 1, int(_streak_bonus * 100)]
		sk.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sk.add_theme_color_override("font_color", Color(1, 0.55, 0.3))
		sk.add_theme_font_size_override("font_size", 18)
		v.add_child(sk)
	# 성취: 경험치 / 레벨 / 최고 기록 / 이번 판 업적
	var gained := GameData.match_xp(me.wave, me.kills, won)
	var lv := Profile.level
	var cur := Profile.xp + gained
	var ups := 0
	while cur >= GameData.xp_to_next(lv):
		cur -= GameData.xp_to_next(lv)
		lv += 1
		ups += 1
	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 10)
	var lvl_lbl := Label.new()
	lvl_lbl.text = "Lv.%d" % lv
	lvl_lbl.add_theme_font_size_override("font_size", 22)
	lvl_lbl.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	xp_row.add_child(lvl_lbl)
	var bar := ProgressBar.new()
	bar.max_value = GameData.xp_to_next(lv)
	bar.value = 0
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(360, 18)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	xp_row.add_child(bar)
	var xp_lbl := Label.new()
	xp_lbl.text = "EXP +%d" % gained
	xp_row.add_child(xp_lbl)
	v.add_child(xp_row)
	create_tween().tween_property(bar, "value", float(cur), 1.2).set_ease(Tween.EASE_OUT)
	if ups > 0:
		var up := Label.new()
		up.text = "레벨 업! Lv.%d  (코인 보상)" % lv
		up.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		up.add_theme_font_size_override("font_size", 24)
		up.add_theme_color_override("font_color", Color(0.5, 0.9, 1.0))
		v.add_child(up)
	if mode != "pvp" and me.wave > int(Profile.stats.get("best_round", 0)):
		var best := Label.new()
		best.text = "최고 기록 갱신!  ROUND %d" % me.wave
		best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		best.add_theme_font_size_override("font_size", 22)
		best.add_theme_color_override("font_color", Color(1, 0.6, 0.3))
		v.add_child(best)
	if not _match_achs.is_empty():
		var ah := HBoxContainer.new()
		ah.alignment = BoxContainer.ALIGNMENT_CENTER
		ah.add_theme_constant_override("separation", 8)
		for e in _match_achs.slice(0, 6):
			var ic := UIIcon.make("trophy", 40, Color(1, 0.8, 0.3))
			ic.tooltip_text = "%s %s" % [e["a"]["name"], ["I", "II", "III"][e["tier"]]]
			ic.mouse_filter = Control.MOUSE_FILTER_PASS
			ah.add_child(ic)
		var al := Label.new()
		al.text = "업적 %d개 달성" % _match_achs.size()
		al.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
		ah.add_child(al)
		v.add_child(ah)
	# 코인 보상
	var coin_row := HBoxContainer.new()
	coin_row.alignment = BoxContainer.ALIGNMENT_CENTER
	coin_row.add_theme_constant_override("separation", 8)
	coin_row.add_child(UIIcon.make("coin", 40))
	var coin_lbl := Label.new()
	coin_lbl.text = "+%d" % _pending_coins
	coin_lbl.add_theme_font_size_override("font_size", 32)
	coin_lbl.add_theme_color_override("font_color", Color(0.85, 0.7, 1.0))
	coin_row.add_child(coin_lbl)
	v.add_child(coin_row)
	if Session.online and mode == "pvp":
		var rl := Label.new()
		rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rl.add_theme_font_size_override("font_size", 20)
		rl.text = "레이팅 %d  (집계 중...)" % Profile.rating
		v.add_child(rl)
		var on_rating := func(r: int, d: int):
			if is_instance_valid(rl):
				rl.text = "레이팅 %d  (%s%d)" % [r, "+" if d >= 0 else "", d]
				rl.add_theme_color_override("font_color", Color(0.5, 1, 0.6) if d >= 0 else Color(1, 0.5, 0.5))
		Net.rating_changed.connect(on_rating)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 14)
	v.add_child(h)
	var bsz := Vector2(120, 96)
	if can_revive:
		var feathers := Profile.item_count("revive")
		if feathers > 0:
			var use_feather := func():
				if Profile.use_item("revive"):
					_do_revive()
			var bf := ActionButton.make("revive", Color(1, 0.45, 0.55), "부활 깃털 사용", use_feather, bsz)
			bf.badge = "x%d" % feathers
			bf.glow = true
			h.add_child(bf)
		if not _ad_revive_used:
			var ad_revive := func():
				Ads.show_rewarded("match_revive", _on_ad_revive)
			var ba := ActionButton.make("revive", Color(0.35, 0.6, 1.0), "광고 보고 부활 (판당 1회)", ad_revive, bsz)
			ba.badge_icon = "ad"
			ba.badge = "부활"
			ba.glow = true
			h.add_child(ba)
	if not _ad_double_used and _pending_coins > 0:
		var bd := ActionButton.make("coin", Color.WHITE, "광고 보고 코인 2배", func(): pass, bsz)
		bd.badge_icon = "ad"
		bd.badge = "x2"
		var on_double := func():
			_ad_double_used = true
			_pending_coins *= 2
			coin_lbl.text = "+%d" % _pending_coins
			bd.disabled = true
		bd.pressed.connect(func(): Ads.show_rewarded("result_double", on_double))
		h.add_child(bd)
	if Session.stage != "" and won:
		var nxt := Story.next_stage(Session.stage)
		if nxt != "":
			var nb := ActionButton.make("play", Color(1, 0.85, 0.35), "다음 스테이지 %s" % nxt, _go_stage.bind(nxt), Vector2(170, 96))
			nb.badge = nxt
			nb.glow = true
			h.add_child(nb)
	if not Session.online:
		h.add_child(ActionButton.make("back" if Session.stage != "" else "play", Color(0.5, 1.0, 0.6), "다시 하기", _restart, bsz))
	h.add_child(ActionButton.make("home", Color(0.85, 0.9, 1.0), "방으로 (재대결)" if Session.online and Net.connected else "메인 메뉴", _to_menu, bsz))
	for c in h.get_children():
		if c is ActionButton:
			c.caption = c.tooltip_text.split("\n")[0]
			c.radius = 20
			match c.icon_name:
				"revive": c.tone = Color(0.8, 0.28, 0.42) if c.badge_icon == "" else UIKit.BLUE
				"coin": c.tone = Color(0.95, 0.65, 0.1)
				"play", "back": c.tone = UIKit.GREEN
				_: c.tone = UIKit.NAVY


func _near_miss_label(me: Board) -> Label:
	## 아깝게 졌을 때 "한 판 더" 를 부르는 문구
	var l := Label.new()
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_font_size_override("font_size", 19)
	l.add_theme_color_override("font_color", Color(1, 0.7, 0.4))
	var boss_left := -1.0
	for e in me.enemies:
		if e.is_boss:
			boss_left = e.hp_ratio()
	var tips := ["기절 유닛으로 보스 시전을 끊어보세요", "서로 다른 유닛을 모으면 시너지가 켜져요", "★3 각성은 특성이 크게 강해져요", "도감에서 유닛 레벨을 올려보세요", "상점의 부활 깃털로 한 번 더!"]
	if boss_left >= 0.0 and boss_left < 0.35:
		l.text = "아까워요! 보스 체력이 %d%%밖에 안 남았어요!
팁: %s" % [maxi(1, int(boss_left * 100)), tips[randi() % tips.size()]]
	elif me.stage_id != "" and me.wave >= me.final_wave - 1:
		l.text = "마지막 라운드까지 왔어요! 조금만 더!
팁: %s" % tips[randi() % tips.size()]
	else:
		l.text = "팁: %s" % tips[randi() % tips.size()]
	return l


func _go_stage(id: String) -> void:
	_give_coins(1)
	Campaign.start_stage(id, get_tree())


func _restart() -> void:
	_give_coins(1)
	Session.seed_value = randi()
	if Session.stage != "":
		Campaign.start_stage(Session.stage, get_tree())
		return
	get_tree().reload_current_scene()


func _on_ad_revive() -> void:
	_ad_revive_used = true
	_do_revive()


func _do_revive() -> void:
	## 패배 → 부활. 보상은 아직 지급 전이므로 버린다.
	var holder: Node = _over_panel.get_meta("holder")
	holder.queue_free()
	_over_panel = null
	_pending_coins = 0
	_ad_double_used = false
	over = false
	for b in boards:
		if not b.is_remote:
			b.revive()


func _give_coins(_mult: int) -> void:
	if _coins_given or not over:
		return
	_coins_given = true
	# 정산은 판 요약 하나로: 로컬에서 바로 반영하고, 온라인 경제면 서버가 같은 요약을 검증해 덮어쓴다
	var s := _match_summary()
	Profile.apply_match_end(s)
	Profile.sync("match_end", [s])


func _match_summary() -> Dictionary:
	## 로컬 사람 전장 기준 판 요약 (서버로 보내는 형식과 같음)
	var me := _local_board()
	var ob: Array = []
	for b in boards:
		if not b.is_bot and not b.is_remote:
			for id in b.obtained.keys():
				if not id in ob:
					ob.append(id)
	return {
		"mode": mode, "stage": Session.stage, "online": Session.online, "won": _last_won,
		"wave": me.wave, "kills": me.kills, "stars": me.stage_stars() if _last_won else 0,
		"merges_done": me.merges_done, "mythics_done": me.mythics_done, "bosses_killed": me.bosses_killed,
		"interrupts": me.interrupts, "slot_jackpots": me.slot_jackpots, "best_combo": me.best_combo,
		"max_star": me.max_star, "obtained": ob, "ad_double": _ad_double_used,
	}


func _mvp_ids(b: Board) -> Array:
	var ids: Array = b.dmg_by_unit.keys()
	ids.sort_custom(func(x, y): return b.dmg_by_unit[x] > b.dmg_by_unit[y])
	return ids.slice(0, 3)


func _mvp(b: Board) -> String:
	if b.dmg_by_unit.is_empty():
		return ""
	var ids: Array = b.dmg_by_unit.keys()
	ids.sort_custom(func(x, y): return b.dmg_by_unit[x] > b.dmg_by_unit[y])
	var parts: Array = []
	for i in mini(3, ids.size()):
		parts.append("%s %s" % [GameData.UNITS[ids[i]]["name"], _fmt(b.dmg_by_unit[ids[i]])])
	return ", ".join(parts)


func _fmt(v: float) -> String:
	if v >= 1000000.0:
		return "%.1fM" % (v / 1000000.0)
	if v >= 1000.0:
		return "%.1fK" % (v / 1000.0)
	return str(int(v))


class _ResultRays:
	extends Control
	## 승리 화면 뒤에서 도는 빛
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(800, 420)
		for i in 16:
			var a0 := t * 0.25 + i * TAU / 16.0
			draw_colored_polygon(PackedVector2Array([c, c + Vector2.from_angle(a0) * 1000, c + Vector2.from_angle(a0 + 0.1) * 1000]), Color(1, 0.85, 0.35, 0.07))
