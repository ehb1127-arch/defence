extends Node
## 온라인 (WebSocket).
##
## 한 스크립트가 세 가지 역할을 한다.
##  - 전용 서버 : `godot --headless --path . -- --server [--port N]`
##               방 목록/생성/참가/빠른 매칭 + 같은 방 두 사람 사이 메시지 중계 + 계정 재화/랭킹/결제
##  - LAN 호스트: 플레이어 한 명이 서버를 겸한다 (peer id 1 = 서버이자 플레이어)
##  - 클라이언트: 서버에 접속해서 방에 들어가 게임
##
## 게임 계산은 각 클라이언트가 자기 전장만 한다. 서버는 스냅샷(표시용)과
## 이벤트(적 보내기/선물/폭격/패배)를 같은 방 상대에게 전달만 한다 (종류·크기·빈도는 검사).
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
## 랭킹. kind = pvp/endless/tower/daily, list = [{name, value, sub}], my_rank = 내 순위 (없으면 -1)
signal leaderboard_received(kind: String, list: Array, my_rank: int)
signal account_synced                          # 서버 계정(재화)과 동기화 완료
signal iap_result(req_id: int, ok: bool, product_id: String, msg: String)
signal recovery_code(code: String)             # 계정 복구 코드 받음 ("" = 받을 수 없음)
signal recovery_result(ok: bool, msg: String)  # 복구 코드 입력 결과
signal notice_received(text: String)           # 서버 공지 (접속 직후, 공지가 있을 때)
signal config_received(config: Dictionary)     # 서버 운영 설정 {notice, event_name, coin_event_mult}

const DEFAULT_PORT := 24680
const PROTOCOL := 5
const MAX_ROOMS := 200
const MAX_NAME := 12
const SETTINGS_PATH := "user://online.cfg"
## 배포용 기본 서버 주소. 코드를 고치지 않고 프로젝트 설정 application/online/server_url 로 바꾼다
## (예: "wss://game.example.com"). 설정이 없으면 이 값. docs/OCI_DEPLOY.md
const DEFAULT_SERVER := "127.0.0.1"
const SERVER_URL_SETTING := "application/online/server_url"

var peer: WebSocketMultiplayerPeer
var is_server := false          # 이 프로세스가 서버 로직을 수행
var dedicated := false          # 플레이어 없는 전용 서버
var connected := false          # (클라이언트로서) 서버와 인사까지 끝남
var my_id := 0
var room: Dictionary = {}       # 내가 들어간 방 (클라이언트 시점)
var rooms: Array = []           # 마지막으로 받은 방 목록
var in_match := false
var my_record: Dictionary = {}
var server_config: Dictionary = {}   # 서버에서 받은 운영 설정 (공지·이벤트)
var server_address := normalize_address(default_server())

# ---- 서버 상태 ----
var _names := {}                # peer_id -> 이름
var _rooms := {}                # room_id -> {id, name, mode, owner, members, playing, quick}
var _peer_room := {}            # peer_id -> room_id
var _next_room := 1
var _local_sender := 0          # LAN 호스트가 자기 서버 함수를 직접 부를 때의 보낸 사람
var _devices := {}              # peer_id -> device_id
var _db := {}                   # device_id -> {name, rating, wins, losses, coop_best, profile, ...}
var _db_dirty := false
var _codes := {}                # 복구 코드 -> device_id (_db 의 recovery 에서 다시 만든다)
const DB_PATH := "user://server_db.json"
const BACKUP_DIR := "user://backups"
const BACKUP_EVERY := 3600.0    # 한 시간마다 백업
const BACKUP_KEEP := 72         # 사흘치
const STARTUP_BACKUP_GAP := 600.0   # 서버 시작 백업은 마지막 백업이 10분보다 오래됐을 때만
const SAVE_EVERY := 5.0         # DB 저장은 최대 5초에 한 번 (바뀐 게 있을 때만)
const CONFIG_PATH := "user://server_config.json"
const ProfileScript := preload("res://scripts/autoload/Profile.gd")
const IapVerifierScript := preload("res://scripts/server/IapVerifier.gd")
const SafeFile := preload("res://scripts/server/SafeFile.gd")
var _econ := {}                 # device_id -> 서버용 Profile 인스턴스 (접속 중인 계정만)
var _bucket := {}               # device_id -> [남은 판 정산 횟수, 마지막 충전 시각]
var _iap: RefCounted = null     # 결제 영수증 검증기 (전용 서버)
var _save_timer := 0.0
var _backup_timer := BACKUP_EVERY
var _tick_timer := 0.0
var _config_timer := 30.0
var _rooms_dirty := false
var _rooms_timer := 0.0
var _config := {}
var _config_mtime := 0
var _rl := {}                   # 빈도 제한: key -> {종류: [남은 수, 마지막 시각]}
var _lb := {}                   # 랭킹 캐시: kind -> {t, list, rank}
var _lb_dirty := {}
var _stats := {}                # 경제 통계 (한 시간마다 로그에 남기고 비움)
const MATCH_END_BURST := 12     # 판 정산 몰아서 보내기 허용량 (오프라인 판 재전송 포함)
const MATCH_END_REFILL := 60.0  # 60초마다 1회씩 다시 채움
const ELO_K := 32.0
const PROVISIONAL_GAMES := 5    # 대전 5판 미만인 계정을 이기면 레이팅은 조금만 오른다 (새 계정으로 점수 몰아주기 방지)
const PROVISIONAL_GAIN := 4
const PVP_SETTLE_WINDOW := 1800  # 온라인 대전 시작 후 이 시간(초) 안의 대전 정산은 그 온라인 판으로 본다
const REPORT_TIMEOUT := 60.0    # 대전 결과: 한쪽만 보고하면 이만큼 기다린 뒤 정리
const LB_KINDS := ["pvp", "endless", "tower", "daily"]
const LB_TOP := 50
const LB_TTL := 60.0
## 요청 빈도 제한 [몰아서 허용량, 초당 충전]. 넘으면 버린다
const LIMITS := {
	"op": [40, 4.0], "event": [40, 12.0], "attack": [16, 2.5], "snap": [40, 20.0], "lobby": [20, 2.0],
	"iap": [6, 0.2], "redeem": [5, 1.0 / 60.0], "code": [5, 0.05], "hello": [3, 0.1],
	"redeem_all": [120, 2.0],   # 복구 코드 틀린 입력: 서버 전체 합계 (프록시 뒤에서는 IP 가 모두 같다)
}
const MAX_SNAP_KEYS := 32
## 스냅샷에 올 수 있는 키와 자료형 (Board.snapshot 과 맞춘다. 이 밖의 키는 거절)
const SNAP_TYPES := {
	"c": "ints", "e": "ints", "g": "int", "m": "int", "w": "int", "k": "int", "f": "int", "sc": "int", "ga": "int",
	"t": "num", "a": "bool", "fc": "bool", "bf": "bool", "u": "up",
}
const MAX_SNAP_ENEMIES := 1200  # 스냅샷 적 배열 길이 (적 1마리 = 2칸)
## 복구 코드 글자 (헷갈리는 0/O/1/I/L 제외)
const CODE_CHARS := "ABCDEFGHJKMNPQRSTUVWXYZ23456789"


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


func _notification(what: int) -> void:
	# 서버 종료 직전: 접속 중인 계정 재화를 DB 에 넣고 저장
	if (what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_EXIT_TREE) and is_server:
		_flush_all()


# ===========================================================================
# 공개 API (메뉴 / Match 에서 사용)
# ===========================================================================
static func default_server() -> String:
	## 빌드에 들어간 기본 서버 주소 (프로젝트 설정 application/online/server_url, 없으면 DEFAULT_SERVER)
	var s := str(ProjectSettings.get_setting(SERVER_URL_SETTING, DEFAULT_SERVER)).strip_edges()
	return s if s != "" else DEFAULT_SERVER


func start_dedicated(port: int) -> Error:
	var err := _listen(port)
	if err != OK:
		push_error("서버 시작 실패: 포트 %d (오류 %d)" % [port, err])
		get_tree().quit(1)
		return err
	dedicated = true
	if not _load_db():
		push_error("server_db.json 이 깨졌고 온전한 백업도 없습니다. 빈 DB 로 시작하려면 SQD_ALLOW_EMPTY_DB=1")
		get_tree().quit(2)
		return ERR_FILE_CORRUPT
	if _db_dirty:
		_save_db(true)   # 백업에서 불러왔으면 본 파일을 바로 온전한 내용으로
	# 시작 백업: 최근 10분 안에 만든 백업이 있으면 건너뛴다 (재시작이 반복돼도 시간별 백업이 밀려나지 않게)
	if FileAccess.file_exists(DB_PATH) and SafeFile.newest_backup_age(DB_PATH, BACKUP_DIR) > STARTUP_BACKUP_GAP:
		SafeFile.backup(DB_PATH, BACKUP_DIR, BACKUP_KEEP)
	_iap = IapVerifierScript.new(self)
	_reload_config(true)
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
	my_record = _public(_record_for(1))
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
	if is_server:
		_flush_all()
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
	_rl.clear()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	Profile.coin_mult = 1.0
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
	## 매치 결과 보고 (서버가 레이팅/기록 반영). 대전은 두 사람 보고가 같아야 레이팅이 바뀐다
	if in_match:
		_to_server("_s_report", [winner, my_round])


func request_leaderboard(kind: String = "pvp") -> void:
	## 랭킹 요청 → leaderboard_received(kind, list, my_rank)
	_to_server("_s_leaderboard", [kind if kind in LB_KINDS else "pvp"])


func request_recovery_code() -> void:
	## 내 계정 복구 코드 받기 → recovery_code(code). 새 폰/재설치 때 이 코드로 계정을 되찾는다
	if connected and not is_server:
		_s_recovery_code.rpc_id(1)
	else:
		recovery_code.emit.call_deferred("")


func redeem_recovery_code(code: String) -> void:
	## 복구 코드 입력 → recovery_result(ok, msg). 성공하면 이 기기가 그 계정이 되고 진행/결제가 다시 동기화된다
	if connected and not is_server:
		_s_redeem.rpc_id(1, code.substr(0, 32))
	else:
		recovery_result.emit.call_deferred(false, "서버에 먼저 연결하세요")


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
		_detach_account(id)
		_rl.erase(id)


func _detach_account(id: int) -> void:
	## 접속 끊긴(또는 계정을 바꾼) peer 의 계정 재화를 DB 에 넣고 메모리에서 내린다
	var dev: String = _devices.get(id, "")
	if _econ.has(dev):
		_store_econ(dev)
		_econ[dev].free()
		_econ.erase(dev)
	_devices.erase(id)


func _on_connected_to_server() -> void:
	my_id = multiplayer.get_unique_id()
	_a_hello.rpc_id(1, _clean_name(Session.player_name), PROTOCOL, Profile.device_id)


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
	var s := n.strip_edges().replace("\n", " ").replace("\r", " ").replace("\t", " ")
	if s == "":
		s = "플레이어"
	return s.substr(0, MAX_NAME)


func _log(msg: String) -> void:
	print("[%s] %s" % [Time.get_datetime_string_from_system(), msg])


func _load_settings() -> void:
	## 저장된 주소는 "그때의 기본 주소"가 지금과 같을 때만 쓴다 (빌드의 기본 서버가 바뀌면 새 주소로)
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		var saved := str(cfg.get_value("online", "server", ""))
		var saved_default := str(cfg.get_value("online", "default", ""))
		if saved != "" and saved_default == normalize_address(default_server()):
			server_address = saved


func _save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("online", "server", server_address)
	cfg.set_value("online", "default", normalize_address(default_server()))
	cfg.save(SETTINGS_PATH)


func _allow(key: Variant, kind: String) -> bool:
	## 빈도 제한 (토큰 버킷). LAN 호스트 자신(1)은 제한 없음
	if not _rl_has(key, kind):
		return false
	_rl_take(key, kind)
	return true


func _rl_bucket(key: Variant, kind: String) -> Array:
	var lim: Array = LIMITS[kind]
	var now := Time.get_ticks_msec() / 1000.0
	var per: Dictionary = _rl.get(key, {})
	var b: Array = per.get(kind, [float(lim[0]), now])
	b[0] = minf(float(lim[0]), b[0] + (now - b[1]) * float(lim[1]))
	b[1] = now
	per[kind] = b
	_rl[key] = per
	return b


func _rl_has(key: Variant, kind: String) -> bool:
	## 버킷에 남은 게 있나 (쓰지는 않는다)
	if key is int and key == 1 and not dedicated:
		return true
	return _rl_bucket(key, kind)[0] >= 1.0


func _rl_take(key: Variant, kind: String) -> void:
	if key is int and key == 1 and not dedicated:
		return
	var b := _rl_bucket(key, kind)
	b[0] = maxf(0.0, b[0] - 1.0)


static func is_private_ip(ip: String) -> bool:
	## 루프백·사설망 주소 (리버스 프록시 뒤라면 모든 접속이 이 주소)
	if ip == "" or ip == "local" or ip == "::1" or ip.begins_with("127.") or ip.begins_with("10.") or ip.begins_with("192.168."):
		return true
	if ip.begins_with("172."):
		var parts := ip.split(".")
		if parts.size() > 1 and int(parts[1]) >= 16 and int(parts[1]) <= 31:
			return true
	var low := ip.to_lower()
	return low.begins_with("fc") or low.begins_with("fd") or low.begins_with("fe80") or low.begins_with("::ffff:127.")


func _redeem_keys(id: int) -> Array:
	## 복구 코드 틀린 입력을 세는 버킷들: 접속별, 계정별, IP별(공인 IP 일 때만), 서버 전체
	var keys: Array = [[id, "redeem"], ["all", "redeem_all"]]
	var dev: String = _devices.get(id, "")
	if dev != "":
		keys.append(["dev:" + dev, "redeem"])
	var ip := _peer_ip(id)
	if not is_private_ip(ip) and OS.get_environment("SQD_BEHIND_PROXY") != "1":
		keys.append(["ip:" + ip, "redeem"])
	return keys


func _stat(key: String, n: int) -> void:
	_stats[key] = int(_stats.get(key, 0)) + n


func _log_stats() -> void:
	## 한 시간 동안의 경제 흐름 (재화 발생/사용 추적용)
	if _stats.is_empty():
		return
	var keys: Array = _stats.keys()
	keys.sort()
	var parts: Array = []
	for k in keys:
		parts.append("%s=%d" % [k, _stats[k]])
	_log("통계(1시간): 접속 %d, %s" % [_names.size(), ", ".join(parts)])
	_stats.clear()


func _peer_ip(id: int) -> String:
	if peer != null and dedicated and id != 1:
		return peer.get_peer_address(id)
	return "local"


# ===========================================================================
# 서버 측 (클라이언트 → 서버)
# ===========================================================================
static func clean_device_id(device_id: String) -> String:
	## 계정 키로 쓸 수 있는 글자만 (영문·숫자·_-), 40자까지
	var out := ""
	for ch in device_id.substr(0, 40):
		if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == "_" or ch == "-":
			out += ch
	return out


## 인사·오류 RPC 이름은 _a_ 로 시작: RPC 번호는 이름순으로 매겨지므로, 다른 RPC 를 더하거나 빼도
## 이 둘의 번호는 그대로 → 버전이 다른 클라이언트도 "업데이트하세요" 안내를 받는다
@rpc("any_peer", "reliable")
func _a_hello(player_name: String, protocol: int, device_id: String) -> void:
	if not is_server:
		return
	var id := _sender()
	if _names.has(id) or not _allow(id, "hello"):
		return
	if protocol != PROTOCOL:
		_to_client(id, "_a_error", ["게임 버전이 서버와 다릅니다. 최신 버전으로 업데이트하세요."])
		if peer != null and id != 1:
			peer.disconnect_peer.call_deferred(id)
		return
	_names[id] = _clean_name(player_name)
	var dev := clean_device_id(device_id)
	if dev == "":
		dev = "peer%d" % id
	if dev in _devices.values():
		# 같은 기기에서 창을 두 개 띄운 경우 (테스트/LAN) 별도 기록으로
		dev += "#%d" % id
	_devices[id] = dev
	var rec := _record_for(id)
	_log("입장: %d = %s (레이팅 %d)" % [id, _names[id], rec["rating"]])
	_to_client(id, "_c_welcome", [id, _room_list(), int(Time.get_unix_time_from_system())])
	_to_client(id, "_c_record", [_public(rec)])
	if dedicated:
		_to_client(id, "_c_config", [_public_config()])
	if dedicated and not "#" in dev:
		var inst := _econ_for(dev)
		_to_client(id, "_c_profile", [inst.to_dict() if inst != null else {}, inst == null])


@rpc("any_peer", "reliable")
func _s_list() -> void:
	if is_server and _allow(_sender(), "lobby"):
		_send_rooms(_sender())


@rpc("any_peer", "reliable")
func _s_create(p_mode: String, room_name: String, quick: bool) -> void:
	if not is_server:
		return
	var id := _sender()
	if not _names.has(id) or not _allow(id, "lobby"):
		return
	if _rooms.size() >= MAX_ROOMS:
		_to_client(id, "_a_error", ["서버에 방이 가득 찼습니다."])
		return
	if not p_mode in ["coop", "pvp"]:
		p_mode = "coop"
	_leave(id)
	var rid := _next_room
	_next_room += 1
	var rn := room_name.strip_edges().replace("\n", " ").replace("\r", " ").substr(0, 20)
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
		_to_client(id, "_a_error", ["방이 없어졌습니다."])
		_send_rooms(id)
		return
	var r: Dictionary = _rooms[room_id]
	if id in r["members"]:
		return
	if r["playing"] or r["members"].size() >= 2:
		_to_client(id, "_a_error", ["이미 가득 찬 방입니다."])
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
	if not _names.has(id) or not _allow(id, "lobby"):
		return
	if not p_mode in ["coop", "pvp"]:
		p_mode = "coop"
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
		_to_client(id, "_a_error", ["방장만 시작할 수 있습니다."])
		return
	if r["members"].size() < 2:
		_to_client(id, "_a_error", ["상대가 들어와야 시작할 수 있습니다."])
		return
	if r["playing"]:
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
	var id := _sender()
	var to := _partner(id)
	if to == 0 or not _allow(id, "event"):
		return
	if kind == "attack" and not _allow(id, "attack"):
		return
	if not _valid_event(id, kind, data):
		_log("이벤트 거절 %d: %s %s" % [id, kind.substr(0, 16), str(data).substr(0, 40)])
		return
	_to_client(to, "_c_event", [kind, data])


func _valid_event(id: int, kind: String, data: Variant) -> bool:
	## 중계 전 검사: 종류별 자료형·범위. 대전에서 남의 패배 선언·자기 승리 선언은 막는다 (자기 전장 패배만 알릴 수 있음)
	var rid: int = _peer_room.get(id, -1)
	if rid < 0:
		return false
	var r: Dictionary = _rooms[rid]
	var my_index: int = r["members"].find(id)
	var pvp: bool = r["mode"] == "pvp"
	match kind:
		"attack":
			# "swarm" 또는 "swarm:17" (보낸 사람 라운드)
			if not pvp or not data is String or data.length() > 24:
				return false
			var parts: PackedStringArray = data.split(":")
			if parts.size() > 2 or (parts.size() == 2 and not parts[1].is_valid_int()):
				return false
			for a in GameData.ATTACKS:
				if a["id"] == parts[0]:
					return true
			return false
		"gold":
			return not pvp and data is int and data > 0 and data <= 100000
		"unit":
			return not pvp and data is String and GameData.UNITS.has(data)
		"blast":
			return not pvp and (data is int or data == null)
		"emote":
			return data is String and data.length() <= 24
		"defeat":
			if not (data is int and data == my_index):
				return false
			r["defeated"] = r.get("defeated", {})
			r["defeated"][id] = true
			return true
		"gameover":
			if not data is Dictionary or data.size() > 4:
				return false
			var w = data.get("winner", -1)
			if not w is int or not data.get("text", "") is String or str(data.get("text", "")).length() > 120:
				return false
			if pvp:
				if w == my_index or w < -1 or w > 1:
					return false   # 승리 선언은 진 쪽만 (상대 승리)
				if w == -1 and not r.get("defeated", {}).has(id):
					# 자기 패배(defeat)를 먼저 알리지 않은 무승부 선언 = 자기 패배로 본다 (가짜 무승부로 패배 피하기 방지)
					data["winner"] = 1 - my_index
					data["text"] = "승리! 상대가 무너졌어요"
				return true
			return w == -1 or w == -2
	# 모르는 종류 (새 기능): 작은 값만 전달
	if kind.length() > 16:
		return false
	return data == null or data is int or data is float or data is bool or (data is String and data.length() <= 32)


@rpc("any_peer", "unreliable_ordered")
func _s_snap(d: Dictionary) -> void:
	if not is_server:
		return
	var id := _sender()
	var to := _partner(id)
	if to == 0 or not _allow(id, "snap") or not _valid_snap(d):
		return
	if to == 1 and not dedicated:
		_c_snap(d)
	else:
		_c_snap.rpc_id(to, d)


func _valid_snap(d: Dictionary) -> bool:
	## 스냅샷 크기·자료형 검사 (받는 쪽이 배열 번호로 쓰는 값은 범위까지)
	if d.size() > MAX_SNAP_KEYS:
		return false
	for k in d:
		var v = d[k]
		if not k is String or k.length() > 12:
			return false
		if v is PackedInt32Array or v is PackedFloat32Array or v is PackedByteArray:
			if v.size() > MAX_SNAP_ENEMIES * 2:
				return false
		elif v is Array:
			if v.size() > 32:
				return false
			for x in v:
				if not (x is int or x is float or x is bool):
					return false
		elif not (v is int or v is float or v is bool):
			return false
		# 키별 자료형 (받는 쪽 Board.apply_snapshot 이 형이 정해진 변수에 넣는다)
		if not SNAP_TYPES.has(k):
			return false
		match SNAP_TYPES[k]:
			"int":
				if not v is int:
					return false
			"num":
				if not (v is int or v is float):
					return false
			"bool":
				if not v is bool:
					return false
			"ints":
				if not v is PackedInt32Array:
					return false
			"up":
				if not v is Array or v.size() != 4:
					return false
				for x in v:
					if not x is int:
						return false
	var c = d.get("c", PackedInt32Array())
	if not c is PackedInt32Array or c.size() > 64:
		return false
	var max_unit := GameData.UNIT_ORDER.size() * 32
	for x in c:
		if x < -1 or x >= max_unit:
			return false
	var e = d.get("e", PackedInt32Array())
	if not e is PackedInt32Array or e.size() % 2 != 0 or e.size() > MAX_SNAP_ENEMIES:
		return false
	var n_enemy := GameData.ENEMY_ORDER.size()
	for i in range(1, e.size(), 2):
		var kind_i: int = e[i] & 0xFF
		if kind_i >= n_enemy:
			return false
	return true


@rpc("any_peer", "reliable")
func _s_report(winner_index: int, my_round: int) -> void:
	## 승패 보고. 대전은 두 사람 보고가 같을 때만 레이팅 반영 (한쪽만 오면 REPORT_TIMEOUT 뒤: 자기 패배 인정만 반영)
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
		return
	if r.get("rated", true) or not r.has("pair") or winner_index < -1 or winner_index > 1:
		return
	var reps: Dictionary = r["reports"]
	if reps.has(id) or not id in r["pair"]:
		return
	# 보고는 방 안 번호가 아니라 매치 시작 때 번호(pair) 기준
	if winner_index == -1 and not r.get("defeated", {}).has(id):
		winner_index = 1 - r["pair"].find(id)   # 자기 패배 알림 없는 무승부 보고 = 자기 패배
	reps[id] = winner_index
	if reps.size() == 1:
		r["report_t"] = Time.get_ticks_msec() / 1000.0
	_try_resolve(rid, false)


func _try_resolve(rid: int, force: bool) -> void:
	## 대전 결과 정리. 두 보고가 같으면 반영, 다르면 무효. force = 시간 초과/방 삭제 (한쪽 보고만으로 정리)
	if not _rooms.has(rid):
		return
	var r: Dictionary = _rooms[rid]
	if r.get("rated", true) or not r.has("pair"):
		return
	var pair: Array = r["pair"]
	var devs: Array = r["pair_dev"]
	var reps: Dictionary = r["reports"]
	var a: int = reps.get(pair[0], -9)
	var b: int = reps.get(pair[1], -9)
	if a != -9 and b != -9:
		if a == b and a >= 0:
			_rate(r, devs[a], devs[1 - a], pair[a], pair[1 - a])
		else:
			r["rated"] = true
			_log("대전 결과 불일치 #%d (%d / %d) → 레이팅 없음" % [rid, a, b])
		return
	if not force:
		return
	r["rated"] = true
	for i in 2:
		var rep: int = reps.get(pair[i], -9)
		if rep == 1 - i:
			# 자기 패배(상대 승리) 보고는 믿는다
			_rate(r, devs[1 - i], devs[i], pair[1 - i], pair[i])
			return
	if not reps.is_empty():
		_log("대전 결과: 한쪽 승리 주장만 있음 #%d → 레이팅 없음" % rid)


@rpc("any_peer", "reliable")
func _s_leaderboard(kind: String) -> void:
	if not is_server:
		return
	var id := _sender()
	if not _names.has(id) or not _allow(id, "lobby"):
		return
	if not kind in LB_KINDS:
		kind = "pvp"
	var lb := _leaderboard(kind)
	var my_dev: String = _devices.get(id, "")
	var my_rank: int = lb["rank"].get(my_dev, -1)
	var top: Array = []
	for i in mini(LB_TOP, lb["list"].size()):
		var e: Dictionary = lb["list"][i]
		top.append({"name": e["name"], "value": e["value"], "sub": e["sub"]})
	_to_client(id, "_c_leaderboard", [kind, top, my_rank])


func _leaderboard(kind: String) -> Dictionary:
	## 랭킹 목록 (전체 정렬 결과를 잠깐 캐시). {t, list: [{name, value, sub, dev}], rank: {dev: 순위}}
	var now := Time.get_ticks_msec() / 1000.0
	var c: Dictionary = _lb.get(kind, {})
	if not c.is_empty():
		var age := now - float(c["t"])
		if age < LB_TTL and not (_lb_dirty.get(kind, false) and age > 2.0):
			return c
	var list: Array = []
	var today := Story.kst_date()
	for dev in _db:
		var e: Dictionary = _db[dev]
		var v := 0
		var sub := ""
		match kind:
			"pvp":
				var w := int(e.get("wins", 0))
				var l := int(e.get("losses", 0))
				if w + l <= 0:
					continue
				v = int(e.get("rating", 1000))
				sub = "%d승 %d패" % [w, l]
			"endless":
				v = int(e.get("endless", 0))
				sub = str(e.get("endless_sub", ""))
			"tower":
				v = int(e.get("tower", 0))
				sub = "%d층" % v
			"daily":
				var d: Dictionary = e.get("daily", {})
				if str(d.get("date", "")) != today:
					continue
				v = int(d.get("wave", 0))
				sub = "클리어" if d.get("won", false) else "%d라운드" % v
		if v <= 0:
			continue
		list.append({"name": str(e.get("name", "?")), "value": v, "sub": sub, "dev": dev})
	list.sort_custom(func(x, y): return x["value"] > y["value"])
	var rank := {}
	for i in list.size():
		rank[list[i]["dev"]] = i + 1
	c = {"t": now, "list": list, "rank": rank}
	_lb[kind] = c
	_lb_dirty[kind] = false
	return c


func _record_match(dev: String, inst: Node) -> void:
	## 검증된 판 요약(판 표가 있는 것만)으로 랭킹 기록: 무한 모드 최고 라운드, 탑 최고 층, 오늘의 결계
	var s: Dictionary = inst.last_summary
	if s.is_empty() or s.get("rejected", false) or not s.get("ticket", false) or not _db.has(dev):
		return
	var rec: Dictionary = _db[dev]
	var stage := str(s.get("stage", ""))
	var wave := int(s.get("wave", 0))
	if stage == "" and s.get("mode", "") == "solo":
		if wave > int(rec.get("endless", 0)):
			rec["endless"] = wave
			rec["endless_sub"] = str(GameData.DIFFICULTIES[clampi(int(s.get("diff", 0)), 0, GameData.DIFFICULTIES.size() - 1)]["name"])
			_lb_dirty["endless"] = true
	elif stage.begins_with("T") and s.get("won", false):
		var floor_n := int(stage.substr(1))
		if floor_n > int(rec.get("tower", 0)):
			rec["tower"] = floor_n
			_lb_dirty["tower"] = true
	elif stage == Story.daily_id():
		var today := Story.kst_date()
		var d: Dictionary = rec.get("daily", {})
		var won: bool = s.get("won", false)
		if str(d.get("date", "")) != today or wave > int(d.get("wave", 0)) or (won and not d.get("won", false)):
			rec["daily"] = {"date": today, "wave": maxi(wave, int(d.get("wave", 0)) if str(d.get("date", "")) == today else 0), "won": won or (d.get("won", false) and str(d.get("date", "")) == today)}
			_lb_dirty["daily"] = true
	_db_dirty = true


func _record_for(id: int) -> Dictionary:
	var dev: String = _devices.get(id, "peer%d" % id)
	return _record_dev(dev, _names.get(id, "?"))


func _record_dev(dev: String, player_name := "") -> Dictionary:
	if not _db.has(dev):
		_db[dev] = {"name": player_name if player_name != "" else "?", "rating": 1000, "wins": 0, "losses": 0, "coop_best": 0}
		_db_dirty = true
	var rec: Dictionary = _db[dev]
	if player_name != "" and player_name != "?" and rec["name"] != player_name:
		rec["name"] = player_name
		_db_dirty = true
	return rec


func _public(rec: Dictionary) -> Dictionary:
	## 레이팅/전적만 (계정 재화는 _c_profile/_c_op 로 따로)
	var d := {}
	for k in ["name", "rating", "wins", "losses", "coop_best", "endless", "tower"]:
		if rec.has(k):
			d[k] = rec[k]
	return d


func _peer_of(dev: String) -> int:
	for id in _devices:
		if _devices[id] == dev:
			return id
	return 0


func _rate(r: Dictionary, wdev: String, ldev: String, wid := 0, lid := 0) -> void:
	r["rated"] = true
	if wdev.split("#")[0] == ldev.split("#")[0]:
		_log("같은 기기끼리 대전 → 레이팅 없음")
		return
	var w := _record_dev(wdev)
	var l := _record_dev(ldev)
	var ew := 1.0 / (1.0 + pow(10.0, (float(l["rating"]) - float(w["rating"])) / 400.0))
	var delta := maxi(1, int(round(ELO_K * (1.0 - ew))))
	var gain := delta
	# 새 계정(대전 5판 미만)을 이긴 기존 계정은 조금만 오른다 (새 계정으로 점수 몰아주기 방지).
	# 둘 다 새 계정이면 정상대로 (새 계정끼리 붙어서 레이팅이 같이 줄어들지 않게)
	var w_new := int(w.get("wins", 0)) + int(w.get("losses", 0)) < PROVISIONAL_GAMES
	var l_new := int(l.get("wins", 0)) + int(l.get("losses", 0)) < PROVISIONAL_GAMES
	if l_new and not w_new:
		gain = mini(delta, PROVISIONAL_GAIN)
	w["rating"] = int(w["rating"]) + gain
	l["rating"] = maxi(0, int(l["rating"]) - delta)
	w["wins"] = int(w["wins"]) + 1
	l["losses"] = int(l["losses"]) + 1
	var now := int(Time.get_unix_time_from_system())
	w["last_pvp"] = {"won": true, "t": now}
	l["last_pvp"] = {"won": false, "t": now}
	_db_dirty = true
	_lb_dirty["pvp"] = true
	_log("레이팅: %s +%d (%d) / %s -%d (%d)" % [w["name"], gain, w["rating"], l["name"], delta, l["rating"]])
	_stat("pvp_rated", 1)
	for pair in [[wdev, wid, w, gain], [ldev, lid, l, -delta]]:
		var pid: int = pair[1] if _devices.get(pair[1], "") == pair[0] else _peer_of(pair[0])
		if pid != 0 and _names.has(pid):
			_to_client(pid, "_c_rating", [_public(pair[2]), pair[3]])


func _load_db() -> bool:
	## DB 읽기. 본 파일이 깨졌으면 최신 온전한 백업으로. 둘 다 안 되면 false (전용 서버는 멈춘다)
	_db = {}
	_codes = {}
	var res := SafeFile.load_json_with_backup(DB_PATH, BACKUP_DIR)
	if res["data"] is Dictionary:
		_db = res["data"]
		if res["source"] != DB_PATH:
			_log("경고: server_db.json 대신 %s 에서 불러왔습니다" % res["source"])
			_db_dirty = true
	elif res["corrupt"]:
		if not dedicated or OS.get_environment("SQD_ALLOW_EMPTY_DB") == "1":
			push_warning("server_db.json 이 깨져 빈 DB 로 시작합니다")
			return true
		return false
	for dev in _db:
		var e = _db[dev]
		if e is Dictionary and str(e.get("recovery", "")) != "":
			_codes[str(e["recovery"])] = dev
	return true


func _save_db(force := false) -> void:
	## 바뀐 게 있을 때만, 임시 파일에 쓰고 교체 (쓰는 중 꺼져도 예전 파일이 남는다)
	if not _db_dirty:
		return
	if not force and _save_timer > 0.0:
		return
	_save_timer = SAVE_EVERY
	if SafeFile.write_text(DB_PATH, JSON.stringify(_db)):
		_db_dirty = false


func _save_soon() -> void:
	## 곧 저장 (1초 안에). 매번 바로 쓰면 큰 DB 에서 서버가 멈칫하므로 모아서 쓴다
	_db_dirty = true
	_save_timer = minf(_save_timer, 1.0)


func _flush_all() -> void:
	for dev in _econ:
		_store_econ(dev)
	_save_db(true)
	if _iap != null:
		_iap.save()


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
	_try_resolve(rid, true)   # 이전 판 결과가 덜 정리됐으면 마무리
	r["playing"] = true
	r["rated"] = r["mode"] != "pvp"
	r["reports"] = {}
	r["defeated"] = {}
	r["report_t"] = 0.0
	var m: Array = r["members"]
	r["pair"] = m.duplicate()
	r["pair_dev"] = [_devices.get(m[0], "peer%d" % m[0]), _devices.get(m[1], "peer%d" % m[1])]
	var seed_v := randi()
	if r["mode"] == "pvp":
		# 온라인 대전 시작 시각: 이 판의 정산은 온라인 판 표로만 (오프라인 판인 척 승리를 주장하지 못하게)
		var t_now := int(Time.get_unix_time_from_system())
		for dev in r["pair_dev"]:
			if _db.has(dev):
				_db[dev]["pvp_room_t"] = t_now
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
		if r["mode"] == "pvp" and not r.get("rated", true) and r.has("pair") and id in r["pair"]:
			# 매치 도중 나간 쪽 패배
			var li: int = r["pair"].find(id)
			_rate(r, r["pair_dev"][1 - li], r["pair_dev"][li], r["pair"][1 - li], id)
		for m in r["members"]:
			_to_client(m, "_c_partner_left", [])
	if r["members"].is_empty():
		_try_resolve(rid, true)
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
	## 로비 목록 갱신은 모아서 (방이 자주 생기고 없어져도 0.3초에 한 번)
	_rooms_dirty = true


func _flush_rooms() -> void:
	## 방에 없는(로비에 있는) 사람들에게만 목록 갱신
	_rooms_dirty = false
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
func _c_welcome(id: int, list: Array, server_time: int) -> void:
	my_id = id
	connected = true
	rooms = list
	if not is_server and server_time > 0:
		# 하루 초기화·방치 보상은 서버 시각 기준 (기기 시계를 바꿔도 같게)
		Story.clock_offset = server_time - int(Time.get_unix_time_from_system())
	connection_changed.emit(true)
	status_changed.emit("서버 접속 완료! 방을 만들거나 참가하세요.")
	rooms_updated.emit(list)


@rpc("authority", "reliable")
func _c_config(cfg: Dictionary) -> void:
	server_config = cfg
	Profile.coin_mult = clampf(float(cfg.get("coin_event_mult", 1.0)), 1.0, 5.0)
	config_received.emit(cfg)
	var notice := str(cfg.get("notice", "")).strip_edges()
	if notice != "":
		notice_received.emit(notice)


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
func _c_leaderboard(kind: String, list: Array, my_rank: int) -> void:
	leaderboard_received.emit(kind, list, my_rank)


@rpc("authority", "reliable")
func _c_rooms(list: Array) -> void:
	rooms = list
	rooms_updated.emit(list)


@rpc("authority", "reliable")
func _c_room(state: Dictionary) -> void:
	room = state
	room_updated.emit(state)


@rpc("authority", "reliable")
func _a_error(msg: String) -> void:
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
# 서버 운영 설정 (user://server_config.json): 공지·코인 이벤트. 서버를 끄지 않고 파일만 고치면 30초 안에 반영
#   {"notice": "점검 안내...", "event_name": "주말 코인 2배", "coin_event_mult": 2.0}
# ===========================================================================
func _reload_config(force := false) -> void:
	if not FileAccess.file_exists(CONFIG_PATH):
		if not _config.is_empty():
			_config = {}
			_broadcast_config()
		return
	var mt := FileAccess.get_modified_time(CONFIG_PATH)
	if not force and mt == _config_mtime:
		return
	_config_mtime = mt
	var d = SafeFile.read_json(CONFIG_PATH)
	if not d is Dictionary:
		_log("server_config.json 을 읽지 못했습니다 (JSON 확인)")
		return
	_config = d
	_log("운영 설정: 공지 '%s', 이벤트 '%s', 코인 x%.1f" % [str(d.get("notice", "")).substr(0, 30), d.get("event_name", ""), _coin_mult()])
	if not force:
		_broadcast_config()


func _coin_mult() -> float:
	return clampf(float(_config.get("coin_event_mult", 1.0)), 1.0, 5.0)


func _public_config() -> Dictionary:
	return {"notice": str(_config.get("notice", "")).substr(0, 300), "event_name": str(_config.get("event_name", "")).substr(0, 40),
		"coin_event_mult": _coin_mult()}


func _broadcast_config() -> void:
	var c := _public_config()
	for id in _names:
		_to_client(id, "_c_config", [c])


# ===========================================================================
# 계정 복구 코드: 서버가 계정마다 코드 하나를 만들어 두고, 새 폰/재설치에서 코드를 넣으면 그 계정을 이어받는다
# ===========================================================================
static func normalize_code(code: String) -> String:
	var out := ""
	for ch in code.to_upper():
		if ch in CODE_CHARS:
			out += ch
	return out


static func format_code(raw: String) -> String:
	return "%s-%s-%s" % [raw.substr(0, 4), raw.substr(4, 4), raw.substr(8, 4)]


func _new_code() -> String:
	var bytes := Crypto.new().generate_random_bytes(12)
	var raw := ""
	for b in bytes:
		raw += CODE_CHARS[b % CODE_CHARS.length()]
	return raw


@rpc("any_peer", "reliable")
func _s_recovery_code() -> void:
	if not (is_server and dedicated):
		return
	var id := _sender()
	var dev: String = _devices.get(id, "")
	if not _allow(id, "code") or dev == "" or "#" in dev or not _db.has(dev) or not _db[dev].has("profile"):
		_to_client(id, "_c_recovery_code", [""])
		return
	var rec: Dictionary = _db[dev]
	var raw := str(rec.get("recovery", ""))
	if raw == "":
		raw = _new_code()
		while _codes.has(raw):
			raw = _new_code()
		rec["recovery"] = raw
		_codes[raw] = dev
		_save_soon()
		_log("복구 코드 발급: %s" % _names.get(id, "?"))
	_to_client(id, "_c_recovery_code", [format_code(raw)])


@rpc("any_peer", "reliable")
func _s_redeem(code: String) -> void:
	if not (is_server and dedicated):
		return
	var id := _sender()
	if not _names.has(id):
		return
	# 틀린 입력만 센다 (맞는 코드는 제한에 걸리지 않게)
	var keys := _redeem_keys(id)
	for k in keys:
		if not _rl_has(k[0], k[1]):
			_to_client(id, "_c_recovery", [false, "잠시 후 다시 시도하세요", ""])
			return
	var raw := normalize_code(code.substr(0, 32))
	var target: String = _codes.get(raw, "")
	if raw.length() != 12 or target == "" or not _db.has(target):
		for k in keys:
			_rl_take(k[0], k[1])
		_to_client(id, "_c_recovery", [false, "코드를 찾을 수 없어요", ""])
		return
	var cur: String = _devices.get(id, "")
	if cur == target:
		_to_client(id, "_c_recovery", [true, "이미 이 계정이에요", target])
		return
	# 그 계정으로 접속 중인 다른 기기는 내보낸다
	var other := _peer_of(target)
	if other != 0 and other != id:
		_to_client(other, "_a_error", ["다른 기기에서 이 계정을 가져갔습니다."])
		_leave(other)
		_detach_account(other)
		if peer != null:
			peer.disconnect_peer.call_deferred(other)
	_leave(id)
	_detach_account(id)
	_devices[id] = target
	var rec := _record_for(id)
	_log("계정 복구: %s → %s" % [cur, target])
	_to_client(id, "_c_recovery", [true, "계정을 되찾았어요", target])
	_to_client(id, "_c_record", [_public(rec)])
	var inst := _econ_for(target)
	_to_client(id, "_c_profile", [inst.to_dict() if inst != null else {}, inst == null])


@rpc("authority", "reliable")
func _c_recovery_code(code: String) -> void:
	recovery_code.emit(code)


@rpc("authority", "reliable")
func _c_recovery(ok: bool, msg: String, dev: String) -> void:
	if ok and dev != "" and dev != Profile.device_id:
		# 이 기기가 그 계정이 된다. 곧 오는 _c_profile 로 진행·결제가 서버 값으로 바뀐다
		Profile.device_id = dev
		Profile.linked = true
		Profile.pending_ops = []
		Profile.save()
		Profile.flush()
	recovery_result.emit(ok, msg)


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
	if not is_server:
		return
	_rooms_timer -= delta
	if _rooms_dirty and _rooms_timer <= 0.0:
		_rooms_timer = 0.3
		_flush_rooms()
	if not dedicated:
		return
	_save_timer -= delta
	if _save_timer <= 0.0:
		_save_db()
	_tick_timer -= delta
	if _tick_timer <= 0.0:
		_tick_timer = 1.0
		_tick()
	_backup_timer -= delta
	if _backup_timer <= 0.0:
		_backup_timer = BACKUP_EVERY
		_log_stats()
		_save_db(true)
		SafeFile.backup(DB_PATH, BACKUP_DIR, BACKUP_KEEP)
		if _iap != null:
			_iap.backup(BACKUP_DIR, BACKUP_KEEP)


func _tick() -> void:
	## 1초마다: 대전 결과 시간 초과 정리, 운영 설정 다시 읽기, 환불 확인
	var now := Time.get_ticks_msec() / 1000.0
	for rid in _rooms.keys():
		var r: Dictionary = _rooms[rid]
		if not r.get("rated", true) and not r.get("reports", {}).is_empty() and now - float(r.get("report_t", now)) > REPORT_TIMEOUT:
			_try_resolve(rid, true)
	_config_timer -= 1.0
	if _config_timer <= 0.0:
		_config_timer = 30.0
		_reload_config()
	if _iap != null:
		_iap.tick()


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


const MIGRATE_SPEND_CAP := 12000   # 이전할 때 인정하는 영구 강화(특성+유닛 레벨) 코인 가치 상한


static func sanitize_migration(d: Dictionary) -> Dictionary:
	## 첫 접속 때 기기에 있던 진행을 서버로 옮긴다. 기기 파일은 조작될 수 있으므로 상한을 둔다
	var p: Node = ProfileScript.new()
	p.server_side = true
	p.from_dict(d)
	p.coins = clampi(p.coins, 0, 5000)
	p.level = clampi(p.level, 1, 30)
	p.xp = clampi(p.xp, 0, GameData.xp_to_next(p.level))
	p.streak = clampi(p.streak, 0, 5)
	for id in p.items.keys():
		if GameData.shop_item(id).is_empty():
			p.items.erase(id)
		else:
			p.items[id] = clampi(int(p.items[id]), 0, 10)
	for id in p.discovered.keys():
		if not GameData.UNITS.has(str(id)):
			p.discovered.erase(id)
	# 영구 강화: 코인 가치 MIGRATE_SPEND_CAP 까지만 (모든 항목을 1레벨씩 번갈아 올려 가며 인정)
	var want := {}
	for id in p.perks.keys():
		if not GameData.perk(id).is_empty():
			want["p:" + id] = clampi(int(p.perks[id]), 0, int(GameData.perk(id)["max"]))
	for id in p.unit_levels.keys():
		if GameData.UNITS.has(id) and p.discovered.has(id):
			want["u:" + id] = clampi(int(p.unit_levels[id]), 0, GameData.UNIT_MAX_LEVEL)
	p.perks = {}
	p.unit_levels = {}
	var budget := MIGRATE_SPEND_CAP
	var progress := true
	while progress:
		progress = false
		for k in want:
			var id: String = k.substr(2)
			var is_perk: bool = k.begins_with("p:")
			var cur: int = p.perk_level(id) if is_perk else p.unit_level(id)
			if cur >= int(want[k]):
				continue
			var cost: int = p.perk_price(id) if is_perk else GameData.unit_level_cost(id, cur)
			if cost > budget:
				continue
			budget -= cost
			if is_perk:
				p.perks[id] = cur + 1
			else:
				p.unit_levels[id] = cur + 1
			progress = true
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
	# 옮긴 기록으로 이미 도달한 업적 단계·★ 상자는 "받은 것"으로 처리 (조작된 기록으로 보상 받기 방지)
	for a in GameData.ACHIEVEMENTS:
		var tier := clampi(int(p.achievements.get(a["id"], 0)), 0, a["goals"].size())
		var v: int = p.ach_value(a["stat"])
		while tier < a["goals"].size() and v >= a["goals"][tier]:
			tier += 1
		p.achievements[a["id"]] = tier
	for ch in Story.CHAPTERS.size():
		for step in Story.CHEST_STEPS.size():
			if p.chapter_stars(ch + 1) >= int(Story.CHEST_STEPS[step][0]):
				p.chests["%d-%d" % [ch + 1, step]] = true
	# 하루 단위 값은 새로 (기기에서 조작된 횟수를 믿지 않음)
	p.ad_date = ""
	p.ad_count = 0
	p.ad_extra = {"date": "", "result": 0, "idle": 0}
	p.roulette = {"date": "", "free": false, "ads": 0}
	p.daily = {"date": "", "progress": {}, "claimed": {}, "all": false}
	p.attendance = {"last": str(p.attendance.get("last", "")).substr(0, 10), "day": clampi(int(p.attendance.get("day", 0)), 0, 6)}
	p.idle_last = clampi(p.idle_last, int(Time.get_unix_time_from_system()) - 8 * 3600, int(Time.get_unix_time_from_system()))
	p.ticket = {}
	p.offline_settle = {"date": "", "n": 0}
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
	if d.size() > 64 or var_to_bytes(d).size() > 256 * 1024:
		d = {}
	_db[dev]["profile"] = sanitize_migration(d)
	_save_soon()
	var inst := _econ_for(dev)
	_log("계정 이전: %s (코인 %d)" % [_names.get(id, "?"), inst.coins])
	_to_client(id, "_c_profile", [inst.to_dict(), false])


func _valid_op_args(op: String, args: Array) -> bool:
	## 작업 인자 모양 검사 (값의 범위는 Profile.run_op 이 다시 확인)
	if op.length() > 24 or not op in ProfileScript.OPS or args.size() > 4:
		return false
	for a in args:
		if a is Dictionary:
			if op != "match_end" or a.size() > 40 or var_to_bytes(a).size() > 16384:
				return false
		elif a is String:
			if a.length() > 64:
				return false
		elif not (a is int or a is float or a is bool):
			return false
	return true


@rpc("any_peer", "reliable")
func _s_op(req_id: int, op: String, args: Array) -> void:
	if not (is_server and dedicated):
		return
	var id := _sender()
	var dev: String = _devices.get(id, "")
	var inst := _econ_for(dev)
	if inst == null:
		return
	var result: Variant = null
	if not _allow(id, "op") or not _valid_op_args(op, args):
		result = null
	elif op == "match_end" and not _take_match_end(dev):
		result = null
	elif op == "match_end" and not (args.size() == 1 and args[0] is Dictionary):
		result = null
	else:
		inst.coin_mult = _coin_mult()
		if op == "match_end":
			_prepare_match_end(dev, inst, args[0])
		var c0: int = inst.coins
		result = inst.run_op(op, args)
		_stat("op_" + op, 1)
		if inst.coins != c0:
			_stat("coins_in" if inst.coins > c0 else "coins_out", absi(inst.coins - c0))
		if op == "begin_match":
			_annotate_ticket(id, inst)
		elif op == "match_end":
			_record_match(dev, inst)
			if result is Dictionary and result.get("rejected", false):
				_stat("match_rejected", 1)
	inst.rating = int(_db[dev].get("rating", 1000))
	_store_econ(dev)
	_to_client(id, "_c_op", [req_id, result, inst.to_dict()])


func _annotate_ticket(id: int, inst: Node) -> void:
	## 판 표에 서버가 아는 사실을 적는다: 지금 온라인 방에서 게임 중이면 온라인 판 (모드는 방 모드)
	var rid: int = _peer_room.get(id, -1)
	if rid >= 0 and _rooms[rid]["playing"]:
		inst.ticket["online"] = true
		inst.ticket["mode"] = _rooms[rid]["mode"]
		inst.ticket["stage"] = ""
		inst.ticket["diff"] = 0


func _prepare_match_end(dev: String, inst: Node, s: Dictionary) -> void:
	## 온라인 대전의 승패는 서버가 반영한 레이팅 결과로 (클라이언트 주장 무시).
	## 정산 안 된 온라인 대전이 있으면 대전 요약은 표가 없거나 오프라인 표여도 그 온라인 판으로 본다
	var tk: Dictionary = inst.ticket
	var online_pvp: bool = tk.get("online", false) and tk.get("mode", "") == "pvp"
	var rt := int(_db[dev].get("pvp_room_t", 0))
	if not online_pvp and str(s.get("mode", "")) == "pvp" and rt > 0 and inst.now() - rt <= PVP_SETTLE_WINDOW:
		inst.ticket = {"mode": "pvp", "stage": "", "diff": 0, "t": rt, "online": true}
		tk = inst.ticket
		online_pvp = true
		s["stage"] = ""
	if online_pvp:
		_db[dev].erase("pvp_room_t")
		var lp: Dictionary = _db[dev].get("last_pvp", {})
		s["won"] = bool(lp.get("won", false)) and int(lp.get("t", 0)) >= int(tk.get("t", 0))


@rpc("any_peer", "reliable")
func _s_iap(req_id: int, product_id: String, token: String) -> void:
	## 결제 영수증 검증 → 지급. 검증은 Google Play Developer API (IapVerifier)
	if not (is_server and dedicated):
		return
	var id := _sender()
	var dev: String = _devices.get(id, "")
	if _econ_for(dev) == null or product_id.length() > 32 or token.length() > 4096:
		return
	if not _allow(id, "iap"):
		_to_client(id, "_c_iap", [req_id, false, product_id, _econ_for(dev).to_dict(), "잠시 후 다시 시도하세요"])
		return
	var res: Dictionary = await _iap.verify(product_id, token, dev)
	var inst := _econ_for(dev)   # 기다리는 동안 나갔을 수 있음 (그래도 지급은 DB 에)
	var temp := false
	if inst == null and _db.has(dev) and _db[dev].has("profile"):
		inst = ProfileScript.new()
		inst.server_side = true
		inst.from_dict(_db[dev]["profile"])
		temp = true
	if inst == null:
		return
	var ok: bool = res.get("ok", false)
	if ok:
		if res.get("grant", "full") == "restore":
			ok = inst.iap_restore(product_id)
			res["msg"] = "구매를 복원했어요" if ok else "이미 받은 상품"
		else:
			ok = inst.iap_grant(product_id)
			if not ok:
				res["msg"] = "이미 받은 상품"
		if temp:
			_db[dev]["profile"] = inst.to_dict()
			_db_dirty = true
		else:
			_store_econ(dev)
		_save_db(true)
		_log("결제 %s: %s %s" % ["지급" if ok else "거절", _names.get(id, "?"), product_id])
		if ok:
			_stat("iap_" + product_id, 1)
	var d: Dictionary = inst.to_dict()
	if temp:
		inst.free()
	if _names.has(id) and _devices.get(id, "") == dev:
		_to_client(id, "_c_iap", [req_id, ok, product_id, d, str(res.get("msg", ""))])


func revoke_purchase(dev: String, product_id: String, full := true) -> void:
	## (IapVerifier) 환불·취소된 결제 회수 (full = false 면 복원 받은 권리만). 접속 중이면 바로 알려 준다
	if not _db.has(dev):
		return
	var inst := _econ_for(dev)
	if inst != null:
		inst.iap_revoke(product_id, full)
		_store_econ(dev)
		var pid := _peer_of(dev)
		if pid != 0:
			_to_client(pid, "_c_op", [0, null, inst.to_dict()])
	elif _db[dev].has("profile"):
		var p: Node = ProfileScript.new()
		p.server_side = true
		p.from_dict(_db[dev]["profile"])
		p.iap_revoke(product_id, full)
		_db[dev]["profile"] = p.to_dict()
		p.free()
	_save_soon()
	_log("결제 회수(환불): %s %s" % [_db[dev].get("name", "?"), product_id])


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
