extends Node
## Match 씬(UI 포함) 스모크 테스트. 봇이 조작하는 게임을 빠르게 돌리며
## 사람 쪽 HUD 도 함께 갱신되는지, 런타임 오류가 없는지 확인한다.
## 실행: godot res://tests/MatchSmoke.tscn -- <mode> <초> [스크린샷 폴더]

var _match: Node
var _shots := ""
var _dur := 30.0
var _t := 0.0
var _shot_i := 0
var _next_shot := 2.0
var _done := false
var _stage_mode := false
var _stage_step := 0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "pvp"
	_dur = float(args[1]) if args.size() > 1 else 30.0
	_shots = args[2] if args.size() > 2 else ""
	Engine.time_scale = float(args[3]) if args.size() > 3 else 1.0
	process_mode = Node.PROCESS_MODE_ALWAYS
	if mode == "campaign":
		Profile.campaign = {"1-1": 3, "1-2": 2, "1-3": 1}
		_match = load("res://scenes/Campaign.tscn").instantiate()
		add_child(_match)
		return
	if mode.begins_with("stage"):
		var sid := mode.substr(5)
		Session.setup_local("solo", [{"name": "플레이어", "kind": "human", "keys": 0}])
		Session.stage = sid
		Session.seed_value = 7
		Profile.story_seen.erase(sid)
		Profile.story_seen.erase(sid + "_end")
		Profile.tutorial_done = true
		_match = load("res://scenes/Match.tscn").instantiate()
		add_child(_match)
		_match.speed = 3.0
		_stage_mode = true
		return
	if mode in ["rewards", "collection"]:
		Session.mode = mode
		Profile.coins = maxi(Profile.coins, 2000)
		Profile.discover(["sword", "archer", "knight", "storm", "dragoon", "phoenix"])
		Profile.add_progress("play", 3)
		_match = load("res://scenes/%s.tscn" % mode.capitalize()).instantiate()
		add_child(_match)
		return
	if mode == "shop":
		_match = load("res://scenes/Shop.tscn").instantiate()
		add_child(_match)
		return
	if mode == "menu":
		_match = load("res://scenes/Main.tscn").instantiate()
		add_child(_match)
		return
	var players: Array = [{"name": "플레이어", "kind": "human", "keys": 0}]
	if mode != "solo":
		players.append({"name": "AI", "kind": "bot", "keys": -1})
	Session.setup_local(mode, players)
	Session.seed_value = 42
	Session.tutorial = OS.get_cmdline_user_args().has("tutorial")
	_match = load("res://scenes/Match.tscn").instantiate()
	add_child(_match)
	_match.speed = 3.0
	# 사람 자리도 봇이 대신 조작 (HUD 는 사람용으로 유지)
	var b0: Board = _match.boards[0]
	_match.bots[0] = BotBrain.new(b0, _match.boards[1] if _match.boards.size() > 1 else null, 2)


func _process(delta: float) -> void:
	if _done:
		return
	_t += delta / Engine.time_scale
	if not "boards" in _match and _match.has_method("_launch"):
		if _t > 1.0:
			_done = true
			get_viewport().get_texture().get_image().save_png("%s/campaign.png" % _shots)
			get_tree().quit()
		return
	if not "boards" in _match and (_match.has_method("_spin") or _match.has_method("_level_up")):
		if _t > 1.0 and _shot_i == 0:
			_shot_i = 1
			get_viewport().get_texture().get_image().save_png("%s/%s_0.png" % [_shots, Session.mode])
			if _match.has_method("_spin"):
				_match._spin(false)
			else:
				_match._select("storm")
				_match._level_up()
		elif _t > 3.0 and _shot_i == 1:
			_shot_i = 2
			get_viewport().get_texture().get_image().save_png("%s/%s_1.png" % [_shots, Session.mode])
		elif _t > 6.0 and _shot_i == 2:
			_done = true
			get_viewport().get_texture().get_image().save_png("%s/%s_2.png" % [_shots, Session.mode])
			get_tree().quit()
		return
	if not "boards" in _match and _match.has_method("toast"):
		# 상점: 탭별 캡처 + 광고 보상 흐름
		if _t > 1.0 and _shot_i == 0:
			_shot_i = 1
			get_viewport().get_texture().get_image().save_png("%s/shop_items.png" % _shots)
			_match._show("perks")
		elif _t > 1.5 and _shot_i == 1:
			_shot_i = 2
			get_viewport().get_texture().get_image().save_png("%s/shop_perks.png" % _shots)
			_match._show("free")
			_match._watch_ad_coins()
		elif _t > 2.5 and _shot_i == 2:
			_shot_i = 3
			get_viewport().get_texture().get_image().save_png("%s/shop_ad.png" % _shots)
			Ads.auto_claim = true
			_match._watch_ad_item()
		elif _t > 3.5 and _shot_i == 3:
			_done = true
			get_viewport().get_texture().get_image().save_png("%s/shop_ad_done.png" % _shots)
			print("SMOKE shop coins=", Profile.coins)
			get_tree().quit()
		return
	if Session.mode == "menu" or not "boards" in _match:
		# 메뉴: 1초 후 캡처 → 로컬 서버(24693)에 접속해 방 만들기 → 캡처 → 도움말 캡처
		if _t > 1.0 and _shot_i == 0:
			_shot_i = 1
			get_viewport().get_texture().get_image().save_png("%s/menu.png" % _shots)
			Session.player_name = "테스터"
			Net.connect_to("127.0.0.1:24693")
			Net.connection_changed.connect(func(c): if c: Net.create_room("pvp", "같이 하실 분"))
		elif _t > 4.0 and _shot_i == 1:
			_shot_i = 2
			get_viewport().get_texture().get_image().save_png("%s/lobby.png" % _shots)
			_match._show_help()
		elif _t > 4.5 and _shot_i == 2:
			_done = true
			get_viewport().get_texture().get_image().save_png("%s/help.png" % _shots)
			get_tree().quit()
		return
	if _stage_mode:
		_stage_capture()
		return
	if OS.get_cmdline_user_args().has("fx2"):
		_fx2_capture()
		return
	if OS.get_cmdline_user_args().has("fx"):
		_fx_capture()
		return
	if _shots != "" and _t >= _next_shot:
		_next_shot += maxf(4.0, _dur / 4.0)
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%d.png" % [_shots, _shot_i])
		_shot_i += 1
		if _match.huds.size() > 0 and _match.huds[0].interactive:
			var kinds := ["slot", "recipe", "upgrade", "attack" if Session.mode == "pvp" else ("coop" if Session.mode == "coop" else "mission")]
			_match.huds[0]._toggle_sheet(kinds[_shot_i % kinds.size()])
			if kinds[_shot_i % kinds.size()] == "slot":
				_match.boards[0].gold += 500
				_match.boards[0].slot_spin(0)
		var b0: Board = _match.boards[0]
		for i in b0.cells.size():
			if b0.cells[i]["id"] != "":
				b0.selected = i
				break
	# 키보드 조작 경로도 확인: 커서 이동/선택/소환/합성 키를 번갈아 입력
	if Engine.get_process_frames() % 20 == 0:
		var keys := [KEY_D, KEY_S, KEY_SPACE, KEY_Q, KEY_E, KEY_T, KEY_F, KEY_SPACE, KEY_RIGHT, KEY_U]
		var ev := InputEventKey.new()
		ev.keycode = keys[(Engine.get_process_frames() / 20) % keys.size()]
		ev.pressed = true
		Input.parse_input_event(ev)
	if _t >= _dur and not _match.over and OS.get_cmdline_user_args().has("defeat"):
		# 결과 화면 확인용 강제 패배
		_match.boards[0].boss_failed = true
		return
	if _t >= _dur or _match.over:
		_done = true
		var b: Board = _match.boards[0]
		print("SMOKE %s wave=%d kills=%d over=%s" % [Session.mode, b.wave, b.kills, _match.over])
		if _shots != "" and _match.over:
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/shot_end.png" % _shots)
		get_tree().quit()


var _fx_step := 0


func _fx_capture() -> void:
	## 슬롯 회전 중 / 결과 / 가챠 연출 중간 캡처
	var b0: Board = _match.boards[0]
	var shot := func(name: String):
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])
	if _fx_step == 0 and _t > 1.0:
		_fx_step = 1
		_match.speed = 1.0
		Engine.time_scale = 1.0
		b0.gold += 2000
		_match.huds[0]._toggle_sheet("slot")
		b0.slot_spin(1)
	elif _fx_step == 1 and _t > 1.6:
		_fx_step = 2
		shot.call("slot_spinning")
	elif _fx_step == 2 and _t > 3.4:
		_fx_step = 3
		shot.call("slot_result")
		_match.huds[0].close_sheet()
		var idx := b0.add_unit("dragoon")
		b0._rare_pull_fx(idx, 3)
	elif _fx_step == 3 and _t > 3.9:
		_fx_step = 4
		shot.call("reveal")
		for k in 30:
			b0._kill(b0._spawn("normal", 1.0, 0.0))
	elif _fx_step == 4 and _t > 4.2:
		_fx_step = 5
		shot.call("combo")
		_done = true
		get_tree().quit()


var _fx2_step := 0


func _fx2_capture() -> void:
	## ★/각성/시너지 + 보스 시전 + 업적 토스트 + 결과 화면
	var b0: Board = _match.boards[0]
	var shot := func(name: String):
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])
	if _fx2_step == 0 and _t > 6.0:
		_fx2_step = 1
		_match.speed = 1.0
		Engine.time_scale = 1.0
		_match.bots[0] = null
		var ids := ["knight", "sniper", "storm", "pyro", "frost", "archmage", "ranger", "bard"]
		for k in ids.size():
			var c := b0._empty_cell()
			c["id"] = ids[k]
			c["n"] = 2
			c["star"] = [1, 2, 3, 5, 0, 4, 3, 0][k]
			b0.cells[7 + k + (2 if k >= 4 else 0)] = c
		b0.selected = 10
		b0._start_wave(10)
		for e in b0.enemies:
			if e.is_boss:
				e.skill_cd[0] = 0.1
				e.skill_cd[1] = 99.0
	elif _fx2_step == 1 and _t > 6.6:
		_fx2_step = 2
		shot.call("boss_cast")
		_match._toast_achievement({"a": GameData.ACHIEVEMENTS[2], "tier": 1})
		b0.gold += 500
		b0.upgrade(0)
	elif _fx2_step == 2 and _t > 7.4:
		_fx2_step = 3
		shot.call("stars_toast")
		b0.boss_failed = true
	elif _fx2_step == 3 and _t > 9.5:
		_fx2_step = 4
		shot.call("result")
		_done = true
		get_tree().quit()



func _stage_capture() -> void:
	## 스토리 스테이지: 대화 캡처 → 대화 넘기고 봇 플레이 → 결과(또는 마무리 대화) 캡처
	var shot := func(name: String):
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [_shots, name])
	var ui: Node = _match.get_node("UI")
	if _stage_step == 0 and _t > 1.2:
		_stage_step = 1
		shot.call("dialogue")
		for c in ui.get_children():
			if c is Dialogue:
				c._finish()
		_match.bots[0] = BotBrain.new(_match.boards[0], null, 2)
	elif _stage_step == 1 and _match.over:
		_stage_step = 2
		_t = 0.0
	elif _stage_step == 2 and _t > 1.0:
		_stage_step = 3
		shot.call("stage_end")
		for c in ui.get_children():
			if c is Dialogue:
				c._finish()
		_t = 0.0
	elif _stage_step == 3 and _t > 2.0:
		shot.call("stage_result")
		print("SMOKE stage wave=%d peak=%d stars=%d" % [_match.boards[0].wave, _match.boards[0].peak_field, _match.boards[0].stage_stars()])
		_done = true
		get_tree().quit()
