extends Control
## 보상 허브: 7일 출석 / 일일 미션 / 일일 룰렛

var _coin_lbl: Label
var _att_box: HBoxContainer
var _att_btn: ActionButton
var _missions: VBoxContainer
var _bonus_btn: ActionButton
var _wheel: RouletteWheel
var _spin_free: ActionButton
var _spin_ad: ActionButton
var _result: Label
var _pending: Dictionary = {}


func _ready() -> void:
	theme = GameData.ui_theme()
	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.1)
	bg.size = Vector2(1600, 900)
	add_child(bg)
	var top := HBoxContainer.new()
	top.position = Vector2(30, 24)
	top.size = Vector2(1540, 70)
	top.add_theme_constant_override("separation", 14)
	add_child(top)
	top.add_child(ActionButton.make("back", Color(0.85, 0.9, 1.0), "뒤로", func(): get_tree().change_scene_to_file("res://scenes/Main.tscn"), Vector2(70, 64)))
	top.add_child(UIIcon.make("gift", 50, Color(1, 0.75, 0.4)))
	var title := Label.new()
	title.text = "보상"
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

	# ---- 출석 (위쪽 전체 폭) ----
	var att := _section(Rect2(30, 110, 1540, 190), "calendar", "7일 출석")
	_att_box = HBoxContainer.new()
	_att_box.add_theme_constant_override("separation", 10)
	att.add_child(_att_box)
	# ---- 일일 미션 (왼쪽) ----
	var mis := _section(Rect2(30, 320, 800, 560), "mission", "일일 미션")
	_missions = VBoxContainer.new()
	_missions.add_theme_constant_override("separation", 8)
	mis.add_child(_missions)
	# ---- 룰렛 (오른쪽) ----
	var rou := _section(Rect2(850, 320, 720, 560), "wheel", "행운의 룰렛")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	rou.add_child(h)
	_wheel = RouletteWheel.new()
	_wheel.segments = GameData.ROULETTE
	_wheel.custom_minimum_size = Vector2(440, 440)
	_wheel.stopped.connect(_on_wheel_stopped)
	h.add_child(_wheel)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 14)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_child(side)
	_spin_free = ActionButton.make("wheel", Color(1, 0.8, 0.3), "무료 돌리기 (하루 1회)", func(): _spin(false), Vector2(210, 110))
	_spin_free.badge = "무료"
	side.add_child(_spin_free)
	_spin_ad = ActionButton.make("wheel", Color(0.4, 0.7, 1.0), "광고 보고 돌리기", func(): _spin(true), Vector2(210, 110))
	_spin_ad.badge_icon = "ad"
	side.add_child(_spin_ad)
	_result = Label.new()
	_result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result.custom_minimum_size = Vector2(210, 80)
	_result.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result.add_theme_font_size_override("font_size", 22)
	side.add_child(_result)
	Profile.changed.connect(_refresh)
	_refresh()


func _section(r: Rect2, icon: String, title: String) -> VBoxContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.15)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.position = r.position
	p.size = r.size
	add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	p.add_child(v)
	var h := HBoxContainer.new()
	h.add_child(UIIcon.make(icon if icon != "calendar" else "star", 30, Color(1, 0.8, 0.35)))
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 22)
	h.add_child(l)
	v.add_child(h)
	return v


func _refresh() -> void:
	_coin_lbl.text = str(Profile.coins)
	# 출석
	for c in _att_box.get_children():
		c.queue_free()
	var today := Profile.attendance_day()
	var can := Profile.can_attend()
	for i in GameData.ATTENDANCE.size():
		var rw: Dictionary = GameData.ATTENDANCE[i]
		var icon: String = GameData.shop_item(rw["item"])["icon"] if rw.has("item") else "coin"
		var cb := func(): _attend()
		var b := ActionButton.make(icon, Color.WHITE, "%d일차" % (i + 1), cb, Vector2(170, 110))
		b.badge = ("%d" % rw["coins"]) if rw.has("coins") else GameData.shop_item(rw["item"])["name"]
		if rw.has("coins") and rw.has("item"):
			b.badge = "%d + %s" % [rw["coins"], GameData.shop_item(rw["item"])["name"]]
		var claimed := i < today
		b.disabled = not (can and i == today)
		b.glow = can and i == today
		b.selected = claimed
		b.count = 0
		var box := VBoxContainer.new()
		var dl := Label.new()
		dl.text = "%d일" % (i + 1)
		dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		dl.add_theme_color_override("font_color", Color(1, 0.85, 0.4) if can and i == today else Color(0.6, 0.65, 0.75))
		box.add_child(dl)
		box.add_child(b)
		_att_box.add_child(box)
	# 미션
	for c in _missions.get_children():
		c.queue_free()
	for m in GameData.DAILY_MISSIONS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		row.add_child(UIIcon.make(m["icon"], 38, Color(0.7, 0.85, 1.0)))
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var nl := Label.new()
		nl.text = m["name"]
		nl.add_theme_font_size_override("font_size", 17)
		col.add_child(nl)
		var bar := ProgressBar.new()
		bar.max_value = m["goal"]
		bar.value = Profile.daily_progress(m)
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(0, 12)
		col.add_child(bar)
		row.add_child(col)
		var prog := Label.new()
		prog.text = "%d/%d" % [Profile.daily_progress(m), m["goal"]]
		prog.custom_minimum_size = Vector2(90, 0)
		prog.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(prog)
		var mm: Dictionary = m
		var claim := ActionButton.make("coin", Color.WHITE, "받기", func(): _claim(mm), Vector2(110, 52))
		claim.icon_name = ""
		claim.badge_icon = "coin"
		claim.badge = "완료" if Profile.daily["claimed"].get(m["id"], false) else str(m["coins"])
		claim.disabled = not Profile.daily_claimable(m)
		claim.glow = Profile.daily_claimable(m)
		row.add_child(claim)
		_missions.add_child(row)
	var brow := HBoxContainer.new()
	brow.alignment = BoxContainer.ALIGNMENT_END
	var bl := Label.new()
	bl.text = "모두 완료 보너스"
	bl.add_theme_color_override("font_color", Color(1, 0.85, 0.4))
	brow.add_child(bl)
	_bonus_btn = ActionButton.make("", Color.WHITE, "모두 완료 보너스", _claim_bonus, Vector2(140, 52))
	_bonus_btn.badge_icon = "coin"
	_bonus_btn.badge = "받음" if Profile.daily.get("all", false) else str(GameData.DAILY_ALL_BONUS)
	_bonus_btn.disabled = not Profile.all_daily_done() or Profile.daily.get("all", false)
	_bonus_btn.glow = not _bonus_btn.disabled
	brow.add_child(_bonus_btn)
	_missions.add_child(brow)
	# 룰렛
	_spin_free.disabled = not Profile.roulette_free_left() or _wheel.spinning
	_spin_free.glow = not _spin_free.disabled
	_spin_ad.badge = "%d회 남음" % Profile.roulette_ads_left()
	_spin_ad.disabled = Profile.roulette_ads_left() <= 0 or _wheel.spinning or Profile.roulette_free_left()
	_spin_free.queue_redraw()
	_spin_ad.queue_redraw()


func _claim_bonus() -> void:
	if Profile.claim_daily_bonus():
		Sfx.play("win")


func _attend() -> void:
	var r := Profile.attend()
	if not r.is_empty():
		Sfx.play("win")


func _claim(m: Dictionary) -> void:
	if Profile.claim_daily(m):
		Sfx.play("merge")


func _pick() -> int:
	var total := 0
	for s in GameData.ROULETTE:
		total += s["w"]
	var r := randi() % total
	for i in GameData.ROULETTE.size():
		r -= GameData.ROULETTE[i]["w"]
		if r < 0:
			return i
	return 0


func _spin(by_ad: bool) -> void:
	if _wheel.spinning:
		return
	if by_ad:
		if Profile.roulette_ads_left() <= 0:
			return
		Ads.show_rewarded("roulette", _start_spin.bind(true))
	else:
		if not Profile.roulette_free_left():
			return
		_start_spin(false)


func _start_spin(by_ad: bool) -> void:
	Profile.use_roulette(by_ad)
	var idx := _pick()
	_pending = GameData.ROULETTE[idx]
	_result.text = "두근두근..."
	_result.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
	_wheel.spin(idx)
	_refresh()


func _on_wheel_stopped(_idx: int) -> void:
	var r := _pending
	Profile.grant(r)
	var txt := ""
	if r.has("coins"):
		txt = "코인 +%d" % r["coins"]
	if r.has("item"):
		txt = GameData.shop_item(r["item"])["name"] + " 획득!"
	if r.get("jackpot", false):
		txt = "JACKPOT!!\n" + txt
		Sfx.play("win")
	else:
		Sfx.play("rare")
	_result.text = txt
	_result.add_theme_color_override("font_color", Color(1, 0.85, 0.3))
	_refresh()
