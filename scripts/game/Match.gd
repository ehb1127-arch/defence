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
	_layout(ui)
	if Session.online:
		Net.event_received.connect(_on_net_event)
		Net.snapshot_received.connect(_on_net_snapshot)
		Net.disconnected.connect(_on_net_disconnected)


func _layout(ui: CanvasLayer) -> void:
	var n := boards.size()
	var human_count := 0
	for p in Session.players:
		if p["kind"] == "human":
			human_count += 1
	if n == 1:
		var b: Board = boards[0]
		b.position = Vector2(30, 30)
		b.scale = Vector2(1.5, 1.5)
		var hud := _make_hud(0, human_count)
		hud.position = Vector2(900, 110)
		hud.size = Vector2(670, 760)
		ui.add_child(hud)
		_build_controls(ui, Rect2(900, 20, 670, 80), false)
	else:
		for i in n:
			var b: Board = boards[i]
			b.position = Vector2(110 + i * 800, 12)
			b.scale = Vector2(1.03, 1.03)
			var hud := _make_hud(i, human_count)
			hud.position = Vector2(15 + i * 800, 604)
			hud.size = Vector2(770, 286)
			ui.add_child(hud)
		_build_controls(ui, Rect2(700, 20, 200, 560), true)


func _make_hud(i: int, human_count: int) -> BoardHUD:
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
	hud.setup(b, interactive, hint, boards.size() == 1)
	huds.append(hud)
	return hud


func _build_controls(ui: CanvasLayer, rect: Rect2, vertical: bool) -> void:
	var box: BoxContainer = VBoxContainer.new() if vertical else HBoxContainer.new()
	box.theme = GameData.ui_theme()
	box.position = rect.position
	box.size = rect.size
	box.add_theme_constant_override("separation", 10)
	ui.add_child(box)
	_lbl_center = Label.new()
	_lbl_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_center.add_theme_font_size_override("font_size", 28 if vertical else 20)
	_lbl_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(_lbl_center)
	if not Session.online:
		_btn_speed = Button.new()
		_btn_speed.text = "배속 x1"
		_btn_speed.focus_mode = Control.FOCUS_NONE
		_btn_speed.custom_minimum_size = Vector2(110, 44)
		_btn_speed.pressed.connect(_cycle_speed)
		box.add_child(_btn_speed)
		_btn_pause = Button.new()
		_btn_pause.text = "일시정지 (Esc)"
		_btn_pause.focus_mode = Control.FOCUS_NONE
		_btn_pause.custom_minimum_size = Vector2(110, 44)
		_btn_pause.pressed.connect(_toggle_pause)
		box.add_child(_btn_pause)
	var quit := Button.new()
	quit.text = "메인 메뉴"
	quit.focus_mode = Control.FOCUS_NONE
	quit.custom_minimum_size = Vector2(110, 44)
	quit.pressed.connect(_to_menu)
	box.add_child(quit)
	if vertical:
		var help := Label.new()
		help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		help.add_theme_font_size_override("font_size", 12)
		help.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
		help.text = {
			"pvp": "대전 규칙\n\n각자 자기 사각형을 지킵니다. 필드 적이 %d마리에 닿으면 패배.\n\n[공격] 탭에서 상대에게 적과 저주를 보내세요!\n\n40웨이브 이후엔 적이 급격히 강해집니다." % GameData.ENEMY_LIMIT,
			"coop": "협동 규칙\n\n두 전장의 적 수 합이 %d에 닿으면 함께 패배.\n\n골드·유닛을 선물하고, 게이지를 모아 합동 폭격!\n\n둘 다 %d웨이브 보스를 잡으면 승리." % [GameData.COOP_ENEMY_LIMIT, GameData.FINAL_WAVE],
		}.get(mode, "")
		box.add_child(help)
	_pause_label = Label.new()
	_pause_label.text = "일시정지"
	_pause_label.add_theme_font_size_override("font_size", 64)
	_pause_label.position = Vector2(600, 380)
	_pause_label.size = Vector2(400, 100)
	_pause_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_label.visible = false
	ui.add_child(_pause_label)


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


func _update_center_label() -> void:
	if _lbl_center == null:
		return
	var tsec := int(_time)
	var ts := "%02d:%02d" % [tsec / 60, tsec % 60]
	match mode:
		"pvp":
			_lbl_center.text = "VS\n" + ts
		"coop":
			var total := 0
			for b in boards:
				total += b.field_count()
			_lbl_center.text = "협동\n%s\n%d/%d" % [ts, total, GameData.COOP_ENEMY_LIMIT]
		_:
			_lbl_center.text = "솔로  " + ts


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
			var all_clear := true
			for b in boards:
				if not b.final_cleared_flag:
					all_clear = false
			if all_clear:
				_finish(-2, "협동 승리! %d웨이브 보스를 모두 격파했습니다" % GameData.FINAL_WAVE, true)
		"pvp":
			for b in boards:
				if b.alive and not b.is_remote and b.field_count() >= b.enemy_limit:
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
			if b.field_count() >= b.enemy_limit:
				b.alive = false
				_finish(-1, "패배... WAVE %d 에서 무너졌습니다" % b.wave, false)
			elif b.final_cleared_flag:
				_finish(0, "승리! %d웨이브를 모두 막아냈습니다" % GameData.FINAL_WAVE, false)


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
	return boards[Session.local_index]


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
	if event is InputEventMouseButton and event.pressed and not over:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT and mb.button_index != MOUSE_BUTTON_RIGHT:
			return
		for b in boards:
			if b.is_bot or b.is_remote:
				continue
			var local: Vector2 = b.get_global_transform().affine_inverse() * mb.position
			if b.handle_click(local, mb.button_index == MOUSE_BUTTON_RIGHT):
				b.show_cursor = false
				get_viewport().set_input_as_handled()
				return
	elif event is InputEventKey and event.pressed and not event.echo:
		var key: int = (event as InputEventKey).keycode
		if key == KEY_ESCAPE:
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
	_btn_speed.text = "배속 x%d" % int(speed)


func _toggle_pause() -> void:
	if Session.online or over:
		return
	paused = not paused
	_pause_label.visible = paused


func _to_menu() -> void:
	if Session.online:
		Net.close()
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


# ===========================================================================
# 종료 화면
# ===========================================================================
func _finish(winner: int, text: String, broadcast: bool) -> void:
	## winner: 보드 인덱스, -1 = 모두 패배, -2 = 모두 승리
	if over:
		return
	over = true
	if Session.online and broadcast:
		Net.send_event("gameover", {"winner": winner, "text": text})
	var won := winner == -2 or (winner >= 0 and (not Session.online or winner == Session.local_index))
	if mode == "solo":
		won = winner == 0
	_over_panel = PanelContainer.new()
	_over_panel.theme = GameData.ui_theme()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.96)
	sb.border_color = Color(1, 0.85, 0.3) if won else Color(0.9, 0.3, 0.3)
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(24)
	_over_panel.add_theme_stylebox_override("panel", sb)
	_over_panel.position = Vector2(450, 230)
	_over_panel.size = Vector2(700, 0)
	get_node("UI").add_child(_over_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_over_panel.add_child(v)
	var title := Label.new()
	title.text = text
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.3) if won else Color(1, 0.45, 0.45))
	v.add_child(title)
	for b in boards:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.add_theme_font_size_override("font_size", 16)
		var s := "%s  -  WAVE %d / 처치 %d / 골드 %d / 과제 %d개" % [b.player_name, b.wave, b.kills, b.gold, b.missions.size()]
		var mvp := _mvp(b)
		if mvp != "":
			s += "\n   MVP: " + mvp
		l.text = s
		v.add_child(l)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	if not Session.online:
		var again := Button.new()
		again.text = "다시 하기"
		again.custom_minimum_size = Vector2(160, 48)
		again.pressed.connect(func():
			Session.seed_value = randi()
			get_tree().reload_current_scene())
		h.add_child(again)
	var menu := Button.new()
	menu.text = "메인 메뉴"
	menu.custom_minimum_size = Vector2(160, 48)
	menu.pressed.connect(_to_menu)
	h.add_child(menu)


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
