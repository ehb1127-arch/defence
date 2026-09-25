extends Node
## LAN 온라인 (ENet). 각 피어는 자기 전장만 시뮬레이션하고
## 스냅샷(표시용)과 이벤트(적 보내기, 선물, 패배 등)만 주고받는다.

signal lobby_changed(text: String)
signal guest_joined(guest_name: String)
signal connection_failed
signal disconnected
signal event_received(kind: String, data: Variant)
signal snapshot_received(data: Dictionary)

const DEFAULT_PORT := 24680

var peer: ENetMultiplayerPeer
var is_host := false
var host_mode := "coop"
var remote_name := ""
var remote_id := 0


func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_active() -> bool:
	return peer != null and multiplayer.multiplayer_peer == peer and remote_id != 0


func host(port: int, p_mode: String) -> Error:
	close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 1)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	host_mode = p_mode
	lobby_changed.emit("방 생성 완료 (포트 %d) - 상대를 기다리는 중..." % port)
	return OK


func join(ip: String, port: int) -> Error:
	close()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		peer = null
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	lobby_changed.emit("%s:%d 에 접속 중..." % [ip, port])
	return OK


func close() -> void:
	if peer != null:
		peer.close()
	peer = null
	remote_id = 0
	remote_name = ""
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()


func _on_peer_connected(id: int) -> void:
	if is_host:
		remote_id = id


func _on_peer_disconnected(id: int) -> void:
	if id == remote_id:
		remote_id = 0
		remote_name = ""
		lobby_changed.emit("상대가 나갔습니다.")
		disconnected.emit()


func _on_connected_to_server() -> void:
	remote_id = 1
	_hello.rpc_id(1, Session.player_name)


func _on_connection_failed() -> void:
	close()
	lobby_changed.emit("접속 실패")
	connection_failed.emit()


func _on_server_disconnected() -> void:
	close()
	lobby_changed.emit("호스트와 연결이 끊겼습니다.")
	disconnected.emit()


@rpc("any_peer", "reliable")
func _hello(guest_name: String) -> void:
	if not is_host:
		return
	remote_id = multiplayer.get_remote_sender_id()
	remote_name = guest_name
	_welcome.rpc_id(remote_id, Session.player_name, host_mode)
	lobby_changed.emit("%s 님이 입장했습니다! 시작 버튼을 누르세요." % guest_name)
	guest_joined.emit(guest_name)


@rpc("authority", "reliable")
func _welcome(host_name: String, p_mode: String) -> void:
	remote_name = host_name
	host_mode = p_mode
	lobby_changed.emit("%s 님의 방(%s)에 입장! 호스트의 시작을 기다리는 중..." % [host_name, Session.mode_name(p_mode)])


func start_match() -> void:
	if not is_host or remote_id == 0:
		return
	var s := randi()
	_start.rpc(host_mode, s, Session.player_name, remote_name)


@rpc("authority", "call_local", "reliable")
func _start(p_mode: String, seed_v: int, host_name: String, guest_name: String) -> void:
	Session.setup_online(p_mode, seed_v, host_name, guest_name, 0 if is_host else 1)
	get_tree().change_scene_to_file("res://scenes/Match.tscn")


func send_event(kind: String, data: Variant) -> void:
	if is_active():
		_event.rpc_id(remote_id, kind, data)


@rpc("any_peer", "reliable")
func _event(kind: String, data: Variant) -> void:
	event_received.emit(kind, data)


func send_snapshot(d: Dictionary) -> void:
	if is_active():
		_snapshot.rpc_id(remote_id, d)


@rpc("any_peer", "unreliable_ordered")
func _snapshot(d: Dictionary) -> void:
	snapshot_received.emit(d)
