extends Node
## 모바일(안드로이드) 대응: 뒤로 가기 버튼, 앱 전환 시 자동 일시정지/저장, 진동.
##
## 뒤로 가기: 현재 장면에 on_back() -> bool 이 있으면 먼저 부른다 (true = 처리함).
##            처리 안 되면 메인 메뉴로, 메인 메뉴에서는 두 번 누르면 종료.
## 앱 전환  : 현재 장면에 on_app_paused() 가 있으면 부른다 (Match 는 자동 일시정지).
## 화면 비율: project.godot 은 stretch aspect "expand". 모든 화면은 1600x900 기준으로 만들어져 있으므로
##            화면이 더 넓으면(19.5:9 휴대폰 등) 그 기준 화면을 가운데로 옮기고, 남는 양옆은 배경색(기본 지우기 색)으로 채운다.
##            (keep 의 검은 띠 대신 게임 배경색 여백)

signal back_pressed

const DESIGN := Vector2(1600, 900)
var margin := Vector2.ZERO      # 1600x900 기준 화면이 실제 화면 안에서 밀려난 만큼 (양옆/위아래 여백)
var _last_back := -10.0
var _toast: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 뒤로 가기로 바로 꺼지지 않게 (project.godot 의 quit_on_go_back=false 와 함께)
	get_tree().quit_on_go_back = false
	if is_mobile():
		# 화면 꺼짐 방지는 게임 중에만 (Match 가 켬/끔)
		DisplayServer.screen_set_keep_on(false)
	get_tree().root.size_changed.connect(_fit_screen)
	get_tree().node_added.connect(_on_node_added)
	_fit_screen.call_deferred()


# ---- 넓은 화면: 기준 화면(1600x900)을 가운데로 ----
func _fit_screen() -> void:
	var root := get_tree().root
	var vis := root.get_visible_rect().size
	margin = ((vis - DESIGN) * 0.5).max(Vector2.ZERO).floor()
	root.canvas_transform = Transform2D(0.0, margin)
	for n in root.find_children("*", "CanvasLayer", true, false):
		_place_layer(n)


func _on_node_added(n: Node) -> void:
	if n is CanvasLayer:
		_place_layer(n)


func _place_layer(l: CanvasLayer) -> void:
	## 코드로 만든 CanvasLayer(게임 UI · 알림 · 광고 창)도 같은 만큼 옮긴다 (원래 offset 은 meta 에 보관)
	if l.get_viewport() != get_tree().root:
		return
	if not l.has_meta("base_offset"):
		l.set_meta("base_offset", l.offset)
	l.offset = Vector2(l.get_meta("base_offset")) + margin


func design_pos(viewport_pos: Vector2) -> Vector2:
	## 화면(뷰포트) 좌표 → 1600x900 기준 좌표 (마우스 위치로 연출을 띄울 때)
	return viewport_pos - margin


func is_mobile() -> bool:
	## 실제 모바일 기기이거나, 테스트용으로 -- --mobile 을 주고 실행
	return OS.has_feature("mobile") or "--mobile" in OS.get_cmdline_user_args()


func vibrate(ms := 30) -> void:
	if not Profile.settings.get("vibrate", true):
		return
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)


func keep_screen_on(on: bool) -> void:
	if OS.has_feature("mobile"):
		DisplayServer.screen_set_keep_on(on)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			handle_back()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			Profile.save()
			var sc := get_tree().current_scene
			if sc != null and sc.has_method("on_app_paused"):
				sc.on_app_paused()


func handle_back() -> void:
	back_pressed.emit()
	if Ads.showing:
		return
	var sc := get_tree().current_scene
	if sc != null and sc.has_method("on_back") and sc.on_back():
		return
	if sc != null and sc.scene_file_path == "res://scenes/Main.tscn":
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_back < 2.0:
			Profile.save()
			get_tree().quit()
			return
		_last_back = now
		show_toast("한 번 더 누르면 종료")
		return
	get_tree().change_scene_to_file("res://scenes/Main.tscn")


func _unhandled_key_input(event: InputEvent) -> void:
	# 데스크톱에서 모바일 뒤로 가기 흉내: Backspace (Esc 는 게임 일시정지에 씀)
	if is_mobile() and event is InputEventKey and event.pressed and not event.echo and (event as InputEventKey).keycode == KEY_BACKSPACE:
		handle_back()


func show_toast(text: String) -> void:
	if _toast == null:
		var layer := CanvasLayer.new()
		layer.layer = 120
		add_child(layer)
		_toast = Label.new()
		_toast.position = Vector2(500, 800)
		_toast.size = Vector2(600, 50)
		_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_toast.add_theme_font_size_override("font_size", 24)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.75)
		sb.set_corner_radius_all(24)
		_toast.add_theme_stylebox_override("normal", sb)
		layer.add_child(_toast)
	_toast.text = text
	_toast.modulate.a = 1.0
	_toast.visible = true
	var tw := create_tween()
	tw.tween_interval(1.4)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.4)
