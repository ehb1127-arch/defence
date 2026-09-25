extends Node
## 보상형 광고.
##
## 지금은 "mock"(테스트용 가짜 광고: 5초 카운트다운 후 보상) 으로 동작한다.
## 실제 광고(AdMob 등)를 붙일 때는 _show_native() 만 구현하면 되고,
## 게임 코드는 Ads.show_rewarded(placement, on_reward) 만 호출한다.
## 자세한 연결 방법: docs/ADS.md
##
## placement(광고 위치) 목록 - 통계/광고 단위 구분용
##   shop_coins     : 상점 - 코인 받기
##   shop_item      : 상점 - 랜덤 아이템
##   match_summon   : 게임 중 - 무료 소환 3회 (판당 1회)
##   match_revive   : 패배 시 - 부활 (판당 1회)
##   result_double  : 결과 화면 - 코인 2배

signal ad_opened(placement: String)
signal ad_closed(placement: String, rewarded: bool)

## Google 공식 "테스트" 보상형 광고 단위 ID. 출시 전 실제 ID 로 교체.
const ANDROID_REWARDED_ID := "ca-app-pub-3940256099942544/5224354917"
const IOS_REWARDED_ID := "ca-app-pub-3940256099942544/1712485313"
const MOCK_SECONDS := 5

var provider := "mock"
var showing := false
var auto_claim := false          # 자동 테스트용: 테스트 광고를 즉시 보상 처리


func _ready() -> void:
	# 네이티브 광고 플러그인이 있으면 여기서 감지해서 provider 를 바꾼다 (docs/ADS.md 참고)
	if Engine.has_singleton("SquareDefenseAds"):
		provider = "native"


func show_rewarded(placement: String, on_reward: Callable) -> void:
	if showing:
		return
	showing = true
	ad_opened.emit(placement)
	var was_paused := get_tree().paused
	get_tree().paused = true
	var finish := func(rewarded: bool):
		showing = false
		get_tree().paused = was_paused
		ad_closed.emit(placement, rewarded)
		if rewarded:
			on_reward.call()
	if auto_claim:
		finish.call(true)
	elif provider == "native":
		_show_native(placement, finish)
	else:
		_show_mock(placement, finish)


func _show_native(placement: String, finish: Callable) -> void:
	## 네이티브 플러그인 호출 자리. 예시 (가상의 싱글톤 API):
	##   var ads = Engine.get_singleton("SquareDefenseAds")
	##   ads.connect("rewarded", func(): finish.call(true), CONNECT_ONE_SHOT)
	##   ads.connect("closed", func(): finish.call(false), CONNECT_ONE_SHOT)
	##   ads.showRewarded(ANDROID_REWARDED_ID, placement)
	push_warning("native 광고 제공자가 구현되지 않아 테스트 광고로 대체합니다: " + placement)
	_show_mock(placement, finish)


func _show_mock(_placement: String, finish: Callable) -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	layer.process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().root.add_child(layer)
	var root := Control.new()
	root.theme = GameData.ui_theme()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.size = Vector2(1600, 900)
	layer.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.size = Vector2(1600, 900)
	root.add_child(bg)
	var icon := UIIcon.make("ad", 180, Color(0.35, 0.6, 1.0))
	icon.position = Vector2(710, 240)
	root.add_child(icon)
	var lbl := Label.new()
	lbl.text = "테스트 광고"
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.position = Vector2(500, 440)
	lbl.size = Vector2(600, 40)
	lbl.add_theme_font_size_override("font_size", 26)
	root.add_child(lbl)
	var timer_lbl := Label.new()
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_lbl.position = Vector2(500, 490)
	timer_lbl.size = Vector2(600, 60)
	timer_lbl.add_theme_font_size_override("font_size", 44)
	timer_lbl.add_theme_color_override("font_color", Color(1, 0.85, 0.35))
	root.add_child(timer_lbl)
	var claim := ActionButton.make("gift", Color(1, 0.85, 0.35), "보상 받기", func(): pass, Vector2(220, 90))
	claim.position = Vector2(690, 580)
	claim.visible = false
	root.add_child(claim)
	var close := ActionButton.make("close", Color(0.8, 0.8, 0.85), "닫기 (보상 없음)", func(): pass, Vector2(56, 56))
	close.position = Vector2(1520, 24)
	root.add_child(close)
	var done := [false]
	var end := func(rewarded: bool):
		if done[0]:
			return
		done[0] = true
		layer.queue_free()
		finish.call(rewarded)
	claim.pressed.connect(func(): end.call(true))
	close.pressed.connect(func(): end.call(false))
	for i in range(MOCK_SECONDS, 0, -1):
		if done[0]:
			return
		timer_lbl.text = str(i)
		await get_tree().create_timer(1.0, true, false, true).timeout
	if not done[0]:
		timer_lbl.text = ""
		claim.visible = true
		claim.badge = "받기"
