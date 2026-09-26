extends Node
## 배경음악: 화면·상황별 곡을 부드럽게 바꿔 튼다 (크로스페이드).
## 곡 파일: res://audio/bgm/<이름>.ogg / .mp3 / .wav 중 먼저 있는 것 (기본은 tools/make_audio.py 로 만든 .wav,
## import 에서 반복·QOA 압축). 전문 음원으로 바꾸려면 같은 이름의 .ogg 를 넣기만 하면 된다 (docs/AUDIO.md).
## 전용 서버/헤드리스에서는 자동으로 꺼진다.

const TRACKS := ["lobby", "map", "battle", "boss"]
const FADE := 0.9
const BASE_DB := -11.0

var enabled := true      # 오디오 장치 사용 가능 (헤드리스/서버면 false)
var muted := false       # 설정에서 끔
var current := ""        # 지금 (또는 곧) 나오는 곡
var _streams := {}
var _players: Array[AudioStreamPlayer] = []
var _active := 0
var _tweens: Array = [null, null]
var _duck := 0.0         # 승리/패배 음악 등 잠깐 줄일 때 (dB)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless" or "--server" in OS.get_cmdline_user_args():
		enabled = false
		return
	for i in 2:
		var p := AudioStreamPlayer.new()
		p.volume_db = -80.0
		p.finished.connect(_on_finished.bind(i))
		add_child(p)
		_players.append(p)


func _stream(track: String) -> AudioStream:
	if _streams.has(track):
		return _streams[track]
	var s: AudioStream = null
	for ext in ["ogg", "mp3", "wav"]:
		var path := "res://audio/bgm/%s.%s" % [track, ext]
		if ResourceLoader.exists(path):
			s = load(path)
			break
	if s != null and "loop" in s:
		s.set("loop", true)   # ogg / mp3
	if s is AudioStreamWAV and (s as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		# import 설정이 빠졌어도 반복되게
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_FORWARD
		(s as AudioStreamWAV).loop_begin = 0
		(s as AudioStreamWAV).loop_end = int((s as AudioStreamWAV).get_length() * (s as AudioStreamWAV).mix_rate)
	_streams[track] = s
	return s


## 곡 바꾸기. 같은 곡이면 아무것도 안 함. "" 이면 멈춤.
func play(track: String) -> void:
	if track == current:
		return
	current = track
	if not enabled:
		return
	if muted or track == "":
		_fade_out_all()
		return
	var s := _stream(track)
	if s == null:
		_fade_out_all()
		return
	var old := _active
	_active = 1 - _active
	var p := _players[_active]
	p.stream = s
	p.volume_db = -40.0
	p.play()
	_fade(_active, _target_db())
	_fade(old, -60.0, true)


func stop() -> void:
	play("")


## 승리·패배 음악처럼 효과음을 돋보이게 할 때 잠깐 줄였다가 되돌림
func duck(seconds: float, amount_db := -14.0) -> void:
	if not enabled:
		return
	_duck = amount_db
	_fade(_active, _target_db(), false, 0.25)
	get_tree().create_timer(seconds, true).timeout.connect(func():
		_duck = 0.0
		if current != "" and not muted:
			_fade(_active, _target_db(), false, 1.2))


func set_muted(on: bool) -> void:
	muted = on
	if not enabled:
		return
	if on:
		_fade_out_all()
	else:
		var t := current
		current = ""
		play(t)


func _target_db() -> float:
	return BASE_DB + _duck


func _fade(i: int, to_db: float, stop_after := false, dur := FADE) -> void:
	if _tweens[i] != null and (_tweens[i] as Tween).is_valid():
		(_tweens[i] as Tween).kill()
	var p := _players[i]
	var tw := create_tween()
	tw.tween_property(p, "volume_db", to_db, dur)
	if stop_after:
		tw.tween_callback(p.stop)
	_tweens[i] = tw


func _fade_out_all() -> void:
	for i in _players.size():
		if _players[i].playing:
			_fade(i, -60.0, true)


func _on_finished(i: int) -> void:
	# 반복 설정이 없는 음원이어도 지금 곡이면 다시 튼다
	if i == _active and current != "" and not muted:
		_players[i].play()
