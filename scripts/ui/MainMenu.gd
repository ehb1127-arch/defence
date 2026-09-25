extends Control
## 메인 메뉴: 모드 선택, AI 난이도, LAN 방 만들기/참가, 게임 방법.

var _name_edit: LineEdit
var _ip_edit: LineEdit
var _port_edit: LineEdit
var _diff: OptionButton
var _net_mode: OptionButton
var _lobby_label: Label
var _btn_start_online: Button
var _help: PanelContainer
var _t := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = GameData.ui_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.11)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "사각 디펜스"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
	title.position = Vector2(0, 50)
	title.size = Vector2(1600, 90)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	var sub := Label.new()
	sub.text = "사각형 안에서 막아라!  소환 · 합성 · 신화 조합 · 협동 & 대전"
	sub.add_theme_font_size_override("font_size", 20)
	sub.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
	sub.position = Vector2(0, 145)
	sub.size = Vector2(1600, 30)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(sub)

	# ---- 왼쪽: 로컬 플레이 ----
	var left := _panel(Vector2(170, 210), Vector2(600, 620), "혼자 / 같은 화면에서")
	var lv: VBoxContainer = left.get_child(0)
	var name_row := HBoxContainer.new()
	lv.add_child(name_row)
	name_row.add_child(_label("닉네임"))
	_name_edit = LineEdit.new()
	_name_edit.text = Session.player_name
	_name_edit.max_length = 10
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(_name_edit)
	var diff_row := HBoxContainer.new()
	lv.add_child(diff_row)
	diff_row.add_child(_label("AI 난이도"))
	_diff = OptionButton.new()
	for d in ["쉬움", "보통", "어려움"]:
		_diff.add_item(d)
	_diff.selected = Session.bot_level
	_diff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	diff_row.add_child(_diff)
	lv.add_child(HSeparator.new())
	lv.add_child(_big_btn("솔로 플레이", "40웨이브를 혼자 막아내세요", func(): _start_local("solo", false)))
	lv.add_child(_big_btn("협동 - AI 동료와", "AI와 함께 두 사각형을 지킵니다", func(): _start_local("coop", false)))
	lv.add_child(_big_btn("대전 - AI 상대로", "먼저 무너지는 쪽이 패배!", func(): _start_local("pvp", false)))
	lv.add_child(_big_btn("협동 - 로컬 2인", "한 화면에서 친구와 (WASD / 방향키)", func(): _start_local("coop", true)))
	lv.add_child(_big_btn("대전 - 로컬 2인", "한 화면에서 친구와 대결", func(): _start_local("pvp", true)))

	# ---- 오른쪽: 온라인 ----
	var right := _panel(Vector2(830, 210), Vector2(600, 620), "온라인 (LAN / IP 직접 접속)")
	var rv: VBoxContainer = right.get_child(0)
	var ip_row := HBoxContainer.new()
	rv.add_child(ip_row)
	ip_row.add_child(_label("주소"))
	_ip_edit = LineEdit.new()
	_ip_edit.text = "127.0.0.1"
	_ip_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ip_row.add_child(_ip_edit)
	ip_row.add_child(_label("포트"))
	_port_edit = LineEdit.new()
	_port_edit.text = str(Net.DEFAULT_PORT)
	_port_edit.custom_minimum_size = Vector2(90, 0)
	ip_row.add_child(_port_edit)
	var mode_row := HBoxContainer.new()
	rv.add_child(mode_row)
	mode_row.add_child(_label("방 모드"))
	_net_mode = OptionButton.new()
	_net_mode.add_item("협동")
	_net_mode.add_item("대전")
	_net_mode.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mode_row.add_child(_net_mode)
	var btn_row := HBoxContainer.new()
	rv.add_child(btn_row)
	btn_row.add_child(_small_btn("방 만들기", _host))
	btn_row.add_child(_small_btn("참가하기", _join))
	btn_row.add_child(_small_btn("나가기", func(): Net.close(); _lobby_label.text = "연결 종료"))
	_btn_start_online = _small_btn("게임 시작!", func(): Net.start_match())
	_btn_start_online.disabled = true
	rv.add_child(_btn_start_online)
	_lobby_label = _label("방을 만들거나 호스트 주소로 참가하세요.")
	_lobby_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lobby_label.custom_minimum_size = Vector2(0, 60)
	rv.add_child(_lobby_label)
	var net_help := _label("호스트는 방 모드를 고르고 [방 만들기] → 상대는 호스트 IP로 [참가하기]\n포트 %d(UDP)가 열려 있어야 합니다." % Net.DEFAULT_PORT)
	net_help.add_theme_font_size_override("font_size", 13)
	net_help.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	net_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rv.add_child(net_help)
	rv.add_child(HSeparator.new())
	rv.add_child(_big_btn("게임 방법", "규칙 · 조합표 · 조작법", _show_help))
	rv.add_child(_big_btn("종료", "", func(): get_tree().quit()))

	Net.lobby_changed.connect(func(t): _lobby_label.text = t)
	_build_help()


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.2
		_btn_start_online.disabled = not (Net.is_host and Net.is_active())


func _panel(pos: Vector2, sz: Vector2, header: String) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.11, 0.12, 0.17)
	sb.border_color = Color(0.3, 0.35, 0.5)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = sz
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var h := _label(header)
	h.add_theme_font_size_override("font_size", 24)
	h.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	v.add_child(h)
	return p


func _label(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.custom_minimum_size = Vector2(70, 0)
	return l


func _big_btn(t: String, desc: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t + ("\n" + desc if desc != "" else "")
	b.custom_minimum_size = Vector2(0, 62 if desc != "" else 44)
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(cb)
	return b


func _small_btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.custom_minimum_size = Vector2(0, 42)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	return b


func _apply_name() -> void:
	var n := _name_edit.text.strip_edges()
	Session.player_name = n if n != "" else "플레이어"
	Session.bot_level = _diff.selected


func _start_local(mode: String, two_humans: bool) -> void:
	_apply_name()
	var players: Array = [{"name": Session.player_name, "kind": "human", "keys": 0}]
	if mode != "solo":
		if two_humans:
			players[0]["name"] = "1P " + Session.player_name
			players.append({"name": "2P", "kind": "human", "keys": 1})
		else:
			var bot_name: String = ["초보 AI", "AI", "고수 AI"][Session.bot_level]
			players.append({"name": ("동료 " if mode == "coop" else "상대 ") + bot_name, "kind": "bot", "keys": -1})
	Session.setup_local(mode, players)
	get_tree().change_scene_to_file("res://scenes/Match.tscn")


func _host() -> void:
	_apply_name()
	var err := Net.host(int(_port_edit.text), "coop" if _net_mode.selected == 0 else "pvp")
	if err != OK:
		_lobby_label.text = "방 생성 실패 (오류 %d) - 포트를 확인하세요" % err


func _join() -> void:
	_apply_name()
	var err := Net.join(_ip_edit.text.strip_edges(), int(_port_edit.text))
	if err != OK:
		_lobby_label.text = "접속 실패 (오류 %d)" % err


func _show_help() -> void:
	_help.visible = true


func _build_help() -> void:
	_help = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.07, 0.1, 0.98)
	sb.border_color = Color(1, 0.85, 0.35)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(12)
	sb.set_content_margin_all(20)
	_help.add_theme_stylebox_override("panel", sb)
	_help.position = Vector2(150, 60)
	_help.size = Vector2(1300, 780)
	_help.visible = false
	add_child(_help)
	var v := VBoxContainer.new()
	_help.add_child(v)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var rt := RichTextLabel.new()
	rt.bbcode_enabled = true
	rt.fit_content = true
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.add_theme_font_size_override("normal_font_size", 16)
	rt.add_theme_font_size_override("bold_font_size", 18)
	rt.text = _help_text()
	scroll.add_child(rt)
	var close := Button.new()
	close.text = "닫기"
	close.custom_minimum_size = Vector2(0, 44)
	close.pressed.connect(func(): _help.visible = false)
	v.add_child(close)


func _help_text() -> String:
	var s := "[b][color=#ffd84d]기본 규칙[/color][/b]\n"
	s += "• 적은 사각형 테두리 길을 시계방향으로 계속 돕니다. 필드에 적이 [b]%d마리[/b] 쌓이면 패배!\n" % GameData.ENEMY_LIMIT
	s += "• 유닛은 사각형 안쪽 칸에 배치되어 사거리 안의 적을 자동 공격합니다. 칸을 클릭 → 다른 칸 클릭으로 위치를 바꿀 수 있어요. (사거리 짧은 유닛은 바깥쪽에!)\n"
	s += "• %d초마다 웨이브, 10웨이브마다 [color=#ff5577]보스[/color] (%d초 안에 못 잡으면 격노: 가중치 2배). %d웨이브 보스를 잡으면 승리.\n" % [int(GameData.WAVE_TIME), int(GameData.BOSS_WAVE_TIME), GameData.FINAL_WAVE]
	s += "\n[b][color=#ffd84d]소환 · 합성 · 조합[/color][/b]\n"
	s += "• [b]소환[/b]: 골드로 무작위 유닛 소환 (쓸 때마다 비용 +1). 같은 유닛은 한 칸에 3마리까지 쌓입니다.\n"
	s += "• [b]합성[/b]: 같은 유닛 3마리가 쌓인 칸(반짝임) → 한 단계 높은 등급 무작위 유닛. (일반→희귀→영웅→전설)\n"
	s += "• [b]도박[/b]: 보석으로 영웅(60%%) / 전설(25%%) 유닛에 도전! 실패하면 꽝.\n"
	s += "• [b]강화[/b]: 등급군별 공격력 강화, [b]소환 행운[/b]은 고등급 소환 확률 증가.\n"
	s += "• [b][color=#ff4050]신화 조합[/color][/b]: 특정 유닛들을 모으면 강력한 신화 유닛으로 조합! 신화는 자동 발동 스킬을 가집니다.\n"
	for m in GameData.RECIPES:
		s += "    - [color=#ff6070]%s[/color] = %s  ([i]%s[/i])\n" % [GameData.UNITS[m]["name"], GameData.recipe_text(m), GameData.UNITS[m]["desc"]]
	s += "\n[b][color=#ffd84d]유닛 도감[/color][/b]\n"
	for r in 4:
		var names: Array = []
		for id in GameData.units_of_rarity(r):
			names.append("%s(%s)" % [GameData.UNITS[id]["name"], GameData.UNITS[id]["desc"]])
		s += "• [color=#%s]%s[/color]: %s\n" % [GameData.RARITY_COLORS[r].to_html(false), GameData.RARITY_NAMES[r], ", ".join(names)]
	s += "\n[b][color=#ffd84d]재미 요소[/color][/b]\n"
	s += "• 5웨이브마다 [b]랜덤 이벤트[/b]: 황금 고블린, 행운의 시간, 광란, 보급품, 번개 폭풍, 보석비\n"
	s += "• 적을 잡으면 가끔 [b]보물상자[/b]가 떨어집니다. 사라지기 전에 클릭!\n"
	s += "• 음유시인은 주변 8칸 공속 버프, 수호천사는 사거리 내 적 둔화 → [b]배치가 전략[/b]\n"
	s += "• [b]도전 과제[/b]를 달성하면 보상 지급 (도박 3연속 실패도 위로금이 있어요)\n"
	s += "\n[b][color=#ffd84d]협동 모드[/color][/b]\n"
	s += "• 두 전장의 적 수 [b]합계 %d[/b]에 닿으면 함께 패배. 둘 다 최종 보스를 잡으면 승리.\n" % GameData.COOP_ENEMY_LIMIT
	s += "• 골드 선물, 유닛 선물(칸 선택 → 선물)로 조합 재료를 몰아주세요. 처치 게이지를 모아 [b]합동 폭격[/b]!\n"
	s += "\n[b][color=#ffd84d]대전 모드[/color][/b]\n"
	s += "• 상대에게 [b]잡몹 떼[/b], [b]정예 괴수[/b], [b]저주[/b](공속 -30%%)를 보내 먼저 무너뜨리세요. 40웨이브 이후 적이 급격히 강해집니다.\n"
	s += "\n[b][color=#ffd84d]조작[/color][/b]\n"
	s += "• 마우스: 칸 클릭 선택/이동, 우클릭 선택 해제, 패널 버튼으로 모든 행동\n"
	s += "• 1P: WASD 커서, Space 선택, Q 소환, E 합성, R 영웅도박, T 신화조합, F 공격/폭격, X 판매\n"
	s += "• 2P: 방향키 커서, Enter 선택, U 소환, I 합성, O 영웅도박, P 신화조합, L 공격/폭격, K 판매 (숫자패드 1~5, 0 도 가능)\n"
	s += "• Esc 일시정지, 배속 버튼으로 x1/x2/x3\n"
	return s
