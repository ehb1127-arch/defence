extends Control
## 상점: 소모 아이템 / 영구 강화 / 광고 무료 보상.
## 이미지 교체: art/ui/shop_bg.png, art/icons/<아이템 icon>.png, art/ui/card.png(9-slice)

var _tab := "items"
var _grid: HBoxContainer
var _note: Label
var _coin_lbl: Label
var _toast: Label
var _toast_t := 0.0
var _tab_btns := {}


func _ready() -> void:
	theme = UIKit.theme()
	var bg_tex := Art.tex("ui/shop_bg")
	if bg_tex != null:
		var tr := TextureRect.new()
		tr.texture = bg_tex
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.size = Vector2(1600, 900)
		add_child(tr)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.07, 0.06, 0.1)
		bg.size = Vector2(1600, 900)
		add_child(bg)
	# 상단
	var top := HBoxContainer.new()
	top.position = Vector2(30, 24)
	top.size = Vector2(1540, 70)
	top.add_theme_constant_override("separation", 14)
	add_child(top)
	top.add_child(ActionButton.make("back", Color(0.85, 0.9, 1.0), "뒤로", func(): get_tree().change_scene_to_file("res://scenes/Main.tscn"), Vector2(70, 64)))
	top.add_child(UIIcon.make("shop", 52, Color(1, 0.8, 0.35)))
	var title := Label.new()
	title.text = "상점"
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	top.add_child(title)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	top.add_child(UIIcon.make("coin", 44))
	_coin_lbl = Label.new()
	_coin_lbl.add_theme_font_size_override("font_size", 32)
	_coin_lbl.add_theme_color_override("font_color", Color(0.85, 0.72, 1.0))
	top.add_child(_coin_lbl)
	# 탭
	var tabs := HBoxContainer.new()
	tabs.position = Vector2(30, 112)
	tabs.add_theme_constant_override("separation", 12)
	add_child(tabs)
	for spec in [["items", "gift", Color(0.8, 0.6, 1.0), "아이템"], ["perks", "upgrade", Color(0.45, 0.95, 0.6), "영구 강화"], ["free", "ad", Color(0.4, 0.7, 1.0), "무료 보상"], ["charge", "coin", Color(1, 0.8, 0.35), "충전"]]:
		var key: String = spec[0]
		var b := ActionButton.make(spec[1], spec[2], spec[3], func(): _show(key), Vector2(220, 84))
		b.wide = true
		b.tone = UIKit.NAVY
		b.radius = 18
		tabs.add_child(b)
		_tab_btns[key] = b
	# 카드 줄: 화면 폭을 넘으면 옆으로 밀어서 본다
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(30, 212)
	scroll.size = Vector2(1540, 540)
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	_grid = HBoxContainer.new()
	_grid.add_theme_constant_override("separation", 16)
	scroll.add_child(_grid)
	_note = UIKit.label("", 21, Color(0.8, 0.85, 0.95), 5)
	_note.position = Vector2(30, 846)
	_note.size = Vector2(1540, 40)
	add_child(_note)
	_toast = Label.new()
	_toast.position = Vector2(300, 770)
	_toast.size = Vector2(1000, 50)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 28)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	add_child(_toast)
	Profile.changed.connect(_rebuild)
	Store.products_updated.connect(_rebuild)
	Store.purchase_finished.connect(_on_purchase)
	var tab: String = Session.get_meta("shop_tab", "")
	Session.set_meta("shop_tab", "")
	_show(tab if tab != "" else "items")
	UIKit.dress_screen(self)

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)


func toast(text: String, good := true) -> void:
	_toast.text = text
	_toast.add_theme_color_override("font_color", Color(0.6, 1.0, 0.7) if good else Color(1, 0.5, 0.5))
	_toast_t = 2.0
	_toast.modulate.a = 1.0
	Sfx.play("merge" if good else "fail")


func _show(tab: String) -> void:
	_tab = tab
	for k in _tab_btns:
		_tab_btns[k].selected = k == tab
		_tab_btns[k].queue_redraw()
	_rebuild()


func _rebuild() -> void:
	_coin_lbl.text = str(Profile.coins)
	for c in _grid.get_children():
		c.queue_free()
	_note.text = {
		"items": "대전에서는 공정하게 아이템·영구 강화가 적용되지 않아요",
		"perks": "대전에서는 공정하게 아이템·영구 강화가 적용되지 않아요",
		"free": "광고는 하루 %d번까지 볼 수 있어요" % GameData.AD_DAILY_LIMIT,
		"charge": "구매 전에 가격·구성·청약철회 안내를 확인하는 창이 떠요",
	}.get(_tab, "")
	match _tab:
		"items":
			for it in GameData.SHOP_ITEMS:
				_grid.add_child(_item_card(it))
		"perks":
			for p in GameData.PERKS:
				_grid.add_child(_perk_card(p))
		"free":
			_grid.add_child(_ad_card("coin", "코인 +%d" % GameData.AD_COINS, "광고를 보고 코인 받기", func(): _watch_ad_coins()))
			_grid.add_child(_ad_card("gift", "랜덤 아이템", "광고를 보고 상점 아이템 1개", func(): _watch_ad_item()))
		"charge":
			for p in GameData.IAP_PRODUCTS:
				_grid.add_child(_iap_card(p))


func _card_base(icon: String, col: Color, title: String, desc: String) -> Array:
	## [PanelContainer, VBoxContainer]
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(292, 520)
	var sb: StyleBox = Art.stylebox("card")
	if sb == null:
		var f := UIKit.panel_box(Color(0.1, 0.12, 0.24, 0.94), col.darkened(0.15), 22)
		f.set_content_margin_all(14)
		f.shadow_size = 10
		sb = f
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var ic := UIIcon.make(icon, 120, col)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	# 카드 그림(양피지)이 밝으므로 글자는 어두운 판 위에
	var tp := PanelContainer.new()
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.05, 0.06, 0.13, 0.82)
	tsb.set_corner_radius_all(12)
	tsb.set_content_margin_all(8)
	tp.add_theme_stylebox_override("panel", tsb)
	tp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(tp)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", 4)
	tp.add_child(tv)
	var t := UIKit.label(title, 28, col.lightened(0.4))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tv.add_child(t)
	var d := UIKit.label(UIKit.keep_words(desc), 22, Color(0.9, 0.92, 1.0), 4)
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(200, 0)
	tv.add_child(d)
	return [p, v, tv]


func _item_card(it: Dictionary) -> Control:
	var id: String = it["id"]
	var base := _card_base(it["icon"], Color(0.85, 0.65, 1.0), it["name"], it["desc"])
	var v: VBoxContainer = base[1]
	var own := Label.new()
	own.text = "보유 %d" % Profile.item_count(id)
	own.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	own.add_theme_font_size_override("font_size", 22)
	own.add_theme_color_override("font_color", Color(1, 0.88, 0.5))
	base[2].add_child(own)
	if id != "revive":
		var eq := CheckButton.new()
		eq.text = "다음 판에 사용"
		eq.custom_minimum_size = Vector2(0, 56)
		eq.button_pressed = Profile.equipped.get(id, false)
		eq.disabled = Profile.item_count(id) <= 0
		eq.toggled.connect(func(_on): Profile.toggle_equip(id))
		base[2].add_child(eq)
	var on_buy := func():
		if Profile.buy_item(id):
			toast("%s 구매!" % it["name"])
		else:
			toast("코인이 부족합니다", false)
	var buy := ActionButton.make("coin", Color.WHITE, "구매", on_buy, Vector2(0, 80))
	buy.icon_name = ""
	buy.badge_icon = "coin"
	buy.badge = str(it["price"])
	buy.disabled = Profile.coins < it["price"]
	buy.tone = UIKit.GREEN
	v.add_child(buy)
	return base[0]


func _perk_card(pk: Dictionary) -> Control:
	var id: String = pk["id"]
	var lvl := Profile.perk_level(id)
	var base := _card_base(pk["icon"], Color(0.45, 0.95, 0.6), pk["name"], "%s / Lv" % pk["desc"])
	var v: VBoxContainer = base[1]
	var pips := HBoxContainer.new()
	pips.alignment = BoxContainer.ALIGNMENT_CENTER
	for k in pk["max"]:
		pips.add_child(UIIcon.make("star", 30, Color(1, 0.85, 0.3) if k < lvl else Color(0.3, 0.32, 0.4)))
	v.add_child(pips)
	var maxed: bool = lvl >= pk["max"]
	var price := Profile.perk_price(id)
	var on_buy := func():
		if Profile.buy_perk(id):
			toast("%s Lv.%d!" % [pk["name"], Profile.perk_level(id)])
		else:
			toast("코인이 부족합니다", false)
	var buy := ActionButton.make("coin", Color.WHITE, "강화", on_buy, Vector2(0, 80))
	buy.icon_name = ""
	buy.badge_icon = "" if maxed else "coin"
	buy.badge = "MAX" if maxed else str(price)
	buy.disabled = maxed or Profile.coins < price
	buy.tone = UIKit.GREEN
	v.add_child(buy)
	return base[0]


func _iap_card(p: Dictionary) -> Control:
	var id: String = p["id"]
	var g: Dictionary = p["grant"]
	var parts: Array = []
	if g.has("coins"):
		parts.append("코인 %d" % g["coins"])
	for it in g.get("items", {}):
		parts.append("%s x%d" % [GameData.shop_item(it)["name"], g["items"][it]])
	var desc: String = p.get("desc", "")
	if desc != "":
		parts.push_front(desc)
	var base := _card_base(p["icon"], Color(1, 0.8, 0.35), p["name"], "\n".join(parts))
	var v: VBoxContainer = base[1]
	var owned := Store.owned(id)
	var buy := ActionButton.make("", Color.WHITE, "구매", func(): _confirm_iap(id), Vector2(0, 80))
	buy.badge = "보유 중" if owned else Store.price(id)
	buy.disabled = owned or not Store.can_buy()
	buy.tone = Color(1.0, 0.7, 0.1)
	if p.has("tag") and not owned:
		buy.count = 0
		var tag := UIKit.label(p["tag"], 24, Color(1, 0.5, 0.45))
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		base[2].add_child(tag)
	if not owned and not Store.can_buy():
		var why := UIKit.label(UIKit.keep_words(Store.block_reason()), 20, Color(1, 0.6, 0.55), 4)
		why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		why.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		base[2].add_child(why)
	v.add_child(buy)
	return base[0]


func _iap_contents(p: Dictionary) -> String:
	var g: Dictionary = p["grant"]
	var parts: Array = []
	if g.get("no_ads", false):
		parts.append("광고 제거 (보상 즉시 받기)")
	if g.has("coins"):
		parts.append("코인 %d" % g["coins"])
	for it in g.get("items", {}):
		parts.append("%s x%d" % [GameData.shop_item(it)["name"], g["items"][it]])
	return ", ".join(parts)


const REFUND_NOTICE := "· 결제 후 7일 안에, 쓰지 않은 상품은 청약철회(환불)를 요청할 수 있어요.\n· 받은 코인·아이템을 이미 썼다면 청약철회가 제한될 수 있어요.\n· 결제는 Google Play 계정으로 청구돼요. 미성년자는 보호자 동의가 필요해요."


func _confirm_iap(id: String) -> void:
	## 결제 전 확인 창: 상품 · 가격 · 받는 것 · 청약철회 안내 → [결제] 를 눌러야 Store.buy
	if not Store.can_buy():
		toast(Store.block_reason(), false)
		return
	var p := GameData.iap_product(id)
	if p.is_empty() or Store.owned(id):
		return
	var notice := UIKit.label(REFUND_NOTICE, 19, Color(0.72, 0.77, 0.88), 3)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.custom_minimum_size = Vector2(660, 0)
	var body := "%s\n가격  %s\n받는 것  %s%s" % [p["name"], Store.price(id), _iap_contents(p), "\n(계정당 1회 구매)" if p.get("once", false) else ""]
	UIKit.confirm(self, "구매 확인", body, "%s 결제" % Store.price(id), func(): Store.buy(id), "취소", Callable(), notice)


func _on_purchase(id: String, ok: bool, msg: String) -> void:
	if ok:
		toast("%s 지급 완료!" % GameData.iap_product(id).get("name", id))
		UIKit.coin_fly(Vector2(800, 450), _coin_lbl, 16)
	elif msg != "":
		toast(msg, false)


func _ad_card(icon: String, title: String, desc: String, cb: Callable) -> Control:
	var base := _card_base(icon, Color(0.45, 0.7, 1.0), title, desc)
	var v: VBoxContainer = base[1]
	var left := Profile.ads_left()
	var l := Label.new()
	l.text = "오늘 남은 횟수 %d / %d" % [left, GameData.AD_DAILY_LIMIT]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	base[2].add_child(l)
	var b := ActionButton.make("", Color.WHITE, "광고 보기", cb, Vector2(0, 80))
	b.badge_icon = "ad"
	b.badge = "광고 보기"
	b.disabled = left <= 0 or not Ads.available()
	b.tone = UIKit.BLUE
	v.add_child(b)
	return base[0]


func _watch_ad_coins() -> void:
	if Profile.ads_left() <= 0:
		return
	Ads.show_rewarded("shop_coins", _reward_coins)


func _watch_ad_item() -> void:
	if Profile.ads_left() <= 0:
		return
	Ads.show_rewarded("shop_item", _reward_item)


func _reward_coins() -> void:
	if await Profile.request("ad_reward", ["shop_coins"]):
		toast("코인 +%d" % GameData.AD_COINS)
		UIKit.coin_fly(Vector2(800, 450), _coin_lbl, 10)


func _reward_item() -> void:
	var id: Variant = await Profile.request("ad_reward", ["shop_item"])
	if id is String and id != "":
		toast("%s 획득!" % GameData.shop_item(id)["name"])
