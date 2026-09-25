extends Node
## 효과음: 외부 파일 없이 코드로 짧은 톤(삑/뿅)을 만들어 재생한다.
## 전용 서버/헤드리스에서는 자동으로 꺼진다.

const RATE := 22050

var enabled := true
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
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = volume_db
		add_child(p)
		_players.append(p)


func play(sound: String) -> void:
	if not enabled or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(sound, -1000)) < 60:
		return
	_last[sound] = now
	for p in _players:
		if not p.playing:
			p.stream = _streams[sound]
			p.play()
			return


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
