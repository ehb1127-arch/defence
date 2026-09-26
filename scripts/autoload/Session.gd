extends Node
## 현재 게임 설정(모드, 참가자)을 씬 전환 사이에 보관한다.

var mode := "solo"                # solo / coop / pvp
var players: Array = []           # [{name, kind: human|bot|remote, keys: -1|0|1}]
var online := false
var local_index := 0
var seed_value := 0
var bot_level := 1                # 0 쉬움 / 1 보통 / 2 어려움
var difficulty := 0               # 무한 모드 난이도 (GameData.DIFFICULTIES)
var carry: Dictionary = {}        # 이어하기: {stage, state} - 다음 스테이지/층에 배치 유지
var player_name := "플레이어"
var tutorial := false             # 다음 솔로 판에서 튜토리얼 표시
var open_recovery := false        # 로비에 돌아가면 계정 복구 창을 바로 연다 (첫 판 대사의 "계정 복구" 버튼)
var stage := ""                   # 스토리 스테이지 id ("" = 무한 모드)


func setup_local(p_mode: String, p_players: Array) -> void:
	stage = ""
	mode = p_mode
	players = p_players
	online = false
	local_index = 0
	seed_value = randi()


func setup_online(p_mode: String, seed_v: int, host_name: String, guest_name: String, my_index: int) -> void:
	mode = p_mode
	stage = ""
	online = true
	seed_value = seed_v
	local_index = my_index
	players = [
		{"name": host_name, "kind": "human" if my_index == 0 else "remote", "keys": 0 if my_index == 0 else -1},
		{"name": guest_name, "kind": "human" if my_index == 1 else "remote", "keys": 0 if my_index == 1 else -1},
	]


func mode_name(m: String) -> String:
	return {"solo": "솔로", "coop": "협동", "pvp": "대전"}.get(m, m)
