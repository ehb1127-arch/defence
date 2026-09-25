extends Node
## 온라인 테스트: 두 프로세스를 띄워 한쪽은 호스트, 한쪽은 참가.
## godot --headless res://tests/NetTest.tscn -- host pvp 20
## godot --headless res://tests/NetTest.tscn -- join pvp 20

var _role := "host"
var _dur := 20.0
var _t := 0.0
var _botted := false
var _done := false
var is_helper := false


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	_role = args[0] if args.size() > 0 else "host"
	var mode := args[1] if args.size() > 1 else "pvp"
	_dur = float(args[2]) if args.size() > 2 else 20.0
	if not is_helper:
		# 씬 전환 때 현재 씬(자기 자신)이 해제되므로, 루트에 도우미 노드를 따로 둔다
		var h: Node = load("res://tests/net_test.gd").new()
		h.is_helper = true
		get_tree().root.add_child.call_deferred(h)
		return
	Engine.time_scale = 4.0
	Session.player_name = "호스트" if _role == "host" else "게스트"
	if _role == "host":
		Net.guest_joined.connect(func(_n): Net.start_match())
		print("host:", Net.host(Net.DEFAULT_PORT + 7, mode))
	else:
		await get_tree().create_timer(1.0).timeout
		print("join:", Net.join("127.0.0.1", Net.DEFAULT_PORT + 7))


func _process(delta: float) -> void:
	if _done or not is_helper:
		return
	_t += delta / Engine.time_scale
	var m := get_tree().current_scene
	if m != null and "boards" in m and not m.boards.is_empty() and not _botted:
		_botted = true
		var me: Board = m.boards[Session.local_index]
		m.bots[Session.local_index] = BotBrain.new(me, m.boards[1 - Session.local_index], 2)
		print(_role, " match started, local_index=", Session.local_index, " mode=", Session.mode)
	if _t >= _dur:
		_done = true
		if m != null and "boards" in m:
			for b in m.boards:
				print("%s sees board%d remote=%s wave=%d gold=%d kills=%d field=%d units=%d alive=%s" % [
					_role, b.index, b.is_remote, b.wave, b.gold, b.kills, b.field_count(), b.used_cells(), b.alive])
			print(_role, " over=", m.over)
		get_tree().quit()
