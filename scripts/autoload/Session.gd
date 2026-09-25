extends Node
## 현재 게임 설정(모드, 참가자)을 씬 전환 사이에 보관한다.

var mode := "solo"                # solo / coop / pvp
var players: Array = []           # [{name, kind: human|bot|remote, keys: -1|0|1}]
var online := false
var local_index := 0
var seed_value := 0
var bot_level := 1                # 0 쉬움 / 1 보통 / 2 어려움
var player_name := "플레이어"


func setup_local(p_mode: String, p_players: Array) -> void:
	mode = p_mode
	players = p_players
	online = false
	local_index = 0
	seed_value = randi()


func setup_online(p_mode: String, seed_v: int, host_name: String, guest_name: String, my_index: int) -> void:
	mode = p_mode
	online = true
	seed_value = seed_v
	local_index = my_index
	players = [
		{"name": host_name, "kind": "human" if my_index == 0 else "remote", "keys": 0 if my_index == 0 else -1},
		{"name": guest_name, "kind": "human" if my_index == 1 else "remote", "keys": 0 if my_index == 1 else -1},
	]


func mode_name(m: String) -> String:
	return {"solo": "솔로", "coop": "협동", "pvp": "대전"}.get(m, m)
