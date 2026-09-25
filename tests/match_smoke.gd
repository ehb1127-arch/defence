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


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "pvp"
	_dur = float(args[1]) if args.size() > 1 else 30.0
	_shots = args[2] if args.size() > 2 else ""
	Engine.time_scale = float(args[3]) if args.size() > 3 else 1.0
	if mode == "menu":
		_match = load("res://scenes/Main.tscn").instantiate()
		add_child(_match)
		return
	var players: Array = [{"name": "플레이어", "kind": "human", "keys": 0}]
	if mode != "solo":
		players.append({"name": "AI", "kind": "bot", "keys": -1})
	Session.setup_local(mode, players)
	Session.seed_value = 42
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
	if Session.mode == "menu" or not "boards" in _match:
		if _t > 1.0:
			_done = true
			get_viewport().get_texture().get_image().save_png("%s/menu.png" % _shots)
			_match._show_help()
			await get_tree().process_frame
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/help.png" % _shots)
			get_tree().quit()
		return
	if _shots != "" and _t >= _next_shot:
		_next_shot += maxf(4.0, _dur / 4.0)
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/shot_%d.png" % [_shots, _shot_i])
		_shot_i += 1
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
	if _t >= _dur or _match.over:
		_done = true
		var b: Board = _match.boards[0]
		print("SMOKE %s wave=%d kills=%d over=%s" % [Session.mode, b.wave, b.kills, _match.over])
		if _shots != "" and _match.over:
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("%s/shot_end.png" % _shots)
		get_tree().quit()
