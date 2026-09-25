extends Node
## 전용 서버 모드에서 띄우는 빈 씬. 실제 로직은 Net(autoload)에 있고,
## 여기서는 주기적으로 상태를 로그로 남긴다.

const STATUS_INTERVAL := 60.0

var _t := 0.0


func _ready() -> void:
	Engine.max_fps = 60
	print("사각 디펜스 전용 서버 준비 완료. 종료: Ctrl+C / systemctl stop sqdefense")


func _process(delta: float) -> void:
	_t += delta
	if _t >= STATUS_INTERVAL:
		_t = 0.0
		var playing := 0
		for rid in Net._rooms:
			if Net._rooms[rid]["playing"]:
				playing += 1
		Net._log("상태: 접속자 %d명, 방 %d개 (게임 중 %d)" % [Net._names.size(), Net._rooms.size(), playing])
