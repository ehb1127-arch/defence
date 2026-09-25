extends Control
## 메인 메뉴: 모드 선택, AI 난이도, 온라인 로비(서버 접속/방 목록/빠른 매칭), 게임 방법.

var _name_edit: LineEdit
var _help: PanelContainer
var _online: PanelContainer
var _settings: PanelContainer
var _coin_lbl: Label
var _rewards_btn: ActionButton
var _achieve: PanelContainer
var _record_lbl: Label
var _rank_panel: PanelContainer
var _rank_list: ItemList
var _diff_btns: Array = []
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
	_build_background()
	_build_top()
	_build_mode_cards()
	_build_bottom()

	# ---- 온라인 로비 (카드 누르면 열리는 창) ----
	_online = _panel(Vector2(500, 100), Vector2(600, 720), "온라인")
	_online.visible = false
	var rv: VBoxContainer = _online.get_child(0)

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
	var rec_row := HBoxContainer.new()
	rv.add_child(rec_row)
	_record_lbl = _label("")
	_record_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_record_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.45))
	rec_row.add_child(_record_lbl)
	var rank_btn := _small_btn("랭킹", func(): Net.request_leaderboard())
	rank_btn.size_flags_horizontal = Control.SIZE_SHRINK_END
	rank_btn.custom_minimum_size = Vector2(110, 40)
	rec_row.add_child(rank_btn)
	rv.add_child(_small_btn("닫기", func(): _online.visible = false))
	_build_rank_panel()
	Net.record_updated.connect(func(_r): _refresh_record())
	Net.leaderboard_received.connect(_on_leaderboard)
	_refresh_record()

	Net.status_changed.connect(_on_status)
	Net.rooms_updated.connect(_on_rooms)
	Net.room_updated.connect(func(_r): _refresh_online())
	Net.connection_changed.connect(func(_c): _refresh_online())
	_on_rooms(Net.rooms)
	_refresh_online()
	_build_help()
	_build_settings()
	_build_achievements()
	# 온라인 매치에서 돌아왔으면 로비를 바로 보여준다
	if Net.connected:
		_online.visible = true


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
	if mode == "solo" and not Profile.tutorial_done:
		Session.tutorial = true
	get_tree().change_scene_to_file("res://scenes/Match.tscn")


# ===========================================================================
# 메인 화면 구성 (이미지 교체: art/ui/menu_bg.png, art/ui/logo.png, art/icons/mode_*.png)
# ===========================================================================
func _build_background() -> void:
	var bg_tex := Art.tex("ui/menu_bg")
	if bg_tex != null:
		var tr := TextureRect.new()
		tr.texture = bg_tex
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.size = Vector2(1600, 900)
		add_child(tr)
		return
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.07, 0.1)
	bg.size = Vector2(1600, 900)
	add_child(bg)
	var deco := _MenuDeco.new()
	deco.size = Vector2(1600, 900)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(deco)


class _MenuDeco:
	extends Control
	## 이미지 배경이 없을 때: 천천히 도는 사각 트랙과 적 점들
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		for k in 3:
			var s := 300.0 + k * 180.0
			var r := Rect2(Vector2(800, 470) - Vector2(s, s) / 2, Vector2(s, s))
			draw_rect(r, Color(0.3, 0.35, 0.5, 0.08 + 0.03 * k), false, 18.0 - k * 4)
			var per := s * 4.0
			for n in 10:
				var d := fmod(t * (40.0 + k * 15.0) + n * per / 10.0, per)
				var side := int(d / s)
				var q := d - side * s
				var p: Vector2 = [r.position + Vector2(q, 0), r.position + Vector2(s, q), r.position + Vector2(s - q, s), r.position + Vector2(0, s - q)][side]
				draw_circle(p, 5.0, Color(0.85, 0.3, 0.3, 0.35))


func _build_top() -> void:
	var logo_tex := Art.tex("ui/logo")
	if logo_tex != null:
		var tr := TextureRect.new()
		tr.texture = logo_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		tr.position = Vector2(40, 24)
		tr.size = Vector2(520, 130)
		add_child(tr)
	else:
		var title := Label.new()
		title.text = "사각 디펜스"
		title.add_theme_font_size_override("font_size", 64)
		title.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
		title.add_theme_color_override("font_outline_color", Color(0.25, 0.12, 0))
		title.add_theme_constant_override("outline_size", 12)
		title.position = Vector2(44, 28)
		add_child(title)
	# 계정 레벨 + 경험치
	var lvbox := HBoxContainer.new()
	lvbox.position = Vector2(48, 112)
	lvbox.add_theme_constant_override("separation", 10)
	add_child(lvbox)
	var lv := Label.new()
	lv.text = "Lv.%d" % Profile.level
	lv.add_theme_font_size_override("font_size", 22)
	lv.add_theme_color_override("font_color", Color(0.5, 0.85, 1.0))
	lvbox.add_child(lv)
	var xb := ProgressBar.new()
	xb.max_value = GameData.xp_to_next(Profile.level)
	xb.value = Profile.xp
	xb.show_percentage = false
	xb.custom_minimum_size = Vector2(220, 14)
	xb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lvbox.add_child(xb)
	var xl := Label.new()
	xl.text = "%d / %d" % [Profile.xp, GameData.xp_to_next(Profile.level)]
	xl.add_theme_font_size_override("font_size", 14)
	xl.add_theme_color_override("font_color", Color(0.6, 0.65, 0.75))
	lvbox.add_child(xl)
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.position = Vector2(770, 30)
	right.size = Vector2(730, 70)
	right.alignment = BoxContainer.ALIGNMENT_END
	add_child(right)
	var chip := PanelContainer.new()
	var csb := StyleBoxFlat.new()
	csb.bg_color = Color(0, 0, 0, 0.45)
	csb.set_corner_radius_all(30)
	csb.content_margin_left = 12
	csb.content_margin_right = 18
	chip.add_theme_stylebox_override("panel", csb)
	var ch := HBoxContainer.new()
	ch.add_child(UIIcon.make("coin", 40))
	_coin_lbl = Label.new()
	_coin_lbl.add_theme_font_size_override("font_size", 28)
	_coin_lbl.add_theme_color_override("font_color", Color(0.85, 0.72, 1.0))
	ch.add_child(_coin_lbl)
	chip.add_child(ch)
	right.add_child(chip)
	_rewards_btn = ActionButton.make("gift", Color(1, 0.75, 0.4), "보상 (출석 · 미션 · 룰렛)", func(): get_tree().change_scene_to_file("res://scenes/Rewards.tscn"), Vector2(70, 64))
	right.add_child(_rewards_btn)
	right.add_child(ActionButton.make("trophy", Color(1, 0.8, 0.3), "업적", func(): _achieve.visible = true, Vector2(70, 64)))
	right.add_child(ActionButton.make("book", Color(0.6, 0.8, 1.0), "도감 (유닛 레벨업)", func(): get_tree().change_scene_to_file("res://scenes/Collection.tscn"), Vector2(70, 64)))
	var shop := ActionButton.make("shop", Color(1, 0.8, 0.35), "상점", func(): get_tree().change_scene_to_file("res://scenes/Shop.tscn"), Vector2(70, 64))
	right.add_child(shop)
	right.add_child(ActionButton.make("help", Color(0.45, 0.6, 0.9), "게임 방법", _show_help, Vector2(64, 64)))
	right.add_child(ActionButton.make("gear", Color(0.85, 0.9, 1.0), "설정", func(): _settings.visible = true, Vector2(64, 64)))
	right.add_child(ActionButton.make("close", Color(1, 0.5, 0.5), "종료", func(): get_tree().quit(), Vector2(64, 64)))
	Profile.changed.connect(_refresh_coins)
	_refresh_coins()


func _refresh_coins() -> void:
	if is_instance_valid(_coin_lbl):
		_coin_lbl.text = str(Profile.coins)
	if is_instance_valid(_rewards_btn):
		var n := Profile.reward_badge()
		_rewards_btn.count = n
		_rewards_btn.glow = n > 0
		_rewards_btn.queue_redraw()


func _build_mode_cards() -> void:
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 22)
	grid.add_theme_constant_override("v_separation", 22)
	grid.position = Vector2(230, 180)
	add_child(grid)
	var cards := [
		["mode_solo", "star", Color(1, 0.85, 0.35), "솔로", "40라운드 생존", func(): _start_local("solo", false)],
		["mode_coop_ai", "gift", Color(0.5, 0.95, 0.8), "협동 · AI", "AI 동료와 함께", func(): _start_local("coop", false)],
		["mode_pvp_ai", "attack", Color(1, 0.5, 0.4), "대전 · AI", "먼저 무너지면 패배", func(): _start_local("pvp", false)],
		["mode_coop_2p", "heart", Color(0.5, 0.95, 0.8), "협동 · 2인", "한 화면에서 친구와", func(): _start_local("coop", true)],
		["mode_pvp_2p", "elite", Color(1, 0.5, 0.4), "대전 · 2인", "한 화면 대결", func(): _start_local("pvp", true)],
		["mode_online", "ad", Color(0.45, 0.7, 1.0), "온라인", "서버 · 빠른 매칭", func(): _online.visible = true],
	]
	for c in cards:
		var card := VBoxContainer.new()
		card.add_theme_constant_override("separation", 6)
		var icon_name: String = c[0] if Art.icon(c[0]) != null else c[1]
		var b := ActionButton.make(icon_name, c[2], c[3] + "\n" + c[4], c[5], Vector2(360, 200))
		card.add_child(b)
		var t := Label.new()
		t.text = c[3]
		t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		t.add_theme_font_size_override("font_size", 24)
		t.add_theme_color_override("font_color", c[2].lightened(0.2))
		card.add_child(t)
		var sub := Label.new()
		sub.text = c[4]
		sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		sub.add_theme_font_size_override("font_size", 15)
		sub.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
		card.add_child(sub)
		grid.add_child(card)


func _build_bottom() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.position = Vector2(230, 812)
	bar.size = Vector2(1140, 60)
	add_child(bar)
	bar.add_child(UIIcon.make("mission", 34, Color(0.6, 0.9, 1.0)))
	_name_edit = LineEdit.new()
	_name_edit.text = Session.player_name
	_name_edit.max_length = 10
	_name_edit.placeholder_text = "닉네임"
	_name_edit.custom_minimum_size = Vector2(220, 48)
	_name_edit.add_theme_font_size_override("font_size", 20)
	bar.add_child(_name_edit)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(20, 0)
	bar.add_child(sp)
	bar.add_child(UIIcon.make("elite", 34, Color(1, 0.55, 0.45)))
	for lvl in 3:
		var lv := lvl
		var b := ActionButton.make("star", [Color(0.6, 0.9, 0.6), Color(1, 0.85, 0.35), Color(1, 0.4, 0.4)][lvl],
			"AI 난이도: " + ["쉬움", "보통", "어려움"][lvl], func(): _set_diff(lv), Vector2(64, 52))
		b.badge = ["1", "2", "3"][lvl]
		bar.add_child(b)
		_diff_btns.append(b)
	_set_diff(Session.bot_level)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(sp2)
	var st := Label.new()
	st.text = "최고 ROUND %d   ·   승리 %d / %d판" % [int(Profile.stats["best_round"]), int(Profile.stats["wins"]), int(Profile.stats["games"])]
	st.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
	st.add_theme_font_size_override("font_size", 16)
	bar.add_child(st)


func _refresh_record() -> void:
	if not is_instance_valid(_record_lbl):
		return
	var r := Net.my_record
	if r.is_empty():
		_record_lbl.text = "대전 레이팅 %d" % Profile.rating
	else:
		_record_lbl.text = "대전 레이팅 %d  ·  %d승 %d패  ·  협동 최고 R%d" % [int(r.get("rating", 1000)), int(r.get("wins", 0)), int(r.get("losses", 0)), int(r.get("coop_best", 0))]


func _build_rank_panel() -> void:
	_rank_panel = _panel(Vector2(520, 120), Vector2(560, 660), "랭킹 (대전 레이팅)")
	_rank_panel.visible = false
	var v: VBoxContainer = _rank_panel.get_child(0)
	_rank_list = ItemList.new()
	_rank_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_rank_list.add_theme_font_size_override("font_size", 18)
	v.add_child(_rank_list)
	v.add_child(_small_btn("닫기", func(): _rank_panel.visible = false))


func _on_leaderboard(list: Array, my_rank: int) -> void:
	_rank_list.clear()
	for i in list.size():
		var e: Dictionary = list[i]
		var idx := _rank_list.add_item("%2d위   %s   %d점   (%d승 %d패)" % [i + 1, e["name"], int(e["rating"]), int(e["wins"]), int(e["losses"])])
		if i < 3:
			_rank_list.set_item_custom_fg_color(idx, [Color(1, 0.85, 0.3), Color(0.85, 0.85, 0.95), Color(0.9, 0.6, 0.35)][i])
	if list.is_empty():
		_rank_list.add_item("아직 기록이 없습니다. 첫 대전의 주인공이 되세요!")
	if my_rank > 0:
		_rank_list.add_item("")
		_rank_list.add_item("내 순위: %d위" % my_rank)
	_rank_panel.visible = true


func _build_achievements() -> void:
	_achieve = _panel(Vector2(360, 90), Vector2(880, 740), "업적")
	_achieve.visible = false
	var v: VBoxContainer = _achieve.get_child(0)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 10)
	scroll.add_child(list)
	for a in GameData.ACHIEVEMENTS:
		var tier := Profile.ach_tier(a["id"])
		var goals: Array = a["goals"]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.add_child(UIIcon.make(a["icon"], 44, Color(1, 0.8, 0.3) if tier > 0 else Color(0.45, 0.47, 0.55)))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := Label.new()
		var next_i := mini(tier, goals.size() - 1)
		t.text = "%s  %s" % [a["name"], "★".repeat(tier) + "☆".repeat(goals.size() - tier)]
		t.add_theme_font_size_override("font_size", 18)
		col.add_child(t)
		var d := Label.new()
		d.text = ("완료!" if tier >= goals.size() else a["desc"] % goals[next_i]) + ("" if tier >= goals.size() else "   보상 코인 %d" % a["coins"][next_i])
		d.add_theme_font_size_override("font_size", 14)
		d.add_theme_color_override("font_color", Color(0.65, 0.7, 0.8))
		col.add_child(d)
		var bar := ProgressBar.new()
		bar.max_value = goals[next_i]
		bar.value = mini(Profile.ach_value(a["stat"]), goals[next_i])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 10)
		col.add_child(bar)
		row.add_child(col)
		var num := Label.new()
		num.text = "%d / %d" % [mini(Profile.ach_value(a["stat"]), goals[next_i]), goals[next_i]]
		num.custom_minimum_size = Vector2(130, 0)
		num.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(num)
		list.add_child(row)
	v.add_child(_small_btn("닫기", func(): _achieve.visible = false))


func _set_diff(lvl: int) -> void:
	Session.bot_level = lvl
	for i in _diff_btns.size():
		_diff_btns[i].selected = i == lvl
		_diff_btns[i].queue_redraw()


func _build_settings() -> void:
	_settings = _panel(Vector2(560, 250), Vector2(480, 330), "설정")
	_settings.visible = false
	var v: VBoxContainer = _settings.get_child(0)
	for spec in [["sound", "효과음"], ["captions", "버튼 이름 표시 (이미지 적용 전 도움)"]]:
		var cb := CheckButton.new()
		cb.text = spec[1]
		cb.button_pressed = Profile.settings[spec[0]]
		var key: String = spec[0]
		cb.toggled.connect(func(on): Profile.set_setting(key, on))
		v.add_child(cb)
	var lab := CheckButton.new()
	lab.text = "전장 유닛 이름 항상 표시"
	lab.button_pressed = Art.show_unit_labels
	lab.toggled.connect(func(on): Art.show_unit_labels = on)
	v.add_child(lab)
	var close := _small_btn("닫기", func(): _settings.visible = false)
	v.add_child(close)


func _replay_tutorial() -> void:
	Profile.tutorial_done = false
	_start_local("solo", false)


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
	var replay := Button.new()
	replay.text = "튜토리얼 다시 하기"
	replay.custom_minimum_size = Vector2(0, 44)
	replay.pressed.connect(_replay_tutorial)
	v.add_child(replay)
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
	s += "\n[b][color=#ffd84d]★ 강화 시도 · 합성 대성공[/color][/b]\n"
	s += "• 칸을 선택하고 망치 버튼: 골드로 ★ 강화 시도. ★당 공격력 +25%%, 공속 +10%%\n"
	s += "• 성공률 85%% → 65%% → 45%% → 30%% → 20%%. ★3 이상에서 실패하면 한 단계 하락할 수 있어요\n"
	s += "• [color=#ffb050]★3 각성[/color]: 특성 수치 1.35배, 연쇄/다중사격 +1   ·   [color=#ff80ff]★5 초월[/color]: 한 번에 두 번 공격\n"
	s += "• 합성하면 8%% 확률로 [b]대성공[/b] - 한 단계를 더 건너뜁니다\n"
	s += "• 등급 강화도 레벨마다 공격력 +12%%, 공속 +3%%\n"
	s += "\n[b][color=#ffd84d]시너지[/color][/b] (서로 다른 유닛 종류 수)\n"
	for tag in GameData.SYNERGY_ORDER:
		var d: Dictionary = GameData.SYNERGIES[tag]
		var tiers: Array = []
		for t in d["tiers"]:
			tiers.append("%d종 %s" % [t[0], d["desc"] % int(t[1] * 100 if tag != "lightning" else t[1])])
		s += "• [color=#%s]%s[/color]: %s\n" % [d["color"].to_html(false), d["name"], " / ".join(tiers)]
	s += "\n[b][color=#ffd84d]보스 스킬[/color][/b]\n"
	s += "• 보스는 돌진·포효(유닛 침묵)·부하 소환·재생·용암 방패·화염 폭발·순간이동을 씁니다\n"
	s += "• 시전 중(빨간 원)에 [b]기절시키면 스킬이 끊깁니다[/b] - 기사·투석병·수호천사·뇌신이 핵심!\n"
	s += "• 최종 보스는 체력 50%%에서 2페이즈로 광폭화\n"
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
