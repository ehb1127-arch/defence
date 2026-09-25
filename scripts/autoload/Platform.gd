extends Node
## 모바일(안드로이드) 대응: 뒤로 가기 버튼, 앱 전환 시 자동 일시정지/저장, 진동.
##
## 뒤로 가기: 현재 장면에 on_back() -> bool 이 있으면 먼저 부른다 (true = 처리함).
##            처리 안 되면 메인 메뉴로, 메인 메뉴에서는 두 번 누르면 종료.
## 앱 전환  : 현재 장면에 on_app_paused() 가 있으면 부른다 (Match 는 자동 일시정지).

signal back_pressed

var _last_back := -10.0
var _toast: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# 뒤로 가기로 바로 꺼지지 않게 (project.godot 의 quit_on_go_back=false 와 함께)
	get_tree().quit_on_go_back = false
	if is_mobile():
		# 화면 꺼짐 방지는 게임 중에만 (Match 가 켬/끔)
		DisplayServer.screen_set_keep_on(false)


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
