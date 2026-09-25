extends Node
## 보상형 광고.
##
## provider
##   "admob" : Godot AdMob 플러그인(poing-studios, addons/admob)이 들어 있고 안드로이드일 때
##   "mock"  : 테스트용 가짜 광고 (5초 카운트다운 후 보상) - PC/에디터/플러그인 없음
## 게임 코드는 Ads.show_rewarded(placement, on_reward) 만 호출한다.
## 광고 제거(Profile.no_ads)를 산 경우 광고 없이 바로 보상.
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
var _classes := {}               # AdMob 플러그인 클래스 (이름 -> Script)
var _rewarded: Object = null     # 미리 불러 둔 보상형 광고
var _loading := false
var _retry := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if OS.get_name() in ["Android", "iOS"] and _find_admob():
		provider = "admob"
		_cls("MobileAds").initialize()
		_preload.call_deferred()


func rewarded_id() -> String:
	## 출시 전 실제 광고 단위 ID 로 교체 (project.godot 의 application/ads/... 로도 덮어쓸 수 있음)
	if OS.get_name() == "iOS":
		return ProjectSettings.get_setting("application/ads/ios_rewarded_id", IOS_REWARDED_ID)
	return ProjectSettings.get_setting("application/ads/android_rewarded_id", ANDROID_REWARDED_ID)


func _process(delta: float) -> void:
	if provider == "admob" and _rewarded == null and not _loading:
		_retry -= delta
		if _retry <= 0.0:
			_preload()


func ready_to_show() -> bool:
	return provider != "admob" or _rewarded != null or Profile.no_ads


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
	if auto_claim or Profile.no_ads:
		finish.call(true)
	elif provider == "admob":
		_show_admob(placement, finish)
	else:
		_show_mock(placement, finish)


# ---- AdMob (poing-studios godot-admob-plugin). 클래스를 이름으로 찾아서 플러그인이 없어도 컴파일됨 ----
func _find_admob() -> bool:
	for c in ProjectSettings.get_global_class_list():
		_classes[c["class"]] = c["path"]
	for n in ["MobileAds", "RewardedAdLoader", "RewardedAdLoadCallback", "AdRequest", "FullScreenContentCallback", "OnUserEarnedRewardListener"]:
		if not _classes.has(n):
			return false
	return true


func _cls(n: String) -> Object:
	var sc: Script = load(_classes[n])
	return sc.new() if n != "MobileAds" else sc


func _preload() -> void:
	if _loading or _rewarded != null:
		return
	_loading = true
	var cb: Object = _cls("RewardedAdLoadCallback")
	cb.on_ad_loaded = func(ad: Object):
		_rewarded = ad
		_loading = false
	cb.on_ad_failed_to_load = func(_err: Object):
		_loading = false
		_retry = 20.0
	_cls("RewardedAdLoader").load(rewarded_id(), _cls("AdRequest"), cb)


func _show_admob(_placement: String, finish: Callable) -> void:
	if _rewarded == null:
		# 아직 못 불러옴 → 잠시 기다려 보고 안 되면 취소
		_preload()
		for i in 6:
			await get_tree().create_timer(0.5, true, false, true).timeout
			if _rewarded != null:
				break
		if _rewarded == null:
			finish.call(false)
			Platform.show_toast("광고를 불러오지 못했어요. 잠시 후 다시 시도해 주세요")
			return
	var ad: Object = _rewarded
	_rewarded = null
	var earned := [false]
	var fs: Object = _cls("FullScreenContentCallback")
	fs.on_ad_dismissed_full_screen_content = func():
		ad.destroy()
		finish.call(earned[0])
		_preload()
	fs.on_ad_failed_to_show_full_screen_content = func(_e: Object):
		ad.destroy()
		finish.call(false)
		_preload()
	ad.full_screen_content_callback = fs
	var lis: Object = _cls("OnUserEarnedRewardListener")
	lis.on_user_earned_reward = func(_item: Object):
		earned[0] = true
	ad.show(lis)


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
