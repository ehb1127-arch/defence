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
signal record_updated(record: Dictionary)      # 내 레이팅/전적
signal rating_changed(rating: int, delta: int)
signal leaderboard_received(list: Array, my_rank: int)
signal account_synced                          # 서버 계정(재화)과 동기화 완료
signal iap_result(req_id: int, ok: bool, product_id: String, msg: String)

const DEFAULT_PORT := 24680
const PROTOCOL := 4
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
var my_record: Dictionary = {}
var server_address := normalize_address(DEFAULT_SERVER)

# ---- 서버 상태 ----
var _names := {}                # peer_id -> 이름
var _rooms := {}                # room_id -> {id, name, mode, owner, members, playing, quick}
var _peer_room := {}            # peer_id -> room_id
var _next_room := 1
var _local_sender := 0          # LAN 호스트가 자기 서버 함수를 직접 부를 때의 보낸 사람
var _devices := {}              # peer_id -> device_id
var _db := {}                   # device_id -> {name, rating, wins, losses, coop_best}
var _db_dirty := false
const DB_PATH := "user://server_db.json"
const ProfileScript := preload("res://scripts/autoload/Profile.gd")
const IapVerifierScript := preload("res://scripts/server/IapVerifier.gd")
var _econ := {}                 # device_id -> 서버용 Profile 인스턴스 (접속 중인 계정만)
var _bucket := {}               # device_id -> [남은 판 정산 횟수, 마지막 충전 시각]
var _iap: RefCounted = null     # 결제 영수증 검증기 (전용 서버)
var _save_timer := 0.0
const MATCH_END_BURST := 10     # 판 정산 몰아서 보내기 허용량 (오프라인 판 재전송 포함)
const MATCH_END_REFILL := 60.0  # 초당 1회씩 다시 채움
const ELO_K := 32.0


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
	_load_db()
	_iap = IapVerifierScript.new(self)
	_log("전용 서버 시작 - 포트 %d, 프로토콜 %d, 등록 플레이어 %d명" % [port, PROTOCOL, _db.size()])
	return OK


func host_lan(port: int) -> Error:
	## 이 PC 에서 서버를 열고 나도 플레이어로 참가
	var err := _listen(port)
	if err != OK:
		status_changed.emit("서버 열기 실패 (포트 %d, 오류 %d)" % [port, err])
		return err
	dedicated = false
	_load_db()
	my_id = 1
	_names[1] = _clean_name(Session.player_name)
	_devices[1] = Profile.device_id
	my_record = _record_for(1)
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
	_devices.clear()
	_rooms.clear()
	_peer_room.clear()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if Profile.econ_server:
		Profile.econ_server = false
		Profile.op_done.emit([-1, null])
	for dev in _econ:
		_econ[dev].free()
	_econ.clear()
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


func report_result(winner: int, my_round: int) -> void:
	## 매치 결과 보고 (서버가 레이팅/기록 반영)
	if in_match:
		_to_server("_s_report", [winner, my_round])


func request_leaderboard() -> void:
	_to_server("_s_leaderboard", [])


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
		var dev: String = _devices.get(id, "")
		if _econ.has(dev):
			_store_econ(dev)
			_econ[dev].free()
			_econ.erase(dev)
			_save_db()
		_devices.erase(id)


func _on_connected_to_server() -> void:
	my_id = multiplayer.get_unique_id()
	_s_hello.rpc_id(1, _clean_name(Session.player_name), PROTOCOL, Profile.device_id)


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
func _s_hello(player_name: String, protocol: int, device_id: String) -> void:
	if not is_server:
		return
	var id := _sender()
	if protocol != PROTOCOL:
		_to_client(id, "_c_error", ["게임 버전이 서버와 다릅니다. 최신 버전으로 업데이트하세요."])
		if peer != null and id != 1:
			peer.disconnect_peer.call_deferred(id)
		return
	_names[id] = _clean_name(player_name)
	var dev := device_id.substr(0, 40) if device_id != "" else "peer%d" % id
	if dev in _devices.values():
		# 같은 기기에서 창을 두 개 띄운 경우 (테스트/LAN) 별도 기록으로
		dev += "#%d" % id
	_devices[id] = dev
	var rec := _record_for(id)
	_log("입장: %d = %s (레이팅 %d)" % [id, _names[id], rec["rating"]])
	_to_client(id, "_c_welcome", [id, _room_list()])
	_to_client(id, "_c_record", [_public(rec)])
	if dedicated and not "#" in dev:
		var inst := _econ_for(dev)
		_to_client(id, "_c_profile", [inst.to_dict() if inst != null else {}, inst == null])


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


@rpc("any_peer", "reliable")
func _s_report(winner_index: int, my_round: int) -> void:
	## 승패 보고. 자기 패배/상대 승리 보고는 바로 인정, 자기 승리 주장은 상대 보고와 일치해야 인정
	if not is_server:
		return
	var id := _sender()
	var rid: int = _peer_room.get(id, -1)
	if rid < 0:
		return
	var r: Dictionary = _rooms[rid]
	var m: Array = r["members"]
	var my_index := m.find(id)
	if my_index < 0:
		return
	var rec := _record_for(id)
	if r["mode"] == "coop":
		rec["coop_best"] = maxi(int(rec.get("coop_best", 0)), clampi(my_round, 0, 999))
		_db_dirty = true
		_save_db()
		return
	if r.get("rated", false) or m.size() < 2 or winner_index < 0 or winner_index > 1:
		return
	r["reports"][id] = winner_index
	var other: int = m[1 - my_index]
	if winner_index != my_index:
		_rate(r, m[winner_index], m[1 - winner_index])
	elif r["reports"].get(other, -1) == winner_index:
		_rate(r, id, other)


@rpc("any_peer", "reliable")
func _s_leaderboard() -> void:
	if not is_server:
		return
	var id := _sender()
	var list: Array = []
	for dev in _db:
		var e: Dictionary = _db[dev]
		if int(e.get("wins", 0)) + int(e.get("losses", 0)) > 0 or int(e.get("coop_best", 0)) > 0:
			list.append({"name": e["name"], "rating": e["rating"], "wins": e.get("wins", 0), "losses": e.get("losses", 0), "coop_best": e.get("coop_best", 0), "dev": dev})
	list.sort_custom(func(a, b): return a["rating"] > b["rating"])
	var my_dev: String = _devices.get(id, "")
	var my_rank := -1
	for i in list.size():
		if list[i]["dev"] == my_dev:
			my_rank = i + 1
	var top: Array = []
	for i in mini(20, list.size()):
		var e: Dictionary = list[i].duplicate()
		e.erase("dev")
		top.append(e)
	_to_client(id, "_c_leaderboard", [top, my_rank])


func _record_for(id: int) -> Dictionary:
	var dev: String = _devices.get(id, "peer%d" % id)
	if not _db.has(dev):
		_db[dev] = {"name": _names.get(id, "?"), "rating": 1000, "wins": 0, "losses": 0, "coop_best": 0}
		_db_dirty = true
	var rec: Dictionary = _db[dev]
	if _names.has(id) and rec["name"] != _names[id]:
		rec["name"] = _names[id]
		_db_dirty = true
	return rec


func _public(rec: Dictionary) -> Dictionary:
	## 레이팅/전적만 (계정 재화는 _c_profile/_c_op 로 따로)
	var d := rec.duplicate()
	d.erase("profile")
	return d


func _rate(r: Dictionary, winner: int, loser: int) -> void:
	r["rated"] = true
	var w := _record_for(winner)
	var l := _record_for(loser)
	var ew := 1.0 / (1.0 + pow(10.0, (l["rating"] - w["rating"]) / 400.0))
	var delta := maxi(1, int(round(ELO_K * (1.0 - ew))))
	w["rating"] = int(w["rating"]) + delta
	l["rating"] = maxi(0, int(l["rating"]) - delta)
	w["wins"] = int(w["wins"]) + 1
	l["losses"] = int(l["losses"]) + 1
	_db_dirty = true
	_save_db()
	_log("레이팅: %s +%d (%d) / %s -%d (%d)" % [w["name"], delta, w["rating"], l["name"], delta, l["rating"]])
	if _names.has(winner):
		_to_client(winner, "_c_rating", [_public(w), delta])
	if _names.has(loser):
		_to_client(loser, "_c_rating", [_public(l), -delta])


func _load_db() -> void:
	if not FileAccess.file_exists(DB_PATH):
		return
	var f := FileAccess.open(DB_PATH, FileAccess.READ)
	var data = JSON.parse_string(f.get_as_text())
	if data is Dictionary:
		_db = data


func _save_db() -> void:
	if not _db_dirty:
		return
	var f := FileAccess.open(DB_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_db))
	_db_dirty = false


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
	r["rated"] = false
	r["reports"] = {}
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
		if r["mode"] == "pvp" and not r.get("rated", false) and r["members"].size() == 1:
			# 매치 도중 나간 쪽 패배
			_rate(r, r["members"][0], id)
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
func _c_record(rec: Dictionary) -> void:
	my_record = rec
	Profile.rating = int(rec.get("rating", 1000))
	Profile.save()
	record_updated.emit(rec)


@rpc("authority", "reliable")
func _c_rating(rec: Dictionary, delta: int) -> void:
	my_record = rec
	Profile.rating = int(rec.get("rating", 1000))
	Profile.save()
	record_updated.emit(rec)
	rating_changed.emit(int(rec.get("rating", 1000)), delta)


@rpc("authority", "reliable")
func _c_leaderboard(list: Array, my_rank: int) -> void:
	leaderboard_received.emit(list, my_rank)


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


# ===========================================================================
# 계정 재화 (전용 서버가 기준). 클라이언트는 같은 규칙(Profile.gd)으로 먼저 반영하고
# 서버가 실행한 결과로 덮어쓴다. 자세한 내용: docs/ECONOMY.md
# ===========================================================================
func send_op(req_id: int, op: String, args: Array) -> void:
	if connected and not is_server:
		_s_op.rpc_id(1, req_id, op, args)


func send_iap(req_id: int, product_id: String, token: String) -> void:
	if connected and not is_server:
		_s_iap.rpc_id(1, req_id, product_id, token)


func econ_online() -> bool:
	return connected and Profile.econ_server


func _process(delta: float) -> void:
	if not (is_server and dedicated):
		return
	_save_timer -= delta
	if _save_timer <= 0.0:
		_save_timer = 5.0
		_save_db()


func _econ_for(dev: String) -> Node:
	## 접속한 계정의 서버용 Profile. 서버에 계정 재화가 아직 없으면 null (첫 접속 → 이전 요청)
	if _econ.has(dev):
		return _econ[dev]
	if not _db.has(dev) or not _db[dev].has("profile"):
		return null
	var inst: Node = ProfileScript.new()
	inst.server_side = true
	inst.from_dict(_db[dev]["profile"])
	inst.rating = int(_db[dev].get("rating", 1000))
	_econ[dev] = inst
	return inst


func _store_econ(dev: String) -> void:
	if _econ.has(dev) and _db.has(dev):
		_db[dev]["profile"] = _econ[dev].to_dict()
		_db_dirty = true


func _take_match_end(dev: String) -> bool:
	var now := Time.get_unix_time_from_system()
	var b: Array = _bucket.get(dev, [float(MATCH_END_BURST), now])
	b[0] = minf(float(MATCH_END_BURST), b[0] + (now - b[1]) / MATCH_END_REFILL)
	b[1] = now
	_bucket[dev] = b
	if b[0] < 1.0:
		return false
	b[0] -= 1.0
	return true


static func sanitize_migration(d: Dictionary) -> Dictionary:
	## 첫 접속 때 기기에 있던 진행을 서버로 옮긴다. 기기 파일은 조작될 수 있으므로 상한을 둔다
	var p: Node = ProfileScript.new()
	p.server_side = true
	p.from_dict(d)
	p.coins = clampi(p.coins, 0, 5000)
	p.level = clampi(p.level, 1, 30)
	p.xp = clampi(p.xp, 0, GameData.xp_to_next(p.level))
	for id in p.items.keys():
		if GameData.shop_item(id).is_empty():
			p.items.erase(id)
		else:
			p.items[id] = clampi(int(p.items[id]), 0, 10)
	for id in p.perks.keys():
		var pk := GameData.perk(id)
		if pk.is_empty():
			p.perks.erase(id)
		else:
			p.perks[id] = clampi(int(p.perks[id]), 0, int(pk["max"]))
	for id in p.unit_levels.keys():
		if not GameData.UNITS.has(id):
			p.unit_levels.erase(id)
		else:
			p.unit_levels[id] = clampi(int(p.unit_levels[id]), 0, GameData.UNIT_MAX_LEVEL)
	for id in p.campaign.keys():
		if Story.get_stage(id).is_empty():
			p.campaign.erase(id)
		else:
			p.campaign[id] = clampi(int(p.campaign[id]), 0, 3)
	for k in p.stats.keys():
		var cap := 500 if k in ["mythics", "bosses", "jackpots", "wins"] else 200000
		if k == "max_star":
			cap = GameData.STAR_MAX
		elif k == "best_round":
			cap = GameData.FINAL_WAVE + 5
		p.stats[k] = clampi(int(p.stats[k]), 0, cap)
	# 옮긴 기록으로 이미 도달한 업적 단계는 "받은 것"으로 처리 (조작된 기록으로 보상 받기 방지)
	for a in GameData.ACHIEVEMENTS:
		var tier := clampi(int(p.achievements.get(a["id"], 0)), 0, a["goals"].size())
		var v: int = p.ach_value(a["stat"])
		while tier < a["goals"].size() and v >= a["goals"][tier]:
			tier += 1
		p.achievements[a["id"]] = tier
	# 결제로만 얻는 것은 옮기지 않는다 (서버 결제 기록이 기준)
	p.no_ads = false
	p.purchases = {}
	var out: Dictionary = p.to_dict()
	p.free()
	return out


@rpc("any_peer", "reliable")
func _s_migrate(d: Dictionary) -> void:
	if not (is_server and dedicated):
		return
	var id := _sender()
	var dev: String = _devices.get(id, "")
	if dev == "" or "#" in dev or not _db.has(dev) or _db[dev].has("profile"):
		return
	_db[dev]["profile"] = sanitize_migration(d)
	_db_dirty = true
	_save_db()
	var inst := _econ_for(dev)
	_log("계정 이전: %s (코인 %d)" % [_names.get(id, "?"), inst.coins])
	_to_client(id, "_c_profile", [inst.to_dict(), false])


@rpc("any_peer", "reliable")
func _s_op(req_id: int, op: String, args: Array) -> void:
	if not (is_server and dedicated):
		return
	var id := _sender()
	var dev: String = _devices.get(id, "")
	var inst := _econ_for(dev)
	if inst == null or args.size() > 4:
		return
	var result: Variant = null
	if op == "match_end" and not _take_match_end(dev):
		result = null
	elif op == "match_end" and not (args.size() == 1 and args[0] is Dictionary):
		result = null
	else:
		result = inst.run_op(op, args)
	inst.rating = int(_db[dev].get("rating", 1000))
	_store_econ(dev)
	_to_client(id, "_c_op", [req_id, result, inst.to_dict()])


@rpc("any_peer", "reliable")
func _s_iap(req_id: int, product_id: String, token: String) -> void:
	## 결제 영수증 검증 → 지급. 검증은 Google Play Developer API (IapVerifier)
	if not (is_server and dedicated):
		return
	var id := _sender()
	var dev: String = _devices.get(id, "")
	if _econ_for(dev) == null:
		return
	var res: Dictionary = await _iap.verify(product_id, token, dev)
	var inst := _econ_for(dev)   # 기다리는 동안 나갔을 수 있음
	if inst == null:
		return
	var ok: bool = res.get("ok", false)
	if ok:
		ok = inst.iap_grant(product_id)
		if not ok:
			res["msg"] = "이미 받은 상품"
		_store_econ(dev)
		_save_db()
		_log("결제 %s: %s %s" % ["지급" if ok else "거절", _names.get(id, "?"), product_id])
	if _names.has(id):
		_to_client(id, "_c_iap", [req_id, ok, product_id, inst.to_dict(), str(res.get("msg", ""))])


@rpc("authority", "reliable")
func _c_profile(d: Dictionary, need_upload: bool) -> void:
	if need_upload:
		_s_migrate.rpc_id(1, Profile.to_dict())
		return
	Profile.link_server(d)
	account_synced.emit()


@rpc("authority", "reliable")
func _c_op(req_id: int, result: Variant, d: Dictionary) -> void:
	Profile.apply_server(d, req_id, result)


@rpc("authority", "reliable")
func _c_iap(req_id: int, ok: bool, product_id: String, d: Dictionary, msg: String) -> void:
	Profile.apply_server(d, 0, null)
	iap_result.emit(req_id, ok, product_id, msg)
