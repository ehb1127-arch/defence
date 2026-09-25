extends Control
## 상점: 소모 아이템 / 영구 강화 / 광고 무료 보상.
## 이미지 교체: art/ui/shop_bg.png, art/icons/<아이템 icon>.png, art/ui/card.png(9-slice)

var _tab := "items"
var _grid: GridContainer
var _coin_lbl: Label
var _toast: Label
var _toast_t := 0.0
var _tab_btns := {}


func _ready() -> void:
	theme = GameData.ui_theme()
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
		var b := ActionButton.make(spec[1], spec[2], spec[3], func(): _show(key), Vector2(200, 76))
		b.badge = spec[3]
		tabs.add_child(b)
		_tab_btns[key] = b
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.position = Vector2(30, 230)
	_grid.add_theme_constant_override("h_separation", 18)
	_grid.add_theme_constant_override("v_separation", 18)
	add_child(_grid)
	var note := Label.new()
	note.text = "대전 모드에서는 공정성을 위해 아이템과 영구 강화가 적용되지 않습니다."
	note.position = Vector2(30, 858)
	note.add_theme_color_override("font_color", Color(0.55, 0.6, 0.7))
	add_child(note)
	_toast = Label.new()
	_toast.position = Vector2(400, 790)
	_toast.size = Vector2(800, 40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_outline_color", Color.BLACK)
	_toast.add_theme_constant_override("outline_size", 6)
	add_child(_toast)
	Profile.changed.connect(_rebuild)
	Store.products_updated.connect(_rebuild)
	Store.purchase_finished.connect(_on_purchase)
	_show("items")


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
	p.custom_minimum_size = Vector2(288, 470)
	var sb: StyleBox = Art.stylebox("card")
	if sb == null:
		var f := StyleBoxFlat.new()
		f.bg_color = Color(0.12, 0.12, 0.18)
		f.border_color = col.darkened(0.3)
		f.set_border_width_all(2)
		f.set_corner_radius_all(14)
		f.set_content_margin_all(14)
		sb = f
	p.add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var ic := UIIcon.make(icon, 150, col)
	ic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(ic)
	var t := Label.new()
	t.text = title
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 24)
	t.add_theme_color_override("font_color", col.lightened(0.3))
	v.add_child(t)
	var d := Label.new()
	d.text = desc
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(250, 60)
	d.add_theme_color_override("font_color", Color(0.7, 0.75, 0.85))
	v.add_child(d)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(sp)
	return [p, v]


func _item_card(it: Dictionary) -> Control:
	var id: String = it["id"]
	var base := _card_base(it["icon"], Color(0.85, 0.65, 1.0), it["name"], it["desc"])
	var v: VBoxContainer = base[1]
	var own := Label.new()
	own.text = "보유 %d" % Profile.item_count(id)
	own.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	own.add_theme_font_size_override("font_size", 18)
	v.add_child(own)
	if id != "revive":
		var eq := CheckButton.new()
		eq.text = "다음 판에 사용"
		eq.button_pressed = Profile.equipped.get(id, false)
		eq.disabled = Profile.item_count(id) <= 0
		eq.toggled.connect(func(_on): Profile.toggle_equip(id))
		v.add_child(eq)
	var on_buy := func():
		if Profile.buy_item(id):
			toast("%s 구매!" % it["name"])
		else:
			toast("코인이 부족합니다", false)
	var buy := ActionButton.make("coin", Color.WHITE, "구매", on_buy, Vector2(250, 70))
	buy.icon_name = ""
	buy.badge_icon = "coin"
	buy.badge = str(it["price"])
	buy.disabled = Profile.coins < it["price"]
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
	var buy := ActionButton.make("coin", Color.WHITE, "강화", on_buy, Vector2(250, 70))
	buy.icon_name = ""
	buy.badge_icon = "" if maxed else "coin"
	buy.badge = "MAX" if maxed else str(price)
	buy.disabled = maxed or Profile.coins < price
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
	var buy := ActionButton.make("", Color.WHITE, "구매", func(): Store.buy(id), Vector2(250, 70))
	buy.badge = "보유 중" if owned else Store.price(id)
	buy.disabled = owned or not Store.available()
	if p.has("tag") and not owned:
		buy.count = 0
		var tag := Label.new()
		tag.text = p["tag"]
		tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tag.add_theme_font_size_override("font_size", 20)
		tag.add_theme_color_override("font_color", Color(1, 0.45, 0.45))
		v.add_child(tag)
	v.add_child(buy)
	return base[0]


func _on_purchase(id: String, ok: bool, msg: String) -> void:
	if ok:
		toast("%s 지급 완료!" % GameData.iap_product(id).get("name", id))
	elif msg != "":
		toast(msg, false)


func _ad_card(icon: String, title: String, desc: String, cb: Callable) -> Control:
	var base := _card_base(icon, Color(0.45, 0.7, 1.0), title, desc)
	var v: VBoxContainer = base[1]
	var left := Profile.ads_left()
	var l := Label.new()
	l.text = "오늘 남은 횟수 %d / %d" % [left, GameData.AD_DAILY_LIMIT]
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var b := ActionButton.make("", Color.WHITE, "광고 보기", cb, Vector2(250, 70))
	b.badge_icon = "ad"
	b.badge = "광고 보기"
	b.disabled = left <= 0
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


func _reward_item() -> void:
	var id: Variant = await Profile.request("ad_reward", ["shop_item"])
	if id is String and id != "":
		toast("%s 획득!" % GameData.shop_item(id)["name"])
