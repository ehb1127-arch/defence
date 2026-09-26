extends Node
## 효과음: res://audio/sfx/<이름>.ogg / .wav 가 있으면 그 음원을, 없으면 코드로 만든 짧은 톤을 재생한다.
## 음원은 tools/make_audio.py 로 만든다. 전용 서버/헤드리스에서는 자동으로 꺼진다.

const RATE := 22050
## 자주 나는 소리는 음량을 낮추고, 너무 촘촘히 겹치지 않게 최소 간격(ms)을 둔다
const GAIN := {"hit": -9.0, "tick": -4.0, "click": -3.0, "coin": -4.0, "summon": -2.0, "heart": 2.0, "alarm": -9.0, "tick_boss": -4.0, "fail": -2.0}
const GAP := {"hit": 70, "coin": 45, "zap": 180, "ice": 180, "boom": 150, "click": 40}
const FILES := ["click", "summon", "merge", "rare", "legend", "coin", "fail", "round", "boss", "alarm",
	"heart", "tick", "tick_boss", "fever", "hit", "boom", "zap", "ice", "reward", "win", "lose"]

var enabled := true      # 오디오 장치 사용 가능 (헤드리스/서버면 false)
var muted := false       # 설정에서 끔
var volume_db := -8.0
var _streams := {}
var _last := {}
var _players: Array[AudioStreamPlayer] = []


func _ready() -> void:
	if DisplayServer.get_name() == "headless" or "--server" in OS.get_cmdline_user_args():
		enabled = false
		return
	_streams["tick"] = _tone([880.0], 0.07, 0.25, "sine")
	_streams["tick_boss"] = _tone([1320.0, 990.0], 0.06, 0.3, "square")
	_streams["round"] = _tone([523.0, 659.0, 784.0], 0.08, 0.25, "square")
	_streams["boss"] = _tone([196.0, 165.0, 196.0, 165.0, 196.0], 0.14, 0.3, "saw")
	_streams["summon"] = _tone([700.0, 950.0], 0.035, 0.15, "sine")
	_streams["merge"] = _tone([440.0, 660.0, 880.0], 0.045, 0.2, "sine")
	_streams["rare"] = _tone([523.0, 659.0, 784.0, 1047.0, 1319.0], 0.06, 0.25, "square")
	_streams["fail"] = _tone([330.0, 260.0, 196.0], 0.1, 0.25, "saw")
	_streams["alarm"] = _tone([600.0, 450.0], 0.09, 0.2, "square")
	_streams["win"] = _tone([523.0, 659.0, 784.0, 1047.0], 0.12, 0.3, "square")
	_streams["lose"] = _tone([392.0, 330.0, 262.0, 196.0], 0.18, 0.3, "saw")
	_streams["click"] = _tone([1200.0], 0.025, 0.12, "sine")
	_streams["heart"] = _tone([70.0, 58.0], 0.09, 0.55, "sine")
	_streams["fever"] = _tone([523.0, 784.0, 1047.0, 1568.0, 2093.0], 0.05, 0.28, "square")
	_streams["coin"] = _tone([1568.0, 2093.0], 0.03, 0.14, "sine")
	_streams["legend"] = _tone([523.0, 784.0, 1047.0, 1568.0, 2093.0], 0.08, 0.28, "square")
	_streams["reward"] = _tone([784.0, 988.0, 1175.0, 1568.0], 0.07, 0.25, "sine")
	_streams["hit"] = _tone([220.0], 0.03, 0.15, "square")
	_streams["boom"] = _tone([110.0, 82.0, 65.0], 0.08, 0.35, "saw")
	_streams["zap"] = _tone([1760.0, 880.0, 1760.0], 0.03, 0.18, "square")
	_streams["ice"] = _tone([2093.0, 2637.0, 3136.0], 0.04, 0.14, "sine")
	# 만들어 둔 음원이 있으면 톤 대신 사용
	for n in FILES:
		for ext in ["ogg", "wav"]:
			var path := "res://audio/sfx/%s.%s" % [n, ext]
			if ResourceLoader.exists(path):
				var st: AudioStream = load(path)
				if st != null:
					_streams[n] = st
					break
	for i in 12:
		var p := AudioStreamPlayer.new()
		p.volume_db = volume_db
		add_child(p)
		_players.append(p)


func play(sound: String) -> void:
	if not enabled or muted or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(sound, -1000)) < int(GAP.get(sound, 60)):
		return
	_last[sound] = now
	for p in _players:
		if not p.playing:
			p.stream = _streams[sound]
			p.volume_db = volume_db + float(GAIN.get(sound, 0.0))
			p.play()
			return
	# 모든 채널이 바쁘면 가벼운 소리는 버리고, 중요한 소리는 가장 오래된 채널을 빼앗는다
	if sound in ["hit", "coin", "tick", "click", "summon"]:
		return
	var oldest := _players[0]
	for p in _players:
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	oldest.stream = _streams[sound]
	oldest.volume_db = volume_db + float(GAIN.get(sound, 0.0))
	oldest.play()


func _tone(freqs: Array, each: float, vol: float, shape: String) -> AudioStreamWAV:
	var data := PackedByteArray()
	var n_each := int(each * RATE)
	data.resize(n_each * freqs.size() * 2)
	var idx := 0
	var phase := 0.0
	for f in freqs:
		for i in n_each:
			phase = fmod(phase + f / RATE, 1.0)
			var v := 0.0
			match shape:
				"square":
					v = 1.0 if phase < 0.5 else -1.0
					v *= 0.5
				"saw":
					v = (phase * 2.0 - 1.0) * 0.6
				_:
					v = sin(phase * TAU)
			# 짧은 어택/릴리즈로 딸깍 소리 방지
			var env := minf(1.0, minf(i / 60.0, (n_each - i) / 200.0))
			var s := int(clampf(v * vol * env, -1.0, 1.0) * 32767.0)
			data.encode_s16(idx, s)
			idx += 2
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w
