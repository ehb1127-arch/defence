extends Node
## 플레이어 프로필 (코인, 보유 아이템, 영구 강화, 광고 시청 횟수, 설정, 기록).
##
## 두 가지로 동작한다.
##  - 로컬: user://profile.cfg 에 저장 (오프라인/개발)
##  - 서버 경제(econ_server): 전용 서버가 계정별로 이 스크립트의 인스턴스(server_side)를 만들어
##    같은 규칙으로 작업(op)을 검증·실행한다. 클라이언트는 즉시 반영(낙관적) 후
##    서버가 돌려준 프로필로 덮어써서 조작된 값은 되돌아간다.

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
var campaign := {}       # 스테이지 id -> 최고 ★ (0~3)
var chests := {}         # "장-단계" -> 받음
var story_seen := {}     # 스테이지 id -> 대사 봄
var streak := 0          # 연승
var idle_last := 0       # 방치 보상 마지막 수령 (유닉스 초)
var settings := {"sound": true, "labels": true, "vibrate": true, "account_sync": true, "focus_layout": false}
var device_id := ""
var unit_levels := {}    # 유닛 id -> 영구 레벨
var discovered := {}     # 도감: 한 번이라도 얻은 유닛
var daily := {"date": "", "progress": {}, "claimed": {}, "all": false}
var attendance := {"last": "", "day": 0}
var tutorial_done := false
var rating := 1000       # 서버에서 받은 대전 레이팅 (캐시)
var roulette := {"date": "", "free": false, "ads": 0}
var no_ads := false      # 광고 제거 구매
var purchases := {}      # 1회 한정 상품 구매 기록 (product id -> true)

var server_side := false # 서버가 계정 처리용으로 만든 인스턴스
var econ_server := false # 클라이언트: 서버가 재화의 기준
var linked := false      # 이 기기 진행이 서버 계정과 연결됨 (한 번이라도 동기화)
var pending_ops: Array = [] # 연결된 계정인데 오프라인일 때 쌓아 둔 작업 → 다음 접속 때 서버에 재전송
const MAX_PENDING := 200
var _req_id := 0
signal op_done(r: Array)   # [req_id, result]

## 저장/동기화 대상 필드 (설정·기기 ID 는 기기별이라 제외)
const PERSIST := ["coins", "items", "equipped", "perks", "ad_date", "ad_count", "stats", "level", "xp",
	"achievements", "campaign", "chests", "story_seen", "streak", "idle_last", "unit_levels", "discovered",
	"daily", "attendance", "tutorial_done", "rating", "roulette", "no_ads", "purchases"]

func _ready() -> void:
	load_profile()
	if idle_last == 0:
		idle_last = int(Time.get_unix_time_from_system())
	if device_id == "":
		device_id = "%08x%08x%08x" % [randi(), randi(), Time.get_ticks_usec() & 0xFFFFFFFF]
		save()
	apply_settings()
	Ads.ad_closed.connect(_on_ad_closed)


func _on_ad_closed(_p: String, rewarded: bool) -> void:
	if rewarded:
		add_progress("ad", 1)
		sync("ad_watched", [])


func mark_story_seen(id: String) -> void:
	story_seen[id] = true
	save()
	sync("story_seen", [id])


func mark_tutorial_done() -> void:
	tutorial_done = true
	save()
	sync("tutorial_done", [])


func load_profile() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	var d := {}
	for k in PERSIST:
		if cfg.has_section_key("p", k):
			d[k] = cfg.get_value("p", k)
	from_dict(d)
	settings.merge(cfg.get_value("p", "settings", {}), true)
	device_id = cfg.get_value("p", "device_id", "")
	linked = cfg.get_value("p", "linked", false)
	pending_ops = cfg.get_value("p", "pending_ops", [])


func save() -> void:
	if server_side:
		return
	var cfg := ConfigFile.new()
	var d := to_dict()
	for k in d:
		cfg.set_value("p", k, d[k])
	cfg.set_value("p", "settings", settings)
	cfg.set_value("p", "device_id", device_id)
	cfg.set_value("p", "linked", linked)
	cfg.set_value("p", "pending_ops", pending_ops)
	cfg.save(PATH)
	changed.emit()


func to_dict() -> Dictionary:
	var d := {}
	for k in PERSIST:
		var v = get(k)
		d[k] = v.duplicate(true) if v is Dictionary or v is Array else v
	return d


func from_dict(d: Dictionary) -> void:
	for k in d:
		if not k in PERSIST:
			continue
		var cur = get(k)
		if cur is Dictionary and d[k] is Dictionary:
			if k == "stats":
				stats.merge(d[k], true)
			else:
				set(k, d[k].duplicate(true))
		elif cur is int:
			set(k, int(d[k]))
		elif cur is bool:
			set(k, bool(d[k]))
		else:
			set(k, d[k])


func apply_settings() -> void:
	Sfx.muted = not settings["sound"]
	ActionButton.show_captions = settings.get("labels", true)


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
	sync("buy_item", [id])
	return true


func buy_perk(id: String) -> bool:
	var p := GameData.perk(id)
	if p.is_empty() or perk_level(id) >= p["max"] or coins < perk_price(id):
		return false
	coins -= perk_price(id)
	perks[id] = perk_level(id) + 1
	save()
	sync("buy_perk", [id])
	return true


func toggle_equip(id: String) -> void:
	equipped[id] = not equipped.get(id, false)
	save()
	sync("toggle_equip", [id])


func give_item(id: String, n := 1) -> void:
	items[id] = item_count(id) + n
	save()


func use_item(id: String) -> bool:
	if item_count(id) <= 0:
		return false
	items[id] = item_count(id) - 1
	save()
	sync("use_item", [id])
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
		sync("take_loadout", [mode])
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
	sync("level_up_unit", [id])
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
	sync("claim_daily", [m["id"]])
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
	sync("claim_daily_bonus", [])
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
	sync("attend", [])
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
const _SUM_STATS := {"kills": "kills", "mythics": "mythics_done", "bosses": "bosses_killed", "interrupts": "interrupts", "jackpots": "slot_jackpots", "merges": "merges_done", "controls": "mind_controls"}
const _MAX_STATS := {"max_star": "max_star", "max_combo": "best_combo", "best_round": "wave"}


func ach_value(stat: String, b: Board = null) -> int:
	## 누적 기록 + (진행 중인 판의 기록)
	match stat:
		"story_stars": return total_stars()
		"hard_stars": return hard_stars()
		"tower": return tower_best()
		"dailies":
			var nd := 0
			for k in campaign:
				if str(k).begins_with("D") and int(campaign[k]) > 0:
					nd += 1
			return nd
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


var _previewed := {}


func preview_achievements(b: Board) -> Array:
	## 게임 중 알림용 (지급은 판 종료 정산 때). 같은 단계는 한 번만 알린다
	var out: Array = []
	for a in GameData.ACHIEVEMENTS:
		var tier := maxi(ach_tier(a["id"]), int(_previewed.get(a["id"], 0)))
		var v := ach_value(a["stat"], b)
		while tier < a["goals"].size() and v >= a["goals"][tier]:
			out.append({"a": a, "tier": tier})
			tier += 1
		_previewed[a["id"]] = tier
	return out


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


func finish_match(s: Dictionary, won: bool) -> Dictionary:
	## 판 종료: 누적 기록 반영 → 경험치/레벨업 → 업적. s 는 Match 가 만든 판 요약
	var wave := int(s.get("wave", 0))
	var best := wave > int(stats.get("best_round", 0))
	for k in _SUM_STATS:
		stats[k] = int(stats.get(k, 0)) + int(s.get(_SUM_STATS[k], 0))
	for k in _MAX_STATS:
		stats[k] = maxi(int(stats.get(k, 0)), int(s.get(_MAX_STATS[k], 0)))
	var gained := GameData.match_xp(wave, int(s.get("kills", 0)), won)
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



# ---- 스토리 ----
func stage_stars(id: String) -> int:
	return int(campaign.get(id, 0))


func stage_unlocked(id: String) -> bool:
	if id == "1-1":
		return true
	if id.begins_with("H"):
		# 악몽: 보통 난이도에서 깬 스테이지만, 그리고 악몽 순서대로
		var base := id.substr(1)
		if stage_stars(base) <= 0:
			return false
		var hids := Story.hard_ids()
		var hi := hids.find(id)
		return hi == 0 or (hi > 0 and stage_stars(hids[hi - 1]) > 0)
	if id.begins_with("T"):
		var n := int(id.substr(1))
		return n >= 1 and n <= tower_best() + 1 and stage_stars("4-4") > 0
	if id.begins_with("D"):
		return id == Story.daily_id() and stage_stars("1-4") > 0
	var ids := Story.all_ids()
	var i := ids.find(id)
	return i > 0 and stage_stars(ids[i - 1]) > 0


func tower_best() -> int:
	var best := 0
	for k in campaign:
		if str(k).begins_with("T") and int(campaign[k]) > 0:
			best = maxi(best, int(str(k).substr(1)))
	return best


func daily_done() -> bool:
	return stage_stars(Story.daily_id()) > 0


func hard_stars() -> int:
	var n := 0
	for k in campaign:
		if str(k).begins_with("H"):
			n += int(campaign[k])
	return n


func chapter_stars(ch: int) -> int:
	var n := 0
	for i in Story.CHAPTERS[ch - 1]["stages"].size():
		n += stage_stars(Story.stage_id(ch, i + 1))
	return n


func total_stars() -> int:
	## 보통 난이도 스토리 ★ (악몽 ★는 hard_stars)
	var n := 0
	for id in campaign:
		var k := str(id)
		if not (k.begins_with("H") or k.begins_with("T") or k.begins_with("D")):
			n += int(campaign[id])
	return n


func record_stage(id: String, stars: int) -> Dictionary:
	## 스테이지 결과 반영. {first, new_stars, coins}
	var old := stage_stars(id)
	var out := Story.stage_reward(id, old, stars)
	if stars > old:
		campaign[id] = stars
	coins += out["coins"]
	save()
	return out


func chest_claimable(ch: int, step: int) -> bool:
	var need: int = Story.CHEST_STEPS[step][0]
	return chapter_stars(ch) >= need and not chests.get("%d-%d" % [ch, step], false)


func claim_chest(ch: int, step: int) -> bool:
	if not chest_claimable(ch, step):
		return false
	chests["%d-%d" % [ch, step]] = true
	var c: Array = Story.CHEST_STEPS[step]
	coins += int(c[1]) * ch
	items[c[2]] = item_count(c[2]) + 1
	save()
	sync("claim_chest", [ch, step])
	return true


# ---- 연승 ----
func streak_mult() -> float:
	return 1.0 + 0.1 * mini(streak, 5)


func note_result(won: bool) -> void:
	streak = streak + 1 if won else 0
	save()


# ---- 방치 보상: 접속하지 않아도 10분마다 코인이 쌓임 (최대 8시간) ----
func idle_rate() -> int:
	## 10분당 코인
	return 4 + total_stars() / 3 + level / 2


func idle_amount() -> int:
	var now := int(Time.get_unix_time_from_system())
	var secs := clampi(now - idle_last, 0, 8 * 3600)
	return (secs / 600) * idle_rate()


func claim_idle(mult := 1) -> int:
	var n := idle_amount() * mult
	coins += n
	idle_last = int(Time.get_unix_time_from_system())
	save()
	sync("claim_idle", [mult])
	return n



# ===========================================================================
# 판 종료 정산 (로컬/서버 공통)
# ===========================================================================
func preview_stage(id: String, stars: int) -> Dictionary:
	var out := Story.stage_reward(id, stage_stars(id), stars)
	out["stars"] = stars
	return out


func match_coins_preview(s: Dictionary) -> Dictionary:
	var won: bool = s.get("won", false)
	var c := GameData.match_coins(int(s.get("wave", 0)), int(s.get("kills", 0)), won)
	var bonus := 0.0
	if won and not s.get("online", false):
		bonus = 0.1 * mini(streak + 1, 5)
	c = int(c * (1.0 + bonus))
	var diff := clampi(int(s.get("diff", 0)), 0, GameData.DIFFICULTIES.size() - 1)
	if s.get("stage", "") == "" and s.get("mode", "solo") != "pvp" and not s.get("online", false):
		c = int(c * float(GameData.DIFFICULTIES[diff]["reward"]))
	if s.get("ad_double", false):
		c *= 2
	return {"coins": c, "streak_bonus": bonus}


func apply_match_end(s: Dictionary) -> Dictionary:
	## 판 결과 반영: 코인/연승/스테이지 ★/도감/일일 미션/누적 기록/경험치/업적
	if server_side:
		s = validate_summary(s)
	var won: bool = s.get("won", false)
	if s.get("ad_double", false):
		note_ad()
	var mc := match_coins_preview(s)
	var out := {"coins": mc["coins"], "streak_bonus": mc["streak_bonus"], "stage": {}}
	coins += mc["coins"]
	var stage: String = s.get("stage", "")
	if stage != "" and won and stage_unlocked(stage):
		out["stage"] = record_stage(stage, int(s.get("stars", 1)))
	stats["games"] = int(stats["games"]) + 1
	if won:
		stats["wins"] = int(stats["wins"]) + 1
	if not s.get("online", false):
		streak = streak + 1 if won else 0
	discover(s.get("obtained", []))
	add_progress("play", 1)
	add_progress("kill", int(s.get("kills", 0)))
	add_progress("merge", int(s.get("merges_done", 0)))
	add_progress("mythic", int(s.get("mythics_done", 0)))
	add_progress("boss", int(s.get("bosses_killed", 0)))
	out["finish"] = finish_match(s, won)
	_previewed.clear()
	save()
	return out


func validate_summary(s: Dictionary) -> Dictionary:
	## 서버: 클라이언트가 보낸 판 요약의 상한 검사 (게임 계산이 클라이언트라 완전한 검증은 불가 → 이득을 제한)
	var v := {}
	var mode := str(s.get("mode", "solo"))
	v["mode"] = mode if mode in ["solo", "coop", "pvp"] else "solo"
	v["online"] = bool(s.get("online", false))
	var wave := clampi(int(s.get("wave", 0)), 0, GameData.FINAL_WAVE + 40)   # 무한 모드 연장전 포함
	var stage := str(s.get("stage", ""))
	var won := bool(s.get("won", false))
	if stage != "":
		var st := Story.get_stage(stage)
		if st.is_empty() or not stage_unlocked(stage):
			stage = ""
			won = false
		else:
			wave = mini(wave, int(st["data"]["rounds"]))
			if wave < int(st["data"]["rounds"]):
				won = false
	elif v["mode"] != "pvp" and won and wave < GameData.FINAL_WAVE:
		won = false
	v["stage"] = stage
	v["wave"] = wave
	v["won"] = won
	var kills := clampi(int(s.get("kills", 0)), 0, wave * 45 + 20)
	v["kills"] = kills
	v["stars"] = clampi(int(s.get("stars", 0)), 0, 3) if won else 0
	v["merges_done"] = clampi(int(s.get("merges_done", 0)), 0, kills / 2 + 50)
	v["mythics_done"] = clampi(int(s.get("mythics_done", 0)), 0, 12)
	v["bosses_killed"] = clampi(int(s.get("bosses_killed", 0)), 0, wave / 10 + 2)
	v["interrupts"] = clampi(int(s.get("interrupts", 0)), 0, 100)
	v["slot_jackpots"] = clampi(int(s.get("slot_jackpots", 0)), 0, 30)
	v["best_combo"] = clampi(int(s.get("best_combo", 0)), 0, kills)
	v["max_star"] = clampi(int(s.get("max_star", 0)), 0, GameData.STAR_MAX)
	v["mind_controls"] = clampi(int(s.get("mind_controls", 0)), 0, wave / 2 + 2)
	v["diff"] = clampi(int(s.get("diff", 0)), 0, GameData.DIFFICULTIES.size() - 1) if stage == "" and v["mode"] != "pvp" and not v["online"] else 0
	var ob: Array = []
	for id in s.get("obtained", []):
		if GameData.UNITS.has(str(id)) and not str(id) in ob:
			ob.append(str(id))
	v["obtained"] = ob
	# 광고 2배는 하루 광고 한도 안에서만
	v["ad_double"] = bool(s.get("ad_double", false)) and ads_left() > 0
	return v


# ===========================================================================
# 작업(op): 서버가 같은 규칙으로 실행하는 재화 변경 목록
# ===========================================================================
const OPS := ["buy_item", "buy_perk", "level_up_unit", "toggle_equip", "claim_daily", "claim_daily_bonus", "attend",
	"claim_chest", "claim_idle", "use_item", "take_loadout", "ad_reward", "roulette", "match_end", "story_seen", "tutorial_done",
	"ad_watched"]


func run_op(op: String, a: Array) -> Variant:
	if not op in OPS:
		return null
	match op:
		"buy_item": return buy_item(str(a[0]))
		"buy_perk": return buy_perk(str(a[0]))
		"level_up_unit": return level_up_unit(str(a[0]))
		"toggle_equip":
			toggle_equip(str(a[0]))
			return true
		"claim_daily":
			for m in GameData.DAILY_MISSIONS:
				if m["id"] == str(a[0]):
					return claim_daily(m)
			return false
		"claim_daily_bonus": return claim_daily_bonus()
		"attend": return attend()
		"claim_chest": return claim_chest(int(a[0]), int(a[1]))
		"claim_idle": return claim_idle(int(a[0]) if a.size() > 0 else 1)
		"use_item": return use_item(str(a[0]))
		"take_loadout": return take_loadout(str(a[0]))
		"ad_reward": return ad_reward(str(a[0]))
		"roulette": return roulette_spin(bool(a[0]))
		"match_end": return apply_match_end(a[0])
		"story_seen":
			story_seen[str(a[0])] = true
			save()
			return true
		"tutorial_done":
			tutorial_done = true
			save()
			return true
		"ad_watched":
			add_progress("ad", 1)
			return true
	return null


func sync(op: String, a: Array) -> void:
	## 클라이언트: 로컬에서 방금 실행한 작업을 서버에도 보낸다 (서버 결과가 최종)
	if server_side:
		return
	if econ_server:
		_req_id += 1
		Net.send_op(_req_id, op, a)
	elif linked:
		if pending_ops.size() < MAX_PENDING:
			pending_ops.append([op, a])
		save()


func link_server(d: Dictionary) -> void:
	## 서버 계정 받음 → 서버 값으로 맞추고, 오프라인 동안 쌓인 작업을 순서대로 다시 보낸다
	from_dict(d)
	econ_server = true
	linked = true
	var q := pending_ops
	pending_ops = []
	save()
	for p in q:
		_req_id += 1
		Net.send_op(_req_id, str(p[0]), p[1])


func request(op: String, a: Array) -> Variant:
	## 결과가 서버 난수에 달린 작업(룰렛·랜덤 보상): 서버 경제면 서버 응답을 기다린다
	if server_side:
		return run_op(op, a)
	if not econ_server:
		var r: Variant = run_op(op, a)
		sync(op, a)
		return r
	_req_id += 1
	var my := _req_id
	Net.send_op(my, op, a)
	while true:
		var r: Array = await op_done
		if r[0] == my:
			return r[1]
		if r[0] == -1:   # 서버 연결이 끊김
			return null
	return null


func apply_server(d: Dictionary, req_id: int, result: Variant) -> void:
	## 서버 응답: 프로필을 서버 값으로 덮어쓰기 (더 최근 요청이 날아가 있으면 그 응답을 기다림)
	if req_id >= _req_id or req_id == 0:
		from_dict(d)
		save()
	op_done.emit([req_id, result])


func ad_reward(placement: String) -> Variant:
	## 상점 광고 보상 (하루 한도). 경기 중 광고 보상은 판 정산에서 처리
	match placement:
		"shop_coins":
			if ads_left() <= 0:
				return false
			note_ad()
			coins += GameData.AD_COINS
			save()
			return true
		"shop_item":
			if ads_left() <= 0:
				return ""
			note_ad()
			var it: Dictionary = GameData.SHOP_ITEMS[randi() % GameData.SHOP_ITEMS.size()]
			items[it["id"]] = item_count(it["id"]) + 1
			save()
			return it["id"]
	return false


func roulette_spin(by_ad: bool) -> int:
	## 룰렛 한 번 (서버 난수). 돌릴 수 없으면 -1
	if by_ad:
		if roulette_ads_left() <= 0:
			return -1
	elif not roulette_free_left():
		return -1
	use_roulette(by_ad)
	var total := 0
	for seg in GameData.ROULETTE:
		total += seg["w"]
	var r := randi() % total
	var idx := 0
	for i in GameData.ROULETTE.size():
		r -= GameData.ROULETTE[i]["w"]
		if r < 0:
			idx = i
			break
	grant(GameData.ROULETTE[idx])
	return idx


func iap_grant(product_id: String) -> bool:
	## 결제 확인 후 지급 (서버 또는 개발용 테스트 결제에서만 호출)
	var p := GameData.iap_product(product_id)
	if p.is_empty():
		return false
	if p.get("once", false) and purchases.get(product_id, false):
		return false
	var g: Dictionary = p["grant"]
	coins += int(g.get("coins", 0))
	for id in g.get("items", {}):
		items[id] = item_count(id) + int(g["items"][id])
	if g.get("no_ads", false):
		no_ads = true
	if p.get("once", false):
		purchases[product_id] = true
	save()
	return true
