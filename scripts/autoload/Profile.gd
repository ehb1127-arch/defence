extends Node
## 플레이어 프로필 (코인, 보유 아이템, 영구 강화, 광고 시청 횟수, 설정, 기록).
## user://profile.cfg 에 저장. 서버 저장이 필요해지면 save()/load_profile() 만 바꾸면 된다.

signal changed

const PATH := "user://profile.cfg"

var coins := 100
var items := {}          # id -> 개수
var equipped := {}       # id -> 다음 판에 사용할지
var perks := {}          # id -> 레벨
var ad_date := ""
var ad_count := 0
var stats := {"games": 0, "wins": 0, "best_round": 0, "kills": 0, "mythics": 0, "max_star": 0, "bosses": 0,
	"max_combo": 0, "interrupts": 0, "jackpots": 0, "merges": 0}
var level := 1
var xp := 0
var achievements := {}   # 업적 id -> 달성한 단계 수
var settings := {"sound": true, "captions": false}
var device_id := ""
var unit_levels := {}    # 유닛 id -> 영구 레벨
var discovered := {}     # 도감: 한 번이라도 얻은 유닛
var daily := {"date": "", "progress": {}, "claimed": {}, "all": false}
var attendance := {"last": "", "day": 0}
var tutorial_done := false
var rating := 1000       # 서버에서 받은 대전 레이팅 (캐시)
var roulette := {"date": "", "free": false, "ads": 0}


func _ready() -> void:
	load_profile()
	if device_id == "":
		device_id = "%08x%08x%08x" % [randi(), randi(), Time.get_ticks_usec() & 0xFFFFFFFF]
		save()
	apply_settings()
	Ads.ad_closed.connect(func(_p, rewarded): if rewarded: add_progress("ad", 1))


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	coins = cfg.get_value("p", "coins", coins)
	items = cfg.get_value("p", "items", {})
	equipped = cfg.get_value("p", "equipped", {})
	perks = cfg.get_value("p", "perks", {})
	ad_date = cfg.get_value("p", "ad_date", "")
	ad_count = cfg.get_value("p", "ad_count", 0)
	stats.merge(cfg.get_value("p", "stats", {}), true)
	settings.merge(cfg.get_value("p", "settings", {}), true)
	device_id = cfg.get_value("p", "device_id", "")
	unit_levels = cfg.get_value("p", "unit_levels", {})
	discovered = cfg.get_value("p", "discovered", {})
	daily = cfg.get_value("p", "daily", daily)
	attendance = cfg.get_value("p", "attendance", attendance)
	tutorial_done = cfg.get_value("p", "tutorial_done", false)
	rating = cfg.get_value("p", "rating", 1000)
	level = cfg.get_value("p", "level", 1)
	xp = cfg.get_value("p", "xp", 0)
	achievements = cfg.get_value("p", "achievements", {})
	roulette = cfg.get_value("p", "roulette", roulette)


func save() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("p", "coins", coins)
	cfg.set_value("p", "items", items)
	cfg.set_value("p", "equipped", equipped)
	cfg.set_value("p", "perks", perks)
	cfg.set_value("p", "ad_date", ad_date)
	cfg.set_value("p", "ad_count", ad_count)
	cfg.set_value("p", "stats", stats)
	cfg.set_value("p", "settings", settings)
	cfg.set_value("p", "device_id", device_id)
	cfg.set_value("p", "unit_levels", unit_levels)
	cfg.set_value("p", "discovered", discovered)
	cfg.set_value("p", "daily", daily)
	cfg.set_value("p", "attendance", attendance)
	cfg.set_value("p", "tutorial_done", tutorial_done)
	cfg.set_value("p", "rating", rating)
	cfg.set_value("p", "level", level)
	cfg.set_value("p", "xp", xp)
	cfg.set_value("p", "achievements", achievements)
	cfg.set_value("p", "roulette", roulette)
	cfg.save(PATH)
	changed.emit()


func apply_settings() -> void:
	Sfx.muted = not settings["sound"]
	ActionButton.show_captions = settings["captions"]


func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	apply_settings()
	save()


# ---- 재화 / 상점 ----
func add_coins(n: int) -> void:
	coins += n
	save()


func item_count(id: String) -> int:
	return int(items.get(id, 0))


func perk_level(id: String) -> int:
	return int(perks.get(id, 0))


func perk_price(id: String) -> int:
	var p := GameData.perk(id)
	return p["base"] + p["step"] * perk_level(id)


func buy_item(id: String) -> bool:
	var it := GameData.shop_item(id)
	if it.is_empty() or coins < it["price"]:
		return false
	coins -= it["price"]
	items[id] = item_count(id) + 1
	if id != "revive":
		equipped[id] = true
	save()
	return true


func buy_perk(id: String) -> bool:
	var p := GameData.perk(id)
	if p.is_empty() or perk_level(id) >= p["max"] or coins < perk_price(id):
		return false
	coins -= perk_price(id)
	perks[id] = perk_level(id) + 1
	save()
	return true


func toggle_equip(id: String) -> void:
	equipped[id] = not equipped.get(id, false)
	save()


func give_item(id: String, n := 1) -> void:
	items[id] = item_count(id) + n
	save()


func use_item(id: String) -> bool:
	if item_count(id) <= 0:
		return false
	items[id] = item_count(id) - 1
	save()
	return true


## 판 시작 시 장착한 소모 아이템을 꺼낸다 (대전은 적용 안 함)
func take_loadout(mode: String) -> Array:
	var out: Array = []
	if mode == "pvp":
		return out
	for it in GameData.SHOP_ITEMS:
		var id: String = it["id"]
		if id == "revive":
			continue
		if equipped.get(id, false) and item_count(id) > 0:
			items[id] = item_count(id) - 1
			out.append(id)
			if item_count(id) <= 0:
				equipped[id] = false
	if not out.is_empty():
		save()
	return out


# ---- 광고 ----
func ads_left() -> int:
	var today := Time.get_date_string_from_system()
	if ad_date != today:
		ad_date = today
		ad_count = 0
	return maxi(0, GameData.AD_DAILY_LIMIT - ad_count)


func note_ad() -> void:
	ads_left()
	ad_count += 1
	save()


# ---- 기록 ----
func record_match(mode: String, wave: int, won: bool) -> void:
	stats["games"] = int(stats["games"]) + 1
	if won:
		stats["wins"] = int(stats["wins"]) + 1
	save()



# ---- 도감 / 유닛 레벨 ----
func unit_level(id: String) -> int:
	return int(unit_levels.get(id, 0))


func discover(ids: Array) -> void:
	var changed_any := false
	for id in ids:
		if not discovered.has(id):
			discovered[id] = true
			changed_any = true
	if changed_any:
		save()


func level_up_unit(id: String) -> bool:
	var lvl := unit_level(id)
	if not discovered.has(id) or lvl >= GameData.UNIT_MAX_LEVEL:
		return false
	var cost := GameData.unit_level_cost(id, lvl)
	if coins < cost:
		return false
	coins -= cost
	unit_levels[id] = lvl + 1
	save()
	return true


# ---- 일일 미션 ----
func _daily_reset() -> void:
	var today := Time.get_date_string_from_system()
	if daily.get("date", "") != today:
		daily = {"date": today, "progress": {}, "claimed": {}, "all": false}


func add_progress(key: String, n: int) -> void:
	if n <= 0:
		return
	_daily_reset()
	daily["progress"][key] = int(daily["progress"].get(key, 0)) + n
	save()


func daily_progress(m: Dictionary) -> int:
	_daily_reset()
	return mini(int(daily["progress"].get(m["key"], 0)), m["goal"])


func daily_claimable(m: Dictionary) -> bool:
	return daily_progress(m) >= m["goal"] and not daily["claimed"].get(m["id"], false)


func claim_daily(m: Dictionary) -> bool:
	if not daily_claimable(m):
		return false
	daily["claimed"][m["id"]] = true
	coins += m["coins"]
	save()
	return true


func all_daily_done() -> bool:
	_daily_reset()
	for m in GameData.DAILY_MISSIONS:
		if not daily["claimed"].get(m["id"], false):
			return false
	return true


func claim_daily_bonus() -> bool:
	if not all_daily_done() or daily.get("all", false):
		return false
	daily["all"] = true
	coins += GameData.DAILY_ALL_BONUS
	save()
	return true


func daily_badge() -> int:
	var n := 0
	for m in GameData.DAILY_MISSIONS:
		if daily_claimable(m):
			n += 1
	if all_daily_done() and not daily.get("all", false):
		n += 1
	return n


# ---- 출석 ----
func can_attend() -> bool:
	return attendance.get("last", "") != Time.get_date_string_from_system()


func attend() -> Dictionary:
	## 오늘 출석 보상 지급. 7일 주기
	if not can_attend():
		return {}
	var day := int(attendance.get("day", 0)) % GameData.ATTENDANCE.size()
	var r: Dictionary = GameData.ATTENDANCE[day]
	if r.has("coins"):
		coins += r["coins"]
	if r.has("item"):
		items[r["item"]] = item_count(r["item"]) + 1
	attendance = {"last": Time.get_date_string_from_system(), "day": day + 1}
	save()
	return r


func attendance_day() -> int:
	## 다음에 받을 칸(0~6)
	return int(attendance.get("day", 0)) % GameData.ATTENDANCE.size()



# ---- 룰렛 ----
func _roulette_reset() -> void:
	var today := Time.get_date_string_from_system()
	if roulette.get("date", "") != today:
		roulette = {"date": today, "free": false, "ads": 0}


func roulette_free_left() -> bool:
	_roulette_reset()
	return not roulette["free"]


func roulette_ads_left() -> int:
	_roulette_reset()
	return GameData.ROULETTE_AD_SPINS - int(roulette["ads"])


func use_roulette(by_ad: bool) -> void:
	_roulette_reset()
	if by_ad:
		roulette["ads"] = int(roulette["ads"]) + 1
	else:
		roulette["free"] = true
	save()


func grant(reward: Dictionary) -> void:
	if reward.has("coins"):
		coins += int(reward["coins"])
	if reward.has("item"):
		items[reward["item"]] = item_count(reward["item"]) + 1
	save()


func reward_badge() -> int:
	## 메뉴 보상 버튼의 빨간 숫자
	var n := daily_badge()
	if can_attend():
		n += 1
	if roulette_free_left():
		n += 1
	return n



# ---- 업적 / 계정 레벨 ----
const _SUM_STATS := {"kills": "kills", "mythics": "mythics_done", "bosses": "bosses_killed", "interrupts": "interrupts", "jackpots": "slot_jackpots", "merges": "merges_done"}
const _MAX_STATS := {"max_star": "max_star", "max_combo": "best_combo", "best_round": "wave"}


func ach_value(stat: String, b: Board = null) -> int:
	## 누적 기록 + (진행 중인 판의 기록)
	if stat == "discovered":
		var n := discovered.size()
		if b != null:
			for id in b.obtained:
				if not discovered.has(id):
					n += 1
		return n
	var v := int(stats.get(stat, 0))
	if b != null:
		if _SUM_STATS.has(stat):
			v += int(b.get(_SUM_STATS[stat]))
		elif _MAX_STATS.has(stat):
			v = maxi(v, int(b.get(_MAX_STATS[stat])))
	return v


func ach_tier(id: String) -> int:
	return int(achievements.get(id, 0))


func check_achievements(b: Board = null) -> Array:
	## 새로 달성한 업적 단계 목록 [{a, tier}] (보상 코인 즉시 지급)
	var out: Array = []
	for a in GameData.ACHIEVEMENTS:
		var tier := ach_tier(a["id"])
		var v := ach_value(a["stat"], b)
		while tier < a["goals"].size() and v >= a["goals"][tier]:
			coins += a["coins"][tier]
			out.append({"a": a, "tier": tier})
			tier += 1
		achievements[a["id"]] = tier
	if not out.is_empty():
		save()
	return out


func finish_match(b: Board, won: bool) -> Dictionary:
	## 판 종료: 누적 기록 반영 → 경험치/레벨업 → 업적. 결과 화면용 요약을 돌려준다
	var best := b.wave > int(stats.get("best_round", 0))
	for k in _SUM_STATS:
		stats[k] = int(stats.get(k, 0)) + int(b.get(_SUM_STATS[k]))
	for k in _MAX_STATS:
		stats[k] = maxi(int(stats.get(k, 0)), int(b.get(_MAX_STATS[k])))
	var gained := GameData.match_xp(b.wave, b.kills, won)
	xp += gained
	var levels := 0
	var level_coins := 0
	while xp >= GameData.xp_to_next(level):
		xp -= GameData.xp_to_next(level)
		level += 1
		levels += 1
		level_coins += 50 + level * 10
	coins += level_coins
	save()
	var achs := check_achievements()
	return {"xp": gained, "levels": levels, "level": level, "level_coins": level_coins, "achievements": achs, "best": best}
