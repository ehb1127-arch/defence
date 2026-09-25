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
var stats := {"games": 0, "wins": 0, "best_round": 0}
var settings := {"sound": true, "captions": false}


func _ready() -> void:
	load_profile()
	apply_settings()


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
	if mode != "pvp":
		stats["best_round"] = maxi(int(stats["best_round"]), wave)
	save()
