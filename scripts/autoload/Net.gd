extends Node
## 온라인 (WebSocket).
##
## 한 스크립트가 세 가지 역할을 한다.
##  - 전용 서버 : `godot --headless --path . -- --server [--port N]`
##               방 목록/생성/참가/빠른 매칭 + 같은 방 두 사람 사이 메시지 중계
##  - LAN 호스트: 플레이어 한 명이 서버를 겸한다 (peer id 1 = 서버이자 플레이어)
##  - 클라이언트: 서버에 접속해서 방에 들어가 게임
##
## 게임 계산은 각 클라이언트가 자기 전장만 한다. 서버는 스냅샷(표시용)과
## 이벤트(적 보내기/선물/폭격/패배)를 같은 방 상대에게 전달만 한다.
##
## 메시지 명세: docs/PROTOCOL.md

signal status_changed(text: String)
signal connection_changed(connected: bool)
signal rooms_updated(rooms: Array)
signal room_updated(room: Dictionary)          # {} = 방 없음
signal error_received(msg: String)
signal disconnected                            # 매치 중 상대 이탈 또는 서버 끊김
signal event_received(kind: String, data: Variant)
signal snapshot_received(data: Dictionary)

const DEFAULT_PORT := 24680
const PROTOCOL := 1
const MAX_ROOMS := 200
const MAX_NAME := 12
const SETTINGS_PATH := "user://online.cfg"
## 배포용 기본 서버 주소. OCI 서버를 만든 뒤 여기에 공인 IP(또는 wss://도메인)를 넣고
## 클라이언트를 빌드하면, 플레이어는 주소 입력 없이 [접속]만 누르면 된다.
const DEFAULT_SERVER := "127.0.0.1"

var peer: WebSocketMultiplayerPeer
var is_server := false          # 이 프로세스가 서버 로직을 수행
var dedicated := false          # 플레이어 없는 전용 서버
var connected := false          # (클라이언트로서) 서버와 인사까지 끝남
var my_id := 0
var room: Dictionary = {}       # 내가 들어간 방 (클라이언트 시점)
var rooms: Array = []           # 마지막으로 받은 방 목록
var in_match := false
var server_address := normalize_address(DEFAULT_SERVER)

# ---- 서버 상태 ----
var _names := {}                # peer_id -> 이름
var _rooms := {}                # room_id -> {id, name, mode, owner, members, playing, quick}
var _peer_room := {}            # peer_id -> room_id
var _next_room := 1
var _local_sender := 0          # LAN 호스트가 자기 서버 함수를 직접 부를 때의 보낸 사람


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_load_settings()
	var args := OS.get_cmdline_user_args()
	if "--server" in args or OS.has_feature("dedicated_server"):
		var port := DEFAULT_PORT
		var i := args.find("--port")
		if i >= 0 and i + 1 < args.size():
			port = int(args[i + 1])
		start_dedicated.call_deferred(port)


# ===========================================================================
# 공개 API (메뉴 / Match 에서 사용)
# ===========================================================================
func start_dedicated(port: int) -> Error:
	var err := _listen(port)
	if err != OK:
		push_error("서버 시작 실패: 포트 %d (오류 %d)" % [port, err])
		get_tree().quit(1)
		return err
	dedicated = true
	_log("전용 서버 시작 - 포트 %d, 프로토콜 %d" % [port, PROTOCOL])
	return OK


func host_lan(port: int) -> Error:
	## 이 PC 에서 서버를 열고 나도 플레이어로 참가
	var err := _listen(port)
	if err != OK:
		status_changed.emit("서버 열기 실패 (포트 %d, 오류 %d)" % [port, err])
		return err
	dedicated = false
	my_id = 1
	_names[1] = _clean_name(Session.player_name)
	connected = true
	connection_changed.emit(true)
	status_changed.emit("이 PC 에서 서버 실행 중 (포트 %d). 친구는 내 IP 로 접속하세요." % port)
	_send_rooms(1)
	return OK


func connect_to(address: String) -> Error:
	close()
	var url := normalize_address(address)
	server_address = url
	_save_settings()
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_client(url)
	if err != OK:
		peer = null
		status_changed.emit("접속 실패 (%s, 오류 %d)" % [url, err])
		return err
	multiplayer.multiplayer_peer = peer
	(multiplayer as SceneMultiplayer).server_relay = false
	status_changed.emit("%s 접속 중..." % url)
	return OK


func close() -> void:
	if peer != null:
		peer.close()
	peer = null
	var was := connected
	is_server = false
	dedicated = false
	connected = false
	in_match = false
	my_id = 0
	room = {}
	rooms = []
	_names.clear()
	_rooms.clear()
	_peer_room.clear()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if was:
		connection_changed.emit(false)
		room_updated.emit({})


func is_active() -> bool:
	## 매치 중이고 상대와 연결되어 있음
	return connected and in_match


static func normalize_address(address: String) -> String:
	var a := address.strip_edges()
	if a == "":
		a = "127.0.0.1"
	if not (a.begins_with("ws://") or a.begins_with("wss://")):
		a = "ws://" + a
	# 포트가 없으면 기본 포트 (wss 는 리버스 프록시 뒤라고 보고 그대로 둔다)
	var host_part := a.split("://")[1].split("/")[0]
	if a.begins_with("ws://") and not ":" in host_part:
		a = a.replace(host_part, "%s:%d" % [host_part, DEFAULT_PORT])
	return a


func request_rooms() -> void:
	_to_server("_s_list", [])


func create_room(p_mode: String, room_name: String) -> void:
	_to_server("_s_create", [p_mode, room_name, false])


func join_room(room_id: int) -> void:
	_to_server("_s_join", [room_id])


func quick_match(p_mode: String) -> void:
	_to_server("_s_quick", [p_mode])


func leave_room() -> void:
	in_match = false
	_to_server("_s_leave", [])


func start_match() -> void:
	_to_server("_s_start", [])


func end_match() -> void:
	## 승패가 났을 때 (방은 유지, 대기 상태로)
	if in_match:
		in_match = false
		_to_server("_s_match_end", [])


func send_event(kind: String, data: Variant) -> void:
	if is_active():
		_to_server("_s_event", [kind, data])


func send_snapshot(d: Dictionary) -> void:
	if not is_active():
		return
	if is_server:
		_local_sender = 1
		_s_snap(d)
		_local_sender = 0
	else:
		_s_snap.rpc_id(1, d)


func is_room_owner() -> bool:
	return not room.is_empty() and int(room.get("owner", -1)) == my_id


# ===========================================================================
# 내부: 연결
# ===========================================================================
func _listen(port: int) -> Error:
	close()
	peer = WebSocketMultiplayerPeer.new()
	var err := peer.create_server(port)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	(multiplayer as SceneMultiplayer).server_relay = false
	is_server = true
	return OK


func _on_peer_connected(id: int) -> void:
	if is_server:
		_log("접속: %d" % id)


func _on_peer_disconnected(id: int) -> void:
	if is_server:
		_log("접속 종료: %d (%s)" % [id, _names.get(id, "?")])
		_names.erase(id)
		_leave(id)


func _on_connected_to_server() -> void:
	my_id = multiplayer.get_unique_id()
	_s_hello.rpc_id(1, _clean_name(Session.player_name), PROTOCOL)


func _on_connection_failed() -> void:
	close()
	status_changed.emit("서버에 접속하지 못했습니다. 주소/포트와 서버 방화벽을 확인하세요.")


func _on_server_disconnected() -> void:
	var was_match := in_match
	close()
	status_changed.emit("서버와 연결이 끊겼습니다.")
	if was_match:
		disconnected.emit()


func _to_server(method: String, args: Array) -> void:
	if is_server:
		if dedicated:
			return
		_local_sender = 1
		callv(method, args)
		_local_sender = 0
	elif peer != null and connected:
		var a: Array = [1, method]
		a.append_array(args)
		callv("rpc_id", a)


func _to_client(id: int, method: String, args: Array) -> void:
	if is_server and not dedicated and id == 1:
		callv(method, args)
	elif peer != null:
		var a: Array = [id, method]
		a.append_array(args)
		callv("rpc_id", a)


func _sender() -> int:
	if _local_sender != 0:
		return _local_sender
	return multiplayer.get_remote_sender_id()


func _clean_name(n: String) -> String:
	var s := n.strip_edges().replace("\n", " ")
	if s == "":
		s = "플레이어"
	return s.substr(0, MAX_NAME)


func _log(msg: String) -> void:
	print("[%s] %s" % [Time.get_datetime_string_from_system(), msg])


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		server_address = cfg.get_value("online", "server", server_address)


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("online", "server", server_address)
	cfg.save(SETTINGS_PATH)


# ===========================================================================
# 서버 측 (클라이언트 → 서버)
# ===========================================================================
@rpc("any_peer", "reliable")
func _s_hello(player_name: String, protocol: int) -> void:
	if not is_server:
		return
	var id := _sender()
	if protocol != PROTOCOL:
		_to_client(id, "_c_error", ["게임 버전이 서버와 다릅니다. 최신 버전으로 업데이트하세요."])
		if peer != null and id != 1:
			peer.disconnect_peer.call_deferred(id)
		return
	_names[id] = _clean_name(player_name)
	_log("입장: %d = %s" % [id, _names[id]])
	_to_client(id, "_c_welcome", [id, _room_list()])


@rpc("any_peer", "reliable")
func _s_list() -> void:
	if is_server:
		_send_rooms(_sender())


@rpc("any_peer", "reliable")
func _s_create(p_mode: String, room_name: String, quick: bool) -> void:
	if not is_server:
		return
	var id := _sender()
	if not _names.has(id):
		return
	if _rooms.size() >= MAX_ROOMS:
		_to_client(id, "_c_error", ["서버에 방이 가득 찼습니다."])
		return
	if not p_mode in ["coop", "pvp"]:
		p_mode = "coop"
	_leave(id)
	var rid := _next_room
	_next_room += 1
	var rn := room_name.strip_edges().substr(0, 20)
	if rn == "":
		rn = "%s의 방" % _names[id]
	_rooms[rid] = {"id": rid, "name": rn, "mode": p_mode, "owner": id, "members": [id], "playing": false, "quick": quick}
	_peer_room[id] = rid
	_log("방 생성 #%d %s (%s) by %s" % [rid, rn, p_mode, _names[id]])
	_send_room_state(rid)
	_broadcast_rooms()


@rpc("any_peer", "reliable")
func _s_join(room_id: int) -> void:
	if not is_server:
		return
	var id := _sender()
	if not _names.has(id):
		return
	if not _rooms.has(room_id):
		_to_client(id, "_c_error", ["방이 없어졌습니다."])
		_send_rooms(id)
		return
	var r: Dictionary = _rooms[room_id]
	if r["playing"] or r["members"].size() >= 2:
		_to_client(id, "_c_error", ["이미 가득 찬 방입니다."])
		return
	_leave(id)
	r["members"].append(id)
	_peer_room[id] = room_id
	_log("입장 #%d <- %s" % [room_id, _names[id]])
	_send_room_state(room_id)
	_broadcast_rooms()
	if r["quick"] and r["members"].size() == 2:
		_start_room(room_id)


@rpc("any_peer", "reliable")
func _s_quick(p_mode: String) -> void:
	if not is_server:
		return
	var id := _sender()
	if not _names.has(id):
		return
	for rid in _rooms:
		var r: Dictionary = _rooms[rid]
		if r["quick"] and r["mode"] == p_mode and not r["playing"] and r["members"].size() == 1 and not id in r["members"]:
			_s_join(rid)
			return
	_s_create(p_mode, "빠른 매칭 (%s)" % Session.mode_name(p_mode), true)


@rpc("any_peer", "reliable")
func _s_leave() -> void:
	if is_server:
		_leave(_sender())
		_send_rooms(_sender())


@rpc("any_peer", "reliable")
func _s_start() -> void:
	if not is_server:
		return
	var id := _sender()
	var rid: int = _peer_room.get(id, -1)
	if rid < 0:
		return
	var r: Dictionary = _rooms[rid]
	if r["owner"] != id:
		_to_client(id, "_c_error", ["방장만 시작할 수 있습니다."])
		return
	if r["members"].size() < 2:
		_to_client(id, "_c_error", ["상대가 들어와야 시작할 수 있습니다."])
		return
	_start_room(rid)


@rpc("any_peer", "reliable")
func _s_match_end() -> void:
	if not is_server:
		return
	var rid: int = _peer_room.get(_sender(), -1)
	if rid >= 0 and _rooms[rid]["playing"]:
		_rooms[rid]["playing"] = false
		_log("매치 종료 #%d" % rid)
		_send_room_state(rid)
		_broadcast_rooms()


@rpc("any_peer", "reliable")
func _s_event(kind: String, data: Variant) -> void:
	if not is_server:
		return
	var to := _partner(_sender())
	if to != 0:
		_to_client(to, "_c_event", [kind, data])


@rpc("any_peer", "unreliable_ordered")
func _s_snap(d: Dictionary) -> void:
	if not is_server:
		return
	var to := _partner(_sender())
	if to == 0:
		return
	if to == 1 and not dedicated:
		_c_snap(d)
	else:
		_c_snap.rpc_id(to, d)


func _partner(id: int) -> int:
	var rid: int = _peer_room.get(id, -1)
	if rid < 0 or not _rooms[rid]["playing"]:
		return 0
	for m in _rooms[rid]["members"]:
		if m != id:
			return m
	return 0


func _start_room(rid: int) -> void:
	var r: Dictionary = _rooms[rid]
	r["playing"] = true
	var seed_v := randi()
	var m: Array = r["members"]
	_log("매치 시작 #%d %s: %s vs %s" % [rid, r["mode"], _names[m[0]], _names[m[1]]])
	for i in m.size():
		_to_client(m[i], "_c_start", [r["mode"], seed_v, _names[m[0]], _names[m[1]], i])
	_broadcast_rooms()


func _leave(id: int) -> void:
	var rid: int = _peer_room.get(id, -1)
	if rid < 0:
		return
	_peer_room.erase(id)
	var r: Dictionary = _rooms[rid]
	r["members"].erase(id)
	if r["playing"]:
		r["playing"] = false
		for m in r["members"]:
			_to_client(m, "_c_partner_left", [])
	if r["members"].is_empty():
		_rooms.erase(rid)
		_log("방 삭제 #%d" % rid)
	else:
		r["owner"] = r["members"][0]
		_send_room_state(rid)
	if _names.has(id):
		_to_client(id, "_c_room", [{}])
	_broadcast_rooms()


func _room_list() -> Array:
	var list: Array = []
	for rid in _rooms:
		var r: Dictionary = _rooms[rid]
		var names: Array = []
		for m in r["members"]:
			names.append(_names.get(m, "?"))
		list.append({"id": rid, "name": r["name"], "mode": r["mode"], "count": r["members"].size(), "playing": r["playing"], "quick": r["quick"], "players": names})
	return list


func _send_rooms(id: int) -> void:
	if _names.has(id):
		_to_client(id, "_c_rooms", [_room_list()])


func _broadcast_rooms() -> void:
	## 방에 없는(로비에 있는) 사람들에게만 목록 갱신
	var list := _room_list()
	for id in _names:
		if not _peer_room.has(id):
			_to_client(id, "_c_rooms", [list])


func _send_room_state(rid: int) -> void:
	var r: Dictionary = _rooms[rid]
	var names: Array = []
	for m in r["members"]:
		names.append(_names.get(m, "?"))
	var state := {"id": rid, "name": r["name"], "mode": r["mode"], "owner": r["owner"], "members": r["members"].duplicate(), "players": names, "playing": r["playing"], "quick": r["quick"]}
	for m in r["members"]:
		_to_client(m, "_c_room", [state])


# ===========================================================================
# 클라이언트 측 (서버 → 클라이언트)
# ===========================================================================
@rpc("authority", "reliable")
func _c_welcome(id: int, list: Array) -> void:
	my_id = id
	connected = true
	rooms = list
	connection_changed.emit(true)
	status_changed.emit("서버 접속 완료! 방을 만들거나 참가하세요.")
	rooms_updated.emit(list)


@rpc("authority", "reliable")
func _c_rooms(list: Array) -> void:
	rooms = list
	rooms_updated.emit(list)


@rpc("authority", "reliable")
func _c_room(state: Dictionary) -> void:
	room = state
	room_updated.emit(state)


@rpc("authority", "reliable")
func _c_error(msg: String) -> void:
	error_received.emit(msg)
	status_changed.emit(msg)


@rpc("authority", "reliable")
func _c_start(p_mode: String, seed_v: int, n0: String, n1: String, my_index: int) -> void:
	in_match = true
	Session.setup_online(p_mode, seed_v, n0, n1, my_index)
	get_tree().change_scene_to_file("res://scenes/Match.tscn")


@rpc("authority", "reliable")
func _c_event(kind: String, data: Variant) -> void:
	event_received.emit(kind, data)


@rpc("authority", "unreliable_ordered")
func _c_snap(d: Dictionary) -> void:
	snapshot_received.emit(d)


@rpc("authority", "reliable")
func _c_partner_left() -> void:
	if in_match:
		in_match = false
		disconnected.emit()
	status_changed.emit("상대가 나갔습니다.")
