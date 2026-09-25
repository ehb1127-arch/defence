extends Node
## 온라인 테스트. 전용 서버 + 클라이언트 2개, 또는 LAN 호스트 + 게스트.
##   서버:   godot --headless res://scenes/Main.tscn -- --server --port 24690
##   빠른매칭: godot --headless res://tests/NetTest.tscn -- quick pvp 20 127.0.0.1:24690
##   LAN:   godot --headless res://tests/NetTest.tscn -- lanhost coop 20 24690
##          godot --headless res://tests/NetTest.tscn -- languest coop 20 127.0.0.1:24690

var is_helper := false
var _role := "quick"
var _mode := "pvp"
var _dur := 20.0
var _t := 0.0
var _botted := false
var _done := false
var _events := {}


func _ready() -> void:
	if not is_helper:
		# 씬 전환 때 현재 씬(자기 자신)이 해제되므로, 루트에 도우미 노드를 따로 둔다
		var h: Node = load("res://tests/net_test.gd").new()
		h.is_helper = true
		get_tree().root.add_child.call_deferred(h)
		return
	var args := OS.get_cmdline_user_args()
	_role = args[0] if args.size() > 0 else "quick"
	_mode = args[1] if args.size() > 1 else "pvp"
	_dur = float(args[2]) if args.size() > 2 else 20.0
	var target: String = args[3] if args.size() > 3 else "127.0.0.1:24690"
	Engine.time_scale = 4.0
	Session.player_name = _role + str(randi() % 100)
	Net.status_changed.connect(func(t): print(_role, " status: ", t))
	Net.error_received.connect(func(t): print(_role, " ERROR: ", t))
	Net.event_received.connect(func(k, _d): _events[k] = _events.get(k, 0) + 1)
	match _role:
		"quick":
			Net.connection_changed.connect(func(c): if c: Net.quick_match(_mode))
			Net.connect_to(target)
		"lanhost":
			Net.host_lan(int(target))
			Net.create_room(_mode, "테스트 방")
			Net.room_updated.connect(func(r): if r.get("members", []).size() == 2 and not r.get("playing", false): Net.start_match())
		"languest":
			Net.rooms_updated.connect(func(list): if not list.is_empty() and Net.room.is_empty(): Net.join_room(list[0]["id"]))
			Net.connect_to(target)


func _process(delta: float) -> void:
	if _done or not is_helper:
		return
	_t += delta / Engine.time_scale
	var m := get_tree().current_scene
	if m != null and "boards" in m and not m.boards.is_empty() and not _botted:
		_botted = true
		var me: Board = m.boards[Session.local_index]
		m.bots[Session.local_index] = BotBrain.new(me, m.boards[1 - Session.local_index], 2)
		# 양방향 이벤트 전달 확인용
		Net.send_event("gold", 1)
		print(_role, " match started, local_index=", Session.local_index, " mode=", Session.mode, " names=", Session.players.map(func(p): return p["name"]))
	if OS.get_cmdline_user_args().has("lose") and _botted and _t >= _dur - 6.0 and m != null and "boards" in m and not m.over:
		# 결과 보고 경로 확인: 이쪽이 보스 실패로 패배
		m.boards[Session.local_index].boss_failed = true
	if _t >= _dur:
		_done = true
		var args := OS.get_cmdline_user_args()
		if args.size() > 4 and args[4].ends_with(".png") and DisplayServer.get_name() != "headless":
			get_viewport().get_texture().get_image().save_png(args[4])
		if m != null and "boards" in m:
			for b in m.boards:
				print("%s sees board%d remote=%s wave=%d gold=%d kills=%d field=%d units=%d alive=%s" % [
					_role, b.index, b.is_remote, b.wave, b.gold, b.kills, b.field_count(), b.used_cells(), b.alive])
			print(_role, " over=", m.over, " events=", _events, " record=", Net.my_record)
		else:
			print(_role, " NO MATCH")
		get_tree().quit()
