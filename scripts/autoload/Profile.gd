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
const BAK_PATH := "user://profile.cfg.bak"     # 바로 전 저장 (본 파일이 깨지면 여기서 읽음)
const TMP_PATH := "user://profile.cfg.tmp"
const ACCOUNT_PATH := "user://account.cfg"     # 계정 ID 만 따로 (프로필 파일이 깨져도 서버 계정은 지킨다)
const SAVE_VERSION := 2
const SafeFile := preload("res://scripts/server/SafeFile.gd")

## 광고 하루 한도 (상점 광고 AD_DAILY_LIMIT 과 따로 센다)
const RESULT_AD_DAILY := 10      # 판 결과 코인 2배
const IDLE_AD_DAILY := 6         # 방치 보상 2배
## 판 표(begin_match) 없이 들어온 정산 = 오프라인에서 한 판을 재접속 때 재전송. 하루 이만큼만 인정
const OFFLINE_SETTLE_DAILY := 8
const TICKET_TTL := 6 * 3600     # 판 표 유효 시간 (초)
## 판 표 검사: 걸린 실제 시간 x 최대 배속으로 갈 수 있는 라운드까지만 인정 (GameData.min_match_time 기준).
## 오프라인 최대 배속 3, 온라인 판은 배속 없음. 약간의 여유(TIME_SLACK 비율 + TIME_GRACE 초)를 준다
const MAX_SPEED := 3.0
const TIME_SLACK := 0.85
const TIME_GRACE := 10.0

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
var settings := {"music": true, "sound": true, "labels": true, "vibrate": true, "account_sync": true, "focus_layout": false}
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
var ad_extra := {"date": "", "result": 0, "idle": 0}   # 결과 2배 / 방치 2배 광고 (하루)
var ticket := {}         # 진행 중인 판 표 {mode, stage, diff, t, online} - 서버가 정산 때 확인
var offline_settle := {"date": "", "n": 0}              # 표 없는 정산 횟수 (하루)

var coin_mult := 1.0     # 이벤트 코인 배수 (서버 설정 coin_event_mult, 저장 안 함)
var last_summary := {}   # 서버: 마지막으로 검증한 판 요약 (랭킹 기록용, 저장 안 함)
var _dirty := false
var _flush_queued := false
var _account_saved := ""
var _begin_unsent: Array = []   # 서버 연결 전에 시작한 판의 begin_match 인자 (연결되면 보낸다)

var server_side := false # 서버가 계정 처리용으로 만든 인스턴스
var ephemeral := false   # 테스트용: 파일에 쓰지 않는다 (개발자 기기의 프로필·계정을 덮어쓰지 않게)
var econ_server := false # 클라이언트: 서버가 재화의 기준
var linked := false      # 이 기기 진행이 서버 계정과 연결됨 (한 번이라도 동기화)
var pending_ops: Array = [] # 연결된 계정인데 오프라인일 때 쌓아 둔 작업 → 다음 접속 때 서버에 재전송
const MAX_PENDING := 200
var _req_id := 0
signal op_done(r: Array)   # [req_id, result]

## 저장/동기화 대상 필드 (설정·기기 ID 는 기기별이라 제외)
const PERSIST := ["coins", "items", "equipped", "perks", "ad_date", "ad_count", "stats", "level", "xp",
	"achievements", "campaign", "chests", "story_seen", "streak", "idle_last", "unit_levels", "discovered",
	"daily", "attendance", "tutorial_done", "rating", "roulette", "no_ads", "purchases", "ad_extra", "ticket",
	"offline_settle"]

func _ready() -> void:
	load_profile()
	if idle_last == 0:
		idle_last = now()
	if device_id == "":
		device_id = "%08x%08x%08x" % [randi(), randi(), Time.get_ticks_usec() & 0xFFFFFFFF]
		save()
	elif _dirty:
		save()
	apply_settings()
	Ads.ad_closed.connect(_on_ad_closed)


func _notification(what: int) -> void:
	# 앱이 내려가거나 닫힐 때 밀린 저장을 바로 쓴다
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_EXIT_TREE:
		flush()


# ---- 시간 (한국 시간 기준 하루) ----
func today() -> String:
	## 모든 하루 초기화(광고·일일 미션·출석·룰렛·오늘의 결계)의 기준 날짜: 한국 시간(UTC+9) "YYYY-MM-DD"
	return Story.kst_date()


func now() -> int:
	## 유닉스 초 (접속 중이면 서버 시각 기준)
	return Story.now()


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
	## 본 파일 → 바로 전 저장(.bak) → 쓰다 만 임시 파일 순서로 읽는다. 모두 깨져도 계정 ID 는 account.cfg 에서 지킨다
	var acc := ConfigFile.new()
	var has_acc := acc.load(ACCOUNT_PATH) == OK
	var cfg := ConfigFile.new()
	var ok := false
	for path in [PATH, BAK_PATH, TMP_PATH]:
		if FileAccess.file_exists(path) and cfg.load(path) == OK and cfg.has_section("p"):
			ok = true
			if path != PATH:
				push_warning("프로필 파일이 깨져 %s 에서 복구했습니다" % path)
				_keep_corrupt()
				_dirty = true   # 본 파일을 복구한 내용으로 다시 쓴다
			break
		cfg = ConfigFile.new()
	if not ok and FileAccess.file_exists(PATH):
		push_warning("프로필 파일이 깨졌고 백업도 없습니다 (서버 계정이 있으면 접속할 때 되살아남)")
		_keep_corrupt()
	if ok:
		var d := {}
		for k in PERSIST:
			if cfg.has_section_key("p", k):
				d[k] = cfg.get_value("p", k)
		_migrate_save(d, int(cfg.get_value("p", "version", 1)))
		from_dict(d)
		settings.merge(cfg.get_value("p", "settings", {}), true)
		device_id = str(cfg.get_value("p", "device_id", ""))
		linked = bool(cfg.get_value("p", "linked", false))
		var q = cfg.get_value("p", "pending_ops", [])
		pending_ops = q if q is Array else []
	if has_acc:
		# 계정 파일이 기준 (프로필이 깨졌거나 예전 백업에서 읽었어도 서버 계정은 그대로)
		var aid := str(acc.get_value("a", "id", ""))
		if aid != "":
			device_id = aid
			linked = linked or bool(acc.get_value("a", "linked", false))
	# account.cfg 가 지금 값과 같을 때만 "저장됨" (없거나 다르면 다음 저장 때 만든다 → 예전 버전에서 올라온 사용자도)
	_account_saved = ""
	if has_acc and str(acc.get_value("a", "id", "")) == device_id and bool(acc.get_value("a", "linked", false)) == linked:
		_account_saved = "%s|%s" % [device_id, linked]
	if not server_side and device_id != "":
		_save_account()


func _keep_corrupt() -> void:
	## 깨진 파일은 덮어쓰기 전에 따로 남겨 둔다 (문의 대응용)
	if FileAccess.file_exists(PATH):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(PATH), ProjectSettings.globalize_path(PATH + ".corrupt"))


func _migrate_save(d: Dictionary, from_version: int) -> void:
	## 저장 형식 버전 올림. 1 → 2: 광고 한도(ad_extra)·판 표 추가 (기본값 사용)
	if from_version < 2:
		d.erase("ticket")


func save() -> void:
	## 값 바뀜 알림은 바로, 파일 쓰기는 한 프레임에 한 번으로 모아서 (판 정산처럼 연달아 바뀔 때)
	if server_side:
		return
	_dirty = true
	if not _flush_queued:
		_flush_queued = true
		flush.call_deferred()
	changed.emit()


func flush() -> void:
	## 밀린 저장을 파일에 쓴다: 임시 파일에 쓰고 → 이전 파일은 .bak 으로 → 임시 파일을 본 파일로 (중간에 꺼져도 안전)
	_flush_queued = false
	if server_side or ephemeral or not _dirty:
		return
	_dirty = false
	var cfg := ConfigFile.new()
	var d := to_dict()
	for k in d:
		cfg.set_value("p", k, d[k])
	cfg.set_value("p", "version", SAVE_VERSION)
	cfg.set_value("p", "settings", settings)
	cfg.set_value("p", "device_id", device_id)
	cfg.set_value("p", "linked", linked)
	cfg.set_value("p", "pending_ops", pending_ops)
	if cfg.save(TMP_PATH) != OK:
		push_warning("프로필 저장 실패")
		return
	SafeFile.commit(TMP_PATH, PATH, BAK_PATH)
	_save_account()


func _save_account() -> void:
	var key := "%s|%s" % [device_id, linked]
	if key == _account_saved or device_id == "" or ephemeral:
		return
	var acc := ConfigFile.new()
	acc.set_value("a", "id", device_id)
	acc.set_value("a", "linked", linked)
	if acc.save(ACCOUNT_PATH + ".tmp") == OK:
		SafeFile.commit(ACCOUNT_PATH + ".tmp", ACCOUNT_PATH, "")
		_account_saved = key


func account_hash() -> String:
	## 결제에 붙이는 계정 표시 (Google Play obfuscatedAccountId). 기기 ID 를 그대로 보내지 않게 해시
	return device_id.sha256_text().substr(0, 64)


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
	Music.set_muted(not settings.get("music", true))
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
	## 상점 광고 (코인/랜덤 아이템) 남은 횟수
	var d := today()
	if ad_date != d:
		ad_date = d
		ad_count = 0
	return maxi(0, GameData.AD_DAILY_LIMIT - ad_count)


func _extra_reset() -> void:
	var d := today()
	if str(ad_extra.get("date", "")) != d:
		ad_extra = {"date": d, "result": 0, "idle": 0}


func result_ads_left() -> int:
	## 판 결과 "광고 보고 코인 2배" 남은 횟수 (0 이면 버튼을 숨기세요)
	_extra_reset()
	return maxi(0, RESULT_AD_DAILY - int(ad_extra.get("result", 0)))


func idle_ads_left() -> int:
	## 방치 보상 2배 광고 남은 횟수
	_extra_reset()
	return maxi(0, IDLE_AD_DAILY - int(ad_extra.get("idle", 0)))


func _note_extra_ad(kind: String) -> void:
	_extra_reset()
	ad_extra[kind] = int(ad_extra.get(kind, 0)) + 1


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
	var d := today()
	if daily.get("date", "") != d:
		daily = {"date": d, "progress": {}, "claimed": {}, "all": false}


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
	return attendance.get("last", "") != today()


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
	attendance = {"last": today(), "day": day + 1}
	save()
	sync("attend", [])
	return r


func attendance_day() -> int:
	## 다음에 받을 칸(0~6)
	return int(attendance.get("day", 0)) % GameData.ATTENDANCE.size()



# ---- 룰렛 ----
func _roulette_reset() -> void:
	var d := today()
	if roulette.get("date", "") != d:
		roulette = {"date": d, "free": false, "ads": 0}


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
	var secs := clampi(now() - idle_last, 0, 8 * 3600)
	return (secs / 600) * idle_rate()


func claim_idle(mult := 1) -> int:
	## 방치 보상 받기. mult 2 = 광고 보고 2배 (하루 IDLE_AD_DAILY 번, 넘으면 1배). 받은 코인을 돌려준다
	mult = clampi(mult, 1, 2)
	var base := idle_amount()
	if base <= 0:
		return 0
	if mult == 2:
		if idle_ads_left() > 0:
			_note_extra_ad("idle")
		else:
			mult = 1
	var n := base * mult
	coins += n
	idle_last = now()
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
	if coin_mult > 1.0:
		c = int(c * coin_mult)   # 코인 이벤트 (서버 설정)
	if s.get("ad_double", false):
		c *= 2
	return {"coins": c, "streak_bonus": bonus}


# ---- 판 표: 판을 시작할 때 서버에 알려 두고, 정산 때 걸린 시간·모드를 확인한다 ----
func begin_match(mode: String, stage: String, diff := -1) -> void:
	## 판이 실제로 시작될 때 한 번 (대사 끝나고 첫 라운드 시작 때). 클라이언트는 서버에 표를 요청한다
	if diff < 0:
		diff = Session.difficulty if not server_side else 0
	ticket = {"mode": mode.substr(0, 8), "stage": stage.substr(0, 24),
		"diff": clampi(diff, 0, GameData.DIFFICULTIES.size() - 1), "t": now(), "online": false}
	if server_side:
		return
	save()
	# 아직 서버 계정과 연결 전이면 연결되는 대로 보낸다 (link_server)
	_begin_unsent = [] if econ_server else [mode, stage, diff]
	sync("begin_match", [mode, stage, diff])


func max_wave_for(mode: String, elapsed: float, online: bool, stage_rounds := 0) -> int:
	## 판 표 이후 elapsed 초(실제 시간) 동안 도달할 수 있는 가장 높은 라운드
	var game_t := elapsed * (1.0 if online else MAX_SPEED) / TIME_SLACK + TIME_GRACE
	var cap := GameData.FINAL_WAVE + 40
	var w := 1
	while w < cap and GameData.min_match_time(mode, w + 1, stage_rounds) <= game_t:
		w += 1
	return w


func apply_match_end(s: Dictionary) -> Dictionary:
	## 판 결과 반영: 코인/연승/스테이지 ★/도감/일일 미션/누적 기록/경험치/업적.
	## 돌려주는 값의 ad_double = 광고 2배가 실제로 적용됐는지 (결과 2배 광고 한도를 넘으면 false)
	if server_side:
		s = validate_summary(s)
		last_summary = s
		if s.get("rejected", false):
			return {"coins": 0, "streak_bonus": 0.0, "stage": {}, "ad_double": false, "rejected": true}
	else:
		s = s.duplicate()
		ticket = {}
		_begin_unsent = []
	var ad_ok: bool = s.get("ad_double", false) and result_ads_left() > 0
	s["ad_double"] = ad_ok
	if ad_ok:
		_note_extra_ad("result")
	var won: bool = s.get("won", false)
	var mc := match_coins_preview(s)
	var out := {"coins": mc["coins"], "streak_bonus": mc["streak_bonus"], "stage": {}, "ad_double": ad_ok}
	if server_side:
		out["ticket"] = s.get("ticket", false)
		out["wave"] = int(s.get("wave", 0))
		out["won"] = s.get("won", false)
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


static func _num(v: Variant) -> int:
	## 요약 값: 수만 (문자열·배열 같은 이상한 값은 0)
	return int(v) if v is int or v is float else 0


static func _flag(v: Variant) -> bool:
	return v if v is bool else (v is int and v != 0)


func validate_summary(s: Dictionary) -> Dictionary:
	## 서버: 클라이언트가 보낸 판 요약의 상한 검사 (게임 계산이 클라이언트라 완전한 검증은 불가 → 이득을 제한)
	##  - 판 표(begin_match)가 있으면: 모드·스테이지가 같아야 하고, 걸린 시간으로 갈 수 있는 라운드까지만 인정. 표는 한 번만 쓴다
	##  - 표가 없으면(오프라인 판 재전송): 하루 OFFLINE_SETTLE_DAILY 번까지만, 온라인 판으로는 인정 안 함
	var v := {}
	var mode := str(s.get("mode", "solo"))
	v["mode"] = mode if mode in ["solo", "coop", "pvp"] else "solo"
	var stage := str(s.get("stage", "")).substr(0, 24)
	var tk := ticket
	ticket = {}
	var t0 := int(tk.get("t", 0))
	var has_ticket: bool = not tk.is_empty() and now() - t0 <= TICKET_TTL and str(tk.get("mode", "")) == v["mode"] \
		and str(tk.get("stage", "")) == stage
	var wave_cap := GameData.FINAL_WAVE + 40   # 무한 모드 연장전 포함
	if has_ticket:
		v["online"] = bool(tk.get("online", false))
		var sr := 0
		if stage != "":
			var st0 := Story.get_stage(stage)
			if not st0.is_empty():
				sr = int(st0["data"]["rounds"])
		wave_cap = mini(wave_cap, max_wave_for(v["mode"], float(now() - t0), v["online"], sr))
	else:
		v["online"] = false
		var d := today()
		if str(offline_settle.get("date", "")) != d:
			offline_settle = {"date": d, "n": 0}
		if int(offline_settle.get("n", 0)) >= OFFLINE_SETTLE_DAILY:
			return {"rejected": true, "ticket": false}
		offline_settle["n"] = int(offline_settle.get("n", 0)) + 1
		wave_cap = GameData.FINAL_WAVE + 10
	v["ticket"] = has_ticket
	var wave := clampi(_num(s.get("wave", 0)), 0, wave_cap)
	var won := _flag(s.get("won", false))
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
	var kills := clampi(_num(s.get("kills", 0)), 0, wave * 45 + 20)
	v["kills"] = kills
	v["stars"] = clampi(_num(s.get("stars", 0)), 0, 3) if won else 0
	v["merges_done"] = clampi(_num(s.get("merges_done", 0)), 0, kills / 2 + 50)
	v["mythics_done"] = clampi(_num(s.get("mythics_done", 0)), 0, 12)
	v["bosses_killed"] = clampi(_num(s.get("bosses_killed", 0)), 0, wave / 10 + 2)
	v["interrupts"] = clampi(_num(s.get("interrupts", 0)), 0, 100)
	v["slot_jackpots"] = clampi(_num(s.get("slot_jackpots", 0)), 0, 30)
	v["best_combo"] = clampi(_num(s.get("best_combo", 0)), 0, kills)
	v["max_star"] = clampi(_num(s.get("max_star", 0)), 0, GameData.STAR_MAX)
	v["mind_controls"] = clampi(_num(s.get("mind_controls", 0)), 0, wave / 2 + 2)
	var diff := clampi(_num(s.get("diff", 0)), 0, GameData.DIFFICULTIES.size() - 1)
	if has_ticket:
		diff = mini(diff, int(tk.get("diff", 0)))   # 시작할 때 정한 난이도보다 높게는 인정 안 함
	v["diff"] = diff if stage == "" and v["mode"] != "pvp" and not v["online"] else 0
	var ob: Array = []
	var src = s.get("obtained", [])
	if src is Array:
		for id in src.slice(0, 200):
			if GameData.UNITS.has(str(id)) and not str(id) in ob:
				ob.append(str(id))
	v["obtained"] = ob
	# 광고 2배는 결과 2배 광고 한도 안에서만 (apply_match_end 에서 확인)
	v["ad_double"] = _flag(s.get("ad_double", false))
	return v


# ===========================================================================
# 작업(op): 서버가 같은 규칙으로 실행하는 재화 변경 목록
# ===========================================================================
const OPS := ["buy_item", "buy_perk", "level_up_unit", "toggle_equip", "claim_daily", "claim_daily_bonus", "attend",
	"claim_chest", "claim_idle", "use_item", "take_loadout", "ad_reward", "roulette", "match_end", "story_seen", "tutorial_done",
	"ad_watched", "begin_match"]
## 오프라인일 때 대기열에 넣지 않는 작업 (판 표는 접속 중일 때만 의미가 있다)
const NO_QUEUE := ["begin_match"]


static func _s(a: Array, i: int) -> String:
	## 작업 인자: 짧은 문자열만
	return str(a[i]).substr(0, 32) if i < a.size() and (a[i] is String or a[i] is StringName) else ""


static func _i(a: Array, i: int, def := 0) -> int:
	## 작업 인자: 정수 (실수는 버림, 그 밖은 기본값)
	return int(a[i]) if i < a.size() and (a[i] is int or a[i] is float) else def


func run_op(op: String, a: Array) -> Variant:
	## 인자는 클라이언트가 보낸 값이므로 종류·범위를 여기서 다시 확인한다
	if not op in OPS:
		return null
	match op:
		"buy_item": return buy_item(_s(a, 0))
		"buy_perk": return buy_perk(_s(a, 0))
		"level_up_unit": return level_up_unit(_s(a, 0))
		"toggle_equip":
			if GameData.shop_item(_s(a, 0)).is_empty():
				return false
			toggle_equip(_s(a, 0))
			return true
		"claim_daily":
			for m in GameData.DAILY_MISSIONS:
				if m["id"] == _s(a, 0):
					return claim_daily(m)
			return false
		"claim_daily_bonus": return claim_daily_bonus()
		"attend": return attend()
		"claim_chest":
			var ch := _i(a, 0)
			var step := _i(a, 1)
			if ch < 1 or ch > Story.CHAPTERS.size() or step < 0 or step >= Story.CHEST_STEPS.size():
				return false
			return claim_chest(ch, step)
		"claim_idle": return claim_idle(clampi(_i(a, 0, 1), 1, 2))
		"use_item": return use_item(_s(a, 0))
		"take_loadout": return take_loadout(_s(a, 0))
		"ad_reward": return ad_reward(_s(a, 0))
		"roulette": return roulette_spin(a.size() > 0 and a[0] is bool and a[0])
		"match_end":
			if a.size() < 1 or not a[0] is Dictionary:
				return null
			return apply_match_end(a[0])
		"begin_match":
			begin_match(_s(a, 0), _s(a, 1), _i(a, 2))
			return true
		"story_seen":
			if Story.get_stage(_s(a, 0).trim_suffix("_end")).is_empty():
				return false
			story_seen[_s(a, 0)] = true
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
	elif linked and not op in NO_QUEUE:
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
	# 서버 연결 전에 시작한 판: 판 표를 지금 요청 (정산이 표 없는 판으로 처리되지 않게)
	if _begin_unsent.size() == 3:
		var b := _begin_unsent
		_begin_unsent = []
		_req_id += 1
		Net.send_op(_req_id, "begin_match", b)


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


func iap_restore(product_id: String) -> bool:
	## 구매 복원 (새 기기/계정에서 같은 영수증): 1회 상품의 권리(광고 제거·구매 기록)만 되살린다. 코인·아이템은 다시 주지 않음
	var p := GameData.iap_product(product_id)
	if p.is_empty() or not p.get("once", false):
		return false
	var changed_any := false
	if p["grant"].get("no_ads", false) and not no_ads:
		no_ads = true
		changed_any = true
	if not purchases.get(product_id, false):
		purchases[product_id] = true
		changed_any = true
	if changed_any:
		save()
	return changed_any


func iap_revoke(product_id: String, full := true) -> void:
	## 환불(무효 구매)된 결제 회수: 준 만큼 빼고(코인은 마이너스가 될 수 있음) 광고 제거·구매 기록을 없앤다.
	## full = false: 복원으로 권리만 받은 계정 → 권리만 회수
	var p := GameData.iap_product(product_id)
	if p.is_empty():
		return
	var g: Dictionary = p["grant"]
	if full:
		coins -= int(g.get("coins", 0))
		for id in g.get("items", {}):
			items[id] = maxi(0, item_count(id) - int(g["items"][id]))
	if g.get("no_ads", false):
		no_ads = false
	purchases.erase(product_id)
	save()


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
