extends Control
## 메인 메뉴: 모드 선택, AI 난이도, 온라인 로비(서버 접속/방 목록/빠른 매칭), 게임 방법.

var _name_edit: LineEdit
var _diff: OptionButton
var _help: PanelContainer
# 온라인
var _addr_edit: LineEdit
var _btn_connect: Button
var _btn_lan: Button
var _btn_disconnect: Button
var _status: Label
var _room_list: ItemList
var _btn_refresh: Button
var _btn_join: Button
var _net_mode: OptionButton
var _room_name: LineEdit
var _btn_create: Button
var _btn_quick_coop: Button
var _btn_quick_pvp: Button
var _room_label: Label
var _btn_start: Button
var _btn_leave: Button
var _t := 0.0


func _ready() -> void:
	if Net.dedicated or "--server" in OS.get_cmdline_user_args() or OS.has_feature("dedicated_server"):
		get_tree().change_scene_to_file.call_deferred("res://scenes/Server.tscn")
		return
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
	var left := _panel(Vector2(170, 190), Vector2(600, 680), "혼자 / 같은 화면에서")
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
	lv.add_child(_big_btn("솔로 플레이", "40라운드를 혼자 막아내세요", func(): _start_local("solo", false)))
	lv.add_child(_big_btn("협동 - AI 동료와", "AI와 함께 두 사각형을 지킵니다", func(): _start_local("coop", false)))
	lv.add_child(_big_btn("대전 - AI 상대로", "먼저 무너지는 쪽이 패배!", func(): _start_local("pvp", false)))
	lv.add_child(_big_btn("협동 - 로컬 2인", "한 화면에서 친구와 (WASD / 방향키)", func(): _start_local("coop", true)))
	lv.add_child(_big_btn("대전 - 로컬 2인", "한 화면에서 친구와 대결", func(): _start_local("pvp", true)))

	lv.add_child(HSeparator.new())
	var misc := HBoxContainer.new()
	lv.add_child(misc)
	misc.add_child(_small_btn("게임 방법", _show_help))
	misc.add_child(_small_btn("종료", func(): get_tree().quit()))

	# ---- 오른쪽: 온라인 ----
	var right := _panel(Vector2(830, 190), Vector2(600, 680), "온라인")
	var rv: VBoxContainer = right.get_child(0)
	rv.add_theme_constant_override("separation", 8)
	var addr_row := HBoxContainer.new()
	rv.add_child(addr_row)
	addr_row.add_child(_label("서버"))
	_addr_edit = LineEdit.new()
	_addr_edit.text = Net.server_address
	_addr_edit.placeholder_text = "OCI 서버 공인 IP 또는 도메인"
	_addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	addr_row.add_child(_addr_edit)
	_btn_connect = _small_btn("접속", _connect)
	_btn_connect.size_flags_horizontal = Control.SIZE_SHRINK_END
	_btn_connect.custom_minimum_size = Vector2(90, 40)
	addr_row.add_child(_btn_connect)
	var conn_row := HBoxContainer.new()
	rv.add_child(conn_row)
	_btn_lan = _small_btn("이 PC 에서 서버 열기 (LAN)", _host_lan)
	conn_row.add_child(_btn_lan)
	_btn_disconnect = _small_btn("연결 끊기", func(): Net.close(); _status.text = "연결을 끊었습니다.")
	conn_row.add_child(_btn_disconnect)
	_status = _label("서버 주소를 입력하고 [접속] 하세요.")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.custom_minimum_size = Vector2(0, 40)
	_status.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	rv.add_child(_status)
	# 방 목록
	_room_list = ItemList.new()
	_room_list.custom_minimum_size = Vector2(0, 150)
	_room_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_list.item_activated.connect(func(_i): _join_selected())
	rv.add_child(_room_list)
	var list_row := HBoxContainer.new()
	rv.add_child(list_row)
	_btn_refresh = _small_btn("새로고침", func(): Net.request_rooms())
	list_row.add_child(_btn_refresh)
	_btn_join = _small_btn("선택한 방 참가", _join_selected)
	list_row.add_child(_btn_join)
	var create_row := HBoxContainer.new()
	rv.add_child(create_row)
	_net_mode = OptionButton.new()
	_net_mode.add_item("협동")
	_net_mode.add_item("대전")
	create_row.add_child(_net_mode)
	_room_name = LineEdit.new()
	_room_name.placeholder_text = "방 이름 (비우면 자동)"
	_room_name.max_length = 20
	_room_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_room_name)
	_btn_create = _small_btn("방 만들기", func(): _apply_name(); Net.create_room(_mode_sel(), _room_name.text))
	_btn_create.size_flags_horizontal = Control.SIZE_SHRINK_END
	_btn_create.custom_minimum_size = Vector2(110, 40)
	create_row.add_child(_btn_create)
	var quick_row := HBoxContainer.new()
	rv.add_child(quick_row)
	_btn_quick_coop = _small_btn("빠른 매칭 - 협동", func(): Net.quick_match("coop"))
	quick_row.add_child(_btn_quick_coop)
	_btn_quick_pvp = _small_btn("빠른 매칭 - 대전", func(): Net.quick_match("pvp"))
	quick_row.add_child(_btn_quick_pvp)
	rv.add_child(HSeparator.new())
	_room_label = _label("")
	_room_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_room_label.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	rv.add_child(_room_label)
	var room_row := HBoxContainer.new()
	rv.add_child(room_row)
	_btn_start = _small_btn("게임 시작!", func(): Net.start_match())
	room_row.add_child(_btn_start)
	_btn_leave = _small_btn("방 나가기", func(): Net.leave_room())
	room_row.add_child(_btn_leave)

	Net.status_changed.connect(_on_status)
	Net.rooms_updated.connect(_on_rooms)
	Net.room_updated.connect(func(_r): _refresh_online())
	Net.connection_changed.connect(func(_c): _refresh_online())
	_on_rooms(Net.rooms)
	_refresh_online()
	_build_help()


func _process(delta: float) -> void:
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_refresh_online()


func _mode_sel() -> String:
	return "coop" if _net_mode.selected == 0 else "pvp"


func _on_status(t: String) -> void:
	if is_instance_valid(_status):
		_status.text = t


func _on_rooms(list: Array) -> void:
	if not is_instance_valid(_room_list):
		return
	var keep := -1
	if _room_list.get_selected_items().size() > 0:
		keep = int(_room_list.get_item_metadata(_room_list.get_selected_items()[0]))
	_room_list.clear()
	for r in list:
		var state := "게임 중" if r["playing"] else ("대기 %d/2" % r["count"])
		var idx := _room_list.add_item("#%d  %s  [%s]  %s  -  %s" % [r["id"], r["name"], Session.mode_name(r["mode"]), state, ", ".join(r["players"])])
		_room_list.set_item_metadata(idx, r["id"])
		if r["playing"] or r["count"] >= 2:
			_room_list.set_item_custom_fg_color(idx, Color(0.5, 0.52, 0.58))
		if r["id"] == keep:
			_room_list.select(idx)
	if list.is_empty():
		var idx := _room_list.add_item("(열린 방이 없습니다 - 방을 만들거나 빠른 매칭!)")
		_room_list.set_item_disabled(idx, true)
		_room_list.set_item_metadata(idx, -1)


func _refresh_online() -> void:
	var c := Net.connected
	var in_room := not Net.room.is_empty()
	_btn_connect.disabled = c
	_btn_lan.disabled = c
	_btn_disconnect.disabled = not c and Net.peer == null
	_btn_refresh.disabled = not c or in_room
	_btn_join.disabled = not c or in_room
	_btn_create.disabled = not c or in_room
	_btn_quick_coop.disabled = not c or in_room
	_btn_quick_pvp.disabled = not c or in_room
	_room_list.visible = true
	_btn_start.disabled = not (c and in_room and Net.is_room_owner() and Net.room.get("members", []).size() >= 2 and not Net.room.get("playing", false))
	_btn_leave.disabled = not (c and in_room)
	if in_room:
		var r := Net.room
		var who := ", ".join(r.get("players", []))
		var wait := "상대를 기다리는 중..." if r.get("members", []).size() < 2 else ("방장이 시작하면 게임이 시작됩니다." if not Net.is_room_owner() else "[게임 시작!] 을 누르세요.")
		if r.get("quick", false):
			wait = "상대를 찾는 중... (들어오면 자동 시작)" if r.get("members", []).size() < 2 else "곧 시작합니다!"
		_room_label.text = "현재 방 #%d %s [%s]  -  %s\n%s" % [r.get("id", 0), r.get("name", ""), Session.mode_name(r.get("mode", "")), who, wait]
	else:
		_room_label.text = "방에 들어가 있지 않습니다." if c else ""


func _connect() -> void:
	_apply_name()
	Net.connect_to(_addr_edit.text)
	_addr_edit.text = Net.server_address


func _host_lan() -> void:
	_apply_name()
	Net.host_lan(Net.DEFAULT_PORT)


func _join_selected() -> void:
	var sel := _room_list.get_selected_items()
	if sel.is_empty():
		_status.text = "참가할 방을 목록에서 선택하세요."
		return
	var rid := int(_room_list.get_item_metadata(sel[0]))
	if rid >= 0:
		Net.join_room(rid)


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
	s += "• %d초마다 라운드가 바뀌고 적은 계속 쏟아집니다. 10라운드마다 [color=#ff5577]보스[/color]: 제한시간(%d초, 최종 보스 %d초) 안에 못 잡으면 [b]즉시 패배[/b]!\n" % [int(GameData.WAVE_TIME), int(GameData.BOSS_WAVE_TIME), int(GameData.FINAL_BOSS_TIME)]
	s += "• 5·15·25·35 라운드는 [color=#ffb0c0]보너스 라운드[/color]: %d초 안에 보물 돼지를 잡아 골드 획득 (전부 잡으면 보석). %d라운드 보스를 잡으면 승리.\n" % [int(GameData.BONUS_WAVE_TIME), GameData.FINAL_WAVE]
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
	s += "• 3·8·13… 라운드마다 [b]랜덤 이벤트[/b]: 황금 고블린, 행운의 시간, 광란, 보급품, 번개 폭풍, 보석비\n"
	s += "• 적을 잡으면 가끔 [b]보물상자[/b]가 떨어집니다. 사라지기 전에 클릭!\n"
	s += "• 음유시인은 주변 8칸 공속 버프, 수호천사는 사거리 내 적 둔화 → [b]배치가 전략[/b]\n"
	s += "• [b]도전 과제[/b]를 달성하면 보상 지급 (도박 3연속 실패도 위로금이 있어요)\n"
	s += "\n[b][color=#ffd84d]협동 모드[/color][/b]\n"
	s += "• 두 전장의 적 수 [b]합계 %d[/b]에 닿으면 함께 패배. 둘 다 최종 보스를 잡으면 승리.\n" % GameData.COOP_ENEMY_LIMIT
	s += "• 골드 선물, 유닛 선물(칸 선택 → 선물)로 조합 재료를 몰아주세요. 처치 게이지를 모아 [b]합동 폭격[/b]!\n"
	s += "\n[b][color=#ffd84d]대전 모드[/color][/b]\n"
	s += "• 상대에게 [b]잡몹 떼[/b], [b]정예 괴수[/b], [b]저주[/b](공속 -30%%)를 보내 먼저 무너뜨리세요. 보스를 놓쳐도 패배! 40라운드 이후 적이 급격히 강해집니다.\n"
	s += "\n[b][color=#ffd84d]조작[/color][/b]\n"
	s += "• 마우스: 칸 클릭 선택/이동, 우클릭 선택 해제, 패널 버튼으로 모든 행동\n"
	s += "• 1P: WASD 커서, Space 선택, Q 소환, E 합성, R 영웅도박, T 신화조합, F 공격/폭격, X 판매\n"
	s += "• 2P: 방향키 커서, Enter 선택, U 소환, I 합성, O 영웅도박, P 신화조합, L 공격/폭격, K 판매 (숫자패드 1~5, 0 도 가능)\n"
	s += "• Esc 일시정지, 배속 버튼으로 x1/x2/x3\n"
	return s
