extends Control
## 메인 메뉴: 모드 선택, AI 난이도, 온라인 로비(서버 접속/방 목록/빠른 매칭), 게임 방법.

var _name_edit: LineEdit
var _help: PanelContainer
var _online: PanelContainer
var _settings: PanelContainer
var _coin_lbl: Label
var _rewards_btn: ActionButton
var _achieve: PanelContainer
var _two_p: PanelContainer
var _idle_btn: ActionButton
var _idle_ad: ActionButton
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
var _dim: ColorRect
# 빠른 매칭 (상대가 없으면 AI 와 시작)
const SEARCH_AI_AFTER := 20.0        # 이만큼 기다려도 상대가 없으면 AI 대전으로
const SEARCH_OFFLINE_AFTER := 8.0    # 서버에 못 붙으면 이만큼 뒤 AI 대전으로
var _search_mode := ""
var _search_t := 0.0
var _quick_box: VBoxContainer
var _search_box: VBoxContainer
var _search_lbl: Label
var _search_sub: Label
var _room_box: VBoxContainer
var _dev_panel: PanelContainer
var _dev_btn: ActionButton
var _dev_taps := 0
var _conn_lbl: Label
# 랭킹
var _rank_kind := "pvp"
var _rank_tabs := {}
var _rank_rows: VBoxContainer
var _rank_mine: Label
# 계정 복구
var _recovery: PanelContainer
var _rec_code: Label
var _rec_edit: LineEdit
var _rec_msg: Label
# 서버 이벤트 배지 (server_config.event_name)
var _event_badge: PanelContainer
var _event_lbl: Label
static var _ftue_redirected := false   # 첫 실행 때 로비 대신 1-1 로 바로 (앱 실행당 한 번)


func _ready() -> void:
	if Net.dedicated or "--server" in OS.get_cmdline_user_args() or OS.has_feature("dedicated_server"):
		get_tree().change_scene_to_file.call_deferred("res://scenes/Server.tscn")
		return
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = UIKit.theme()
	# 완전히 새 계정의 첫 실행: 버튼 많은 로비 대신 바로 첫 스테이지 대사로 (FTUE)
	if _first_time() and not _ftue_redirected and not "--no-ftue" in OS.get_cmdline_user_args():
		_ftue_redirected = true
		var tree := get_tree()
		(func(): Campaign.start_stage("1-1", tree)).call_deferred()
		return
	_ftue_redirected = true
	Music.play("lobby")
	_build_background()
	_build_top()
	_build_mode_cards()
	_build_bottom()
	_build_idle()

	# 팝업 뒤 어둡게 (누르면 닫힘)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.6)
	_dim.size = Vector2(1600, 900)
	_dim.visible = false
	_dim.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: on_back())
	add_child(_dim)
	_build_online()
	_build_rank_panel()
	Net.record_updated.connect(func(_r): _refresh_record())
	Net.leaderboard_received.connect(_on_leaderboard)
	Net.notice_received.connect(_on_notice)
	Net.recovery_code.connect(_on_recovery_code)
	Net.recovery_result.connect(_on_recovery_result)
	Net.config_received.connect(func(_c): _refresh_event())
	Net.account_synced.connect(_refresh_coins)
	_refresh_record()
	Net.status_changed.connect(_on_status)
	Net.rooms_updated.connect(_on_rooms)
	Net.room_updated.connect(func(_r): _refresh_online())
	Net.connection_changed.connect(_on_connection)
	_on_rooms(Net.rooms)
	_refresh_online()
	_build_help()
	_build_settings()
	_build_achievements()
	_build_two_player()
	_build_event_badge()
	_auto_account()
	# 온라인 매치에서 돌아왔으면 로비를 바로 보여준다
	if Net.connected:
		_online.visible = true
		_check_notice.call_deferred()
	# 첫 판 대사에서 "계정 복구"를 눌러 왔으면 복구 창부터
	if Session.open_recovery:
		Session.open_recovery = false
		_open_recovery.call_deferred()


func _process(delta: float) -> void:
	if _dim != null:
		var any := false
		for p in _popups():
			if p != null and p.visible:
				any = true
		_dim.visible = any
	if _search_mode != "":
		_update_search(delta)
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		_refresh_online()
		_refresh_idle()


func _mode_sel() -> String:
	return "coop" if _net_mode.selected == 0 else "pvp"


func _on_status(t: String) -> void:
	if is_instance_valid(_status):
		_status.text = t
	_refresh_conn()


func _refresh_conn() -> void:
	## 플레이어용 연결 상태 (자세한 서버 메시지는 개발자 메뉴에서만)
	if not is_instance_valid(_conn_lbl):
		return
	if Net.connected:
		_conn_lbl.text = "● 서버 연결됨"
		_conn_lbl.add_theme_color_override("font_color", Color(0.5, 1, 0.6))
	elif Net.peer != null:
		_conn_lbl.text = "서버에 연결하는 중..."
		_conn_lbl.add_theme_color_override("font_color", Color(1, 0.9, 0.5))
	else:
		_conn_lbl.text = "서버에 연결되지 않았어요 · AI 와는 바로 할 수 있어요"
		_conn_lbl.add_theme_color_override("font_color", Color(1, 0.7, 0.55))


func _on_connection(c: bool) -> void:
	_refresh_online()
	if c:
		_check_notice()
		if _search_mode != "" and Net.room.is_empty():
			Net.quick_match(_search_mode)
		if is_instance_valid(_rank_panel) and _rank_panel.visible:
			Net.request_leaderboard(_rank_kind)


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
	if not is_instance_valid(_quick_box):
		return
	var c := Net.connected
	var in_room := not Net.room.is_empty()
	var quick_room: bool = in_room and Net.room.get("quick", false)
	_refresh_conn()
	_btn_connect.disabled = c
	_btn_lan.disabled = c
	_btn_disconnect.disabled = not c and Net.peer == null
	_btn_refresh.disabled = not c or in_room
	_btn_join.disabled = not c or in_room
	_btn_create.disabled = not c or in_room
	_search_box.visible = _search_mode != ""
	_quick_box.visible = _search_mode == "" and not (in_room and not quick_room)
	_room_box.visible = in_room and not quick_room and _search_mode == ""
	_dev_btn.visible = _dev_on()
	_btn_start.disabled = not (c and in_room and Net.is_room_owner() and Net.room.get("members", []).size() >= 2 and not Net.room.get("playing", false))
	_btn_leave.disabled = not (c and in_room)
	if in_room:
		var r := Net.room
		var who := ", ".join(r.get("players", []))
		var wait := "상대를 기다리는 중..." if r.get("members", []).size() < 2 else ("방장이 시작하면 게임이 시작돼요" if not Net.is_room_owner() else "[게임 시작!] 을 누르세요")
		_room_label.text = "방 #%d %s [%s]\n%s\n%s" % [r.get("id", 0), r.get("name", ""), Session.mode_name(r.get("mode", "")), who, wait]
	else:
		_room_label.text = ""


func _dev_on() -> bool:
	## 서버 주소 · LAN · 방 목록 같은 개발자용 조작: 디버그 빌드이거나 숨은 스위치(연결 상태 7번 누르기)
	if "--player-ui" in OS.get_cmdline_user_args():
		return false   # 테스트: 출시 빌드 화면 확인용
	return OS.is_debug_build() or bool(UIKit.ui_get("dev_online", false))


func _dev_tap() -> void:
	_dev_taps += 1
	if _dev_taps >= 7:
		_dev_taps = 0
		UIKit.ui_set("dev_online", not bool(UIKit.ui_get("dev_online", false)))
		Platform.show_toast("개발자 메뉴 %s" % ("켬" if _dev_on() else "끔"))
		_refresh_online()


# ---- 빠른 매칭: 상대가 없으면 AI 와 ----
func _quick(mode: String) -> void:
	_apply_name()
	_search_mode = mode
	_search_t = 0.0
	Sfx.play("click")
	if Net.connected:
		if Net.room.is_empty():
			Net.quick_match(mode)
	elif Net.peer == null and not Net.is_server:
		Net.connect_to(Net.server_address)
	_refresh_online()
	_update_search(0.0)


func _update_search(delta: float) -> void:
	if not Net.room.is_empty() and Net.room.get("playing", false):
		return   # 곧 게임 화면으로 넘어감
	_search_t += delta
	var limit := SEARCH_AI_AFTER if Net.connected else SEARCH_OFFLINE_AFTER
	var left := maxi(0, int(ceil(limit - _search_t)))
	var dots := ".".repeat(1 + int(_search_t * 2.0) % 3)
	var full: bool = Net.room.get("members", []).size() >= 2
	_search_lbl.text = ("상대를 찾았어요!" if full else "상대를 찾는 중" + dots)
	_search_sub.text = ("%s · %d초 뒤 AI 와 시작" % [Session.mode_name(_search_mode), left]) if Net.connected else ("서버 연결 중 · %d초 뒤 AI 와 시작" % left)
	if _search_t >= limit and not full:
		Platform.show_toast("상대가 없어 AI 와 시작해요")
		_play_ai()


func _cancel_search() -> void:
	if _search_mode == "":
		return
	_search_mode = ""
	if not Net.room.is_empty() and Net.room.get("quick", false):
		Net.leave_room()
	_refresh_online()


func _play_ai() -> void:
	## 빠른 매칭 대신 AI 와 같은 모드로 (로컬 판)
	var mode := _search_mode if _search_mode != "" else "pvp"
	_cancel_search()
	_start_local(mode, false)


func _build_online() -> void:
	_online = _panel(Vector2(440, 150), Vector2(720, 540), "온라인")
	_online.visible = false
	var rv: VBoxContainer = _online.get_child(0)
	rv.add_theme_constant_override("separation", 14)
	# 연결 상태 (7번 누르면 개발자 메뉴)
	_conn_lbl = UIKit.label("", 22, Color(1, 0.8, 0.6), 4)
	_conn_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_conn_lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	_conn_lbl.gui_input.connect(func(e): if e is InputEventMouseButton and e.pressed: _dev_tap())
	rv.add_child(_conn_lbl)
	_record_lbl = UIKit.label("", 24, Color(1, 0.85, 0.45), 4)
	_record_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rv.add_child(_record_lbl)
	# 큰 빠른 매칭 버튼 두 개
	_quick_box = VBoxContainer.new()
	_quick_box.add_theme_constant_override("separation", 14)
	rv.add_child(_quick_box)
	for spec in [["pvp", "attack", Color(1, 0.6, 0.5), Color(0.8, 0.28, 0.22), "빠른 매칭 · 대전", "먼저 무너지면 패배"], ["coop", "heart", Color(0.5, 1, 0.85), Color(0.15, 0.55, 0.45), "빠른 매칭 · 협동", "둘이 함께 %d라운드" % GameData.FINAL_WAVE]]:
		var m: String = spec[0]
		var b := ActionButton.make(spec[1], spec[2], spec[4], func(): _quick(m), Vector2(0, 124))
		b.wide = true
		b.tone = spec[3]
		b.radius = 22
		b.sub = spec[5]
		_quick_box.add_child(b)
		if m == "pvp":
			_btn_quick_pvp = b
		else:
			_btn_quick_coop = b
	# 찾는 중
	_search_box = VBoxContainer.new()
	_search_box.add_theme_constant_override("separation", 12)
	_search_box.visible = false
	rv.add_child(_search_box)
	_search_lbl = UIKit.label("상대를 찾는 중...", 36, Color(1, 0.9, 0.55))
	_search_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_search_box.add_child(_search_lbl)
	_search_sub = UIKit.label("", 22, Color(0.8, 0.87, 1.0), 4)
	_search_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_search_box.add_child(_search_sub)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 14)
	_search_box.add_child(sh)
	var ai := ActionButton.make("play", Color(0.6, 1, 0.7), "AI 와 바로 하기", _play_ai, Vector2(0, 96))
	ai.wide = true
	ai.tone = UIKit.GREEN
	ai.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(ai)
	var cancel := ActionButton.make("close", Color(0.9, 0.9, 0.95), "취소", _cancel_search, Vector2(0, 96))
	cancel.wide = true
	cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sh.add_child(cancel)
	# 직접 만든 방 (개발자 메뉴로 만든 방)
	_room_box = VBoxContainer.new()
	_room_box.add_theme_constant_override("separation", 8)
	rv.add_child(_room_box)
	_room_label = UIKit.label("", 22, Color(1, 0.85, 0.45), 4)
	_room_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_room_box.add_child(_room_label)
	var room_row := HBoxContainer.new()
	room_row.add_theme_constant_override("separation", 10)
	_room_box.add_child(room_row)
	_btn_start = _small_btn("게임 시작!", func(): Net.start_match())
	room_row.add_child(_btn_start)
	_btn_leave = _small_btn("방 나가기", func(): Net.leave_room())
	room_row.add_child(_btn_leave)
	# 랭킹 · 닫기
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 14)
	rv.add_child(bottom)
	var rank := ActionButton.make("crown", Color(1, 0.85, 0.35), "랭킹", _open_rank, Vector2(0, 88))
	rank.wide = true
	rank.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(rank)
	_dev_btn = ActionButton.make("gear", Color(0.8, 0.85, 0.95), "개발자 메뉴 (서버 주소 · LAN · 방 목록)", func(): _show_panel(_dev_panel), Vector2(96, 88))
	_dev_btn.caption = "개발"
	bottom.add_child(_dev_btn)
	var close := ActionButton.make("close", Color(0.9, 0.9, 0.95), "닫기", func(): _cancel_search(); _online.visible = false, Vector2(0, 88))
	close.wide = true
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(close)
	# ---- 개발자 메뉴: 서버 주소 / LAN / 방 목록 (디버그 빌드 또는 숨은 스위치) ----
	_dev_panel = _panel(Vector2(400, 70), Vector2(800, 740), "개발자 메뉴")
	_dev_panel.visible = false
	var _dev_box: VBoxContainer = _dev_panel.get_child(0)
	var addr_row := HBoxContainer.new()
	_dev_box.add_child(addr_row)
	addr_row.add_child(_label("서버"))
	_addr_edit = LineEdit.new()
	_addr_edit.text = Net.server_address
	_addr_edit.placeholder_text = "서버 주소 (wss://... 또는 IP)"
	_addr_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	addr_row.add_child(_addr_edit)
	_btn_connect = _small_btn("접속", _connect)
	_btn_connect.size_flags_horizontal = Control.SIZE_SHRINK_END
	_btn_connect.custom_minimum_size = Vector2(110, 64)
	addr_row.add_child(_btn_connect)
	var conn_row := HBoxContainer.new()
	_dev_box.add_child(conn_row)
	_btn_lan = _small_btn("이 PC 에서 서버 열기 (LAN)", _host_lan)
	conn_row.add_child(_btn_lan)
	_btn_disconnect = _small_btn("연결 끊기", func(): Net.close(); _status.text = "연결을 끊었습니다.")
	conn_row.add_child(_btn_disconnect)
	_status = _label("")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_dev_box.add_child(_status)
	_room_list = ItemList.new()
	_room_list.custom_minimum_size = Vector2(0, 200)
	_room_list.item_activated.connect(func(_i): _join_selected())
	_dev_box.add_child(_room_list)
	var list_row := HBoxContainer.new()
	_dev_box.add_child(list_row)
	_btn_refresh = _small_btn("새로고침", func(): Net.request_rooms())
	list_row.add_child(_btn_refresh)
	_btn_join = _small_btn("선택한 방 참가", _join_selected)
	list_row.add_child(_btn_join)
	var create_row := HBoxContainer.new()
	_dev_box.add_child(create_row)
	_net_mode = OptionButton.new()
	_net_mode.add_item("협동")
	_net_mode.add_item("대전")
	create_row.add_child(_net_mode)
	_room_name = LineEdit.new()
	_room_name.placeholder_text = "방 이름"
	_room_name.max_length = 20
	_room_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_row.add_child(_room_name)
	_btn_create = _small_btn("방 만들기", func(): _apply_name(); Net.create_room(_mode_sel(), _room_name.text))
	_btn_create.size_flags_horizontal = Control.SIZE_SHRINK_END
	_btn_create.custom_minimum_size = Vector2(140, 64)
	create_row.add_child(_btn_create)
	_dev_box.add_child(_small_btn("닫기", func(): _dev_panel.visible = false))


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
	## 팝업 창: 파란 테두리 패널 + 위쪽 리본 제목 (art/ui/popup_panel.png 로 교체 가능)
	var p := PanelContainer.new()
	var sb: StyleBox = Art.stylebox("popup_panel")
	if sb == null:
		var f := UIKit.panel_box()
		f.content_margin_top = 40
		f.content_margin_left = 24
		f.content_margin_right = 24
		sb = f
	p.add_theme_stylebox_override("panel", sb)
	p.position = pos
	p.size = sz
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var ribbon := PanelContainer.new()
	var rsb := UIKit.bevel(Color(0.3, 0.45, 0.95), 14, 5)
	rsb.content_margin_left = 34
	rsb.content_margin_right = 34
	rsb.content_margin_top = 4
	ribbon.add_theme_stylebox_override("panel", rsb)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var h := UIKit.label(header, 26)
	h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ribbon.add_child(h)
	# 제목 리본은 VBox 첫 줄(높이 0)에 붙여 패널 위 가장자리에 걸친다 (기존 코드의 get_child(0) 호환)
	var hold := Control.new()
	hold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(hold)
	hold.add_child(ribbon)
	var place := func():
		ribbon.size = ribbon.get_combined_minimum_size()
		ribbon.position = Vector2((hold.size.x - ribbon.size.x) * 0.5, -40 - ribbon.size.y * 0.5)
	hold.resized.connect(place)
	place.call_deferred()
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
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 24)
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
		# 그림 배경은 화려해서 글자가 묻힘 → 위·아래·양옆을 어둡게, 가운데는 살짝
		var shade := UIKit.Shade.new()
		shade.size = Vector2(1600, 900)
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(shade)
		return
	var deco := ScreenBG.new()
	deco.size = Vector2(1600, 900)
	deco.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(deco)


class _LevelBadge:
	extends Control
	## 계정 레벨: 금테 육각형 + 경험치 링
	var level := 1
	var ratio := 0.0

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 3
		draw_arc(c, r, -PI / 2, -PI / 2 + TAU, 48, Color(0, 0, 0, 0.5), 6.0)
		draw_arc(c, r, -PI / 2, -PI / 2 + TAU * ratio, 48, Color(0.4, 0.9, 1.0), 6.0)
		var hex := PackedVector2Array()
		for i in 6:
			hex.append(c + Vector2.from_angle(PI / 6 + i * TAU / 6) * (r - 7))
		draw_colored_polygon(hex, Color(0.95, 0.7, 0.15))
		var inner := PackedVector2Array()
		for i in 6:
			inner.append(c + Vector2.from_angle(PI / 6 + i * TAU / 6) * (r - 12))
		draw_colored_polygon(inner, Color(0.25, 0.35, 0.8))
		var f := get_theme_font("font")
		var s := str(level)
		var fs := 26 if level < 100 else 20
		var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		UIKit.draw_text_outlined(self, f, c + Vector2(-w * 0.5, fs * 0.36), s, fs)


class _Hero:
	extends Control
	## 로비 가운데 대표 유닛 (가장 높은 등급)
	var unit_id := "sword"
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		queue_redraw()

	func _draw() -> void:
		var c := Vector2(size.x * 0.5, size.y * 0.5 + sin(t * 2.0) * 8.0)
		var col: Color = GameData.RARITY_COLORS[GameData.UNITS[unit_id]["rarity"]]
		for k in 5:
			draw_circle(c, 150 - k * 18, Color(col, 0.05 + 0.02 * k))
		var tex := Art.tex("units/" + unit_id)
		if tex != null:
			draw_texture_rect(tex, Rect2(c - Vector2(120, 120), Vector2(240, 240)), false)
		else:
			Glyphs.draw_unit_token(self, unit_id, c, 95, 0.0, 1.0)
		# 반짝임
		for i in 3:
			var a := t * 1.3 + i * TAU / 3
			var p := c + Vector2(cos(a) * 130, sin(a) * 50 - 20)
			draw_circle(p, 4, Color(1, 1, 0.8, 0.6 + 0.4 * sin(t * 5 + i)))


func _hero_unit() -> String:
	var best := "sword"
	var best_score := -1
	for id in Profile.discovered:
		if not GameData.UNITS.has(id):
			continue
		var sc := int(GameData.UNITS[id]["rarity"]) * 100 + Profile.unit_level(id)
		if sc > best_score:
			best_score = sc
			best = id
	return best


func _side_button(icon: String, col: Color, caption: String, tip: String, cb: Callable, tone := Color(0.22, 0.3, 0.55)) -> VBoxContainer:
	## 로비 양옆 둥근 아이콘 + 아래 이름표
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -6)
	var b := ActionButton.make(icon, col, tip, cb, Vector2(96, 90))
	b.caption = ""
	b.tone = tone
	b.radius = 20
	v.add_child(b)
	var l := UIKit.label(caption, 21)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	return v


func _build_top() -> void:
	# ---- 왼쪽 위: 프로필 (레벨 배지 + 닉네임 + 경험치) ----
	var prof := PanelContainer.new()
	var psb := UIKit.pill(Color(0.03, 0.04, 0.1, 0.6))
	psb.content_margin_left = 4
	psb.content_margin_right = 18
	prof.add_theme_stylebox_override("panel", psb)
	prof.position = Vector2(16, 12)
	add_child(prof)
	var ph := HBoxContainer.new()
	ph.add_theme_constant_override("separation", 10)
	prof.add_child(ph)
	var badge := _LevelBadge.new()
	badge.custom_minimum_size = Vector2(70, 70)
	badge.level = Profile.level
	badge.ratio = float(Profile.xp) / maxf(1.0, GameData.xp_to_next(Profile.level))
	badge.tooltip_text = "계정 레벨 %d  (경험치 %d / %d)" % [Profile.level, Profile.xp, GameData.xp_to_next(Profile.level)]
	ph.add_child(badge)
	var pv := VBoxContainer.new()
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	pv.add_theme_constant_override("separation", 2)
	ph.add_child(pv)
	_name_edit = LineEdit.new()
	_name_edit.text = Session.player_name
	_name_edit.max_length = 10
	_name_edit.placeholder_text = "닉네임"
	_name_edit.custom_minimum_size = Vector2(190, 36)
	_name_edit.add_theme_font_size_override("font_size", 22)
	_name_edit.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
	_name_edit.add_theme_color_override("font_outline_color", UIKit.INK)
	_name_edit.add_theme_constant_override("outline_size", 4)
	_name_edit.tooltip_text = "눌러서 닉네임 바꾸기"
	pv.add_child(_name_edit)
	var sub := UIKit.label("대전 %d점  ·  최고 R%d" % [Profile.rating, int(Profile.stats.get("best_round", 0))], 20, Color(0.75, 0.85, 1.0), 4)
	pv.add_child(sub)
	# ---- 오른쪽 위: 재화 + 설정 ----
	var right := HBoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	right.position = Vector2(900, 18)
	right.size = Vector2(684, 64)
	right.alignment = BoxContainer.ALIGNMENT_END
	add_child(right)
	var chip := PanelContainer.new()
	chip.add_theme_stylebox_override("panel", UIKit.pill())
	var ch := HBoxContainer.new()
	ch.add_theme_constant_override("separation", 6)
	ch.add_child(UIIcon.make("coin", 44))
	_coin_lbl = UIKit.label("0", 28)
	_coin_lbl.custom_minimum_size = Vector2(110, 0)
	ch.add_child(_coin_lbl)
	var plus := ActionButton.make("", Color.WHITE, "충전 (상점)", func(): _go_shop("charge"), Vector2(56, 56))
	plus.tone = UIKit.GREEN
	plus.radius = 10
	plus.badge = "+"
	plus.font_px = 28
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ch.add_child(plus)
	chip.add_child(ch)
	right.add_child(chip)
	var gear := ActionButton.make("gear", Color(0.9, 0.93, 1.0), "설정", func(): _show_panel(_settings), Vector2(84, 76))
	gear.tone = UIKit.NAVY
	right.add_child(gear)
	Profile.changed.connect(_refresh_coins)
	_refresh_coins()


func _go_shop(tab := "") -> void:
	Session.set_meta("shop_tab", tab)
	get_tree().change_scene_to_file("res://scenes/Shop.tscn")


func _show_panel(p: Control) -> void:
	p.visible = true
	UIKit.pop_in(p)
	Sfx.play("tick")


func _refresh_coins() -> void:
	if is_instance_valid(_coin_lbl):
		_coin_lbl.text = _fmt_num(Profile.coins)
	if is_instance_valid(_rewards_btn):
		var n := Profile.reward_badge()
		_rewards_btn.count = n
		_rewards_btn.glow = n > 0
		_rewards_btn.queue_redraw()


static func _fmt_num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


# ---- 가운데: 대표 유닛 + 모드 선택 + 전투 시작 ----
static var _mode_i := 0
var _mode_icon: UIIcon
var _mode_name: Label
var _mode_sub: Label
var _battle: ActionButton
var _diff_row: HBoxContainer
var _hero: Control


func _modes() -> Array:
	return [
		{"id": "story", "icon": "book", "col": Color(1, 0.8, 0.4), "name": "스토리", "sub": _story_sub(), "go": "모험 시작!" if _first_time() else "스토리 계속"},
		{"id": "daily", "icon": "clock", "col": Color(1, 0.75, 0.35), "name": "오늘의 결계",
			"sub": ("오늘 완료! 내일 새 규칙" if Profile.daily_done() else "매일 바뀌는 규칙 · 보상 300코인") if Profile.stage_unlocked(Story.daily_id()) or Profile.daily_done() else "스토리 1장을 깨면 열려요",
			"go": "다시 도전" if Profile.daily_done() else "도전!"},
		{"id": "tower", "icon": "crown", "col": Color(0.7, 0.85, 1.0), "name": "결계의 탑",
			"sub": ("최고 %d층 · 끝없는 도전" % Profile.tower_best()) if Profile.stage_unlocked("T1") else "스토리 4장을 깨면 열려요",
			"go": "%d층 도전" % (Profile.tower_best() + 1)},
		{"id": "solo", "icon": "star", "col": Color(1, 0.85, 0.35), "name": "무한 모드", "sub": "%s · 보상 x%.1f · 최고 R%d" % [GameData.DIFFICULTIES[Session.difficulty]["name"], GameData.DIFFICULTIES[Session.difficulty]["reward"], int(Profile.stats.get("best_round", 0))], "go": "전투 시작"},
		{"id": "coop", "icon": "heart", "col": Color(0.5, 0.95, 0.8), "name": "협동 · AI", "sub": "AI 동료와 함께 40라운드", "go": "전투 시작"},
		{"id": "pvp", "icon": "attack", "col": Color(1, 0.5, 0.4), "name": "대전 · AI", "sub": "먼저 무너지면 패배", "go": "전투 시작"},
	]


func _build_mode_cards() -> void:
	_hero = _Hero.new()
	_hero.unit_id = _hero_unit()
	_hero.position = Vector2(620, 150)
	_hero.size = Vector2(360, 330)
	_hero.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hero)
	var u: Dictionary = GameData.UNITS[_hero.unit_id]
	var plate_box := PanelContainer.new()
	plate_box.add_theme_stylebox_override("panel", UIKit.pill(Color(0.03, 0.04, 0.1, 0.8)))
	plate_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var plate := UIKit.label("%s  %s  Lv.%d" % [GameData.RARITY_NAMES[u["rarity"]], u["name"], Profile.unit_level(_hero.unit_id) + 1], 22, GameData.RARITY_COLORS[u["rarity"]].lightened(0.35))
	plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	plate_box.add_child(plate)
	add_child(plate_box)
	var place_plate := func():
		plate_box.size = plate_box.get_combined_minimum_size()
		plate_box.position = Vector2(800 - plate_box.size.x * 0.5, 462)
	place_plate.call_deferred()
	# 모드 선택 (◀ 모드 ▶)
	var sel := PanelContainer.new()
	var ssb := UIKit.panel_box(Color(0.08, 0.1, 0.22, 0.88), Color(0.45, 0.58, 1.0), 20)
	ssb.set_content_margin_all(8)
	sel.add_theme_stylebox_override("panel", ssb)
	sel.position = Vector2(520, 515)
	sel.size = Vector2(560, 100)
	add_child(sel)
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 12)
	sel.add_child(sh)
	var prev := ActionButton.make("", Color.WHITE, "이전 모드", func(): _cycle_mode(-1), Vector2(64, 80))
	prev.badge = "◀"
	prev.font_px = 34
	prev.tone = UIKit.BLUE
	sh.add_child(prev)
	_mode_icon = UIIcon.make("star", 70)
	sh.add_child(_mode_icon)
	var mv := VBoxContainer.new()
	mv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mv.alignment = BoxContainer.ALIGNMENT_CENTER
	mv.add_theme_constant_override("separation", 0)
	sh.add_child(mv)
	_mode_name = UIKit.label("", 32)
	mv.add_child(_mode_name)
	_mode_sub = UIKit.label("", 22, Color(0.8, 0.87, 1.0), 4)
	mv.add_child(_mode_sub)
	var nxt := ActionButton.make("", Color.WHITE, "다음 모드", func(): _cycle_mode(1), Vector2(64, 80))
	nxt.badge = "▶"
	nxt.font_px = 34
	nxt.tone = UIKit.BLUE
	sh.add_child(nxt)
	# 전투 시작
	_battle = ActionButton.make("", Color.WHITE, "선택한 모드로 시작", _start_selected, Vector2(400, 116))
	_battle.tone = Color(1.0, 0.72, 0.1)
	_battle.radius = 24
	_battle.glow = true
	_battle.font_px = 44
	_battle.position = Vector2(600, 626)
	add_child(_battle)
	# AI 난이도 (협동/대전 AI 일 때)
	_diff_row = HBoxContainer.new()
	_diff_row.position = Vector2(1020, 660)
	_diff_row.add_theme_constant_override("separation", 6)
	add_child(_diff_row)
	var dl := UIKit.label("AI", 22, Color(1, 0.7, 0.6))
	dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_diff_row.add_child(dl)
	for lvl in 3:
		var lv := lvl
		var b := ActionButton.make("star", [Color(0.6, 0.9, 0.6), Color(1, 0.85, 0.35), Color(1, 0.4, 0.4)][lvl],
			"AI 난이도: " + ["쉬움", "보통", "어려움"][lvl], func(): _set_diff(lv), Vector2(88, 88))
		b.badge = ["쉬움", "보통", "고수"][lvl]
		b.tone = UIKit.NAVY
		_diff_row.add_child(b)
		_diff_btns.append(b)
	_set_diff(Session.bot_level)
	# 무한 모드 난이도 (보통/어려움/지옥)
	_endless_row = HBoxContainer.new()
	_endless_row.position = Vector2(1020, 652)
	_endless_row.add_theme_constant_override("separation", 8)
	add_child(_endless_row)
	Session.difficulty = int(Profile.settings.get("endless_diff", 0))
	for di in GameData.DIFFICULTIES.size():
		var dd: Dictionary = GameData.DIFFICULTIES[di]
		var dix := di
		var db := ActionButton.make("", Color.WHITE, "%s\n적 체력 x%.1f · 보상 x%.1f" % [dd["name"], dd["hp"], dd["reward"]], func(): _set_endless_diff(dix), Vector2(92, 72))
		db.badge = dd["name"]
		db.font_px = 22
		db.tone = dd["color"].darkened(0.2)
		_endless_row.add_child(db)
		_endless_btns.append(db)
	_set_endless_diff(Session.difficulty)
	_cycle_mode(0)


var _endless_row: HBoxContainer
var _endless_btns: Array = []


func _set_endless_diff(i: int) -> void:
	Session.difficulty = i
	if int(Profile.settings.get("endless_diff", 0)) != i:
		Profile.set_setting("endless_diff", i)
	for k in _endless_btns.size():
		_endless_btns[k].selected = k == i
		_endless_btns[k].queue_redraw()
	if _mode_sub != null and _modes()[_mode_i]["id"] == "solo":
		_mode_sub.text = _modes()[_mode_i]["sub"]


func _cycle_mode(d: int) -> void:
	var ms := _modes()
	_mode_i = posmod(_mode_i + d, ms.size())
	var m: Dictionary = ms[_mode_i]
	_mode_icon.set_icon(m["icon"], m["col"])
	_mode_name.text = m["name"]
	_mode_name.add_theme_color_override("font_color", m["col"].lightened(0.25))
	_mode_sub.text = m["sub"]
	_battle.badge = m["go"]
	_battle.queue_redraw()
	_diff_row.visible = m["id"] in ["coop", "pvp"]
	if _endless_row != null:
		_endless_row.visible = m["id"] == "solo"
	if d != 0:
		Sfx.play("tick")
		UIKit.pop_in(_mode_name, 0.9)


func _first_time() -> bool:
	## 아직 한 판도 안 한 새 계정: 지도 대신 바로 1-1 로
	return not Profile.tutorial_done and Profile.campaign.is_empty()


func _start_selected() -> void:
	var id: String = _modes()[_mode_i]["id"]
	if id == "story":
		if _first_time():
			_apply_name()
			Campaign.start_stage("1-1", get_tree())
			return
		_open_story()
	elif id == "daily" or id == "tower":
		var sid := Story.daily_id() if id == "daily" else "T%d" % (Profile.tower_best() + 1)
		if not Profile.stage_unlocked(sid) and not (id == "daily" and Profile.daily_done()):
			Platform.show_toast(_modes()[_mode_i]["sub"])
			return
		_apply_name()
		Campaign.start_stage(sid, get_tree())
	else:
		_start_local(id, false)


# ---- 양옆 아이콘 ----
func _build_sides() -> void:
	var left := VBoxContainer.new()
	left.position = Vector2(24, 120)
	left.add_theme_constant_override("separation", 14)
	add_child(left)
	var rw := _side_button("gift", Color(1, 0.8, 0.45), "보상", "보상 (출석 · 미션 · 룰렛)", func(): get_tree().change_scene_to_file("res://scenes/Rewards.tscn"), Color(0.85, 0.35, 0.3))
	_rewards_btn = rw.get_child(0)
	left.add_child(rw)
	left.add_child(_side_button("trophy", Color(1, 0.85, 0.35), "업적", "업적", func(): _show_panel(_achieve)))
	left.add_child(_side_button("wheel", Color(1, 0.75, 0.5), "룰렛", "행운의 룰렛 (매일 무료)", func(): get_tree().change_scene_to_file("res://scenes/Rewards.tscn")))
	left.add_child(_side_button("help", Color(0.7, 0.85, 1.0), "도움말", "게임 방법", _show_help))
	var right := VBoxContainer.new()
	right.position = Vector2(1488, 120)
	right.add_theme_constant_override("separation", 14)
	add_child(right)
	right.add_child(_side_button("attack", Color(1, 0.9, 0.9), "온라인", "온라인: 빠른 매칭 · 방 · 랭킹", func(): _show_panel(_online), Color(0.3, 0.5, 0.95)))
	if not Platform.is_mobile():
		# 로컬 2인은 키보드 두 벌이 필요 → 휴대폰에서는 숨김
		right.add_child(_side_button("heart", Color(0.6, 1, 0.85), "2인", "로컬 2인 (한 화면에서 친구와)", func(): _show_panel(_two_p)))
	_refresh_coins()


func _open_rank() -> void:
	_show_panel(_rank_panel)
	_rank_tab(_rank_kind)


func _open_story() -> void:
	_apply_name()
	get_tree().change_scene_to_file("res://scenes/Campaign.tscn")


func _story_sub() -> String:
	var cur := "1-1"
	for id in Story.all_ids():
		if Profile.stage_unlocked(id):
			cur = id
	return "진행 %s  ·  ★ %d / %d" % [cur, Profile.total_stars(), Story.all_ids().size() * 3]


func _build_two_player() -> void:
	_two_p = _panel(Vector2(560, 300), Vector2(480, 260), "로컬 2인 (WASD / 방향키)")
	_two_p.visible = false
	var v: VBoxContainer = _two_p.get_child(0)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 16)
	v.add_child(h)
	var coop := ActionButton.make("heart", Color(0.5, 0.95, 0.8), "협동", func(): _start_local("coop", true), Vector2(200, 110))
	coop.badge = "협동"
	h.add_child(coop)
	var pvp := ActionButton.make("attack", Color(1, 0.5, 0.4), "대전", func(): _start_local("pvp", true), Vector2(200, 110))
	pvp.badge = "대전"
	h.add_child(pvp)
	v.add_child(_small_btn("닫기", func(): _two_p.visible = false))


func _build_idle() -> void:
	## 방치 보상: 접속하지 않은 동안 쌓인 코인 (최대 8시간) - 전투 버튼 왼쪽 상자
	var box := HBoxContainer.new()
	box.position = Vector2(372, 636)
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_idle_btn = ActionButton.make("chest", Color.WHITE, "방치 보상 받기\n접속하지 않아도 10분마다 코인이 쌓여요 (최대 8시간)", _claim_idle, Vector2(120, 96))
	_idle_btn.badge_icon = "coin"
	_idle_btn.tone = Color(0.55, 0.35, 0.2)
	_idle_btn.radius = 18
	box.add_child(_idle_btn)
	_idle_ad = ActionButton.make("ad", Color(0.8, 0.9, 1.0), "광고 보고 방치 보상 2배", _claim_idle_ad, Vector2(76, 96))
	_idle_ad.badge = "x2"
	_idle_ad.tone = UIKit.BLUE
	_idle_ad.radius = 18
	box.add_child(_idle_ad)
	_refresh_idle()


func _refresh_idle() -> void:
	if not is_instance_valid(_idle_btn):
		return
	var n := Profile.idle_amount()
	_idle_btn.badge = str(n)
	_idle_btn.disabled = n <= 0
	_idle_btn.glow = n > 0
	var ads_left := Profile.idle_ads_left()
	_idle_ad.visible = Ads.available()
	_idle_ad.disabled = n <= 0 or ads_left <= 0
	_idle_ad.badge = "x2" if ads_left > 0 else "내일"
	_idle_btn.queue_redraw()
	_idle_ad.queue_redraw()


func _claim_idle() -> void:
	if Profile.claim_idle() > 0:
		Sfx.play("win")
		UIKit.coin_fly(Platform.design_pos(get_viewport().get_mouse_position()), _coin_lbl, 10)
	_refresh_idle()


func _claim_idle_ad() -> void:
	if Profile.idle_ads_left() <= 0:
		Platform.show_toast("오늘 광고 2배는 다 썼어요")
		return
	Ads.show_rewarded("idle_double", _grant_idle_double)


func _grant_idle_double() -> void:
	Profile.claim_idle(2)
	Sfx.play("win")
	UIKit.coin_fly(_idle_btn.get_global_rect().get_center(), _coin_lbl, 14)
	_refresh_idle()


func _build_bottom() -> void:
	## 하단 탭 바: 상점 · 도감 · [전투] · 스토리 · 온라인
	_build_sides()
	var bar := Panel.new()
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = Color(0.05, 0.06, 0.14, 0.94)
	bsb.border_color = Color(0.4, 0.52, 0.95, 0.8)
	bsb.border_width_top = 3
	bar.add_theme_stylebox_override("panel", bsb)
	bar.position = Vector2(0, 772)
	bar.size = Vector2(1600, 128)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	var tabs := [
		["shop", Color(1, 0.8, 0.35), "상점", func(): _go_shop()],
		["book", Color(0.6, 0.8, 1.0), "도감", func(): get_tree().change_scene_to_file("res://scenes/Collection.tscn")],
		["attack", Color(1, 0.95, 0.9), "전투", _start_selected],
		["star", Color(1, 0.85, 0.4), "스토리", _open_story],
		["crown", Color(1, 0.85, 0.35), "랭킹", _open_rank],
	]
	var w := 1600.0 / tabs.size()
	for i in tabs.size():
		var tb: Array = tabs[i]
		var home: bool = i == 2
		var b := ActionButton.make(tb[0], tb[1], tb[2], tb[3], Vector2(w - 24, 118 if home else 104))
		b.tone = Color(0.95, 0.65, 0.12) if home else Color(0.16, 0.2, 0.38)
		b.radius = 18
		b.caption = tb[2]
		b.position = Vector2(i * w + 12, 766 if home else 786)
		add_child(b)
		if i == 1:
			var up := 0
			for id in Profile.discovered:
				if Profile.coins >= GameData.unit_level_cost(id, Profile.unit_level(id)) and Profile.unit_level(id) < GameData.UNIT_MAX_LEVEL:
					up += 1
			b.count = up


func _refresh_record() -> void:
	if not is_instance_valid(_record_lbl):
		return
	var r := Net.my_record
	if r.is_empty():
		_record_lbl.text = "대전 레이팅 %d" % Profile.rating
	else:
		_record_lbl.text = "대전 레이팅 %d  ·  %d승 %d패  ·  협동 최고 R%d" % [int(r.get("rating", 1000)), int(r.get("wins", 0)), int(r.get("losses", 0)), int(r.get("coop_best", 0))]


const RANK_TABS := [["pvp", "attack", "대전"], ["endless", "star", "무한"], ["tower", "crown", "탑"], ["daily", "clock", "오늘의 결계"]]


func _build_rank_panel() -> void:
	_rank_panel = _panel(Vector2(360, 60), Vector2(880, 770), "랭킹")
	_rank_panel.visible = false
	var v: VBoxContainer = _rank_panel.get_child(0)
	v.add_theme_constant_override("separation", 12)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 10)
	v.add_child(tabs)
	for t in RANK_TABS:
		var kind: String = t[0]
		var b := ActionButton.make(t[1], Color(1, 0.88, 0.5), t[2], func(): _rank_tab(kind), Vector2(0, 80))
		b.wide = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tabs.add_child(b)
		_rank_tabs[kind] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 440)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_rank_rows = VBoxContainer.new()
	_rank_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rank_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rank_rows)
	_rank_mine = UIKit.label("", 26, Color(0.6, 0.95, 1.0))
	_rank_mine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_rank_mine)
	v.add_child(_small_btn("닫기", func(): _rank_panel.visible = false))


func _rank_tab(kind: String) -> void:
	_rank_kind = kind
	for k in _rank_tabs:
		_rank_tabs[k].selected = k == kind
		_rank_tabs[k].tone = Color(0.95, 0.62, 0.12) if k == kind else UIKit.NAVY
		_rank_tabs[k].queue_redraw()
	for c in _rank_rows.get_children():
		c.queue_free()
	_rank_mine.text = ""
	if Net.connected:
		_rank_rows.add_child(_rank_note("불러오는 중..."))
		Net.request_leaderboard(kind)
	else:
		_rank_rows.add_child(_rank_note("서버에 연결되면 랭킹을 볼 수 있어요"))
		if Net.peer == null and not Net.is_server:
			Net.connect_to(Net.server_address)


func _rank_note(t: String) -> Label:
	var l := UIKit.label(t, 24, Color(0.75, 0.8, 0.95), 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(0, 80)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func _rank_value(kind: String, v: int) -> String:
	match kind:
		"pvp":
			return "%d점" % v
		"tower":
			return "%d층" % v
	return "R%d" % v


func _on_leaderboard(kind: String, list: Array, my_rank: int) -> void:
	if not is_instance_valid(_rank_rows) or kind != _rank_kind:
		return
	for c in _rank_rows.get_children():
		c.queue_free()
	for i in list.size():
		var e: Dictionary = list[i]
		var row := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.05, 0.07, 0.15, 0.75) if i % 2 == 0 else Color(0.08, 0.1, 0.2, 0.75)
		sb.set_corner_radius_all(10)
		sb.content_margin_left = 16
		sb.content_margin_right = 16
		sb.content_margin_top = 6
		sb.content_margin_bottom = 6
		row.add_theme_stylebox_override("panel", sb)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		row.add_child(h)
		var medal: Color = [Color(1, 0.85, 0.3), Color(0.85, 0.87, 0.95), Color(0.9, 0.6, 0.35)][i] if i < 3 else Color(0.8, 0.84, 0.95)
		var rk := UIKit.label("%d" % (i + 1), 28, medal)
		rk.custom_minimum_size = Vector2(56, 0)
		h.add_child(rk)
		var nm := UIKit.label(str(e.get("name", "?")), 26, medal if i < 3 else Color.WHITE)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		nm.clip_text = true
		h.add_child(nm)
		var sub := UIKit.label(str(e.get("sub", "")), 20, Color(0.7, 0.76, 0.9), 4)
		sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(sub)
		var val := UIKit.label(_rank_value(kind, int(e.get("value", 0))), 28, Color(1, 0.9, 0.55))
		val.custom_minimum_size = Vector2(120, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		h.add_child(val)
		_rank_rows.add_child(row)
	if list.is_empty():
		_rank_rows.add_child(_rank_note("아직 기록이 없어요. 첫 주인공이 되어 보세요!"))
	_rank_mine.text = ("내 순위  %d위" % my_rank) if my_rank > 0 else "아직 순위가 없어요"


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
		row.add_child(UIIcon.make(a["icon"], 56, Color(1, 0.8, 0.3) if tier > 0 else Color(0.45, 0.47, 0.55)))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var t := Label.new()
		var next_i := mini(tier, goals.size() - 1)
		t.text = "%s  %s" % [a["name"], "★".repeat(tier) + "☆".repeat(goals.size() - tier)]
		t.add_theme_font_size_override("font_size", 24)
		col.add_child(t)
		var d := Label.new()
		d.text = ("완료!" if tier >= goals.size() else a["desc"] % goals[next_i]) + ("" if tier >= goals.size() else "   보상 코인 %d" % a["coins"][next_i])
		d.add_theme_font_size_override("font_size", 20)
		d.add_theme_color_override("font_color", Color(0.75, 0.8, 0.9))
		col.add_child(d)
		var bar := ProgressBar.new()
		bar.max_value = goals[next_i]
		bar.value = mini(Profile.ach_value(a["stat"]), goals[next_i])
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 14)
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
	_settings = _panel(Vector2(260, 90), Vector2(1080, 700), "설정")
	_settings.visible = false
	var v: VBoxContainer = _settings.get_child(0)
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 28)
	v.add_child(cols)
	# 왼쪽: 켜고 끄기
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 4)
	cols.add_child(left)
	var toggles := [["music", "배경음악"], ["sound", "효과음"], ["vibrate", "진동"], ["labels", "버튼 이름 표시"], ["account_sync", "온라인 계정 자동 연결"]]
	if not Platform.is_mobile():
		toggles.append(["focus_layout", "대전: 내 전장 크게 보기"])
	for spec in toggles:
		var cb := CheckButton.new()
		cb.text = spec[1]
		cb.add_theme_font_size_override("font_size", 26)
		cb.custom_minimum_size.y = 72
		cb.button_pressed = Profile.settings.get(spec[0], true)
		var key: String = spec[0]
		cb.toggled.connect(func(on): Profile.set_setting(key, on))
		left.add_child(cb)
	var lab := CheckButton.new()
	lab.text = "전장 유닛 이름 항상 표시"
	lab.add_theme_font_size_override("font_size", 26)
	lab.custom_minimum_size.y = 72
	lab.button_pressed = Art.show_unit_labels
	lab.toggled.connect(func(on): Art.show_unit_labels = on)
	left.add_child(lab)
	# 오른쪽: 계정 · 약관
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(400, 0)
	right.add_theme_constant_override("separation", 14)
	cols.add_child(right)
	right.add_child(UIKit.label("계정", 26, Color(1, 0.88, 0.5)))
	var rec := ActionButton.make("gear", Color(0.7, 0.9, 1.0), "계정 복구 코드\n새 폰·재설치 때 진행과 구매를 되찾아요", _open_recovery, Vector2(0, 96))
	rec.wide = true
	rec.tone = UIKit.BLUE
	right.add_child(rec)
	right.add_child(UIKit.label("약관", 26, Color(1, 0.88, 0.5)))
	for spec in [["book", "이용약관", "terms_url", LEGAL_TERMS], ["help", "개인정보처리방침", "privacy_url", LEGAL_PRIVACY]]:
		var key: String = spec[2]
		var fallback: String = spec[3]
		var b := ActionButton.make(spec[0], Color(0.85, 0.9, 1.0), spec[1], func(): _open_legal(key, fallback), Vector2(0, 88))
		b.wide = true
		right.add_child(b)
	var vs := str(ProjectSettings.get_setting("application/config/version", ""))
	if vs != "":
		right.add_child(UIKit.label("버전 %s" % vs, 20, Color(0.6, 0.66, 0.8), 4))
	var close := _small_btn("닫기", func(): _settings.visible = false)
	close.add_theme_font_size_override("font_size", 28)
	close.custom_minimum_size.y = 80
	v.add_child(close)
	_build_recovery()


## 약관 주소: project.godot 의 application/legal/terms_url, privacy_url (출시 전 실제 주소로)
const LEGAL_TERMS := "https://example.com/terms"
const LEGAL_PRIVACY := "https://example.com/privacy"


func _open_legal(key: String, fallback: String) -> void:
	var url := str(ProjectSettings.get_setting("application/legal/" + key, fallback))
	if OS.shell_open(url) != OK:
		Platform.show_toast("주소를 열 수 없어요: " + url)


# ---- 계정 복구 코드 ----
func _build_recovery() -> void:
	_recovery = _panel(Vector2(360, 150), Vector2(880, 560), "계정 복구")
	_recovery.visible = false
	var v: VBoxContainer = _recovery.get_child(0)
	v.add_theme_constant_override("separation", 14)
	var d := UIKit.label(UIKit.keep_words("내 코드를 적어 두면, 새 폰이나 다시 설치했을 때 그 코드로 진행과 구매를 되찾을 수 있어요."), 22, Color(0.85, 0.9, 1.0), 4)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(d)
	var mine := HBoxContainer.new()
	mine.add_theme_constant_override("separation", 14)
	v.add_child(mine)
	_rec_code = UIKit.label("- - -", 40, Color(1, 0.9, 0.5))
	_rec_code.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rec_code.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mine.add_child(_rec_code)
	var get_b := ActionButton.make("", Color.WHITE, "내 코드 보기", _request_code, Vector2(200, 84))
	get_b.badge = "내 코드 보기"
	get_b.font_px = 24
	get_b.tone = UIKit.BLUE
	mine.add_child(get_b)
	var copy := ActionButton.make("", Color.WHITE, "복사", _copy_code, Vector2(120, 84))
	copy.badge = "복사"
	copy.font_px = 24
	mine.add_child(copy)
	v.add_child(HSeparator.new())
	v.add_child(UIKit.label("다른 기기의 코드 입력", 24, Color(1, 0.88, 0.5)))
	var enter := HBoxContainer.new()
	enter.add_theme_constant_override("separation", 14)
	v.add_child(enter)
	_rec_edit = LineEdit.new()
	_rec_edit.placeholder_text = "예: ABCD-EFGH-JKLM"
	_rec_edit.max_length = 20
	_rec_edit.add_theme_font_size_override("font_size", 30)
	_rec_edit.custom_minimum_size = Vector2(0, 84)
	_rec_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	enter.add_child(_rec_edit)
	var go := ActionButton.make("", Color.WHITE, "복구하기", _redeem_code, Vector2(200, 84))
	go.badge = "복구하기"
	go.font_px = 26
	go.tone = Color(0.95, 0.62, 0.12)
	enter.add_child(go)
	var warn := UIKit.label(UIKit.keep_words("복구하면 이 기기의 지금 진행은 그 계정으로 바뀌어요."), 20, Color(1, 0.7, 0.55), 4)
	warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(warn)
	_rec_msg = UIKit.label("", 24, Color(0.6, 1, 0.7))
	_rec_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_rec_msg)
	v.add_child(_small_btn("닫기", func(): _recovery.visible = false))


func _copy_code() -> void:
	if _rec_code.text.length() > 6 and not _rec_code.text.begins_with("-") and _rec_code.text != "...":
		DisplayServer.clipboard_set(_rec_code.text)
		Platform.show_toast("복사했어요")


func _open_recovery() -> void:
	_settings.visible = false
	_rec_msg.text = ""
	_show_panel(_recovery)
	_request_code()


func _ensure_online() -> bool:
	## 서버에 붙어 있으면 true. 아니면 접속을 시작하고 false
	if Net.connected:
		return true
	if Net.peer == null and not Net.is_server:
		Net.connect_to(Net.server_address)
	return false


func _request_code() -> void:
	if _ensure_online():
		_rec_code.text = "..."
		Net.request_recovery_code()
	else:
		_rec_msg.text = "서버에 연결하는 중이에요. 잠시 후 다시 눌러 주세요"
		_rec_msg.add_theme_color_override("font_color", Color(1, 0.8, 0.5))


func _on_recovery_code(code: String) -> void:
	if not is_instance_valid(_rec_code):
		return
	_rec_code.text = code if code != "" else "- - -"
	if code == "":
		_rec_msg.text = "지금은 코드를 받을 수 없어요"
		_rec_msg.add_theme_color_override("font_color", Color(1, 0.6, 0.5))


func _redeem_code() -> void:
	var code := _rec_edit.text.strip_edges().to_upper()
	if code.length() < 6:
		_rec_msg.text = "코드를 정확히 입력해 주세요"
		_rec_msg.add_theme_color_override("font_color", Color(1, 0.6, 0.5))
		return
	if not _ensure_online():
		_rec_msg.text = "서버에 연결하는 중이에요. 잠시 후 다시 눌러 주세요"
		_rec_msg.add_theme_color_override("font_color", Color(1, 0.8, 0.5))
		return
	var run := func():
		_rec_msg.text = "확인 중..."
		_rec_msg.add_theme_color_override("font_color", Color(0.8, 0.85, 1.0))
		Net.redeem_recovery_code(code)
	UIKit.confirm(self, "계정 복구", "이 기기의 진행이 코드의 계정으로 바뀌어요.\n계속할까요?", "복구하기", run)


func _on_recovery_result(ok: bool, msg: String) -> void:
	if not is_instance_valid(_rec_msg):
		return
	_rec_msg.text = msg if msg != "" else ("계정을 되찾았어요!" if ok else "복구하지 못했어요")
	_rec_msg.add_theme_color_override("font_color", Color(0.6, 1, 0.7) if ok else Color(1, 0.6, 0.5))
	if ok:
		Sfx.play("reward")
		_rec_edit.text = ""
		_refresh_coins()
		# 서버 계정을 받으면 로비 전체(레벨·이름·기록·스토리)를 새로 그린다
		Net.account_synced.connect(_reload_after_recovery, CONNECT_ONE_SHOT)


func _reload_after_recovery() -> void:
	if is_inside_tree():
		get_tree().reload_current_scene()


# ---- 서버 공지 (같은 글은 한 번만) ----
func _check_notice() -> void:
	var n := str(Net.server_config.get("notice", "")).strip_edges()
	if n != "":
		_on_notice(n)


func _on_notice(text: String) -> void:
	if text == "" or str(UIKit.ui_get("notice_seen", "")) == text:
		return
	UIKit.ui_set("notice_seen", text)
	var ev := str(Net.server_config.get("event_name", ""))
	UIKit.confirm(self, "공지" if ev == "" else "공지 · " + ev, UIKit.keep_words(text), "확인", func(): pass, "")


func _build_event_badge() -> void:
	## 서버 이벤트 이름 (예: "주말 코인 2배") - 로비 위쪽 가운데. 이벤트가 없으면 숨김
	_event_badge = PanelContainer.new()
	var sb := UIKit.pill(Color(0.55, 0.12, 0.2, 0.92))
	sb.border_color = Color(1, 0.8, 0.35)
	sb.set_border_width_all(2)
	_event_badge.add_theme_stylebox_override("panel", sb)
	_event_badge.mouse_filter = Control.MOUSE_FILTER_STOP
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	_event_badge.add_child(h)
	h.add_child(UIIcon.make("gift", 36))
	_event_lbl = UIKit.label("", 24, Color(1, 0.92, 0.6), 4)
	h.add_child(_event_lbl)
	_event_badge.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			var n := str(Net.server_config.get("notice", ""))
			if n != "":
				UIKit.confirm(self, "공지 · " + _event_lbl.text, UIKit.keep_words(n), "확인", func(): pass, ""))
	add_child(_event_badge)
	_refresh_event()


func _refresh_event() -> void:
	if not is_instance_valid(_event_badge):
		return
	var ev := str(Net.server_config.get("event_name", "")).strip_edges()
	_event_badge.visible = ev != ""
	if ev == "":
		return
	var mult := float(Net.server_config.get("coin_event_mult", 1.0))
	_event_lbl.text = ev + ("  코인 x%s" % String.num(mult, 1).trim_suffix(".0") if mult > 1.0 else "")
	var place := func():
		_event_badge.size = _event_badge.get_combined_minimum_size()
		_event_badge.position = Vector2(800 - _event_badge.size.x * 0.5, 100)
	place.call_deferred()


func _auto_account() -> void:
	## 재화를 서버 계정에 맞추기 위해 메뉴에 들어오면 조용히 서버에 접속해 둔다
	if Net.peer != null or Net.is_server or not Profile.settings.get("account_sync", true):
		return
	if "127.0.0.1" in Net.server_address or "localhost" in Net.server_address:
		return   # 서버 주소를 정하기 전 (Net.DEFAULT_SERVER 를 OCI 주소로 바꾸면 자동 접속)
	Net.connect_to(Net.server_address)


func _popups() -> Array:
	return [_recovery, _dev_panel, _rank_panel, _achieve, _settings, _help, _two_p, _online]


func on_back() -> bool:
	## 안드로이드 뒤로 가기: 열린 창부터 닫는다
	for p in _popups():
		if p != null and p.visible:
			if p == _online and _search_mode != "":
				_cancel_search()
			p.visible = false
			return true
	return false


func _replay_tutorial() -> void:
	Profile.tutorial_done = false
	_start_local("solo", false)


func _show_help() -> void:
	_show_panel(_help)


var _help_body: VBoxContainer
var _help_tabs := {}


func _build_help() -> void:
	## 게임 방법: 탭 + 그림 카드 (아이콘 · 제목 · 한 줄). 긴 글 대신 핵심만
	_help = _panel(Vector2(170, 64), Vector2(1260, 780), "게임 방법")
	_help.visible = false
	var v: VBoxContainer = _help.get_child(0)
	v.add_theme_constant_override("separation", 16)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 12)
	v.add_child(tabs)
	for spec in [["basic", "star", "기본"], ["grow", "upgrade", "성장"], ["mythic", "recipe", "신화 조합"], ["modes", "play", "모드"], ["keys", "gear", "조작"]]:
		var key: String = spec[0]
		var b := ActionButton.make(spec[1], Color(1, 0.9, 0.6), spec[2], func(): _help_tab(key), Vector2(200, 78))
		b.wide = true
		b.radius = 18
		tabs.add_child(b)
		_help_tabs[key] = b
	_help_body = VBoxContainer.new()
	_help_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_help_body.add_theme_constant_override("separation", 14)
	v.add_child(_help_body)
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 16)
	v.add_child(bottom)
	var replay := ActionButton.make("", Color.WHITE, "튜토리얼 다시 하기", _replay_tutorial, Vector2(0, 70))
	replay.badge = "튜토리얼 다시 하기"
	replay.font_px = 24
	replay.tone = UIKit.BLUE
	replay.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(replay)
	var close := ActionButton.make("", Color.WHITE, "닫기", func(): _help.visible = false, Vector2(0, 70))
	close.badge = "닫기"
	close.font_px = 26
	close.tone = UIKit.GREEN
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(close)
	_help_tab("basic")


func _help_tab(key: String) -> void:
	for k in _help_tabs:
		_help_tabs[k].selected = k == key
		_help_tabs[k].tone = Color(0.95, 0.62, 0.12) if k == key else UIKit.NAVY
		_help_tabs[k].queue_redraw()
	for c in _help_body.get_children():
		c.queue_free()
	match key:
		"basic":
			_help_cards([
				["skull", Color(1, 0.45, 0.45), "적 %d마리면 패배" % GameData.ENEMY_LIMIT, "적은 사각 길을 계속 돌아요"],
				["summon", Color(0.5, 1, 0.6), "소환", "골드로 랜덤 유닛 뽑기"],
				["merge", Color(1, 0.85, 0.4), "합성", "같은 유닛 3마리 → 상위 등급"],
				["clock", Color(1, 0.6, 0.6), "보스", "10라운드마다 · 시간 안에 처치!"],
			])
		"grow":
			_help_cards([
				["hammer", Color(1, 0.8, 0.4), "★ 강화", "★3 각성 · ★5 초월"],
				["upgrade", Color(0.5, 1, 0.65), "등급 강화", "등급별 공격력 올리기"],
				["gamble", Color(0.8, 0.55, 1), "운명 소환", "보석으로 영웅·전설에 도전"],
				["synergy", Color(0.5, 0.85, 1), "시너지", "다른 종류를 모으면 발동"],
			])
		"mythic":
			# 신화 11종: 두 줄로 (아이콘을 누르면 이름·설명 말풍선)
			var grid := GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 26)
			grid.add_theme_constant_override("v_separation", 4)
			_help_body.add_child(grid)
			for m in GameData.RECIPES:
				var row := HBoxContainer.new()
				row.add_theme_constant_override("separation", 0)
				row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				for ing in GameData.RECIPES[m]:
					row.add_child(UnitIcon.make(ing, 58))
				var arrow := UIIcon.make("play", 24, Color(1, 0.85, 0.4))
				arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(arrow)
				row.add_child(UnitIcon.make(m, 70))
				var nm := UIKit.label(GameData.UNITS[m]["name"], 24, GameData.RARITY_COLORS[4].lightened(0.35))
				nm.custom_minimum_size = Vector2(120, 0)
				nm.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				row.add_child(nm)
				grid.add_child(row)
		"modes":
			_help_cards([
				["book", Color(1, 0.8, 0.45), "스토리", "%d장 %d스테이지 · ★ 모으기" % [Story.CHAPTERS.size(), Story.all_ids().size()]],
				["star", Color(1, 0.85, 0.35), "무한 모드", "%d라운드 버티기" % GameData.FINAL_WAVE],
				["heart", Color(0.5, 0.95, 0.8), "협동", "둘이 합쳐 적 %d마리 전에!" % GameData.COOP_ENEMY_LIMIT],
				["attack", Color(1, 0.5, 0.4), "대전", "적을 보내 먼저 무너뜨리기"],
			])
		"keys":
			var cards := [
				["play", Color(0.7, 0.85, 1), "터치", "유닛 누르기 → 빈 칸 누르면 이동"],
				["help", Color(0.7, 0.85, 1), "길게 누르기", "버튼·아이콘을 길게 누르면 설명"],
			]
			if not Platform.is_mobile():
				cards.append(["gear", Color(0.7, 0.85, 1), "키보드 1P", "WASD · Space · Q 소환 · E 합성"])
				cards.append(["gear", Color(0.7, 0.85, 1), "키보드 2P", "방향키 · Enter · U 소환 · I 합성"])
			_help_cards(cards)


func _help_cards(cards: Array) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help_body.add_child(grid)
	for c in cards:
		var card := PanelContainer.new()
		var sb := UIKit.panel_box(Color(0.1, 0.13, 0.26, 0.95), Color(c[1], 0.6), 20)
		sb.set_content_margin_all(18)
		sb.shadow_size = 6
		card.add_theme_stylebox_override("panel", sb)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(0, 150)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 18)
		card.add_child(h)
		h.add_child(UIIcon.make(c[0], 104, c[1]))
		var tv := VBoxContainer.new()
		tv.alignment = BoxContainer.ALIGNMENT_CENTER
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(tv)
		tv.add_child(UIKit.label(c[2], 34, c[1].lightened(0.35)))
		var d := UIKit.label(c[3], 22, Color(0.88, 0.92, 1.0), 4)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(d)
		grid.add_child(card)
