class_name Board
extends Node2D
## 플레이어 한 명의 사각형 전장.
## 바깥 테두리 트랙을 적이 시계방향으로 돌고, 안쪽 격자에 유닛을 배치해 막는다.
## is_remote 가 true 면 시뮬레이션 없이 네트워크 스냅샷만 그린다.

signal defeated(board)
signal action_attack(board, attack_id)
signal action_gift_gold(board, amount)
signal action_gift_unit(board, unit_id)
signal action_blast(board)
signal final_cleared(board)

const SIZE := 560.0
const INSET := 28.0
const SIDE := 504.0
const LOOP := 2016.0
const COLS := 6
const ROWS := 6
const CELL := 448.0 / 6.0                 # 트랙 안쪽(56~504)을 격자로 꽉 채움
const GRID_ORIGIN := Vector2(56.0, 56.0)
const HEADER := 34.0                       # 전장 위(-HEADER~0)에 그리는 이름/적 수/보스 체력 줄
const CHEST_CHANCE := 0.012

var index := 0
var player_name := "플레이어"
var mode := "solo"
var is_remote := false
var is_bot := false
var accent := Color(0.3, 0.7, 1.0)
var enemy_limit := GameData.ENEMY_LIMIT
var partner_count := 0            # 협동: 파트너 필드 적 수 (표시용)
var rng := RandomNumberGenerator.new()
var event_rng := RandomNumberGenerator.new()

var cells: Array = []
var enemies: Array[EnemyState] = []
var effects: Array = []
var texts: Array = []
var chests: Array = []

var gold := GameData.START_GOLD
var gems := GameData.START_GEMS
var summon_count := 0
var upgrades := [0, 0, 0, 0]
var wave := 0
var wave_timer := GameData.PREP_TIME
var spawn_left := 0
var spawn_t := 0.0
var kills := 0
var free_summons := 0
var lucky_t := 0.0
var curse_t := 0.0
var frenzy := false
var rush_t := 0.0                # 위기: 폭주 (적 속도)
var eclipse_t := 0.0             # 위기: 일식 (사거리)
var sand_t := 0.0                # 보스 모래 폭풍 (사거리 감소)
var bless_t := 0.0               # 성기사 신성 축복 (공속 증가)
var horde := false               # 위기: 대침공 (이번 라운드 적 3배)
var crisis := ""                 # 이번 라운드 위기 이벤트 id (버티면 보상)
var fever_t := 0.0               # 피버 타임
var slowmo_t := 0.0              # 보스 처치 순간 슬로 모션 (Match 가 읽음)
var _heart_t := 0.0
var gauge := 0
var alive := true
var final_cleared_flag := false
var boss_failed := false         # 보스 제한시간 초과 = 패배
var bonus_left := 0
var boss_kill_times := {}          # 라운드 -> 처치까지 걸린 초 (통계/밸런스용)
var sfx := false                  # 이 전장에서 효과음을 낼지 (로컬 사람 플레이어만)
var _last_tick := -1
var bonus_chest := 0.0            # 영구 강화: 보물상자 확률 배수 추가
var bonus_gamble := 0.0           # 영구 강화: 운명 소환 성공률 추가
var bonus_boss_time := 0.0        # 영구 강화: 보스 제한시간 추가
var revived := 0
var unit_levels := {}             # 도감 유닛 영구 레벨 (대전은 비움)
var obtained := {}                # 이번 판에 얻은 유닛 (도감 등록용)
var merges_done := 0
var mythics_done := 0
var bosses_killed := 0
var combo := 0
var best_combo := 0
var _combo_t := 0.0
var combo_pop := 0.0
var boss_warn_t := 0.0
var mc_cd := 0.0                 # 지배 쿨타임
var pity_epic := 0               # 영웅 이상 없이 소환한 횟수
var pity_legend := 0
var summons_total := 0
var pending_pick: Array = []     # 골라 뽑기 후보 3개 (유닛 id)
var mind_controls := 0           # 이번 판 지배 횟수
var _hero_t := -1.0              # 적 영웅 등장까지 남은 시간 (-1 = 없음)
var pending_slot := {}            # 돌아가는 중인 슬롯 {reels, bet, t}
var last_slot := {}               # 마지막 결과 (UI 표시용)
var slot_spins := 0
var emote := ""
var syn := {}                     # 시너지 태그 -> 수치 (0 = 비활성)
var syn_counts := {}              # 시너지 태그 -> 서로 다른 유닛 종류 수
var syn_version := 0
var _syn_t := 0.0
var max_star := 0
# 스토리 스테이지
var final_wave := GameData.FINAL_WAVE
var stage_id := ""
var stage_hp_mult := 1.0
var stage_mods: Array = []
var stage_chapter := 0           # 스토리 장 번호 (탑/오늘의 결계 0)
var stage_hard := false
var difficulty := 0              # 무한 모드 난이도 (0 보통 / 1 어려움 / 2 지옥)
var mob_growth := GameData.MOB_EXTRA_GROWTH   # 밸런스 테스트에서 바꿔 볼 수 있게
var stage_boss := -1
var peak_field := 0              # ★ 평가용 최대 적 수 (보스·중간보스 무게 제외)
var gamble_fails: Array = [0, 0] # 운명 소환 종류별 연속 실패 (천장 계산)
var interrupts := 0
var slot_jackpots := 0
var pending_enhance := {}         # ★ 강화 시도 진행 중 {cell, t}
var last_enhance := {}
var emote_t := 0.0
var _alarm_t := 0.0
var attack_cd := 0.0            # 대전 공격 재사용 대기 (서버 중계 빈도 제한과 맞춤: 초당 2번)
const ATTACK_COOLDOWN := 0.5
var missions := {}
var gamble_wins := 0
var gamble_lose_streak := 0
var chests_opened := 0
var dmg_by_unit := {}
var legend_src := {}              # 전설을 어디서 얻었나 (밸런스 통계: summon/merge/gamble/mc/pick/slot/chest)
var time_alive := 0.0
var selected := -1
var hover := -1
var cursor := 0
var show_cursor := false
var banner := ""
var banner_sub := ""
var banner_t := 0.0
var banner_color := Color.WHITE
var shake := 0.0
var flash_t := 0.0
var flash_color := Color.WHITE
var remote_stats := {}
var _mission_t := 0.0
var _heal_t := 0.0
var _anim := 0.0

var font: Font


func _ready() -> void:
	font = load("res://fonts/NanumSquareRoundB.ttf")
	if font == null:
		font = ThemeDB.fallback_font
	if cells.is_empty():
		_reset_cells()


func setup(p_index: int, p_name: String, p_mode: String, seed_value: int, remote: bool, bot: bool) -> void:
	index = p_index
	player_name = p_name
	mode = p_mode
	is_remote = remote
	is_bot = bot
	rng.seed = seed_value * 7919 + p_index * 104729 + 17
	event_rng.seed = seed_value
	accent = [Color(0.35, 0.7, 1.0), Color(1.0, 0.5, 0.35)][p_index % 2]
	enemy_limit = GameData.COOP_ENEMY_LIMIT if mode == "coop" else GameData.ENEMY_LIMIT
	_reset_cells()


func _reset_cells() -> void:
	cells.clear()
	for i in COLS * ROWS:
		cells.append(_empty_cell())


func _empty_cell() -> Dictionary:
	return {"id": "", "n": 0, "timers": [0.0, 0.0, 0.0], "ramp": 0, "last": null, "hits": 0, "skill_t": 0.0, "kick": 0.0, "star": 0, "silence": 0.0}


# ===========================================================================
# 좌표 도우미
# ===========================================================================
static func path_pos(d: float) -> Vector2:
	var dd := fposmod(d, LOOP)
	var s := int(dd / SIDE)
	var r := dd - s * SIDE
	match s:
		0:
			return Vector2(INSET + r, INSET)
		1:
			return Vector2(INSET + SIDE, INSET + r)
		2:
			return Vector2(INSET + SIDE - r, INSET + SIDE)
		_:
			return Vector2(INSET, INSET + SIDE - r)


static func cell_center(i: int) -> Vector2:
	var c := i % COLS
	var r := i / COLS
	return GRID_ORIGIN + Vector2((c + 0.5) * CELL, (r + 0.5) * CELL)


static func cell_at(local: Vector2) -> int:
	var p := local - GRID_ORIGIN
	if p.x < 0 or p.y < 0:
		return -1
	var c := int(p.x / CELL)
	var r := int(p.y / CELL)
	if c >= COLS or r >= ROWS:
		return -1
	return r * COLS + c


# ===========================================================================
# 조회
# ===========================================================================
func field_count() -> int:
	if is_remote:
		return int(remote_stats.get("f", 0))
	var n := 0
	for e in enemies:
		if e.alive:
			n += e.weight * (2 if e.enraged else 1)
	return n


func rated_field_count() -> int:
	## ★ 평가용 적 수: 보스·중간보스 무게는 빼고 센다 (보스 스테이지도 ★3 가능)
	if is_remote:
		return field_count()
	var n := 0
	for e in enemies:
		if e.alive and not e.is_boss and e.kind != "midboss" and e.boss_name != "그림자 분신":
			n += e.weight * (2 if e.enraged else 1)
	return n


func summon_cost() -> int:
	var c := GameData.SUMMON_BASE_COST + GameData.SUMMON_COST_STEP * summon_count
	if lucky_t > 0.0:
		c = int(ceil(c * 0.5))
	return c


func unit_counts() -> Dictionary:
	var counts := {}
	for c in cells:
		if c["id"] != "":
			counts[c["id"]] = counts.get(c["id"], 0) + c["n"]
	return counts


func used_cells() -> int:
	var n := 0
	for c in cells:
		if c["id"] != "":
			n += 1
	return n


func has_space_for(id: String) -> bool:
	for c in cells:
		if c["id"] == "" or (c["id"] == id and c["n"] < GameData.MAX_STACK and c["star"] == 0):
			return true
	return false


func can_combine(mythic: String) -> bool:
	var need := {}
	for m in GameData.RECIPES[mythic]:
		need[m] = need.get(m, 0) + 1
	var have := unit_counts()
	for k in need:
		if have.get(k, 0) < need[k]:
			return false
	return true


func recipe_progress(mythic: String) -> Array:
	## [보유 재료 수, 필요 재료 수]
	var need := {}
	for m in GameData.RECIPES[mythic]:
		need[m] = need.get(m, 0) + 1
	var have := unit_counts()
	var got := 0
	var total := 0
	for k in need:
		total += need[k]
		got += mini(have.get(k, 0), need[k])
	return [got, total]


func mergeable(i: int) -> bool:
	var c: Dictionary = cells[i]
	return c["id"] != "" and c["n"] >= GameData.MAX_STACK and GameData.UNITS[c["id"]]["rarity"] <= GameData.Rarity.EPIC


func closest_recipe() -> String:
	## 가장 완성에 가까운 신화 (모자란 재료가 가장 적은 것 → 가진 재료가 많은 것 → 조합식 순서). 재료가 하나도 없으면 ""
	var have := unit_counts()
	var best := ""
	var best_missing := 999
	var best_got := 0
	for m in GameData.RECIPES:
		var need := {}
		for ing in GameData.RECIPES[m]:
			need[ing] = need.get(ing, 0) + 1
		var missing := 0
		var got := 0
		for ing in need:
			var h: int = mini(int(have.get(ing, 0)), need[ing])
			got += h
			missing += need[ing] - h
		if got == 0:
			continue
		if missing < best_missing or (missing == best_missing and got > best_got):
			best = m
			best_missing = missing
			best_got = got
	return best


func merge_protected(i: int, recipe := "?") -> bool:
	## 이 칸을 합성하면 가장 가까운 신화 조합의 재료가 모자라게 되는가 (합성 버튼이 아껴 두는 칸)
	if i < 0 or i >= cells.size() or cells[i]["id"] == "":
		return false
	var m := closest_recipe() if recipe == "?" else recipe
	if m == "":
		return false
	var id: String = cells[i]["id"]
	var need: int = GameData.RECIPES[m].count(id)
	if need == 0:
		return false
	return int(unit_counts().get(id, 0)) - int(cells[i]["n"]) < need


# ===========================================================================
# 라운드 규칙 (무한 모드 / 스토리 스테이지 공통)
# ===========================================================================
func apply_stage(id: String) -> void:
	var st := Story.get_stage(id)
	if st.is_empty():
		return
	var ch: Dictionary = st["chapter"]
	var d: Dictionary = st["data"]
	stage_id = id
	final_wave = d["rounds"]
	stage_hp_mult = ch["hp"]
	stage_mods = d.get("mods", [])
	stage_boss = d.get("boss", -1)
	stage_chapter = Story.chapter_of(id)
	stage_hard = st.get("hard", false)
	gold = ch["gold"]
	gems = ch["gems"]
	if "poor" in stage_mods:
		gold = int(gold * 0.7)


func is_boss_round(w: int) -> bool:
	if stage_id != "":
		return stage_boss >= 0 and w == final_wave
	return GameData.is_boss_wave(w)


func is_bonus_round(w: int) -> bool:
	if stage_id != "":
		return w == 5 and final_wave >= 8
	return GameData.is_bonus_wave(w)


func hp_at(w: int) -> float:
	var hp: float = GameData.wave_hp(w) * stage_hp_mult * pow(mob_growth, w - 1) * float(GameData.DIFFICULTIES[difficulty]["hp"])
	if "swarm" in stage_mods:
		hp *= 0.75
	if stage_id == "":
		hp *= GameData.mob_curve(w)
		if mode == "coop":
			hp *= GameData.COOP_MOB_HP
	if mode == "pvp":
		hp *= _pvp_ramp(w)
	return hp


func _pvp_ramp(w: int) -> float:
	## 대전: 일찍부터 라운드마다 더 단단해져 20라운드 전후에 승부가 난다
	return pow(GameData.PVP_RAMP, maxi(0, w - GameData.PVP_RAMP_FROM))


func boss_hp_at(w: int) -> float:
	if stage_id != "":
		var hp := GameData.wave_hp(w) * stage_hp_mult * GameData.BOSS_HP_MULT * GameData.STAGE_BOSS_HP
		if stage_boss in Story.FINAL_BOSSES:
			hp *= 1.5
		return hp
	if mode == "pvp":
		# 짧은 보스 제한시간에 맞춰 체력도 줄인다 (초반 보스 강화 배수 대신 기본 배수, 연장 가속은 그대로)
		var n := maxi(w / 10, 1)
		return GameData.wave_hp(w) * GameData.BOSS_HP_MULT * pow(GameData.BOSS_HP_DECAY, n - 1) * GameData.PVP_BOSS_TIME / GameData.BOSS_WAVE_TIME * _pvp_ramp(w)
	var hp: float = GameData.boss_hp(w) * (1.0 + (GameData.DIFFICULTIES[difficulty]["hp"] - 1.0) * 0.8)
	if mode == "coop":
		hp *= GameData.COOP_BOSS_HP   # 협동: 두 사람이 각자 보스를 잡아야 하고 필드 한도를 나눠 쓴다
	return hp


func boss_time_at(w: int) -> float:
	if stage_id != "":
		return 75.0 if stage_boss in Story.FINAL_BOSSES else GameData.BOSS_WAVE_TIME
	if mode == "pvp":
		return GameData.PVP_BOSS_TIME
	return GameData.boss_time(w)


func stage_stars() -> int:
	## 클리어 평가: 클리어 ★1, 최대 적 수 30 미만 ★2, 15 미만(부활 없이) ★3.
	## 최대 적 수는 보스·중간보스 무게를 빼고 센다 (peak_field)
	if not final_cleared_flag:
		return 0
	var st := 1
	if peak_field < 30:
		st += 1
	if peak_field < 15 and revived == 0:
		st += 1
	return st


func unit_power(id: String) -> float:
	## 강화(등급군) x 도감 유닛 레벨
	var u: Dictionary = GameData.UNITS[id]
	return dmg_mult(u["rarity"]) * (1.0 + GameData.UNIT_LEVEL_BONUS * int(unit_levels.get(id, 0)))


func dmg_mult(rarity: int) -> float:
	var lvl := 0
	for t in 3:
		if rarity in GameData.UPGRADES[t]["rarities"]:
			lvl = upgrades[t]
	return 1.0 + GameData.UPGRADE_DMG_PER_LEVEL * lvl


func upgrade_speed(rarity: int) -> float:
	var lvl := 0
	for t in 3:
		if rarity in GameData.UPGRADES[t]["rarities"]:
			lvl = upgrades[t]
	return 1.0 + GameData.UPGRADE_SPD_PER_LEVEL * lvl


func can_afford_upgrade(track: int) -> bool:
	if upgrades[track] >= (GameData.MAX_LUCK if track == 3 else GameData.MAX_UPGRADE):
		return false
	var cost := GameData.upgrade_cost(track, upgrades[track])
	if GameData.UPGRADES[track]["cur"] == "gems":
		return gems >= cost
	return gold >= cost


# ===========================================================================
# 플레이어 행동 (HUD / 키보드 / 봇 공통 API)
# ===========================================================================
func summon() -> bool:
	if not alive or is_remote:
		return false
	var free := free_summons > 0
	var cost := summon_cost()
	if not free and gold < cost:
		float_text(Vector2(SIZE / 2, 150), "골드 부족!", Color(1, 0.4, 0.4))
		return false
	var rarity := GameData.roll_summon_rarity(rng, upgrades[3])
	# 천장: 오래 안 나오면 확정
	var pity_hit := false
	if pity_legend + 1 >= GameData.PITY_LEGEND and rarity < GameData.Rarity.LEGEND:
		rarity = GameData.Rarity.LEGEND
		pity_hit = true
	elif pity_epic + 1 >= GameData.PITY_EPIC and rarity < GameData.Rarity.EPIC:
		rarity = GameData.Rarity.EPIC
		pity_hit = true
	var pick := (summons_total + 1) % GameData.PICK_EVERY == 0 and pending_pick.is_empty()
	var id := GameData.random_unit_of(rng, rarity)
	if not pick and not has_space_for(id):
		float_text(Vector2(SIZE / 2, 150), "빈 칸이 없어요!", Color(1, 0.4, 0.4))
		return false
	if free:
		free_summons -= 1
	else:
		gold -= cost
		summon_count += 1
	summons_total += 1
	pity_epic = 0 if rarity >= GameData.Rarity.EPIC else pity_epic + 1
	pity_legend = 0 if rarity >= GameData.Rarity.LEGEND else pity_legend + 1
	if pity_hit:
		show_banner("천장 도달!", "%s 등급 확정!" % GameData.RARITY_NAMES[rarity], GameData.RARITY_COLORS[rarity])
	if pick:
		# 골라 뽑기: 이번 등급 1장 + 같은 규칙으로 2장 더 → 셋 중 하나 고르기
		pending_pick = [id]
		while pending_pick.size() < 3:
			var r2 := maxi(GameData.roll_summon_rarity(rng, upgrades[3]), GameData.Rarity.RARE)
			var alt := _biased_unit_of(r2)
			if not alt in pending_pick:
				pending_pick.append(alt)
		show_banner("골라 뽑기!", "마음에 드는 유닛 하나를 고르세요", Color(0.6, 0.9, 1.0))
		_sfx("rare")
		return true
	var idx := add_unit(id)
	_count_legend(id, "summon")
	if rarity >= GameData.Rarity.EPIC:
		_rare_pull_fx(idx, rarity)
	else:
		_sfx("summon")
	return true


func _count_legend(id: String, src: String) -> void:
	if GameData.UNITS[id]["rarity"] == GameData.Rarity.LEGEND:
		legend_src[src] = int(legend_src.get(src, 0)) + 1


func export_state() -> Dictionary:
	## 다음 스테이지/층으로 이어갈 판 상태 (배치·강화·재화·천장)
	var cl: Array = []
	for c in cells:
		cl.append([c["id"], c["n"], c.get("star", 0)])
	return {"cells": cl, "upgrades": upgrades.duplicate(), "gold": gold, "gems": gems, "summon_count": summon_count,
		"pity_epic": pity_epic, "pity_legend": pity_legend, "summons_total": summons_total, "free_summons": free_summons,
		"obtained": obtained.keys()}


func import_state(d: Dictionary, gold_bonus: int, gem_bonus: int) -> void:
	var cl: Array = d.get("cells", [])
	for i in mini(cells.size(), cl.size()):
		cells[i] = _empty_cell()
		var e: Array = cl[i]
		if str(e[0]) != "" and GameData.UNITS.has(str(e[0])):
			cells[i]["id"] = str(e[0])
			cells[i]["n"] = clampi(int(e[1]), 1, GameData.MAX_STACK)
			cells[i]["star"] = clampi(int(e[2]), 0, GameData.STAR_MAX)
	var up: Array = d.get("upgrades", [])
	for i in mini(upgrades.size(), up.size()):
		upgrades[i] = int(up[i])
	gold = int(d.get("gold", 0)) + gold_bonus
	gems = int(d.get("gems", 0)) + gem_bonus
	summon_count = int(d.get("summon_count", 0))
	pity_epic = int(d.get("pity_epic", 0))
	pity_legend = int(d.get("pity_legend", 0))
	summons_total = int(d.get("summons_total", 0))
	free_summons = int(d.get("free_summons", 0))
	for id in d.get("obtained", []):
		obtained[id] = true
	_recalc_synergy()


func choose_pick(i: int) -> bool:
	if i < 0 or i >= pending_pick.size() or not alive:
		return false
	var id: String = pending_pick[i]
	if not has_space_for(id):
		float_text(Vector2(SIZE / 2, 150), "빈 칸이 없어요!", Color(1, 0.4, 0.4))
		return false
	pending_pick = []
	var idx := add_unit(id)
	_count_legend(id, "pick")
	var r: int = GameData.UNITS[id]["rarity"]
	if r >= GameData.Rarity.EPIC:
		_rare_pull_fx(idx, r)
	else:
		_sfx("summon")
	return true


func _biased_unit_of(rarity: int) -> String:
	## 이 등급에서 무작위 유닛. 단, 가장 가까운 신화 조합에 모자란 유닛은 더 잘 나온다 (합성·골라 뽑기용)
	var pool := GameData.units_of_rarity(rarity)
	var have := unit_counts()
	var want := {}
	var best_missing := 99
	for m in GameData.RECIPES:
		var need := {}
		for ing in GameData.RECIPES[m]:
			need[ing] = need.get(ing, 0) + 1
		var missing: Array = []
		for ing in need:
			for k in maxi(0, need[ing] - int(have.get(ing, 0))):
				missing.append(ing)
		if missing.is_empty() or missing.size() > 3:
			continue
		if missing.size() < best_missing:
			best_missing = missing.size()
			want = {}
		if missing.size() == best_missing:
			for ing in missing:
				want[ing] = true
	var weights: Array = []
	var total := 0.0
	for id in pool:
		var w := 1.0 + (GameData.MERGE_BIAS if want.has(id) else 0.0)
		weights.append(w)
		total += w
	var r := rng.randf() * total
	for i in pool.size():
		r -= weights[i]
		if r <= 0.0:
			return pool[i]
	return pool[pool.size() - 1]


func add_unit(id: String) -> int:
	## 같은 유닛 스택(3 미만) 우선, 없으면 빈칸. 실패 시 -1
	var target := -1
	for i in cells.size():
		if cells[i]["id"] == id and cells[i]["n"] < GameData.MAX_STACK and cells[i]["star"] == 0:
			target = i
			break
	if target < 0:
		target = best_cell_for(id)
		if target < 0:
			return -1
		cells[target] = _empty_cell()
		cells[target]["id"] = id
	var c: Dictionary = cells[target]
	obtained[id] = true
	c["timers"][c["n"]] = rng.randf() * 0.3
	c["n"] += 1
	var col: Color = GameData.RARITY_COLORS[GameData.UNITS[id]["rarity"]]
	_add_effect({"type": "ring", "pos": cell_center(target), "r0": 6.0, "r1": 40.0, "t": 0.0, "dur": 0.35, "color": col})
	_check_missions_now()
	return target


static func cell_ring(i: int) -> int:
	## 0 = 트랙과 닿은 바깥 칸, 1 = 한 칸 안쪽, 2 = 가운데 네 칸
	var c := i % COLS
	var r := i / COLS
	return mini(mini(c, r), mini(COLS - 1 - c, ROWS - 1 - r))


static func preferred_ring(id: String) -> int:
	## 새 유닛 자리: 사거리 짧은 유닛은 트랙 옆 바깥(0), 중간 사거리는 1, 긴 사거리·주변 버프 유닛은 안쪽(2)
	var u: Dictionary = GameData.UNITS[id]
	if u["fx"].has("aura_speed"):
		return 2
	var r: float = u["range"]
	if r < 200.0:
		return 0
	if r < 280.0:
		return 1
	return 2


static var _track_pts: PackedVector2Array


static func _track_coverage(i: int, rr: float) -> int:
	## 이 칸에서 사거리 안에 들어오는 트랙 지점 수 (48개 표본)
	if _track_pts.is_empty():
		for k in 48:
			_track_pts.append(path_pos(k * LOOP / 48.0))
	var c := cell_center(i)
	var n := 0
	for p in _track_pts:
		if p.distance_squared_to(c) <= rr * rr:
			n += 1
	return n


func best_cell_for(id: String) -> int:
	## 새 유닛을 둘 빈 칸 (없으면 -1). 선호 줄 → 트랙을 많이 덮는 칸 → 무작위. 배치 후 옮기는 건 자유
	var pref := preferred_ring(id)
	var order: Array = [[0, 1, 2], [1, 0, 2], [2, 1, 0]][pref]
	var rr: float = GameData.UNITS[id]["range"]
	for ring in order:
		var best: Array = []
		var best_cov := -1
		for i in cells.size():
			if cells[i]["id"] != "" or cell_ring(i) != ring:
				continue
			var cov := _track_coverage(i, rr)
			if cov > best_cov:
				best_cov = cov
				best = [i]
			elif cov == best_cov:
				best.append(i)
		if not best.is_empty():
			return best[rng.randi() % best.size()]
	return -1


func remove_units(id: String, count: int) -> void:
	## 스택이 작은 칸부터 제거
	var left := count
	while left > 0:
		var best := -1
		for i in cells.size():
			if cells[i]["id"] == id and (best < 0 or cells[i]["n"] < cells[best]["n"]):
				best = i
		if best < 0:
			return
		cells[best]["n"] -= 1
		left -= 1
		if cells[best]["n"] <= 0:
			cells[best] = _empty_cell()
			if selected == best:
				selected = -1


func merge_cell(i: int) -> bool:
	if not alive or i < 0 or not mergeable(i):
		return false
	var rarity: int = GameData.UNITS[cells[i]["id"]]["rarity"]
	cells[i] = _empty_cell()
	var new_r := rarity + 1
	var great_star := 0
	if rng.randf() < GameData.MERGE_GREAT_CHANCE:
		# 합성 대성공: 두 단계 점프 (전설 이상은 ★1 로)
		if new_r + 1 <= GameData.Rarity.LEGEND:
			new_r += 1
		else:
			great_star = 1
		show_banner("합성 대성공!", "", Color(1, 0.85, 0.3))
		_coin_burst(cell_center(i), 16)
		_sfx("legend")
	var id := _biased_unit_of(new_r)
	# 합성 연출: 세 마리가 가운데로 빨려 들어감
	_add_effect({"type": "merge", "pos": cell_center(i), "t": 0.0, "dur": 0.35, "color": GameData.RARITY_COLORS[new_r]})
	var idx := _place_unit(id, great_star, i)
	_count_legend(id, "merge")
	rarity = new_r - 1
	if selected == i and cells[i]["id"] == "":
		selected = idx
	merges_done += 1
	_sfx("merge")
	if rarity + 1 >= GameData.Rarity.EPIC:
		_rare_pull_fx(idx, rarity + 1)
	else:
		float_text(cell_center(idx), "합성!", GameData.RARITY_COLORS[rarity + 1])
	return true


func _place_unit(id: String, star: int, prefer := -1) -> int:
	## ★ 가 붙은 유닛은 따로 빈 칸에 (가능하면 prefer 칸)
	if star <= 0:
		return add_unit(id)
	var target := -1
	if prefer >= 0 and cells[prefer]["id"] == "":
		target = prefer
	else:
		target = best_cell_for(id)
	if target < 0:
		return add_unit(id)
	cells[target] = _empty_cell()
	cells[target]["id"] = id
	cells[target]["star"] = star
	cells[target]["n"] = 1
	obtained[id] = true
	return target


func _merge_pick(allow_protected: bool) -> int:
	## 합성할 칸: 가장 낮은 등급부터. 가장 가까운 신화 조합의 재료는 다른 칸이 없을 때만 (allow_protected)
	var recipe := closest_recipe()
	var best := -1
	var best_prot := true
	for i in cells.size():
		if not mergeable(i):
			continue
		var prot := merge_protected(i, recipe)
		if prot and not allow_protected:
			continue
		if best < 0 or (best_prot and not prot) or (prot == best_prot and GameData.UNITS[cells[i]["id"]]["rarity"] < GameData.UNITS[cells[best]["id"]]["rarity"]):
			best = i
			best_prot = prot
	return best


func auto_merge() -> bool:
	## 가장 낮은 등급의 합성 가능한 칸부터 합성. 신화 재료는 다른 합성거리가 없을 때만 쓴다
	var best := _merge_pick(true)
	if best < 0:
		return false
	return merge_cell(best)


func merge_all() -> int:
	## 합성 가능한 칸을 한 번에 모두 합성 (가장 가까운 신화 재료는 남겨 둠). 합성한 횟수를 돌려준다
	var done := 0
	for k in 16:
		var i := _merge_pick(false)
		if i < 0 or not merge_cell(i):
			break
		done += 1
	return done


func combine(mythic: String) -> bool:
	if not alive or not can_combine(mythic):
		return false
	var need := {}
	for m in GameData.RECIPES[mythic]:
		need[m] = need.get(m, 0) + 1
	for k in need:
		remove_units(k, need[k])
	var idx := add_unit(mythic)
	mythics_done += 1
	_rare_pull_fx(idx, GameData.Rarity.MYTHIC)
	_complete_mission("first_mythic")
	return true


func first_combinable() -> String:
	for m in GameData.RECIPES:
		if can_combine(m):
			return m
	return ""


func gamble(g: int) -> bool:
	if not alive:
		return false
	if "no_gamble" in stage_mods:
		float_text(Vector2(SIZE / 2, 150), "운 봉인! 운명 소환 불가", Color(1, 0.4, 0.4))
		return false
	var d: Dictionary = GameData.GAMBLES[g]
	if gems < d["gems"]:
		float_text(Vector2(SIZE / 2, 150), "보석 부족!", Color(1, 0.4, 0.4))
		return false
	var probe: String = GameData.units_of_rarity(d["rarity"])[0]
	if used_cells() >= cells.size() and not has_space_for(probe):
		float_text(Vector2(SIZE / 2, 150), "빈 칸이 없어요!", Color(1, 0.4, 0.4))
		return false
	gems -= d["gems"]
	var pity: int = d.get("pity", 0)
	var sure: bool = pity > 0 and int(gamble_fails[g]) >= pity
	if sure or rng.randf() < d["chance"] + bonus_gamble:
		var id := GameData.random_unit_of(rng, d["rarity"]) if not sure else _biased_unit_of(d["rarity"])
		var idx := add_unit(id)
		if idx < 0:
			gems += d["gems"]
			return false
		gamble_wins += 1
		gamble_lose_streak = 0
		gamble_fails[g] = 0
		_count_legend(id, "gamble")
		_rare_pull_fx(idx, d["rarity"])
		float_text(cell_center(idx), ("운명의 천장! %s" if sure else "대박! %s") % GameData.UNITS[id]["name"], GameData.RARITY_COLORS[d["rarity"]])
		if gamble_wins >= 3:
			_complete_mission("gamble_win3")
	else:
		gamble_lose_streak += 1
		gamble_fails[g] += 1
		if pity > 0 and gamble_fails[g] >= pity:
			float_text(Vector2(SIZE / 2, 185), "다음 %s 확정!" % d["name"], GameData.RARITY_COLORS[d["rarity"]], 16)
		var lines := ["꽝!", "다음엔 될 거야...", "운이 없네요", "보석이 증발했다", "하... 꽝"]
		float_text(Vector2(SIZE / 2, 150), lines[rng.randi() % lines.size()], Color(0.7, 0.7, 0.75), 20)
		_sfx("fail")
		shake = 4.0
		if gamble_lose_streak >= 3:
			_complete_mission("gamble_lose3")
	return true


func upgrade(track: int) -> bool:
	if not alive or not can_afford_upgrade(track):
		return false
	var cost := GameData.upgrade_cost(track, upgrades[track])
	if GameData.UPGRADES[track]["cur"] == "gems":
		gems -= cost
	else:
		gold -= cost
	upgrades[track] += 1
	var what := "소환 확률 UP" if track == 3 else "공격력 +%d%% · 공속 +%d%%" % [int(GameData.UPGRADE_DMG_PER_LEVEL * 100), int(GameData.UPGRADE_SPD_PER_LEVEL * 100)]
	float_text(Vector2(SIZE / 2, 150), "%s Lv.%d  %s" % [GameData.UPGRADES[track]["name"], upgrades[track], what], Color(0.6, 1.0, 0.6), 16)
	# 강화된 유닛 칸마다 ▲ 표시
	for k in cells.size():
		if cells[k]["id"] != "" and track < 3 and GameData.UNITS[cells[k]["id"]]["rarity"] in GameData.UPGRADES[track]["rarities"]:
			_add_effect({"type": "up", "pos": cell_center(k), "t": 0.0, "dur": 0.8, "color": Color(0.5, 1.0, 0.6)})
	_sfx("merge")
	return true


func sell_one(i: int) -> bool:
	if not alive or i < 0 or cells[i]["id"] == "":
		return false
	var id: String = cells[i]["id"]
	var r: int = GameData.UNITS[id]["rarity"]
	if r >= GameData.Rarity.MYTHIC:
		float_text(cell_center(i), "신화는 판매 불가", Color(1, 0.4, 0.4))
		return false
	cells[i]["n"] -= 1
	if cells[i]["n"] <= 0:
		cells[i] = _empty_cell()
		selected = -1
	var g: int = GameData.SELL_GOLD[r]
	var m: int = GameData.SELL_GEMS[r]
	gold += g
	gems += m
	float_text(cell_center(i), ("+%dG" % g) if g > 0 else ("+%d보석" % m), Color(1, 0.9, 0.3))
	return true


func swap_cells(a: int, b: int) -> void:
	if a < 0 or b < 0 or a == b:
		return
	var ca: Dictionary = cells[a]
	var cb: Dictionary = cells[b]
	# 같은 유닛이면 합쳐서 스택 채우기
	if ca["id"] != "" and ca["id"] == cb["id"]:
		var move := mini(ca["n"], GameData.MAX_STACK - cb["n"])
		cb["n"] += move
		ca["n"] -= move
		if ca["n"] <= 0:
			cells[a] = _empty_cell()
		return
	cells[a] = cb
	cells[b] = ca


func take_unit(i: int) -> String:
	## 협동 선물용으로 한 마리 꺼내기
	if i < 0 or cells[i]["id"] == "":
		return ""
	var id: String = cells[i]["id"]
	cells[i]["n"] -= 1
	if cells[i]["n"] <= 0:
		cells[i] = _empty_cell()
		selected = -1
	return id


func request_attack(attack_id: String) -> bool:
	## 대전 공격 보내기. 너무 빨리 연달아 누르면 재화를 쓰지 않고 거절 (attack_cd)
	if not alive:
		return false
	if attack_cd > 0.0:
		return false
	for a in GameData.ATTACKS:
		if a["id"] == attack_id:
			if gold < a["gold"] or gems < a["gems"]:
				float_text(Vector2(SIZE / 2, 150), "재화 부족!", Color(1, 0.4, 0.4))
				return false
			gold -= a["gold"]
			gems -= a["gems"]
			attack_cd = ATTACK_COOLDOWN
			float_text(Vector2(SIZE / 2, 150), "%s 발사!" % a["name"], Color(1, 0.5, 0.3), 20)
			# "id:라운드" - 받는 쪽이 보낸 사람의 라운드에 맞춰 세기를 정한다
			action_attack.emit(self, "%s:%d" % [attack_id, wave])
			return true
	return false


func request_gift_gold(amount: int) -> bool:
	if not alive or gold < amount:
		return false
	gold -= amount
	float_text(Vector2(SIZE / 2, 150), "골드 %d 선물!" % amount, Color(1, 0.9, 0.3))
	action_gift_gold.emit(self, amount)
	return true


func request_gift_unit(i: int) -> bool:
	if not alive:
		return false
	var id := take_unit(i)
	if id == "":
		return false
	float_text(cell_center(i), "%s 선물!" % GameData.UNITS[id]["name"], Color(0.6, 1.0, 0.8))
	action_gift_unit.emit(self, id)
	return true


func request_blast() -> bool:
	if not alive or gauge < GameData.COOP_BLAST_NEED:
		return false
	gauge = 0
	action_blast.emit(self)
	return true


func open_chest(i: int) -> void:
	if i < 0 or i >= chests.size():
		return
	var ch: Dictionary = chests[i]
	chests.remove_at(i)
	chests_opened += 1
	var roll := rng.randf()
	if roll < 0.55:
		var g := 30 + wave * 4
		gold += g
		float_text(ch["pos"], "보물상자 +%dG" % g, Color(1, 0.9, 0.3), 18)
	elif roll < 0.8:
		gems += 1
		float_text(ch["pos"], "보물상자 +1 보석", Color(0.6, 0.9, 1.0), 18)
	elif roll < 0.95:
		free_summons += 2
		float_text(ch["pos"], "무료 소환 +2", Color(0.6, 1.0, 0.6), 18)
	else:
		var id := GameData.random_unit_of(rng, GameData.Rarity.EPIC)
		if add_unit(id) >= 0:
			float_text(ch["pos"], "영웅 %s 획득!" % GameData.UNITS[id]["name"], GameData.RARITY_COLORS[2], 18)
		else:
			gems += 2
			float_text(ch["pos"], "보물상자 +2 보석", Color(0.6, 0.9, 1.0), 18)
	_add_effect({"type": "ring", "pos": ch["pos"], "r0": 5.0, "r1": 50.0, "t": 0.0, "dur": 0.4, "color": Color(1, 0.85, 0.3)})
	if chests_opened >= 5:
		_complete_mission("chest_5")


# ===========================================================================
# 외부에서 받는 효과 (상대/파트너)
# ===========================================================================
func attack_power(attack_id: String, sender_wave: int) -> Dictionary:
	## 보내기 공격의 세기: 보낸 사람의 라운드가 높을수록 강하다 {count, hp_mult, time}
	var w := maxi(sender_wave, 1)
	match attack_id:
		"swarm":
			return {"count": 6 + w / 3, "hp_mult": 1.0, "time": 0.0}
		"elite":
			return {"count": 1 + (1 if w >= 12 else 0) + (1 if w >= 24 else 0), "hp_mult": 1.0 + w * 0.02, "time": 0.0}
		"curse":
			return {"count": 0, "hp_mult": 1.0, "time": 10.0 + w * 0.25}
	return {}


func receive_attack(attack_id: String) -> void:
	## attack_id: "swarm" 또는 "swarm:17"(보낸 사람 라운드). 조작 방지로 내 라운드 +2 까지만 인정
	if not alive or is_remote:
		return
	var parts := attack_id.split(":")
	var aid: String = parts[0]
	var sw := wave
	if parts.size() > 1:
		sw = clampi(int(parts[1]), 1, wave + 2)
	var w := maxi(maxi(wave, sw), 1)
	var pw := attack_power(aid, w)
	match aid:
		"swarm":
			for k in int(pw["count"]):
				var e := _spawn("fast", hp_at(w), -k * 16.0)
				e.sent = true
				e.no_mc = true
			show_banner("적이 몰려온다!", "상대가 잡몹 %d마리를 보냈습니다" % int(pw["count"]), Color(1, 0.5, 0.3))
		"elite":
			for k in int(pw["count"]):
				var e := _spawn("elite", hp_at(w) * float(pw["hp_mult"]), -k * 40.0)
				e.sent = true
				e.no_mc = true
			show_banner("정예 괴수 습격!", "상대가 정예 %d마리를 보냈습니다" % int(pw["count"]), Color(1, 0.3, 0.3))
		"curse":
			curse_t = float(pw["time"])
			show_banner("저주에 걸렸다!", "%d초간 공격 속도 -30%%" % int(pw["time"]), Color(0.7, 0.4, 1.0))
		_:
			return
	shake = 8.0
	_sfx("alarm")


func receive_gold(amount: int) -> void:
	if is_remote:
		return
	gold += amount
	float_text(Vector2(SIZE / 2, 150), "파트너 선물 +%dG" % amount, Color(1, 0.9, 0.3), 20)


func receive_unit(id: String) -> bool:
	if is_remote:
		return true
	var idx := add_unit(id)
	if idx < 0:
		# 자리가 없으면 판매 가격으로 환급
		var r: int = GameData.UNITS[id]["rarity"]
		gold += GameData.SELL_GOLD[r] * 2
		gems += maxi(GameData.SELL_GEMS[r], 1 if r >= 3 else 0)
		float_text(Vector2(SIZE / 2, 150), "자리 부족 - 환급받음", Color(1, 0.8, 0.4))
		return false
	float_text(cell_center(idx), "선물 도착! %s" % GameData.UNITS[id]["name"], Color(0.6, 1.0, 0.8), 18)
	return true


func receive_blast() -> void:
	if is_remote:
		return
	_flash(Color(1.0, 0.95, 0.6), 0.6)
	shake = 12.0
	for e in enemies:
		if e.alive:
			var dmg: float = e.max_hp * (0.1 if e.is_boss else 0.35)
			_damage(e, dmg, "", true)
	show_banner("합동 폭격!", "모든 적에게 큰 피해", Color(1, 0.95, 0.5))


# ===========================================================================
# 시뮬레이션
# ===========================================================================
func step(dt: float) -> void:
	_anim += dt
	_update_visuals(dt)
	if is_remote or not alive:
		return
	time_alive += dt
	lucky_t = maxf(0.0, lucky_t - dt)
	rush_t = maxf(0.0, rush_t - dt)
	fever_t = maxf(0.0, fever_t - dt)
	slowmo_t = maxf(0.0, slowmo_t - dt)
	attack_cd = maxf(0.0, attack_cd - dt)
	# 위기 심장 박동: 적이 한도 85% 이상
	if alive and not is_remote and float(field_count() + partner_count) / enemy_limit >= 0.85:
		_heart_t -= dt
		if _heart_t <= 0.0:
			_heart_t = 0.8
			_sfx("heart")
	eclipse_t = maxf(0.0, eclipse_t - dt)
	sand_t = maxf(0.0, sand_t - dt)
	bless_t = maxf(0.0, bless_t - dt)
	mc_cd = maxf(0.0, mc_cd - dt)
	peak_field = maxi(peak_field, rated_field_count())
	curse_t = maxf(0.0, curse_t - dt)
	_update_waves(dt)
	_update_enemies(dt)
	_update_units(dt)
	_update_chests(dt)
	_update_slot(dt)
	_update_enhance(dt)
	_cleanup()
	_mission_t -= dt
	if _mission_t <= 0.0:
		_mission_t = 0.5
		_check_missions_now()


func _update_waves(dt: float) -> void:
	var finished := mode != "pvp" and final_cleared_flag
	if not finished:
		wave_timer -= dt
		var sec := int(ceil(wave_timer))
		if sec != _last_tick and sec >= 1 and sec <= 5:
			_last_tick = sec
			_sfx("tick_boss" if is_boss_round(wave) else "tick")
		if wave_timer <= 0.0:
			_end_wave()
			if boss_failed:
				return
			if stage_id != "" and wave >= final_wave and not is_boss_round(wave):
				# 보스 없는 스테이지: 마지막 라운드를 버티면 클리어
				final_cleared_flag = true
				final_cleared.emit(self)
				show_banner("스테이지 클리어!", "", Color(1, 0.85, 0.35))
				return
			_start_wave(wave + 1)
	# 적이 한도에 가까우면 경보
	_alarm_t -= dt
	if _alarm_t <= 0.0 and float(field_count() + partner_count) / enemy_limit >= 0.8:
		_alarm_t = 2.0
		_sfx("alarm")
	if _hero_t > 0.0:
		_hero_t -= dt
		if _hero_t <= 0.0:
			_hero_t = -1.0
			_spawn_hero()
	if spawn_left > 0:
		spawn_t -= dt
		if spawn_t <= 0.0:
			spawn_t = GameData.PVP_SPAWN_INTERVAL if mode == "pvp" else GameData.SPAWN_INTERVAL
			spawn_left -= 1
			var kind := GameData.pick_enemy(rng, wave, _special_wave(wave))
			if "tank" in stage_mods and rng.randf() < 0.35:
				kind = "tank"
			elif "elites" in stage_mods and rng.randf() < 0.07:
				kind = "elite"
			_spawn(kind, hp_at(wave) * (0.55 if horde else 1.0), 0.0)
			if horde:
				spawn_t *= 0.4
			# 남은 수가 라운드 안에 다 나오도록 간격을 줄인다 (대전 후반 +1마리씩, 대군 위기)
			if spawn_left > 0 and wave_timer > 1.0:
				spawn_t = minf(spawn_t, maxf(0.12, (wave_timer - 1.0) / spawn_left))


func _special_wave(w: int) -> int:
	## 분열체·치유사 해금용 라운드: 스토리 깊은 장·탑 높은 층·오늘의 결계·악몽은 앞당긴다
	if stage_id == "":
		return w
	var tower := int(stage_id.substr(1)) if stage_id.begins_with("T") else 0
	return w + GameData.stage_special_offset(stage_chapter, tower, stage_id.begins_with("D"), stage_hard)


func _end_wave() -> void:
	frenzy = false
	horde = false
	if crisis != "" and alive:
		gems += GameData.CRISIS_REWARD_GEMS
		show_banner("위기 극복!", "보석 +%d" % GameData.CRISIS_REWARD_GEMS, Color(0.5, 1, 0.6))
		_sfx("reward")
	crisis = ""
	if wave <= 0:
		return
	if is_boss_round(wave):
		for e in enemies:
			if e.alive and e.is_boss:
				boss_failed = true
		if boss_failed:
			show_banner("보스 제한시간 초과!", "보스를 잡지 못했습니다", Color(1, 0.2, 0.2))
			_flash(Color(1, 0, 0), 0.6)
			shake = 14.0
	elif is_bonus_round(wave):
		var missed := 0
		for e in enemies:
			if e.alive and e.kind == "bonus":
				e.alive = false
				missed += 1
		if missed > 0:
			float_text(Vector2(SIZE / 2, 150), "보너스 종료 - 놓친 돼지 %d마리" % missed, Color(1, 0.7, 0.75), 16)
	else:
		var bonus := 10 + wave * 2
		gold += bonus
		float_text(Vector2(SIZE / 2, 150), "라운드 보너스 +%dG" % bonus, Color(1, 0.9, 0.3))


func _start_wave(w: int) -> void:
	wave = w
	_last_tick = -1
	if is_boss_round(w):
		wave_timer = boss_time_at(w) + bonus_boss_time
		spawn_left = 0
		var b: EnemyState = _spawn("boss", boss_hp_at(w), 0.0)
		b.boss_name = GameData.BOSS_NAMES[(w / 10 - 1) % GameData.BOSS_NAMES.size()]
		b.art = GameData.BOSS_ART[(w / 10 - 1) % GameData.BOSS_ART.size()]
		var eb := _endless_boss(w)
		if stage_boss < 0 and (eb >= 5 or (w > GameData.FINAL_WAVE and eb != 4)):
			# 연장전 보스: 스킬과 같은 보스의 이름·그림으로 (2부 보스들이 차례로)
			b.boss_name = Story.BOSS_NAMES[eb]
			b.art = "boss_" + Story.BOSS_CHARS[eb]
		if stage_boss >= 0:
			b.boss_name = Story.BOSS_NAMES[stage_boss]
			b.art = "boss_" + Story.BOSS_CHARS[stage_boss]
		elif w == final_wave:
			b.art = "boss_lord"
		if (stage_id == "" and w == final_wave) or stage_boss in Story.FINAL_BOSSES:
			b.boss_name = "최종 보스 · " + (Story.BOSS_NAMES[stage_boss] if stage_boss >= 0 else "사각의 군주")
			b.size *= 1.3
		boss_warn_t = 2.5
		_setup_boss_skills(b, w)
		show_banner("ROUND %d - 보스!" % w, "%s 등장! %d초 안에 못 잡으면 패배" % [b.boss_name, int(boss_time_at(w))], Color(1, 0.3, 0.5))
		_sfx("boss")
	elif is_bonus_round(w):
		wave_timer = GameData.PVP_BONUS_TIME if mode == "pvp" else GameData.BONUS_WAVE_TIME
		spawn_left = 0
		bonus_left = GameData.BONUS_COUNT
		for k in GameData.BONUS_COUNT:
			_spawn("bonus", hp_at(w), -k * 36.0)
		show_banner("ROUND %d - 보너스!" % w, "%d초 안에 보물 돼지를 잡아 골드를 챙기세요" % int(wave_timer), Color(1, 0.75, 0.8))
		_sfx("round")
	else:
		wave_timer = GameData.PVP_WAVE_TIME if mode == "pvp" else GameData.WAVE_TIME
		spawn_left = GameData.SPAWN_PER_WAVE * (3 if "swarm" in stage_mods else 2) / 2
		if mode == "pvp" and w >= GameData.PVP_EXTRA_SPAWN_FROM:
			spawn_left += w - GameData.PVP_EXTRA_SPAWN_FROM + 1
		spawn_t = 0.0
		if _midboss_round(w):
			var mb := _spawn("midboss", hp_at(w), 0.0)
			var mi := (w / 10 + (stage_chapter if stage_id != "" else 0)) % GameData.MIDBOSS_NAMES.size()
			mb.boss_name = GameData.MIDBOSS_NAMES[mi]
			mb.art = GameData.MIDBOSS_ART[mi]
			boss_warn_t = 1.5
			show_banner("ROUND %d - 중간보스!" % w, "%s 등장! 오래 두면 적 한도가 빨리 차요" % mb.boss_name, Color(0.85, 0.45, 1.0))
			_sfx("boss")
		else:
			show_banner("ROUND %d" % w, "", Color(0.9, 0.9, 1.0))
			_sfx("round")
		# 적 영웅: 라운드 중간에 난입 (대전은 같은 시드라 두 사람에게 똑같이)
		if not _midboss_round(w) and event_rng.randf() < _hero_chance(w):
			_hero_t = 5.0 + event_rng.randf() * 6.0
	if GameData.is_event_wave(w):
		_random_event()


func _midboss_round(w: int) -> bool:
	if w >= final_wave:
		return false
	if stage_id == "":
		return GameData.is_midboss_wave(w)
	# 스토리/탑: '중간보스' 규칙이 있을 때 4·8라운드, 3장 이후 10라운드 이상 스테이지는 7라운드
	if "midboss" in stage_mods and (w == 4 or w == 8):
		return true
	return stage_chapter >= 3 and final_wave >= 10 and w == 7


func _hero_chance(w: int) -> float:
	if "heroes" in stage_mods:
		return 1.0 if w >= 2 else 0.0
	if w < GameData.HERO_FROM_WAVE:
		return 0.0
	if stage_id != "" and stage_chapter > 0 and stage_chapter < 3 and not stage_hard:
		return 0.0   # 초반 스토리는 영웅 없이
	return GameData.HERO_CHANCE


func _crisis_event(ev: Dictionary) -> void:
	crisis = ev["id"]
	show_banner(ev["name"], ev["desc"], Color(1, 0.25, 0.25))
	_flash(Color(1, 0.1, 0.1), 0.4)
	boss_warn_t = 2.0
	shake = maxf(shake, 8.0)
	_sfx("alarm")
	match crisis:
		"horde":
			horde = true
			spawn_left = spawn_left * 3
		"rush":
			rush_t = 10.0
		"eclipse":
			eclipse_t = 15.0
		"quake":
			var occupied: Array = []
			for k in cells.size():
				if cells[k]["id"] != "":
					occupied.append(k)
			for n in mini(3, occupied.size()):
				var k: int = occupied[rng.randi() % occupied.size()]
				occupied.erase(k)
				cells[k]["silence"] = 3.0
				_add_effect({"type": "boom", "pos": cell_center(k), "r": 36.0, "t": 0.0, "dur": 0.5, "color": Color(0.7, 0.55, 0.3)})
			shake = 16.0


func _spawn_hero() -> void:
	var h: Dictionary = GameData.ENEMY_HEROES[event_rng.randi() % GameData.ENEMY_HEROES.size()]
	var e := _spawn("hero", hp_at(wave) * h["hp"], 0.0)
	e.hero = h["id"]
	e.art = "hero_" + h["id"]
	e.boss_name = h["name"]
	e.speed = h["speed"]
	e.armor = h["armor"]
	e.color = h["color"]
	if "fast" in stage_mods:
		e.speed *= 1.25
	boss_warn_t = 1.2
	show_banner("적 영웅 출현!", "%s - %s" % [h["name"], h["desc"]], Color(1, 0.45, 0.3))
	_flash(Color(1, 0.3, 0.2), 0.25)
	_sfx("alarm")


func _update_hero(e: EnemyState, dt: float) -> void:
	## 적 영웅 능력 + 모든 영웅은 가끔 돌진 (잠깐 2.6배 속도)
	e.dash_t -= dt
	if e.dash_t <= 0.0:
		e.dash_t = 7.0 + rng.randf() * 3.0
		e.buff_t = 1.2
		float_text(e.pos + Vector2(0, -40), "돌진!", e.color.lightened(0.3), 16)
		_add_effect({"type": "ring", "pos": e.pos, "r0": 8.0, "r1": 50.0, "t": 0.0, "dur": 0.35, "color": e.color})
	match e.hero:
		"thief":
			var lap := int(e.dist / LOOP)
			if lap > e.lap:
				e.lap = lap
				var steal := mini(gold, 10 + wave * 2)
				if steal > 0:
					gold -= steal
					float_text(e.pos + Vector2(0, -24), "-%dG 도둑맞음!" % steal, Color(1, 0.45, 0.45), 17)
					_sfx("fail")
		"berserker":
			var base: float = GameData.enemy_hero("berserker")["speed"]
			e.speed = base * (1.0 + (1.0 - e.hp_ratio()) * 1.3)
			e.enraged = e.hp_ratio() < 0.5
		"shaman", "warlord":
			e.skill_t -= dt
			if e.skill_t <= 0.0:
				e.skill_t = 1.0 if e.hero == "shaman" else 3.0
				for o in enemies:
					if not o.alive or o == e or o.is_boss or o.pos.distance_to(e.pos) > 120.0:
						continue
					if e.hero == "shaman":
						o.hp = minf(o.max_hp, o.hp + o.max_hp * 0.05)
					else:
						o.shield = maxf(o.shield, o.max_hp * 0.12)
						o.max_shield = maxf(o.max_shield, o.shield)
				_add_effect({"type": "ring", "pos": e.pos, "r0": 10.0, "r1": 120.0, "t": 0.0, "dur": 0.5, "color": e.color})


func can_mind_control() -> bool:
	return alive and not is_remote and mc_cd <= 0.0 and gems >= GameData.MC_GEMS and _mc_target() != null and used_cells() < cells.size()


func _mc_target() -> EnemyState:
	## 가장 강한 적 (중간보스 > 적 영웅 > 정예 > ...), 같은 종류면 체력이 많은 쪽. 보스는 불가
	var best: EnemyState = null
	var best_rank := 999
	for e in enemies:
		if not e.alive or e.is_boss or e.no_mc or not GameData.MC_RARITY.has(e.kind):
			continue
		var rank: int = GameData.MC_PRIORITY.find(e.kind)
		if rank < best_rank or (rank == best_rank and e.hp > best.hp):
			best = e
			best_rank = rank
	return best


func mind_control() -> bool:
	## 지배: 보석으로 트랙 위의 가장 강한 적을 빼앗아 내 유닛으로 (스타크래프트 마인드 컨트롤처럼)
	if not can_mind_control():
		if mc_cd > 0.0:
			float_text(Vector2(SIZE / 2, 150), "지배 대기 %d초" % int(ceil(mc_cd)), Color(0.8, 0.6, 1.0))
		elif gems < GameData.MC_GEMS:
			float_text(Vector2(SIZE / 2, 150), "보석 부족!", Color(1, 0.4, 0.4))
		elif used_cells() >= cells.size():
			float_text(Vector2(SIZE / 2, 150), "빈 칸이 없어요!", Color(1, 0.4, 0.4))
		return false
	var e := _mc_target()
	var rarity: int = GameData.MC_RARITY[e.kind]
	var id := GameData.random_unit_of(rng, rarity)
	var name := e.boss_name if e.boss_name != "" else "적"
	e.alive = false
	gems -= GameData.MC_GEMS
	mc_cd = GameData.MC_COOLDOWN
	mind_controls += 1
	var idx := add_unit(id)
	_count_legend(id, "mc")
	if idx < 0:
		return false
	var to := cell_center(idx)
	_add_effect({"type": "pierce", "from": e.pos, "to": to, "t": 0.0, "dur": 0.6, "color": Color(0.8, 0.4, 1.0)})
	_add_effect({"type": "ring", "pos": e.pos, "r0": 8.0, "r1": 60.0, "t": 0.0, "dur": 0.5, "color": Color(0.8, 0.4, 1.0)})
	show_banner("지배 성공!", "%s → %s" % [name, GameData.UNITS[id]["name"]], Color(0.8, 0.5, 1.0))
	_flash(Color(0.7, 0.3, 1.0), 0.3)
	if rarity >= GameData.Rarity.LEGEND:
		_rare_pull_fx(idx, rarity)
	else:
		_sfx("rare")
	return true


func _random_event() -> void:
	# 위기 이벤트: 긴장감. 보스 라운드·보너스 라운드는 제외
	if wave >= GameData.CRISIS_FROM_WAVE and not is_boss_round(wave) and not is_bonus_round(wave) \
			and event_rng.randf() < GameData.DIFFICULTIES[difficulty]["crisis"]:
		_crisis_event(GameData.CRISES[event_rng.randi() % GameData.CRISES.size()])
		return
	var pool: Array = GameData.EVENTS.duplicate()
	if is_boss_round(wave):
		pool = pool.filter(func(ev): return ev["id"] != "frenzy")
	var ev: Dictionary = pool[event_rng.randi() % pool.size()]
	show_banner(ev["name"], ev["desc"], Color(1.0, 0.85, 0.3))
	match ev["id"]:
		"goblin":
			_spawn("goblin", hp_at(wave), 0.0)
		"lucky":
			lucky_t = 15.0
		"frenzy":
			frenzy = true
		"supply":
			free_summons += 3
		"storm":
			_flash(Color(0.8, 0.9, 1.0), 0.4)
			for e in enemies:
				if e.alive:
					_damage(e, e.max_hp * (0.08 if e.is_boss else 0.25), "", true)
		"gemrain":
			gems += 2


func _spawn(kind: String, base_hp: float, offset: float) -> EnemyState:
	var e := EnemyState.new()
	e.setup(kind, base_hp)
	if "fast" in stage_mods:
		e.speed *= 1.25
	if "armored" in stage_mods:
		e.armor += 15.0
	e.dist = offset
	e.pos = path_pos(e.dist)
	e.wobble = rng.randf() * TAU
	enemies.append(e)
	return e


func _update_enemies(dt: float) -> void:
	_heal_t -= dt
	var do_heal := _heal_t <= 0.0
	if do_heal:
		_heal_t = 1.0
	for e in enemies:
		if not e.alive:
			continue
		e.flash = maxf(0.0, e.flash - dt)
		# 상태이상
		if e.burn_t > 0.0:
			e.burn_t -= dt
			_damage(e, e.burn_dps * dt, "", false)
		if e.poison_t > 0.0:
			e.poison_t -= dt
			_damage(e, e.poison_dps * dt, "", false)
		if not e.alive:
			continue
		if e.slow_t > 0.0:
			e.slow_t -= dt
			if e.slow_t <= 0.0:
				e.slow = 0.0
		if e.is_boss:
			_update_boss(e, dt)
		elif e.hero != "":
			_update_hero(e, dt)
		e.freeze_t = maxf(0.0, e.freeze_t - dt)
		var spd: float = e.speed * (1.0 - maxf(e.slow, e.aura_slow))
		if e.buff_t > 0.0:
			e.buff_t -= dt
			spd *= 2.6
		if frenzy:
			spd *= 1.3
		if rush_t > 0.0:
			spd *= 1.6
		e.aura_slow = 0.0
		if e.stun_t > 0.0:
			e.stun_t -= dt
			spd = 0.0
		e.dist += spd * dt
		e.pos = path_pos(e.dist)
		if e.kind == "goblin" and e.dist >= LOOP:
			e.alive = false
			float_text(e.pos, "고블린이 도망쳤다!", Color(1, 0.8, 0.3))
		if do_heal and e.heal > 0.0:
			for o in enemies:
				if o.alive and o != e and o.hp < o.max_hp and o.pos.distance_squared_to(e.pos) < 90.0 * 90.0:
					o.hp = minf(o.max_hp, o.hp + o.max_hp * e.heal)
			_add_effect({"type": "ring", "pos": e.pos, "r0": 10.0, "r1": 90.0, "t": 0.0, "dur": 0.4, "color": Color(1, 0.6, 0.85, 0.6)})


func _aura_speed(i: int) -> float:
	var c := i % COLS
	var r := i / COLS
	var bonus := 0.0
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nc: int = c + dx
			var nr: int = r + dy
			if nc < 0 or nr < 0 or nc >= COLS or nr >= ROWS:
				continue
			var o: Dictionary = cells[nr * COLS + nc]
			if o["id"] != "":
				var a: float = GameData.UNITS[o["id"]]["fx"].get("aura_speed", 0.0)
				bonus += a * o["n"]
	return minf(bonus, 0.6)


# ===========================================================================
# 시너지 / ★ / 각성
# ===========================================================================
func _recalc_synergy() -> void:
	var kinds := {}
	for c in cells:
		if c["id"] != "":
			for tag in GameData.UNIT_TAGS.get(c["id"], []):
				if not kinds.has(tag):
					kinds[tag] = {}
				kinds[tag][c["id"]] = true
	var new_syn := {}
	var counts := {}
	for tag in GameData.SYNERGY_ORDER:
		var n: int = kinds.get(tag, {}).size()
		counts[tag] = n
		var val := 0.0
		for tier in GameData.SYNERGIES[tag]["tiers"]:
			if n >= tier[0]:
				val = tier[1]
		new_syn[tag] = val
	if new_syn != syn:
		# 새 시너지 발동 알림
		for tag in new_syn:
			if new_syn[tag] > syn.get(tag, 0.0) and not is_remote:
				float_text(Vector2(SIZE / 2, SIZE - 110), "시너지 발동: %s" % GameData.SYNERGIES[tag]["name"], GameData.SYNERGIES[tag]["color"], 16)
		syn = new_syn
		syn_version += 1
	syn_counts = counts


func has_tag(id: String, tag: String) -> bool:
	return tag in GameData.UNIT_TAGS.get(id, [])


func cell_damage(c: Dictionary) -> float:
	var id: String = c["id"]
	var m: float = unit_power(id) * (1.0 + GameData.STAR_DMG * c.get("star", 0))
	if has_tag(id, "warrior"):
		m *= 1.0 + syn.get("warrior", 0.0)
	return GameData.UNITS[id]["dmg"] * m


func cell_range(c: Dictionary) -> float:
	var id: String = c["id"]
	var r: float = GameData.UNITS[id]["range"]
	if has_tag(id, "archer"):
		r *= 1.0 + syn.get("archer", 0.0) * 0.8
	if eclipse_t > 0.0:
		r *= 0.75
	if sand_t > 0.0:
		r *= 0.75
	return r


func cell_speed(c: Dictionary) -> float:
	var id: String = c["id"]
	var s: float = (1.0 + GameData.STAR_SPEED * c.get("star", 0)) * (1.0 + syn.get("support", 0.0)) * upgrade_speed(GameData.UNITS[id]["rarity"])
	if has_tag(id, "archer"):
		s *= 1.0 + syn.get("archer", 0.0)
	if "curse" in stage_mods:
		s *= 0.85
	if fever_t > 0.0:
		s *= 1.0 + GameData.FEVER_SPEED
	return s


func cell_fx(c: Dictionary) -> Dictionary:
	## 기본 특성 + 각성(★3) + 시너지를 합친 실제 특성 (칸별 캐시)
	var key := "%s_%d_%d" % [c["id"], c.get("star", 0), syn_version]
	if c.get("fx_key", "") == key:
		return c["fx_cache"]
	var id: String = c["id"]
	var fx: Dictionary = GameData.UNITS[id]["fx"].duplicate()
	var awake: bool = c.get("star", 0) >= GameData.AWAKEN_STAR
	var k := 1.35 if awake else 1.0
	for f in ["splash", "slow", "burn", "poison", "armor_break", "knockback", "freeze_chance", "meteor_mult", "gold_chance"]:
		if fx.has(f):
			fx[f] = fx[f] * k
	if fx.has("stun_chance"):
		fx["stun_chance"] = minf(0.6, fx["stun_chance"] * k + (0.05 if syn.get("lightning", 0.0) > 0.0 and has_tag(id, "lightning") else 0.0))
	if fx.has("slow"):
		fx["slow"] = minf(0.7, fx["slow"])
	if awake:
		if fx.has("chain"):
			fx["chain"] += 1
		if fx.has("multishot"):
			fx["multishot"] += 1
		if fx.has("crit"):
			fx["crit"] += 0.1
	if has_tag(id, "mage") and fx.has("splash"):
		fx["splash"] *= 1.0 + syn.get("mage", 0.0)
	if has_tag(id, "lightning") and fx.has("chain"):
		fx["chain"] += int(syn.get("lightning", 0.0))
	if has_tag(id, "ice"):
		fx["freeze_chance"] = fx.get("freeze_chance", 0.0) + syn.get("ice", 0.0)
	var asn: float = syn.get("assassin", 0.0)
	if asn > 0.0:
		fx["crit"] = fx.get("crit", 0.0) + asn
		fx["crit_mult"] = fx.get("crit_mult", 2.0)
	if syn.get("fire", 0.0) > 0.0:
		for f in ["burn", "poison"]:
			if fx.has(f):
				fx[f] *= 1.0 + syn["fire"]
	c["fx_key"] = key
	c["fx_cache"] = fx
	return fx


func _update_units(dt: float) -> void:
	var speed_mult := 0.7 if curse_t > 0.0 else 1.0
	if bless_t > 0.0:
		speed_mult *= 1.35
	_syn_t -= dt
	if _syn_t <= 0.0:
		_syn_t = 0.4
		_recalc_synergy()
	for i in cells.size():
		var c: Dictionary = cells[i]
		if c["id"] == "":
			continue
		var u: Dictionary = GameData.UNITS[c["id"]]
		var fx := cell_fx(c)
		var center := cell_center(i)
		var rr := cell_range(c)
		var rng_sq: float = rr * rr
		# 보스 포효/화염 폭발: 침묵 중에는 공격 불가
		if c.get("silence", 0.0) > 0.0:
			c["silence"] -= dt
			continue
		# 수호천사: 사거리 내 적 둔화 오라
		if fx.has("slow_aura"):
			for e in enemies:
				if e.alive and e.pos.distance_squared_to(center) <= rng_sq:
					e.aura_slow = maxf(e.aura_slow, fx["slow_aura"])
		# 신화 스킬 (마법사 시너지로 쿨 감소)
		if u.has("skill"):
			c["skill_t"] += dt * (1.0 + (syn.get("mage", 0.0) * 0.5 if has_tag(c["id"], "mage") else 0.0))
			if c["skill_t"] >= u["skill"]["cd"] and _has_target_near(center, INF):
				c["skill_t"] = 0.0
				_cast_skill(i, c, u)
		var spd := speed_mult * (1.0 + _aura_speed(i)) * cell_speed(c)
		if fx.has("ramp"):
			spd *= 1.0 + fx["ramp"] * c["ramp"]
		for k in c["n"]:
			c["timers"][k] -= dt * spd
			if c["timers"][k] > 0.0:
				continue
			var target := _find_target(center, rng_sq)
			if target == null:
				c["timers"][k] = 0.05
				c["ramp"] = 0
				continue
			c["timers"][k] = u["cd"]
			c["kick"] = 0.12
			_attack(i, c, u, target, fx, rr)
			if c.get("star", 0) >= GameData.TRANSCEND_STAR and target.alive:
				# ★5 초월: 한 번에 두 번 공격
				_attack(i, c, u, target, fx, rr)


func _has_target_near(center: Vector2, r: float) -> bool:
	for e in enemies:
		if e.alive and (r == INF or e.pos.distance_to(center) <= r):
			return true
	return false


func _find_target(center: Vector2, rng_sq: float) -> EnemyState:
	var best: EnemyState = null
	for e in enemies:
		if e.alive and e.pos.distance_squared_to(center) <= rng_sq:
			if best == null or e.dist > best.dist:
				best = e
	return best


func _targets_in_range(center: Vector2, rng_sq: float, count: int) -> Array:
	var list: Array = []
	for e in enemies:
		if e.alive and e.pos.distance_squared_to(center) <= rng_sq:
			list.append(e)
	list.sort_custom(func(a, b): return a.dist > b.dist)
	return list.slice(0, count)


## 유닛 문양 → 공격 연출 (유닛마다 다르게 보이도록)
const ATK_STYLE := {
	"blade": "slash", "axe": "spin", "dagger": "stab", "spear": "thrust", "shield": "bash",
	"bow": "arrow", "arrows": "arrow", "scope": "tracer", "rock": "lob", "coin": "coin",
	"orb": "orb", "meteor": "fireball", "flame": "fireball", "snow": "ice", "bolt": "zap",
	"flask": "flask", "note": "note", "halo": "holy", "wing": "lance",
	"phoenix": "fireball", "clock": "clockwork", "crown": "coin", "skull": "scythe",
}
const ATK_SFX := {"ice": "ice", "zap": "zap", "clockwork": "zap"}
const ATK_DUR := {
	"slash": 0.18, "spin": 0.22, "stab": 0.12, "thrust": 0.16, "bash": 0.2, "arrow": 0.16, "tracer": 0.14,
	"lob": 0.3, "coin": 0.26, "orb": 0.2, "fireball": 0.22, "ice": 0.18, "zap": 0.12, "flask": 0.3,
	"note": 0.3, "holy": 0.26, "lance": 0.15, "clockwork": 0.22, "scythe": 0.22,
}


func _attack(i: int, c: Dictionary, u: Dictionary, target: EnemyState, fx: Dictionary, rr: float) -> void:
	var center := cell_center(i)
	var id: String = c["id"]
	var base: float = cell_damage(c)
	var col: Color = u["color"]
	var awake: bool = c.get("star", 0) >= GameData.AWAKEN_STAR
	# 광전사 가속
	if fx.has("ramp"):
		if c["last"] == target:
			c["ramp"] = mini(c["ramp"] + 1, fx["ramp_max"])
		else:
			c["ramp"] = 0
		c["last"] = target
	var targets: Array = [target]
	if fx.has("multishot"):
		targets = _targets_in_range(center, rr * rr, fx["multishot"])
	for t in targets:
		var dmg := base
		var crit := false
		if fx.has("crit") and rng.randf() < fx["crit"]:
			dmg *= fx["crit_mult"]
			crit = true
		var style: String = u.get("atk", ATK_STYLE.get(u["glyph"], "orb"))
		_sfx(ATK_SFX.get(style, "hit"))
		_add_effect({"type": "atk", "style": style, "from": center, "to": t.pos, "t": 0.0, "dur": ATK_DUR.get(style, 0.16),
			"color": col.lightened(0.3) if awake else col, "big": u["rarity"] >= 3 or awake, "seed": rng.randf() * TAU})
		_hit(t, dmg, id, fx, crit)
		# 관통: 대상 뒤 일직선의 적도 관통
		if fx.has("pierce"):
			var dir: Vector2 = (t.pos - center).normalized()
			var end: Vector2 = center + dir * rr * 1.4
			_add_effect({"type": "pierce", "from": center, "to": end, "t": 0.0, "dur": 0.15, "color": col})
			for e in enemies:
				if e.alive and e != t and Geometry2D.get_closest_point_to_segment(e.pos, center, end).distance_to(e.pos) < 14.0:
					_hit(e, dmg * 0.7, id, {}, false)
		# 연쇄 번개
		if fx.has("chain"):
			var hit_list: Array = [t]
			var prev: EnemyState = t
			var cdmg := dmg
			for n in fx["chain"]:
				var nxt := _nearest_unhit(prev.pos, 130.0, hit_list)
				if nxt == null:
					break
				cdmg *= 0.85
				_add_effect({"type": "bolt", "from": prev.pos, "to": nxt.pos, "t": 0.0, "dur": 0.18, "color": Color(1, 1, 0.5)})
				_hit(nxt, cdmg, id, {"stun_chance": 0.05, "stun": 0.3} if syn.get("lightning", 0.0) > 0.0 else {}, false)
				hit_list.append(nxt)
				prev = nxt
	# 메테오
	if fx.has("meteor_every"):
		c["hits"] += 1
		if c["hits"] >= fx["meteor_every"] - (1 if awake else 0):
			c["hits"] = 0
			var p: Vector2 = target.pos
			var r: float = fx["meteor_radius"]
			_add_effect({"type": "boom", "pos": p, "r": r, "t": 0.0, "dur": 0.5, "color": Color(1, 0.5, 0.2)})
			shake = maxf(shake, 5.0)
			for e in enemies:
				if e.alive and e.pos.distance_to(p) <= r:
					_damage(e, base * fx["meteor_mult"], id, true)
	# 도적/황금왕 골드 강탈
	if fx.has("gold_chance") and rng.randf() < fx["gold_chance"]:
		gold += fx["gold"]
		if rng.randf() < 0.3:
			float_text(target.pos + Vector2(0, -14), "+%dG" % fx["gold"], Color(1, 0.9, 0.3), 12)


func _hit(t: EnemyState, dmg: float, id: String, fx: Dictionary, crit: bool) -> void:
	if not t.alive:
		return
	var splash: float = fx.get("splash", 0.0)
	var victims: Array = [t]
	if splash > 0.0:
		for e in enemies:
			if e.alive and e != t and e.pos.distance_squared_to(t.pos) <= splash * splash:
				victims.append(e)
		_add_effect({"type": "boom", "pos": t.pos, "r": splash, "t": 0.0, "dur": 0.25, "color": GameData.UNITS[id]["color"] if id != "" else Color.WHITE})
	for v in victims:
		if fx.has("armor_break"):
			v.armor_break = minf(v.armor_break + fx["armor_break"], 60.0)
		if fx.has("slow"):
			v.slow = maxf(v.slow, fx["slow"])
			v.slow_t = maxf(v.slow_t, fx["slow_time"])
		if fx.has("burn"):
			v.burn_dps = maxf(v.burn_dps, dmg * fx["burn"])
			v.burn_t = fx["burn_time"]
		if fx.has("poison"):
			v.poison_dps = maxf(v.poison_dps, dmg * fx["poison"])
			v.poison_t = fx["poison_time"]
		_damage(v, dmg, id, v == t and (crit or dmg >= 150.0))
	if fx.has("stun_chance") and t.alive and rng.randf() < fx["stun_chance"]:
		t.stun_t = maxf(t.stun_t, fx["stun"] * (0.4 if t.is_boss else 1.0))
	# 빙결: 짧게 완전히 멈춤 (보스는 짧게)
	if fx.get("freeze_chance", 0.0) > 0.0 and t.alive and rng.randf() < fx["freeze_chance"]:
		var ft := 0.4 if t.is_boss else 1.1
		t.stun_t = maxf(t.stun_t, ft)
		t.freeze_t = ft
	# 넉백: 적을 트랙 뒤로 밀어냄 (보스는 25%)
	if fx.has("knockback") and t.alive:
		var kb: float = fx["knockback"] * (0.25 if t.is_boss else 1.0)
		t.dist = maxf(0.0, t.dist - kb)
		t.pos = path_pos(t.dist)
	if fx.has("execute") and t.alive and not t.is_boss and not t.kind in ["elite", "midboss", "hero"] and t.hp_ratio() <= fx["execute"]:
		float_text(t.pos + Vector2(0, -16), "처형!", Color(0.8, 0.4, 1.0), 14)
		_damage(t, t.hp + t.shield + 1.0, id, false, true)
	if crit:
		float_text(t.pos + Vector2(rng.randf_range(-8, 8), -18), str(int(dmg)), Color(1, 0.35, 0.3), 16)
		_sparks(t.pos, Color(1, 0.8, 0.3), 6)


func _nearest_unhit(p: Vector2, r: float, hit_list: Array) -> EnemyState:
	var best: EnemyState = null
	var bd := r * r
	for e in enemies:
		if e.alive and not hit_list.has(e):
			var d := e.pos.distance_squared_to(p)
			if d <= bd:
				bd = d
				best = e
	return best


func _damage(e: EnemyState, amount: float, src: String, _show: bool, true_dmg := false) -> void:
	if not e.alive or amount <= 0.0:
		return
	var dmg := amount
	if not true_dmg:
		dmg *= 1.0 - e.effective_armor() / 100.0
	if e.shield_t > 0.0:
		dmg *= 0.2
	if src != "":
		dmg_by_unit[src] = dmg_by_unit.get(src, 0.0) + minf(dmg, e.hp + e.shield)
	if e.shield > 0.0:
		var absorbed := minf(e.shield, dmg)
		e.shield -= absorbed
		dmg -= absorbed
	e.hp -= dmg
	e.flash = 0.08
	if e.hp <= 0.0:
		_kill(e)


func _kill(e: EnemyState) -> void:
	e.alive = false
	kills += 1
	# 콤보: 짧은 시간 안에 연속 처치
	combo += 1
	_combo_t = GameData.COMBO_WINDOW
	combo_pop = 1.0
	best_combo = maxi(best_combo, combo)
	if combo % GameData.FEVER_EVERY == 0:
		fever_t = GameData.FEVER_TIME
		show_banner("FEVER!!", "%d 콤보! 8초 동안 공격속도 +30%%, 골드 +50%%" % combo, Color(1, 0.6, 0.2))
		_flash(Color(1, 0.7, 0.2), 0.3)
		_sfx("fever")
	if combo % GameData.COMBO_STEP == 0:
		var cb := 5 + combo / 4 + wave
		gold += cb
		float_text(Vector2(SIZE - 110, 150), "+%dG" % cb, Color(1, 0.6, 0.2), 20)
		_sfx("merge")
	# 잭팟 처치
	if not e.is_boss and e.weight > 0 and rng.randf() < GameData.JACKPOT_CHANCE:
		var jg := 50 + wave * 10
		gold += jg
		show_banner("JACKPOT!", "+%d 골드" % jg, Color(1, 0.85, 0.2))
		_coin_burst(e.pos, 14)
		_flash(Color(1, 0.85, 0.3), 0.35)
		_sfx("reward")
	gauge = mini(gauge + 1, GameData.COOP_BLAST_NEED)
	var g := 1 + wave / 10
	match e.kind:
		"boss":
			bosses_killed += 1
			_coin_burst(e.pos, 22)
			boss_kill_times[wave] = snappedf(boss_time_at(wave) + bonus_boss_time - wave_timer, 0.1)
			g = 100 + wave * 10
			var gm := 3 + wave / 10
			slowmo_t = 0.35
			if wave_timer <= GameData.CLUTCH_TIME:
				gm += GameData.CLUTCH_GEMS
				float_text(e.pos + Vector2(0, -80), "간발의 차!! +%d 보석" % GameData.CLUTCH_GEMS, Color(1, 0.95, 0.4), 26)
			gems += gm
			show_banner("보스 처치!", "+%d 골드  +%d 보석" % [g, gm], Color(1, 0.85, 0.3))
			_sfx("boom")
			_sfx("legend")
			_flash(Color(1, 0.9, 0.5), 0.5)
			shake = 14.0
			if wave >= final_wave and mode != "pvp" and not final_cleared_flag:
				final_cleared_flag = true
				final_cleared.emit(self)
		"elite":
			# 상대가 보낸 정예는 골드 조금만 (보석 없음)
			g = 20 if e.sent else 40
			if not e.sent:
				gems += 1
		"midboss":
			g = 50 + wave * 4
			gems += 2
			_coin_burst(e.pos, 16)
			show_banner("중간보스 처치!", "+%d 골드  +2 보석" % g, Color(0.85, 0.55, 1.0))
			_sfx("boom")
			_sfx("reward")
			shake = 8.0
		"hero":
			g = 30 + wave * 2
			gems += 1
			_coin_burst(e.pos, 10)
			show_banner("적 영웅 처치!", "%s  +%d 골드  +1 보석" % [e.boss_name, g], Color(1, 0.6, 0.35))
			_sfx("rare")
		"goblin":
			g = 80 + wave * 5
			gems += 2
			show_banner("고블린 사냥 성공!", "+%d 골드  +2 보석" % g, Color(1, 0.9, 0.2))
			_sfx("rare")
		"bonus":
			g = 8 + wave
			float_text(e.pos + Vector2(0, -16), "+%dG" % g, Color(1, 0.9, 0.3), 15)
			bonus_left -= 1
			if bonus_left <= 0:
				gems += 1
				show_banner("퍼펙트 보너스!", "돼지 전부 처치 +1 보석", Color(1, 0.8, 0.85))
				_sfx("rare")
	if fever_t > 0.0:
		g = int(ceil(g * 1.5))
	if "rich" in stage_mods:
		g = int(ceil(g * 1.5))
	elif "poor" in stage_mods:
		g = maxi(1, int(g * 0.7))
	gold += g
	for n in e.split:
		var m := _spawn("mini", e.max_hp / GameData.ENEMIES["splitter"]["hp"], e.dist - 10.0 * n)
		m.pos = path_pos(m.dist)
	_add_effect({"type": "pop", "pos": e.pos, "r": e.size * 1.8, "t": 0.0, "dur": 0.25, "color": e.color})
	if rng.randf() < CHEST_CHANCE * (1.0 + bonus_chest) and chests.size() < 3:
		chests.append({"pos": e.pos, "t": 8.0})


func _cast_skill(i: int, c: Dictionary, u: Dictionary) -> void:
	var center := cell_center(i)
	var n: int = c["n"]
	var base: float = u["dmg"] * unit_power(c["id"])
	var sid: String = u["skill"]["id"]
	float_text(center + Vector2(0, -30), u["skill"]["name"] + "!", u["color"], 18)
	_sfx({"judgement": "zap", "timestop": "ice", "goldrain": "reward", "breath": "ice", "blackhole": "zap", "arrowrain": "hit", "bless": "rare"}.get(sid, "boom"))
	match sid:
		"firestorm":
			_add_effect({"type": "boom", "pos": center, "r": u["range"], "t": 0.0, "dur": 0.7, "color": Color(1, 0.4, 0.1)})
			_add_effect({"type": "firestorm", "pos": center, "r": u["range"], "t": 0.0, "dur": 1.0, "color": Color(1, 0.45, 0.1), "seed": rng.randf() * 100.0})
			_flash(Color(1, 0.45, 0.1), 0.25)
			for e in enemies:
				if e.alive and e.pos.distance_to(center) <= u["range"]:
					e.burn_dps = maxf(e.burn_dps, base)
					e.burn_t = 4.0
					_damage(e, base * 4.0 * n, c["id"], true)
			shake = 10.0
		"judgement":
			_flash(Color(1, 1, 0.6), 0.35)
			for e in enemies:
				if e.alive:
					_add_effect({"type": "strike", "pos": e.pos, "t": 0.0, "dur": 0.4, "color": Color(1, 1, 0.5), "seed": rng.randf() * TAU})
					e.stun_t = maxf(e.stun_t, 0.25 if e.is_boss else 0.5)
					_damage(e, base * 2.0 * n, c["id"], false)
			shake = 8.0
		"timestop":
			_flash(Color(0.4, 0.9, 1.0), 0.6)
			_add_effect({"type": "timestop", "pos": Vector2(SIZE / 2, SIZE / 2), "t": 0.0, "dur": 2.5, "color": Color(0.5, 0.85, 1.0)})
			for e in enemies:
				if e.alive:
					e.stun_t = maxf(e.stun_t, 1.2 if e.is_boss else 2.5)
		"goldrain":
			# 황금비: 라운드에 비례한 골드 + 3번에 한 번 보석, 사거리 안 적에게 보유 골드 비례 금화 폭격
			var g := (30 + wave * 6) * n
			gold += g
			c["casts"] = int(c.get("casts", 0)) + 1
			var gem_txt := ""
			if c["casts"] % 3 == 0:
				gems += 1
				gem_txt = " +1보석"
			var mult := clampf(1.0 + gold / 400.0, 1.0, 6.0)
			for e in enemies:
				if e.alive and e.pos.distance_to(center) <= u["range"]:
					_add_effect({"type": "atk", "style": "coin", "from": center, "to": e.pos, "t": 0.0, "dur": 0.4, "color": Color(1, 0.85, 0.2), "big": true, "seed": rng.randf() * TAU})
					_damage(e, base * mult * n, c["id"], true)
			float_text(center, "황금비 +%dG%s" % [g, gem_txt], Color(1, 0.9, 0.2), 20)
			_add_effect({"type": "ring", "pos": center, "r0": 10.0, "r1": 200.0, "t": 0.0, "dur": 0.7, "color": Color(1, 0.85, 0.2)})
			_add_effect({"type": "goldrain", "pos": Vector2.ZERO, "t": 0.0, "dur": 1.4, "color": Color(1, 0.85, 0.2), "seed": rng.randf() * 100.0})
			_coin_burst(center, 12)
		"reap":
			var list: Array = []
			for e in enemies:
				if e.alive:
					list.append(e)
			list.sort_custom(func(a, b): return a.hp > b.hp)
			var reaped := 0
			for e in list:
				if reaped >= 1 + n:
					break
				_add_effect({"type": "pop", "pos": e.pos, "r": 30.0, "t": 0.0, "dur": 0.5, "color": Color(0.6, 0.2, 0.8)})
				_add_effect({"type": "atk", "style": "scythe", "from": center, "to": e.pos, "t": 0.0, "dur": 0.45, "color": Color(0.75, 0.3, 1.0), "big": true, "seed": rng.randf() * TAU})
				if e.is_boss or e.kind in ["elite", "midboss", "hero"]:
					_damage(e, base * 5.0, c["id"], true)
				else:
					_damage(e, e.hp + e.shield + 1.0, c["id"], false, true)
				reaped += 1
		"quake":
			# 대지 강타: 주변 적 큰 피해 + 기절
			var qr: float = u["range"] * 1.3
			_add_effect({"type": "quake", "pos": center, "r": qr, "t": 0.0, "dur": 0.8, "color": Color(0.85, 0.6, 0.35), "seed": rng.randf() * TAU})
			for e in enemies:
				if e.alive and e.pos.distance_to(center) <= qr:
					e.stun_t = maxf(e.stun_t, 0.5 if e.is_boss else 1.5)
					_damage(e, base * 4.0 * n, c["id"], false)
			shake = 14.0
		"bless":
			# 신성 축복: 모든 수호병 공속 +35%, 모든 적 방어 -25 + 신성 피해
			bless_t = maxf(bless_t, 4.0 + 2.0 * n)
			for k in cells.size():
				if cells[k]["id"] != "":
					_add_effect({"type": "bless", "pos": cell_center(k), "t": 0.0, "dur": 1.0, "color": Color(1, 0.92, 0.55)})
			for e in enemies:
				if e.alive:
					e.armor_break = minf(e.armor_break + 25.0, 60.0)
					_add_effect({"type": "pillar", "pos": e.pos, "t": 0.0, "dur": 0.6, "color": Color(1, 0.95, 0.65)})
					_damage(e, base * 1.5 * n, c["id"], false)
			_flash(Color(1, 0.95, 0.7), 0.25)
		"plague":
			# 역병 확산: 모든 적 맹독 6초 + 방어 감소
			for e in enemies:
				if e.alive:
					e.poison_dps = maxf(e.poison_dps, base * 1.2 * n)
					e.poison_t = maxf(e.poison_t, 6.0)
					e.armor_break = minf(e.armor_break + 20.0, 60.0)
					_add_effect({"type": "miasma", "pos": e.pos, "t": 0.0, "dur": 1.2, "color": Color(0.5, 0.95, 0.3), "seed": rng.randf() * TAU})
			_flash(Color(0.4, 0.9, 0.3), 0.2)
		"arrowrain":
			# 화살비: 무작위 적에게 화살 8+4n 발
			var alive_list: Array = []
			for e in enemies:
				if e.alive:
					alive_list.append(e)
			for k in 8 + 4 * n:
				if alive_list.is_empty():
					break
				var t: EnemyState = alive_list[rng.randi() % alive_list.size()]
				_add_effect({"type": "rainarrow", "pos": t.pos, "t": -k * 0.04, "dur": 0.35, "color": Color(0.7, 1.0, 0.85)})
				_damage(t, base * 3.0, c["id"], false)
				if not t.alive:
					alive_list.erase(t)
		"breath":
			# 빙결 숨결: 적이 가장 많은 변 전체를 얼리고 피해
			var side_n := [0, 0, 0, 0]
			for e in enemies:
				if e.alive:
					side_n[int(fposmod(e.dist, LOOP) / SIDE) % 4] += 1
			var side := 0
			for k in 4:
				if side_n[k] > side_n[side]:
					side = k
			var a := path_pos(side * SIDE + 1.0)
			var b := path_pos(side * SIDE + SIDE - 1.0)
			_add_effect({"type": "breath", "from": center, "a": a, "b": b, "t": 0.0, "dur": 0.9, "color": Color(0.7, 0.95, 1.0)})
			for e in enemies:
				if e.alive and int(fposmod(e.dist, LOOP) / SIDE) % 4 == side:
					var ft := 0.6 if e.is_boss else 2.0
					e.stun_t = maxf(e.stun_t, ft)
					e.freeze_t = maxf(e.freeze_t, ft)
					_damage(e, base * 3.0 * n, c["id"], false)
			_flash(Color(0.6, 0.9, 1.0), 0.2)
		"blackhole":
			# 블랙홀: 적이 가장 몰린 곳으로 주변 적을 끌어모아 기절 + 폭발
			var core: EnemyState = null
			var core_n := -1
			for e in enemies:
				if not e.alive:
					continue
				var cnt := 0
				for o in enemies:
					if o.alive and absf(o.dist - e.dist) < 220.0:
						cnt += 1
				if cnt > core_n:
					core_n = cnt
					core = e
			if core == null:
				return
			var cp := core.pos
			_add_effect({"type": "vortex", "pos": cp, "r": 110.0, "t": 0.0, "dur": 1.1, "color": Color(0.6, 0.35, 1.0)})
			for e in enemies:
				if e.alive and absf(e.dist - core.dist) < 220.0:
					if not e.is_boss:
						e.dist = lerpf(e.dist, core.dist, 0.8)
						e.pos = path_pos(e.dist)
					e.stun_t = maxf(e.stun_t, 0.4 if e.is_boss else 1.2)
					_damage(e, base * 3.0 * n, c["id"], false)
			shake = 10.0


func _update_chests(dt: float) -> void:
	for i in range(chests.size() - 1, -1, -1):
		chests[i]["t"] -= dt
		if chests[i]["t"] <= 0.0:
			chests.remove_at(i)


func _cleanup() -> void:
	var i := 0
	while i < enemies.size():
		if not enemies[i].alive:
			enemies.remove_at(i)
		else:
			i += 1


# ===========================================================================
# 도전 과제
# ===========================================================================
func _check_missions_now() -> void:
	if is_remote:
		return
	var best := -1
	for c in cells:
		if c["id"] != "":
			best = maxi(best, GameData.UNITS[c["id"]]["rarity"])
	if best >= 2:
		_complete_mission("first_epic")
	if best >= 3:
		_complete_mission("first_legend")
	if kills >= 500:
		_complete_mission("kill_500")
	if used_cells() >= 24:
		_complete_mission("full_board")


func _complete_mission(mid: String) -> void:
	if missions.has(mid):
		return
	missions[mid] = true
	for m in GameData.MISSIONS:
		if m["id"] == mid:
			gold += m["gold"]
			gems += m["gems"]
			var reward := []
			if m["gold"] > 0:
				reward.append("+%dG" % m["gold"])
			if m["gems"] > 0:
				reward.append("+%d보석" % m["gems"])
			float_text(Vector2(SIZE / 2, 120), "과제 달성: %s %s" % [m["name"], " ".join(reward)], Color(0.5, 1.0, 0.7), 16)


# ===========================================================================
# 네트워크 스냅샷
# ===========================================================================
func snapshot() -> Dictionary:
	var c := PackedInt32Array()
	for cell in cells:
		if cell["id"] == "":
			c.append(-1)
		else:
			c.append(GameData.unit_index(cell["id"]) * 32 + cell["star"] * 4 + cell["n"])
	# 적 1마리 = int32 2개 (위치 / 종류+체력+상태) 로 압축
	var e := PackedInt32Array()
	for en in enemies:
		if en.alive:
			e.append(int(en.pos.x) | (int(en.pos.y) << 16))
			e.append(GameData.enemy_index(en.kind) | (int(en.hp_ratio() * 255.0) << 8) | (en.status_flags() << 16))
	return {
		"c": c, "e": e, "g": gold, "m": gems, "w": wave, "t": wave_timer, "k": kills,
		"f": field_count(), "a": alive, "fc": final_cleared_flag, "sc": summon_cost(),
		"u": upgrades, "ga": gauge, "bf": boss_failed,
	}


func apply_snapshot(d: Dictionary) -> void:
	remote_stats = d
	gold = d.get("g", 0)
	gems = d.get("m", 0)
	wave = d.get("w", 0)
	wave_timer = d.get("t", 0.0)
	kills = d.get("k", 0)
	final_cleared_flag = d.get("fc", false)
	boss_failed = d.get("bf", false)
	upgrades = d.get("u", [0, 0, 0, 0])
	gauge = d.get("ga", 0)
	var c: PackedInt32Array = d.get("c", PackedInt32Array())
	for i in mini(c.size(), cells.size()):
		if c[i] < 0:
			cells[i]["id"] = ""
			cells[i]["n"] = 0
		else:
			cells[i]["id"] = GameData.UNIT_ORDER[c[i] / 32]
			cells[i]["star"] = (c[i] / 4) % 8
			cells[i]["n"] = c[i] % 4
	var e: PackedInt32Array = d.get("e", PackedInt32Array())
	var count := e.size() / 2
	while enemies.size() > count:
		enemies.pop_back()
	while enemies.size() < count:
		enemies.append(EnemyState.new())
	for i in count:
		var en: EnemyState = enemies[i]
		var a: int = e[i * 2]
		var b: int = e[i * 2 + 1]
		var kind: String = GameData.ENEMY_ORDER[clampi(b & 0xFF, 0, GameData.ENEMY_ORDER.size() - 1)]
		if en.kind != kind or en.id != -1:
			en.setup(kind, 1.0)
			en.id = -1
		en.max_hp = 1.0
		en.pos = Vector2(a & 0xFFFF, (a >> 16) & 0xFFFF)
		en.hp = ((b >> 8) & 0xFF) / 255.0
		var f := (b >> 16) & 0xFF
		en.slow_t = 1.0 if f & 1 else 0.0
		en.stun_t = 1.0 if f & 2 else 0.0
		en.burn_t = 1.0 if f & 4 else 0.0
		en.shield = 1.0 if f & 8 else 0.0
		en.max_shield = 1.0
		en.enraged = (f & 16) != 0
		en.casting = "cast" if f & 32 else ""
		en.shield_t = 1.0 if f & 64 else 0.0
	if alive and not d.get("a", true):
		alive = false


# ===========================================================================
# 시각 효과
# ===========================================================================
func apply_loadout(item_ids: Array, perk_levels: Dictionary, p_unit_levels := {}) -> Array:
	## 상점 아이템/영구 강화/도감 유닛 레벨 적용. 적용된 아이템 목록을 돌려준다.
	var notes: Array = []
	unit_levels = p_unit_levels.duplicate()
	var pg: int = perk_levels.get("p_gold", 0)
	if pg > 0:
		gold += 15 * pg
	bonus_chest = 0.2 * int(perk_levels.get("p_chest", 0))
	bonus_gamble = 0.02 * int(perk_levels.get("p_gamble", 0))
	bonus_boss_time = 3.0 * int(perk_levels.get("p_boss", 0))
	for id in item_ids:
		match id:
			"start_gold":
				gold += 100
			"start_gems":
				gems += 3
			"summon_ticket":
				free_summons += 5
			"lucky_charm":
				upgrades[3] = mini(upgrades[3] + 1, GameData.MAX_LUCK)
		notes.append(id)
	return notes


func revive() -> void:
	## 광고/부활 깃털: 보스와 적 절반을 치우고 다시 시작
	revived += 1
	alive = true
	boss_failed = false
	var others: Array = []
	var boss_alive := false
	for e in enemies:
		if not e.alive:
			continue
		if e.is_boss:
			# 보스는 남기되 체력 30% 감소 + 제한시간 30초 추가로 재도전
			boss_alive = true
			e.hp = maxf(1.0, e.hp - e.max_hp * 0.3)
		else:
			others.append(e)
	# 가장 멀리 간 적부터 절반 제거
	others.sort_custom(func(a, b): return a.dist > b.dist)
	for k in others.size() / 2:
		others[k].alive = false
	_cleanup()
	if boss_alive:
		wave_timer = 30.0
		_last_tick = -1
	show_banner("부활!", "적 절반 제거" + (" · 보스 재도전 30초" if boss_alive else ""), Color(0.5, 1.0, 0.7))
	_flash(Color(0.6, 1.0, 0.8), 0.6)
	_sfx("rare")


# ===========================================================================
# ★ 강화 시도
# ===========================================================================
func enhance_cost_of(i: int) -> int:
	var c: Dictionary = cells[i]
	return GameData.enhance_cost(GameData.UNITS[c["id"]]["rarity"], c["star"])


func can_enhance(i: int) -> bool:
	if i < 0 or not alive or not pending_enhance.is_empty():
		return false
	var c: Dictionary = cells[i]
	return c["id"] != "" and c["star"] < GameData.STAR_MAX and gold >= enhance_cost_of(i)


func enhance_try(i: int) -> bool:
	if not can_enhance(i):
		return false
	var cost := enhance_cost_of(i)
	gold -= cost
	pending_enhance = {"cell": cells[i], "t": GameData.ENHANCE_TIME, "cost": cost}
	last_enhance = {}
	_sfx("tick")
	return true


func _update_enhance(dt: float) -> void:
	if pending_enhance.is_empty():
		return
	pending_enhance["t"] -= dt
	var c: Dictionary = pending_enhance["cell"]
	var idx := cells.find(c)
	if idx >= 0 and fmod(pending_enhance["t"], 0.2) < dt:
		_sparks(cell_center(idx), Color(1, 0.85, 0.4), 4)
		_sfx("tick")
	if pending_enhance["t"] > 0.0:
		return
	var paid: int = pending_enhance["cost"]
	pending_enhance = {}
	if idx < 0 or c["id"] == "":
		gold += paid
		return
	var star: int = c["star"]
	var p := cell_center(idx)
	var res := {"ok": false, "star": star, "down": false}
	if rng.randf() < GameData.STAR_CHANCE[star]:
		c["star"] = star + 1
		res = {"ok": true, "star": star + 1, "down": false}
		_add_effect({"type": "ring", "pos": p, "r0": 8.0, "r1": 90.0, "t": 0.0, "dur": 0.6, "color": Color(1, 0.85, 0.3)})
		_coin_burst(p, 8 + star * 4)
		float_text(p + Vector2(0, -30), "★%d 성공!" % (star + 1), Color(1, 0.85, 0.3), 20)
		float_text(p + Vector2(0, -8), "공격력 +%d%% · 공속 +%d%%" % [int(GameData.STAR_DMG * 100), int(GameData.STAR_SPEED * 100)], Color(0.6, 1.0, 0.6), 13)
		_add_effect({"type": "up", "pos": p, "t": 0.0, "dur": 0.9, "color": Color(1, 0.85, 0.3)})
		max_star = maxi(max_star, star + 1)
		if star + 1 == GameData.TRANSCEND_STAR:
			show_banner("초월!", "%s ★5 - 두 번 공격" % GameData.UNITS[c["id"]]["name"], Color(1, 0.4, 0.9))
			_coin_burst(p, 30, Color(1, 0.5, 1.0))
		if star + 1 == GameData.AWAKEN_STAR:
			show_banner("각성!", "%s 특성 강화" % GameData.UNITS[c["id"]]["name"], Color(1, 0.7, 0.3))
			_flash(Color(1, 0.8, 0.4), 0.4)
		_sfx("legend" if star + 1 >= 3 else "reward")
	else:
		if rng.randf() < GameData.STAR_DOWN_CHANCE[star]:
			c["star"] = star - 1
			res = {"ok": false, "star": star - 1, "down": true}
			float_text(p + Vector2(0, -30), "하락... ★%d" % (star - 1), Color(1, 0.35, 0.35), 20)
			shake = 10.0
		else:
			float_text(p + Vector2(0, -30), "실패", Color(0.7, 0.7, 0.75), 20)
			shake = 5.0
		_add_effect({"type": "pop", "pos": p, "r": 30.0, "t": 0.0, "dur": 0.5, "color": Color(0.5, 0.5, 0.55)})
		_sfx("fail")
	last_enhance = res


# ===========================================================================
# 보스 스킬
# ===========================================================================
func _endless_boss(w: int) -> int:
	## 무한/대전 보스 번호 (Story.BOSS_CHARS 순서): 10·20·30 = 0·1·2, 40(최종) = 4, 연장전 50·60… = 5,6,7,8,3 순환
	var n := w / 10
	if n <= 3 and w != final_wave:
		return clampi(n - 1, 0, 2)
	if w == GameData.FINAL_WAVE or w == final_wave:
		return 4
	return [5, 6, 7, 8, 3][(n - 5) % 5] if n >= 5 else 3


func _setup_boss_skills(b: EnemyState, w: int) -> void:
	## 보스마다 고유한 기술 조합 (GameData.BOSS_SKILLS, Story.BOSS_CHARS 순서)
	var set_i := stage_boss if stage_boss >= 0 else _endless_boss(w)
	set_i = clampi(set_i, 0, GameData.BOSS_SKILLS.size() - 1)
	var list: Array = GameData.BOSS_SKILLS[set_i].duplicate(true)
	b.skills = list
	b.skill_cd = []
	for k in list.size():
		b.skill_cd.append(4.0 + k * 2.5)


func _update_boss(e: EnemyState, dt: float) -> void:
	e.shield_t = maxf(0.0, e.shield_t - dt)
	# 최종 보스 2페이즈
	if e.boss_name.begins_with("최종") and not e.phase2 and e.hp_ratio() < 0.5:
		e.phase2 = true
		e.speed *= 1.35
		for k in e.skill_cd.size():
			e.skill_cd[k] = minf(e.skill_cd[k], 1.5)
		for s2 in e.skills:
			s2[1] *= 0.7
		show_banner("2페이즈!", "%s 광폭화!" % e.boss_name.trim_prefix("최종 보스 · "), Color(1, 0.2, 0.3))
		_flash(Color(1, 0.1, 0.2), 0.5)
		_boss_skill(e, "summon")
		shake = 14.0
	if e.casting != "":
		if e.stun_t > 0.0:
			# 시전 중 기절 → 스킬 차단
			float_text(e.pos + Vector2(0, -40), "시전 차단!", Color(0.5, 1.0, 0.6), 18)
			interrupts += 1
			_sparks(e.pos, Color(0.5, 1, 0.6), 10)
			e.casting = ""
			_sfx("merge")
			return
		e.cast_t -= dt
		if e.cast_t <= 0.0:
			var sid := e.casting
			e.casting = ""
			_boss_skill(e, sid)
		return
	if e.stun_t > 0.0:
		return
	for k in e.skills.size():
		e.skill_cd[k] -= dt
		if e.skill_cd[k] <= 0.0:
			e.skill_cd[k] = e.skills[k][1] * rng.randf_range(0.9, 1.1)
			e.casting = e.skills[k][0]
			e.cast_t = GameData.BOSS_CAST_TIME
			float_text(e.pos + Vector2(0, -44), GameData.BOSS_SKILL_NAMES[e.casting] + "!", Color(1, 0.4, 0.4), 18)
			_sfx("alarm")
			return


func _boss_skill(e: EnemyState, sid: String) -> void:
	_sfx("boom")
	match sid:
		"dash":
			e.buff_t = 2.0
			_add_effect({"type": "ring", "pos": e.pos, "r0": 10.0, "r1": 70.0, "t": 0.0, "dur": 0.4, "color": Color(1, 0.5, 0.2)})
			_boss_callout(e, "돌진!", Color(1, 0.55, 0.2))
		"roar":
			var hit := 0
			for k in cells.size():
				if cells[k]["id"] != "" and cell_center(k).distance_to(e.pos) < 220.0:
					cells[k]["silence"] = 2.5
					hit += 1
			_add_effect({"type": "ring", "pos": e.pos, "r0": 20.0, "r1": 220.0, "t": 0.0, "dur": 0.6, "color": Color(0.7, 0.3, 1.0)})
			_add_effect({"type": "ring", "pos": e.pos, "r0": 10.0, "r1": 160.0, "t": 0.0, "dur": 0.45, "color": Color(1, 0.3, 0.4)})
			_boss_callout(e, "포효!", Color(0.8, 0.45, 1.0))
			shake = 10.0
			if hit > 0:
				float_text(e.pos + Vector2(0, -60), "유닛 %d칸 침묵!" % hit, Color(0.8, 0.5, 1.0), 16)
		"summon":
			var n := 8 if e.phase2 else 5
			for k in n:
				var m := _spawn("normal", hp_at(maxi(wave, 1)) * 0.7, e.dist - 18.0 * (k + 1))
				m.color = Color(0.75, 0.75, 0.8)
			_add_effect({"type": "boom", "pos": e.pos, "r": 60.0, "t": 0.0, "dur": 0.5, "color": Color(0.6, 0.6, 0.7)})
			_add_effect({"type": "portal", "pos": e.pos, "t": 0.0, "dur": 0.9, "color": Color(0.55, 0.3, 0.9)})
			_boss_callout(e, "부하 소환!", Color(0.7, 0.7, 0.8))
		"regen":
			e.hp = minf(e.max_hp, e.hp + e.max_hp * 0.1)
			float_text(e.pos + Vector2(0, -60), "재생 +10%", Color(0.4, 1.0, 0.5), 16)
			_add_effect({"type": "ring", "pos": e.pos, "r0": 40.0, "r1": 10.0, "t": 0.0, "dur": 0.6, "color": Color(0.4, 1, 0.5)})
			_add_effect({"type": "heal", "pos": e.pos, "t": 0.0, "dur": 0.9, "color": Color(0.4, 1, 0.5)})
		"shield":
			e.shield_t = 3.5
			_boss_callout(e, "용암 방패!", Color(1, 0.6, 0.15))
		"blast":
			var occupied: Array = []
			for k in cells.size():
				if cells[k]["id"] != "":
					occupied.append(k)
			occupied.shuffle()
			for k in occupied.slice(0, 3):
				cells[k]["silence"] = 3.0
				_add_effect({"type": "boom", "pos": cell_center(k), "r": 40.0, "t": 0.0, "dur": 0.6, "color": Color(1, 0.4, 0.1)})
				_add_effect({"type": "pierce", "from": e.pos, "to": cell_center(k), "t": 0.0, "dur": 0.35, "color": Color(1, 0.5, 0.1)})
			_boss_callout(e, "화염 폭발!", Color(1, 0.45, 0.15))
			shake = 12.0
		"blink":
			_add_effect({"type": "pop", "pos": e.pos, "r": 30.0, "t": 0.0, "dur": 0.5, "color": Color(0.6, 0.3, 1.0)})
			var from_pos := e.pos
			e.dist += 220.0
			e.pos = path_pos(e.dist)
			_add_effect({"type": "pop", "pos": e.pos, "r": 30.0, "t": 0.0, "dur": 0.5, "color": Color(0.6, 0.3, 1.0)})
			_add_effect({"type": "portal", "pos": from_pos, "t": 0.0, "dur": 0.6, "color": Color(0.6, 0.3, 1.0)})
			_add_effect({"type": "portal", "pos": e.pos, "t": 0.0, "dur": 0.6, "color": Color(0.6, 0.3, 1.0)})
			_boss_callout(e, "순간이동!", Color(0.7, 0.45, 1.0))
		"frostbite":
			# 서리 감옥: 유닛이 가장 많은 가로줄 또는 세로줄 전체를 얼려 침묵
			var line := _busiest_line()
			var hit := 0
			for k in line:
				if cells[k]["id"] != "":
					cells[k]["silence"] = maxf(cells[k]["silence"], 3.0)
					hit += 1
				_add_effect({"type": "icecell", "pos": cell_center(k), "t": 0.0, "dur": 3.0, "color": Color(0.7, 0.95, 1.0)})
			if not line.is_empty():
				_add_effect({"type": "pierce", "from": cell_center(line[0]), "to": cell_center(line[line.size() - 1]), "t": 0.0, "dur": 0.5, "color": Color(0.8, 1, 1)})
			_flash(Color(0.6, 0.9, 1.0), 0.3)
			_boss_callout(e, "서리 감옥!", Color(0.6, 0.9, 1.0))
			if hit > 0:
				float_text(e.pos + Vector2(0, -80), "한 줄 %d칸 빙결!" % hit, Color(0.7, 0.95, 1.0), 16)
			shake = 8.0
		"sandstorm":
			# 모래 폭풍: 6초 동안 수호병 사거리 -25%
			sand_t = 6.0
			_add_effect({"type": "sand", "pos": Vector2.ZERO, "t": 0.0, "dur": 6.0, "color": Color(0.95, 0.78, 0.45), "seed": rng.randf() * 100.0})
			_boss_callout(e, "모래 폭풍!", Color(1, 0.8, 0.45))
			float_text(e.pos + Vector2(0, -80), "6초간 사거리 -25%", Color(1, 0.85, 0.55), 16)
		"sanctuary":
			# 빛의 성역: 모든 적에게 체력 25% 보호막, 보스는 체력 4% 회복
			for o in enemies:
				if not o.alive:
					continue
				if o.is_boss:
					o.hp = minf(o.max_hp, o.hp + o.max_hp * 0.04)
				else:
					o.shield = maxf(o.shield, o.max_hp * 0.25)
					o.max_shield = maxf(o.max_shield, o.shield)
				_add_effect({"type": "pillar", "pos": o.pos, "t": 0.0, "dur": 0.8, "color": Color(1, 0.95, 0.6)})
			_flash(Color(1, 0.95, 0.7), 0.3)
			_boss_callout(e, "빛의 성역!", Color(1, 0.95, 0.6))
		"shadow":
			# 그림자 분신: 보스 체력 18% 의 분신 (지배 불가). 이미 있으면 보스가 잠시 돌진
			var has_clone := false
			for o in enemies:
				if o.alive and o.boss_name == "그림자 분신":
					has_clone = true
			if has_clone:
				e.buff_t = 1.5
				_boss_callout(e, "돌진!", Color(0.6, 0.5, 0.85))
				return
			var cl := _spawn("elite", 1.0, e.dist - 70.0)
			cl.max_hp = e.max_hp * 0.18
			cl.hp = cl.max_hp
			cl.armor = e.armor
			cl.speed = e.speed * 1.2
			cl.size = e.size * 0.75
			cl.color = Color(0.35, 0.28, 0.55)
			cl.art = e.art
			cl.boss_name = "그림자 분신"
			cl.no_mc = true
			cl.sent = true   # 처치 보상은 보낸 정예처럼 작게 (보석 없음)
			cl.pos = path_pos(cl.dist)
			_add_effect({"type": "portal", "pos": cl.pos, "t": 0.0, "dur": 0.9, "color": Color(0.4, 0.3, 0.7)})
			_add_effect({"type": "pierce", "from": e.pos, "to": cl.pos, "t": 0.0, "dur": 0.4, "color": Color(0.5, 0.4, 0.8)})
			_boss_callout(e, "그림자 분신!", Color(0.65, 0.55, 0.95))
		"rift":
			# 공허 균열: 가장 강한 수호병 4칸을 2.5초 침묵
			var best: Array = []
			for k in cells.size():
				if cells[k]["id"] != "":
					best.append(k)
			best.sort_custom(func(a, b): return GameData.UNITS[cells[a]["id"]]["rarity"] > GameData.UNITS[cells[b]["id"]]["rarity"])
			for k in best.slice(0, 4):
				cells[k]["silence"] = maxf(cells[k]["silence"], 2.5)
				_add_effect({"type": "rift", "from": e.pos, "to": cell_center(k), "t": 0.0, "dur": 0.7, "color": Color(0.55, 0.2, 0.85), "seed": rng.randf() * TAU})
				_add_effect({"type": "boom", "pos": cell_center(k), "r": 34.0, "t": 0.0, "dur": 0.5, "color": Color(0.4, 0.1, 0.6)})
			_flash(Color(0.3, 0.05, 0.45), 0.35)
			_boss_callout(e, "공허 균열!", Color(0.75, 0.45, 1.0))
			shake = 12.0


func _busiest_line() -> Array:
	## 유닛이 가장 많은 가로줄/세로줄의 칸 번호 목록
	var best: Array = []
	var best_n := -1
	for k in ROWS + COLS:
		var line: Array = []
		for j in COLS:
			line.append(k * COLS + j if k < ROWS else j * COLS + (k - ROWS))
		var n := 0
		for idx in line:
			if cells[idx]["id"] != "":
				n += 1
		if n > best_n:
			best_n = n
			best = line
	return best


func _boss_callout(e: EnemyState, text: String, col: Color) -> void:
	## 보스가 기술을 쓸 때 이름을 크게 외친다 (무슨 일이 일어났는지 바로 알 수 있게)
	var p := e.pos + Vector2(0, -56)
	p.y = maxf(p.y, 24.0)
	float_text(p, text, col, 22)


# ===========================================================================
# 럭키 슬롯
# ===========================================================================
func slot_bet(i: int) -> int:
	return GameData.SLOT_BETS[i] + (GameData.SLOT_BETS[i] * wave) / 20


func slot_spin(i: int) -> bool:
	if not alive or not pending_slot.is_empty():
		return false
	if "no_gamble" in stage_mods:
		float_text(Vector2(SIZE / 2, 150), "운 봉인! 슬롯 불가", Color(1, 0.4, 0.4))
		return false
	var bet := slot_bet(i)
	if gold < bet:
		float_text(Vector2(SIZE / 2, 150), "골드 부족!", Color(1, 0.4, 0.4))
		return false
	gold -= bet
	slot_spins += 1
	var reels: Array = []
	for r in 3:
		reels.append(_roll_symbol())
	# 가끔 "아깝다" 연출: 두 개가 같으면 세 번째가 한 칸 옆에 멈춘 것처럼 보이게 (결과는 그대로)
	pending_slot = {"reels": reels, "bet": bet, "big": i == 1, "t": GameData.SLOT_SPIN_TIME}
	last_slot = {}
	_sfx("summon")
	return true


func _roll_symbol() -> String:
	var total := 0
	for w in GameData.SLOT_WEIGHTS:
		total += w
	var r := rng.randi() % total
	for k in GameData.SLOT_SYMBOLS.size():
		r -= GameData.SLOT_WEIGHTS[k]
		if r < 0:
			return GameData.SLOT_SYMBOLS[k]
	return "skull"


func _update_slot(dt: float) -> void:
	if pending_slot.is_empty():
		return
	pending_slot["t"] -= dt
	if pending_slot["t"] > 0.0:
		return
	var reels: Array = pending_slot["reels"]
	var bet: int = pending_slot["bet"]
	var big: bool = pending_slot["big"]
	pending_slot = {}
	var result := {"reels": reels, "text": "꽝", "win": 0}
	var center := Vector2(SIZE / 2, SIZE / 2 - 40)
	if reels[0] == reels[1] and reels[1] == reels[2]:
		match reels[0]:
			"gold":
				gold += bet * 8
				result["text"] = "JACKPOT +%dG" % (bet * 8)
				show_banner("JACKPOT!!", "+%d 골드" % (bet * 8), Color(1, 0.85, 0.2))
				_coin_burst(center, 30)
			"gem":
				var gm := 6 if big else 2
				gems += gm
				result["text"] = "보석 +%d" % gm
				show_banner("보석 잭팟!", "+%d 보석" % gm, Color(0.5, 0.85, 1.0))
				_coin_burst(center, 20, Color(0.5, 0.85, 1.0))
			"summon":
				var fs := 10 if big else 3
				free_summons += fs
				result["text"] = "무료 소환 +%d" % fs
				show_banner("소환 잭팟!", "무료 소환 +%d" % fs, Color(0.5, 1.0, 0.6))
			"star":
				var r := GameData.Rarity.LEGEND if big and rng.randf() < 0.5 else GameData.Rarity.EPIC
				var id := GameData.random_unit_of(rng, r)
				var idx := add_unit(id)
				_count_legend(id, "slot")
				if idx >= 0:
					_rare_pull_fx(idx, r)
					result["text"] = "%s 획득!" % GameData.UNITS[id]["name"]
				else:
					gems += 3
					result["text"] = "보석 +3"
			"skull":
				result["text"] = "꽝꽝꽝..."
				shake = 8.0
		result["win"] = 2 if reels[0] != "skull" else 0
		if reels[0] != "skull":
			slot_jackpots += 1
		if reels[0] != "skull":
			_flash(Color(1, 0.9, 0.4), 0.4)
		_sfx("legend" if reels[0] != "skull" else "fail")
	elif (reels[0] == reels[1] or reels[1] == reels[2] or reels[0] == reels[2]):
		var pair: String = reels[1] if (reels[1] == reels[0] or reels[1] == reels[2]) else reels[0]
		if pair != "skull":
			var back := int(bet * 1.5)
			gold += back
			result["text"] = "아깝다! +%dG" % back
			result["win"] = 1
			_sfx("merge")
		else:
			result["text"] = "해골 둘... 꽝"
			_sfx("fail")
	else:
		_sfx("fail")
	last_slot = result
	float_text(center, result["text"], Color(1, 0.85, 0.3) if result["win"] > 0 else Color(0.7, 0.7, 0.75), 22 if result["win"] > 1 else 18)


# ===========================================================================
# 파티클
# ===========================================================================
func _coin_burst(p: Vector2, n: int, col := Color(1, 0.85, 0.25)) -> void:
	for k in n:
		var v := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(80, 260) + Vector2(0, -120)
		_add_effect({"type": "coin", "pos": p, "vel": v, "t": 0.0, "dur": rng.randf_range(0.6, 1.0), "color": col})


func _sparks(p: Vector2, col: Color, n: int) -> void:
	for k in n:
		var v := Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(60, 160)
		_add_effect({"type": "spark", "pos": p, "vel": v, "t": 0.0, "dur": 0.25, "color": col})


func _sfx(sound: String) -> void:
	if sfx:
		Sfx.play(sound)


func show_emote(name: String) -> void:
	emote = name
	emote_t = 2.5
	_sfx("tick")


func float_text(p: Vector2, text: String, color: Color, fsize := 14) -> void:
	# 같은 자리에 막 뜬 글자가 있으면 아래로 한 줄씩 밀어서 겹치지 않게
	var pos := p
	for k in 6:
		var clash := false
		for t in texts:
			if t["t"] < 0.6 and absf(t["pos"].y - pos.y) < fsize + 4 and absf(t["pos"].x - pos.x) < 140:
				clash = true
				break
		if not clash:
			break
		pos.y += fsize + 8
	texts.append({"pos": pos, "text": text, "color": color, "t": 0.0, "dur": 1.1, "size": fsize})
	if texts.size() > 40:
		texts.pop_front()


func show_banner(title: String, sub: String, color: Color) -> void:
	banner = title
	banner_sub = sub
	banner_color = color
	banner_t = 2.4


func _flash(color: Color, dur: float) -> void:
	flash_color = color
	flash_t = dur


func _add_effect(fx: Dictionary) -> void:
	if effects.size() < 320:
		effects.append(fx)


func _rare_pull_fx(idx: int, rarity: int) -> void:
	if idx < 0:
		return
	var col: Color = GameData.RARITY_COLORS[rarity]
	_sfx("legend" if rarity >= GameData.Rarity.LEGEND else "rare")
	# 가챠 연출: 등급이 높을수록 길고 화려하게
	if rarity >= GameData.Rarity.EPIC and sfx:
		effects = effects.filter(func(f): return f["type"] != "reveal")
		effects.append({"type": "reveal", "id": cells[idx]["id"], "rarity": rarity, "pos": cell_center(idx), "t": 0.0,
			"dur": [0.0, 0.0, 0.9, 1.3, 1.8][rarity], "color": col})
	_add_effect({"type": "ring", "pos": cell_center(idx), "r0": 10.0, "r1": 110.0, "t": 0.0, "dur": 0.7, "color": col})
	_add_effect({"type": "beam", "pos": cell_center(idx), "t": 0.0, "dur": 0.8, "color": col})
	if rarity >= GameData.Rarity.LEGEND:
		_flash(col, 0.3)
		shake = maxf(shake, 6.0)
		_coin_burst(cell_center(idx), 10 if rarity == 3 else 20, col)


func _update_visuals(dt: float) -> void:
	for i in range(effects.size() - 1, -1, -1):
		effects[i]["t"] += dt
		if effects[i]["t"] >= effects[i]["dur"]:
			effects.remove_at(i)
	for i in range(texts.size() - 1, -1, -1):
		texts[i]["t"] += dt
		if texts[i]["t"] >= texts[i]["dur"]:
			texts.remove_at(i)
	banner_t = maxf(0.0, banner_t - dt)
	flash_t = maxf(0.0, flash_t - dt)
	combo_pop = maxf(0.0, combo_pop - dt * 4.0)
	emote_t = maxf(0.0, emote_t - dt)
	boss_warn_t = maxf(0.0, boss_warn_t - dt)
	for c in cells:
		if c["kick"] > 0.0:
			c["kick"] = maxf(0.0, c["kick"] - dt)
	if _combo_t > 0.0:
		_combo_t -= dt
		if _combo_t <= 0.0:
			combo = 0
	shake = maxf(0.0, shake - dt * 30.0)
	queue_redraw()


# ===========================================================================
# 입력 (마우스)
# ===========================================================================
func handle_click(local: Vector2, right: bool) -> bool:
	## Match 가 로컬 좌표로 변환해서 전달. 처리했으면 true
	if local.x < 0 or local.y < 0 or local.x > SIZE or local.y > SIZE:
		return false
	for i in chests.size():
		if chests[i]["pos"].distance_to(local) < 22.0:
			open_chest(i)
			return true
	var idx := cell_at(local)
	if idx < 0:
		selected = -1
		return true
	if right:
		selected = -1
		return true
	select_cell(idx)
	return true


func select_cell(idx: int) -> void:
	if selected < 0:
		if cells[idx]["id"] != "":
			selected = idx
	elif selected == idx:
		selected = -1
	else:
		swap_cells(selected, idx)
		selected = -1


# ===========================================================================
# 그리기
# ===========================================================================
func _draw() -> void:
	var off := Vector2.ZERO
	if shake > 0.0:
		off = Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) * 0.5
	_draw_header()
	_draw_emote()
	draw_set_transform(off)
	_draw_field()
	_draw_grid()
	_draw_enemies()
	_draw_effects()
	_draw_chests()
	_draw_texts()
	draw_set_transform(Vector2.ZERO)
	if flash_t > 0.0:
		var fc := flash_color
		fc.a = clampf(flash_t, 0.0, 0.5) * 0.6
		draw_rect(Rect2(0, 0, SIZE, SIZE), fc)
	_draw_boss_warning()
	if banner_t <= 0.0:
		_draw_tag(hover if hover >= 0 else selected)
	_draw_combo()
	_draw_countdown()
	_draw_reveal()
	_draw_banner()
	if not alive:
		draw_rect(Rect2(0, 0, SIZE, SIZE), Color(0, 0, 0, 0.6))
		Glyphs.draw_icon(self, "defeat", Vector2(SIZE / 2, SIZE / 2), 70.0, Color(1, 0.3, 0.3))
	elif final_cleared_flag and mode != "pvp" and banner_t <= 0.0:
		# 큰 배너가 떠 있는 동안은 같은 글을 두 번 그리지 않는다
		_text(Vector2(SIZE / 2, SIZE / 2 - 110), "스테이지 클리어!" if stage_id != "" else "최종 보스 격파!", 26, Color(1, 0.9, 0.4))


func _text(center: Vector2, s: String, fsize: int, color: Color, outline := true) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var p := center + Vector2(-w / 2.0, fsize * 0.35)
	if outline:
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, 0.85))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)


func _draw_field() -> void:
	var bg := Art.tex("board/background")
	if bg != null:
		# 전장 전체 이미지 (560x560 기준, 트랙 폭 56 / 안쪽 448)
		draw_texture_rect(bg, Rect2(0, 0, SIZE, SIZE), false)
		draw_rect(Rect2(1, 1, SIZE - 2, SIZE - 2), accent, false, 2.0)
		Glyphs.draw_icon(self, "spawn", Vector2(INSET, INSET), 16.0, Color(1, 0.4, 0.4))
		return
	draw_rect(Rect2(0, 0, SIZE, SIZE), Color(0.13, 0.15, 0.2))
	# 트랙
	var track_col := Color(0.32, 0.27, 0.22)
	draw_rect(Rect2(0, 0, SIZE, 56), track_col)
	draw_rect(Rect2(0, SIZE - 56, SIZE, 56), track_col)
	draw_rect(Rect2(0, 0, 56, SIZE), track_col)
	draw_rect(Rect2(SIZE - 56, 0, 56, SIZE), track_col)
	# 트랙 방향 표시 (흐르는 화살표)
	var flow := fmod(_anim * 40.0, 72.0)
	for k in 28:
		var d := k * 72.0 + flow
		var p := path_pos(d)
		var p2 := path_pos(d + 10.0)
		var dir := (p2 - p).normalized()
		var n := Vector2(-dir.y, dir.x)
		draw_colored_polygon(PackedVector2Array([p + dir * 7, p - dir * 5 + n * 6, p - dir * 5 - n * 6]), Color(1, 1, 1, 0.07))
	# 내부 필드 테두리
	draw_rect(Rect2(56, 56, SIZE - 112, SIZE - 112), Color(0.1, 0.12, 0.16))
	draw_rect(Rect2(56, 56, SIZE - 112, SIZE - 112), accent.darkened(0.3), false, 3.0)
	draw_rect(Rect2(1, 1, SIZE - 2, SIZE - 2), accent, false, 2.0)
	# 스폰 지점
	var sp := Art.icon("spawn")
	if sp != null:
		draw_texture_rect(sp, Rect2(Vector2(INSET, INSET) - Vector2(18, 18), Vector2(36, 36)), false)
	else:
		var pulse := 0.5 + 0.5 * sin(_anim * 4.0)
		draw_circle(Vector2(INSET, INSET), 17.0 + 3.0 * pulse, Color(0.8, 0.1, 0.15, 0.35))
		draw_circle(Vector2(INSET, INSET), 12.0, Color(0.55, 0.08, 0.12))
		draw_arc(Vector2(INSET, INSET), 12.0, 0, TAU, 20, Color(1, 0.4, 0.4), 2.0)


func _draw_emote() -> void:
	if emote_t <= 0.0:
		return
	var pop := minf(1.0, (2.5 - emote_t) * 6.0)
	var a := clampf(emote_t * 2.0, 0.0, 1.0)
	var c := Vector2(SIZE - 40, -HEADER - 30)
	draw_circle(c, 30 * pop, Color(1, 1, 1, 0.95 * a))
	draw_colored_polygon(PackedVector2Array([c + Vector2(-8, 24), c + Vector2(8, 24), c + Vector2(0, 38)]), Color(1, 1, 1, 0.95 * a))
	var colors := {"emote": Color(1, 0.8, 0.2), "heart": Color(1, 0.35, 0.45), "star": Color(1, 0.8, 0.2), "skull": Color(0.4, 0.4, 0.45), "attack": Color(0.9, 0.3, 0.3), "gift": Color(0.3, 0.8, 0.6)}
	Glyphs.draw_icon(self, emote, c, 20 * pop, Color(colors.get(emote, Color.WHITE), a))


func _draw_header() -> void:
	## 전장 바로 위 한 줄: 이름+상태 | 적 수 게이지 | 보스 체력
	var y0 := -HEADER
	draw_rect(Rect2(0, y0, SIZE, HEADER - 3), Color(0.1, 0.11, 0.15))
	draw_rect(Rect2(0, y0, 4, HEADER - 3), accent)
	var name_font := 14
	draw_string(font, Vector2(10, y0 + 15), player_name, HORIZONTAL_ALIGNMENT_LEFT, 150, name_font, accent.lightened(0.35))
	var status := []
	if lucky_t > 0.0:
		status.append("행운 %ds" % int(ceil(lucky_t)))
	if curse_t > 0.0:
		status.append("저주 %ds" % int(ceil(curse_t)))
	if frenzy:
		status.append("광란")
	if difficulty > 0:
		status.append(GameData.DIFFICULTIES[difficulty]["name"])
	if fever_t > 0.0:
		status.append("FEVER %ds" % int(ceil(fever_t)))
	if rush_t > 0.0:
		status.append("폭주 %ds" % int(ceil(rush_t)))
	if eclipse_t > 0.0:
		status.append("일식 %ds" % int(ceil(eclipse_t)))
	if sand_t > 0.0:
		status.append("모래 %ds" % int(ceil(sand_t)))
	if bless_t > 0.0:
		status.append("축복 %ds" % int(ceil(bless_t)))
	if horde:
		status.append("대침공")
	if free_summons > 0:
		status.append("무료 %d" % free_summons)
	if not status.is_empty():
		draw_string(font, Vector2(10, y0 + 28), " ".join(status), HORIZONTAL_ALIGNMENT_LEFT, 150, 13, Color(1, 0.85, 0.5))
	# 적 수 게이지
	var count := field_count()
	var shown := count + (partner_count if mode == "coop" else 0)
	var ratio := clampf(float(shown) / enemy_limit, 0.0, 1.0)
	var bar := Rect2(165, y0 + 5, 215, HEADER - 13)
	draw_rect(bar, Color(0.04, 0.04, 0.06))
	var bc := Color(0.4, 0.85, 0.4).lerp(Color(1, 0.2, 0.2), ratio)
	if ratio > 0.8 and fmod(_anim, 0.5) < 0.25:
		bc = Color(1, 1, 1)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), bc)
	draw_rect(bar, Color(1, 1, 1, 0.3), false, 1.0)
	var label := ("적 %d / %d" % [shown, enemy_limit]) if mode != "coop" else ("합산 %d / %d" % [shown, enemy_limit])
	_text(bar.get_center(), label, 15, Color.WHITE)
	# 보스 체력 (없으면 처치 수)
	var r := Rect2(390, y0 + 5, SIZE - 396, HEADER - 13)
	var boss: EnemyState = null
	for e in enemies:
		if e.alive and e.is_boss:
			boss = e
			break
	if boss == null:
		for e in enemies:
			if e.alive and (e.kind == "midboss" or e.kind == "hero") and (boss == null or e.kind == "midboss"):
				boss = e
	if boss != null:
		var bar_col := Color(0.85, 0.15, 0.4) if boss.is_boss else (Color(0.65, 0.3, 0.95) if boss.kind == "midboss" else Color(0.95, 0.45, 0.2))
		draw_rect(r, Color(0.12, 0.02, 0.06))
		draw_rect(Rect2(r.position, Vector2(r.size.x * boss.hp_ratio(), r.size.y)), bar_col)
		draw_rect(r, Color(1, 0.5, 0.6, 0.5), false, 1.0)
		_text(r.get_center(), boss.boss_name if boss.boss_name != "" else "보스", 14, Color(1, 0.9, 0.92))
	else:
		_text(r.get_center(), "처치 %d" % kills, 15, Color(0.85, 0.9, 1.0), false)


func _draw_grid() -> void:
	var cell_tex := Art.tex("board/cell")
	for i in cells.size():
		var center := cell_center(i)
		var rect := Rect2(center - Vector2(CELL, CELL) / 2 + Vector2(2.5, 2.5), Vector2(CELL - 5, CELL - 5))
		var c: Dictionary = cells[i]
		if cell_tex != null:
			# 칸 그림은 배경 역할: 유닛이 먼저 보이도록 어둡고 반투명하게
			draw_texture_rect(cell_tex, rect, false, Color(0.62, 0.66, 0.78, 0.55))
		else:
			draw_rect(rect, Color(0.16, 0.18, 0.24))
			draw_rect(Rect2(rect.position, Vector2(rect.size.x, 3)), Color(1, 1, 1, 0.04))
		if c["id"] != "":
			var rc: Color = GameData.RARITY_COLORS[GameData.UNITS[c["id"]]["rarity"]]
			var tile := StyleBoxFlat.new()
			tile.bg_color = Color(0.03, 0.04, 0.1, 0.72)
			tile.border_color = Color(rc, 0.95)
			tile.set_border_width_all(2)
			tile.border_width_bottom = 5
			tile.set_corner_radius_all(9)
			tile.draw(get_canvas_item(), rect.grow(-1.0))
			draw_rect(Rect2(rect.position + Vector2(4, 4), Vector2(rect.size.x - 8, rect.size.y * 0.45)), Color(rc, 0.1))
		if not is_remote and mergeable(i):
			var pulse := 0.5 + 0.5 * sin(_anim * 6.0)
			draw_rect(rect, Color(1, 0.9, 0.4, 0.4 + 0.5 * pulse), false, 3.0)
		if c["id"] != "":
			_draw_unit_stack(center, c)
	if selected >= 0 and selected < cells.size() and cells[selected]["id"] != "":
		var sc := cell_center(selected)
		var u: Dictionary = GameData.UNITS[cells[selected]["id"]]
		draw_circle(sc, u["range"], Color(1, 1, 1, 0.04))
		draw_arc(sc, u["range"], 0, TAU, 64, Color(1, 1, 1, 0.4), 2.0)
		draw_rect(Rect2(sc - Vector2(CELL, CELL) / 2, Vector2(CELL, CELL)), Color(1, 1, 1, 0.95), false, 3.0)
	if not pending_enhance.is_empty():
		var pi := cells.find(pending_enhance["cell"])
		if pi >= 0:
			var pc := cell_center(pi)
			var sw := sin(_anim * 22.0)
			draw_rect(Rect2(pc - Vector2(CELL, CELL) / 2, Vector2(CELL, CELL)), Color(1, 0.85, 0.3, 0.5 + 0.4 * sw), false, 3.0)
			Glyphs.draw(self, "hammer", pc + Vector2(14, -14) + Vector2(0, -6 * absf(sw)), 12.0, Color(1, 0.9, 0.6))
	if show_cursor:
		var cc := cell_center(cursor)
		draw_rect(Rect2(cc - Vector2(CELL, CELL) / 2 + Vector2(1, 1), Vector2(CELL - 2, CELL - 2)), accent.lightened(0.4), false, 2.0)


func _draw_unit_stack(center: Vector2, c: Dictionary) -> void:
	var u: Dictionary = GameData.UNITS[c["id"]]
	var rc: Color = GameData.RARITY_COLORS[u["rarity"]]
	var n: int = c["n"]
	var bob := sin(_anim * 3.0 + center.x * 0.1) * 1.5
	var p := center + Vector2(0, -4 + bob)
	var st: int = c.get("star", 0)
	if st >= 1:
		var aura: Color = [Color(1, 1, 1), Color(0.5, 0.8, 1.0), Color(0.6, 1.0, 0.6), Color(1, 0.7, 0.3), Color(1, 0.45, 0.35), Color(1, 0.5, 1.0)][st]
		if st >= GameData.TRANSCEND_STAR:
			aura = Color.from_hsv(fmod(_anim * 0.3, 1.0), 0.6, 1.0)
		draw_circle(p, CELL * (0.3 + 0.02 * st), Color(aura, 0.15 + 0.05 * st + 0.05 * sin(_anim * 4.0)))
	# 그림자 + 크게 (칸의 약 90%)
	draw_set_transform(center + Vector2(0, CELL * 0.3), 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, CELL * 0.3, Color(0, 0, 0, 0.45))
	draw_set_transform(Vector2.ZERO)
	Glyphs.draw_unit_token(self, c["id"], p, CELL * 0.33 * (1.0 + 0.035 * st) * (1.0 + c.get("kick", 0.0) * 1.2), _anim)
	# 마릿수: 하단 점 (1~3)
	for k in n:
		var x := (k - (n - 1) / 2.0) * 11.0
		var q := center + Vector2(x, CELL * 0.37)
		draw_colored_polygon(PackedVector2Array([q + Vector2(0, -6), q + Vector2(6, 0), q + Vector2(0, 6), q + Vector2(-6, 0)]), Color(0, 0, 0, 0.8))
		draw_colored_polygon(PackedVector2Array([q + Vector2(0, -4), q + Vector2(4, 0), q + Vector2(0, 4), q + Vector2(-4, 0)]), rc.lightened(0.2))
	if u.has("skill"):
		var ratio := clampf(c["skill_t"] / u["skill"]["cd"], 0.0, 1.0)
		draw_arc(p, CELL * 0.4, -PI / 2, -PI / 2 + TAU * ratio, 24, Color(1, 1, 1, 0.55), 2.5)
	var star: int = c.get("star", 0)
	if star >= GameData.AWAKEN_STAR:
		# 각성 오라
		draw_arc(p, CELL * 0.36, _anim * 2.0, _anim * 2.0 + PI * 1.4, 20, Color(1, 0.75, 0.3, 0.8), 3.0)
	for k in star:
		var sp := center + Vector2(-CELL * 0.4 + 8 + k * 12, -CELL * 0.4 + 8)
		Glyphs.draw(self, "star", sp, 7.5, Color(0, 0, 0, 0.7))
		Glyphs.draw(self, "star", sp, 6.2, Color(1, 0.85, 0.3))
	if c.get("silence", 0.0) > 0.0:
		draw_rect(Rect2(center - Vector2(CELL, CELL) * 0.46, Vector2(CELL, CELL) * 0.92), Color(0.3, 0.1, 0.45, 0.55))
		Glyphs.draw(self, "close", center, 14.0, Color(0.85, 0.5, 1.0))
	if Art.show_unit_labels:
		_text(center + Vector2(0, CELL * 0.3), u["name"], 13, rc)


func _draw_enemy_marks(e: EnemyState, body: Vector2, s: float) -> void:
	## 그림 적 위 표시: 상태이상(빙결·둔화·기절·화상·중독), 보스 시전(빨간 원)·용암 방패, 이름표
	if e.freeze_t > 0.0:
		# 얼음 덩어리
		var ib := Rect2(body - Vector2(s, s) * 1.25, Vector2(s, s) * 2.5)
		var ice := StyleBoxFlat.new()
		ice.bg_color = Color(0.6, 0.9, 1.0, 0.45)
		ice.border_color = Color(0.9, 1, 1, 0.95)
		ice.set_border_width_all(2)
		ice.set_corner_radius_all(4)
		ice.draw(get_canvas_item(), ib)
		draw_line(ib.position + Vector2(4, 6), ib.position + Vector2(ib.size.x * 0.45, 3), Color(1, 1, 1, 0.8), 2.0)
		Glyphs.draw(self, "snow", body + Vector2(s * 0.9, -s * 0.9), 6.0, Color(1, 1, 1))
	elif e.slow_t > 0.0 or e.aura_slow > 0.0:
		for j in 3:
			var ang := _anim * 3.0 + j * TAU / 3.0
			var fp := body + Vector2(cos(ang) * s * 1.2, sin(ang) * s * 0.5 + s * 0.6)
			draw_colored_polygon(PackedVector2Array([fp + Vector2(0, -3), fp + Vector2(3, 0), fp + Vector2(0, 3), fp + Vector2(-3, 0)]), Color(0.7, 0.95, 1.0, 0.9))
	if e.stun_t > 0.0 and e.freeze_t <= 0.0:
		for j in 3:
			var ang2 := _anim * 6.0 + j * TAU / 3.0
			Glyphs.draw(self, "star", body + Vector2(cos(ang2) * s * 0.8, -s * 1.3 + sin(ang2) * 4.0), 4.5, Color(1, 0.95, 0.4))
	if e.burn_t > 0.0:
		for j in 2:
			var fl := body + Vector2((j - 0.5) * s * 0.8, -s * 0.2)
			var hgt := 8.0 + 4.0 * sin(_anim * 14.0 + j * 2.0)
			draw_colored_polygon(PackedVector2Array([fl + Vector2(-4, 0), fl + Vector2(4, 0), fl + Vector2(0, -hgt)]), Color(1, 0.5, 0.1, 0.85))
	if e.poison_t > 0.0:
		for j in 3:
			var bq := fmod(_anim * 0.8 + j * 0.33, 1.0)
			draw_circle(body + Vector2((j - 1) * s * 0.5, -s * 0.5 - bq * s), 2.5 + bq * 1.5, Color(0.45, 1.0, 0.35, 0.8 * (1.0 - bq)))
	if e.is_boss:
		if e.casting != "":
			var cr := s * 1.4 + 10 + 8 * sin(_anim * 16.0)
			draw_arc(body, cr, 0, TAU, 28, Color(1, 0.2, 0.2, 0.95), 4.0)
			draw_arc(body, cr + 8, 0, TAU * (1.0 - e.cast_t / GameData.BOSS_CAST_TIME), 28, Color(1, 0.8, 0.3, 0.95), 4.0)
		if e.shield_t > 0.0:
			draw_arc(body, s * 1.4 + 6, 0, TAU, 28, Color(1, 0.6, 0.1, 0.9), 5.0)
	if e.shield > 0.0:
		draw_arc(body, s * 1.3, 0, TAU, 20, Color(0.5, 0.8, 1.0, 0.9), 2.5)
	if e.boss_name != "":
		var fs := 13
		var w := font.get_string_size(e.boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var tp := body + Vector2(-w * 0.5, -s * 1.55 - 12)
		tp.y = maxf(tp.y, 16.0)
		tp.x = clampf(tp.x, 4.0, SIZE - w - 4.0)
		draw_string_outline(font, tp, e.boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.9))
		draw_string(font, tp, e.boss_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, e.color.lightened(0.5) if not e.is_boss else Color(1, 0.75, 0.8))


func _draw_tag(i: int) -> void:
	## 마우스 오버/선택한 칸 위 이름표 (평소엔 글자 없음)
	if i < 0 or i >= cells.size() or cells[i]["id"] == "":
		return
	var u: Dictionary = GameData.UNITS[cells[i]["id"]]
	var rc: Color = GameData.RARITY_COLORS[u["rarity"]]
	var label := "%s  x%d" % [u["name"], cells[i]["n"]]
	var fs := 14
	var w := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x + 16
	var c := cell_center(i) + Vector2(0, -CELL * 0.62)
	c.x = clampf(c.x, w / 2 + 4, SIZE - w / 2 - 4)
	var r := Rect2(c - Vector2(w / 2, 12), Vector2(w, 24))
	draw_rect(r, Color(0.05, 0.06, 0.09, 0.92))
	draw_rect(r, rc, false, 1.5)
	draw_string(font, r.position + Vector2(8, 17), label, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, rc.lightened(0.2))


func _draw_enemies() -> void:
	for e in enemies:
		if is_remote or e.alive:
			var p: Vector2 = e.pos
			var col: Color = e.color
			if e.flash > 0.0:
				col = Color.WHITE
			if e.enraged:
				col = col.lerp(Color(1, 0, 0), 0.5 + 0.5 * sin(_anim * 10.0))
			var s: float = e.size
			var body := p + Vector2(0, sin(_anim * 8.0 + e.wobble) * 1.5)
			# 그림 우선순위: 전용 그림(hero_thief, boss_lich …) → 종류 그림(hero, midboss, boss …) → 비슷한 그림에 색 입히기
			var etex: Texture2D = Art.enemy(e.art) if e.art != "" else null
			if etex == null:
				etex = Art.enemy(e.kind)
			var tint := Color(1, 1, 1)
			if etex == null and (e.kind == "midboss" or e.kind == "hero"):
				# 전용 그림이 없으면 보스/정예 그림을 색만 바꿔서
				etex = Art.enemy("boss" if e.kind == "midboss" else "elite")
				tint = e.color.lightened(0.35)
			if etex != null:
				var mod := tint
				if e.flash > 0.0:
					mod = Color(2, 2, 2)
				elif e.stun_t > 0.0:
					mod = Color(1, 1, 0.6)
				elif e.slow_t > 0.0 or e.aura_slow > 0.0:
					mod = Color(0.7, 0.9, 1.2)
				draw_set_transform(body + Vector2(0, s * 1.05), 0.0, Vector2(1.0, 0.35))
				draw_circle(Vector2.ZERO, s * 1.0, Color(0, 0, 0, 0.4))
				draw_set_transform(Vector2.ZERO)
				if e.is_boss or e.kind == "midboss" or e.kind == "hero":
					var ring := Color(1, 0.2, 0.3) if e.is_boss else (Color(0.75, 0.4, 1.0) if e.kind == "midboss" else Color(1, 0.55, 0.2))
					draw_arc(body, s * 1.35, 0, TAU, 32, Color(ring, 0.55 + 0.3 * sin(_anim * 5.0)), 3.0)
				draw_texture_rect(etex, Rect2(body - Vector2(s, s) * 1.4, Vector2(s, s) * 2.8), false, mod)
				_draw_enemy_marks(e, body, s)
				_draw_enemy_bar(e, body, s)
				continue
			draw_circle(body + Vector2(2, 3), s, Color(0, 0, 0, 0.3))
			if e.kind == "tank" or e.kind == "boss" or e.kind == "elite":
				draw_rect(Rect2(body - Vector2(s, s), Vector2(s, s) * 2), col)
				draw_rect(Rect2(body - Vector2(s, s), Vector2(s, s) * 2), col.darkened(0.5), false, 2.0)
			else:
				draw_circle(body, s, col)
				draw_arc(body, s, 0, TAU, 16, col.darkened(0.5), 1.5)
			# 눈
			draw_circle(body + Vector2(-s * 0.35, -s * 0.2), s * 0.2, Color.WHITE)
			draw_circle(body + Vector2(s * 0.35, -s * 0.2), s * 0.2, Color.WHITE)
			if e.is_boss:
				if e.casting != "":
					var cr := s + 10 + 8 * sin(_anim * 16.0)
					draw_arc(body, cr, 0, TAU, 28, Color(1, 0.2, 0.2, 0.9), 3.0)
					draw_arc(body, cr + 8, 0, TAU * (1.0 - e.cast_t / GameData.BOSS_CAST_TIME), 28, Color(1, 0.8, 0.3, 0.9), 3.0)
				if e.shield_t > 0.0:
					draw_arc(body, s + 6, 0, TAU, 28, Color(1, 0.6, 0.1, 0.9), 5.0)
					draw_circle(body, s + 6, Color(1, 0.5, 0.1, 0.18))
				if e.buff_t > 0.0:
					draw_line(body, body - (path_pos(e.dist + 5) - body).normalized() * 40.0, Color(1, 0.5, 0.2, 0.6), s)
			if e.freeze_t > 0.0:
				draw_circle(body, s + 2, Color(0.6, 0.9, 1.0, 0.45))
			if e.kind == "goblin":
				draw_arc(body, s + 4, 0, TAU, 16, Color(1, 1, 0.4, 0.8), 2.0)
			elif e.kind == "bonus":
				# 보물 돼지: 귀 + 코
				draw_colored_polygon(PackedVector2Array([body + Vector2(-s * 0.8, -s * 0.5), body + Vector2(-s * 0.3, -s * 0.95), body + Vector2(-s * 0.9, -s * 1.1)]), col)
				draw_colored_polygon(PackedVector2Array([body + Vector2(s * 0.8, -s * 0.5), body + Vector2(s * 0.3, -s * 0.95), body + Vector2(s * 0.9, -s * 1.1)]), col)
				draw_circle(body + Vector2(0, s * 0.25), s * 0.35, col.darkened(0.2))
				draw_circle(body + Vector2(-s * 0.12, s * 0.25), s * 0.08, Color(0.3, 0.1, 0.1))
				draw_circle(body + Vector2(s * 0.12, s * 0.25), s * 0.08, Color(0.3, 0.1, 0.1))
				draw_string(font, body + Vector2(-4, -s - 10), "$", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 0.9, 0.3))
			if e.shield > 0.0:
				draw_arc(body, s + 3, 0, TAU, 16, Color(0.5, 0.8, 1.0, 0.9), 2.0)
			if e.slow_t > 0.0 or e.aura_slow > 0.0:
				draw_arc(body, s + 1, 0, TAU, 16, Color(0.5, 0.9, 1.0, 0.7), 2.0)
			if e.burn_t > 0.0 or e.poison_t > 0.0:
				draw_circle(body + Vector2(0, -s - 4), 2.5, Color(1, 0.5, 0.1))
			if e.stun_t > 0.0:
				for k in 3:
					draw_circle(body + Vector2.from_angle(_anim * 6.0 + k * TAU / 3) * (s + 2) + Vector2(0, -s), 2.0, Color(1, 1, 0.4))
			_draw_enemy_bar(e, body, s)


func _draw_enemy_bar(e: EnemyState, body: Vector2, s: float) -> void:
	var hr: float = e.hp_ratio()
	if hr < 0.999 or e.is_boss:
		var w := s * 2.4
		var y := -s * 1.35 - 6
		draw_rect(Rect2(body + Vector2(-w / 2 - 1, y - 1), Vector2(w + 2, 6)), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(body + Vector2(-w / 2, y), Vector2(w * hr, 4)), Color(0.3, 1.0, 0.3).lerp(Color(1, 0.2, 0.2), 1.0 - hr))


func _draw_effects() -> void:
	for fx in effects:
		var k: float = fx["t"] / fx["dur"]
		if k < 0.0:
			continue
		var col: Color = fx["color"]
		match fx["type"]:
			"atk":
				_draw_atk(fx, k, col)
			"icecell", "sand", "pillar", "rift", "quake", "bless", "miasma", "rainarrow", "breath", "vortex":
				_draw_special(fx, k, col)
			"firestorm":
				var fc: Vector2 = fx["pos"]
				var fr: float = fx["r"]
				for j in 10:
					var h := fmod(sin(j * 12.9898 + fx["seed"]) * 43758.5453, 1.0)
					var ang: float = fx["seed"] + j * 2.4
					var tgt := fc + Vector2.from_angle(ang) * fr * (0.2 + 0.8 * absf(h))
					var q := clampf((k - j * 0.06) / 0.4, 0.0, 1.4)
					if q <= 0.0:
						continue
					if q < 1.0:
						var mp := (tgt + Vector2(-70, -190)).lerp(tgt, q)
						for tr in 4:
							draw_circle(mp - Vector2(-70, -190).normalized() * tr * 9.0, 9.0 - tr * 2.0, Color(1, 0.5 + tr * 0.1, 0.1, 0.9 - tr * 0.2))
						draw_circle(mp, 5.0, Color(1, 0.95, 0.6))
					else:
						var ib := (q - 1.0) / 0.4
						draw_circle(tgt, 26.0 * ib + 6.0, Color(1, 0.45, 0.1, 0.55 * (1.0 - ib)))
						draw_arc(tgt, 30.0 * ib + 8.0, 0, TAU, 20, Color(1, 0.85, 0.4, 1.0 - ib), 3.0)
			"strike":
				var sp: Vector2 = fx["pos"]
				var top := Vector2(sp.x + sin(fx["seed"]) * 30.0, maxf(0.0, sp.y - 320.0))
				var pts := PackedVector2Array([top])
				for j in range(1, 7):
					var m := top.lerp(sp, j / 7.0)
					pts.append(m + Vector2(sin(fx["seed"] * 3.0 + j * 1.7) * 14.0, 0))
				pts.append(sp)
				var ka := 1.0 - k
				draw_polyline(pts, Color(1, 1, 0.7, ka), 7.0 * ka + 1.0)
				draw_polyline(pts, Color(1, 1, 1, ka), 2.5)
				draw_circle(sp, 22.0 * (0.5 + k), Color(1, 1, 0.5, 0.45 * ka))
			"timestop":
				var ta := minf(1.0, minf(k * 6.0, (1.0 - k) * 4.0))
				draw_rect(Rect2(0, 0, SIZE, SIZE), Color(0.35, 0.6, 1.0, 0.16 * ta))
				var tc: Vector2 = fx["pos"]
				draw_circle(tc, 96, Color(0.1, 0.2, 0.4, 0.35 * ta))
				draw_arc(tc, 96, 0, TAU, 60, Color(0.7, 0.95, 1.0, 0.9 * ta), 5.0)
				for j in 12:
					var d := Vector2.from_angle(j * TAU / 12.0)
					draw_line(tc + d * 80, tc + d * (90 if j % 3 else 70), Color(0.8, 1, 1, ta), 3.0)
				var back := -k * TAU * 3.0
				draw_line(tc, tc + Vector2.from_angle(back - PI / 2) * 70, Color(1, 1, 1, ta), 5.0)
				draw_line(tc, tc + Vector2.from_angle(back * 0.1 - PI / 2) * 45, Color(1, 1, 1, ta), 7.0)
			"goldrain":
				for j in 28:
					var hx := absf(fmod(sin(j * 78.233 + fx["seed"]) * 43758.5453, 1.0))
					var y := -20.0 + (k * 1.5 - (j % 7) * 0.08) * SIZE
					if y < -20.0 or y > SIZE + 20.0:
						continue
					var cp := Vector2(hx * SIZE, y)
					var wsc := absf(cos(k * 18.0 + j))
					draw_set_transform(cp, 0.0, Vector2(maxf(0.15, wsc), 1.0))
					draw_circle(Vector2.ZERO, 7.0, Color(1, 0.8, 0.15))
					draw_circle(Vector2.ZERO, 4.5, Color(1, 0.95, 0.5))
					draw_set_transform(Vector2.ZERO)
			"portal":
				var pc: Vector2 = fx["pos"]
				var pr := 34.0 * sin(k * PI)
				for j in 3:
					var ra := pr * (1.0 - j * 0.25)
					draw_set_transform(pc, 0.0, Vector2(1.0, 0.45))
					draw_arc(Vector2.ZERO, ra, k * 9.0 + j, k * 9.0 + j + PI * 1.4, 20, Color(col.lightened(j * 0.2), 0.9), 3.0)
					draw_set_transform(Vector2.ZERO)
				draw_circle(pc, pr * 0.5, Color(0.1, 0.0, 0.2, 0.5 * sin(k * PI)))
			"heal":
				for j in 5:
					var hp_pos: Vector2 = fx["pos"] + Vector2((j - 2) * 14.0, -20.0 - k * 50.0 - (j % 2) * 10.0)
					var ha := 1.0 - k
					draw_rect(Rect2(hp_pos - Vector2(2, 7), Vector2(4, 14)), Color(0.4, 1, 0.5, ha))
					draw_rect(Rect2(hp_pos - Vector2(7, 2), Vector2(14, 4)), Color(0.4, 1, 0.5, ha))
			"shot":
				var p: Vector2 = fx["from"].lerp(fx["to"], minf(1.0, k * 1.3))
				draw_circle(p, 4.0 if fx["big"] else 2.5, col.lightened(0.3))
				draw_line(p, p - (fx["to"] - fx["from"]).normalized() * 10.0, Color(col, 0.6), 2.0)
			"bolt":
				var a: Vector2 = fx["from"]
				var b: Vector2 = fx["to"]
				var pts := PackedVector2Array([a])
				for j in range(1, 5):
					var m := a.lerp(b, j / 5.0)
					var n := (b - a).orthogonal().normalized() * randf_range(-8, 8)
					pts.append(m + n)
				pts.append(b)
				draw_polyline(pts, Color(col, 1.0 - k), 2.5)
			"boom":
				draw_circle(fx["pos"], fx["r"] * (0.4 + 0.6 * k), Color(col, 0.35 * (1.0 - k)))
				draw_arc(fx["pos"], fx["r"] * (0.4 + 0.6 * k), 0, TAU, 32, Color(col, 0.8 * (1.0 - k)), 2.0)
			"pop":
				draw_arc(fx["pos"], fx["r"] * (0.5 + k), 0, TAU, 16, Color(col, 1.0 - k), 2.0)
			"ring":
				var r: float = lerpf(fx["r0"], fx["r1"], k)
				draw_arc(fx["pos"], r, 0, TAU, 40, Color(col, 1.0 - k), 3.0)
			"coin":
				var t: float = fx["t"]
				var p: Vector2 = fx["pos"] + fx["vel"] * t + Vector2(0, 420) * t * t
				var r := 5.0 * (1.0 - k * 0.5)
				draw_circle(p, r, Color(col.darkened(0.3), 1.0 - k * k))
				draw_circle(p, r * 0.65, Color(col.lightened(0.2), 1.0 - k * k))
			"spark":
				var p0: Vector2 = fx["pos"] + fx["vel"] * fx["t"]
				draw_line(p0, p0 - fx["vel"] * 0.05, Color(col, 1.0 - k), 2.0)
			"reveal":
				pass
			"up":
				var up_p: Vector2 = fx["pos"] + Vector2(0, -20 - 26 * k)
				draw_colored_polygon(PackedVector2Array([up_p + Vector2(0, -9), up_p + Vector2(8, 3), up_p + Vector2(-8, 3)]), Color(col, 1.0 - k))
				draw_arc(fx["pos"], 18 + 20 * k, 0, TAU, 24, Color(col, 0.7 * (1.0 - k)), 2.0)
			"pierce":
				draw_line(fx["from"], fx["to"], Color(col.lightened(0.4), 0.9 * (1.0 - k)), 3.0 * (1.0 - k) + 1.0)
			"merge":
				var mp: Vector2 = fx["pos"]
				for q in 3:
					var from := mp + Vector2.from_angle(-PI / 2 + q * TAU / 3.0) * CELL * 0.45
					draw_circle(from.lerp(mp, k), 9.0 * (1.0 - k * 0.5), Color(col.lightened(0.3), 1.0 - k * 0.4))
				draw_circle(mp, CELL * 0.5 * k, Color(col, 0.35 * (1.0 - k)))
				draw_arc(mp, CELL * 0.55 * k + 4, 0, TAU, 24, Color(1, 1, 1, 0.8 * (1.0 - k)), 3.0)
			"beam":
				var h := 200.0 * (1.0 - k)
				draw_rect(Rect2(fx["pos"] + Vector2(-8, -h), Vector2(16, h)), Color(col, 0.5 * (1.0 - k)))


func _draw_special(fx: Dictionary, k: float, col: Color) -> void:
	## 신화 스킬(2차) · 보스 기술(5~9번 보스) 연출
	var a := 1.0 - k
	match fx["type"]:
		"icecell":
			# 서리 감옥: 칸을 덮는 얼음 덩어리 (끝날 때 녹음)
			var ic: Vector2 = fx["pos"]
			var ia := minf(1.0, minf(k * 8.0, a * 5.0))
			var half := CELL * 0.46
			var r := Rect2(ic - Vector2(half, half), Vector2(half, half) * 2.0)
			draw_rect(r, Color(0.6, 0.9, 1.0, 0.4 * ia))
			draw_rect(r, Color(0.9, 1, 1, 0.9 * ia), false, 2.5)
			draw_line(r.position + Vector2(6, 10), r.position + Vector2(r.size.x * 0.5, 4), Color(1, 1, 1, 0.8 * ia), 2.0)
			draw_line(r.end - Vector2(8, 18), r.end - Vector2(r.size.x * 0.4, 6), Color(1, 1, 1, 0.5 * ia), 2.0)
			Glyphs.draw(self, "snow", ic + Vector2(half - 10, -half + 10), 7.0, Color(1, 1, 1, ia))
		"sand":
			# 모래 폭풍: 전장을 가로지르는 모래 줄기
			var sa := minf(1.0, minf(k * 6.0, a * 4.0))
			draw_rect(Rect2(0, 0, SIZE, SIZE), Color(col, 0.12 * sa))
			for j in 18:
				var hy := absf(fmod(sin(j * 12.9898 + fx["seed"]) * 43758.5453, 1.0))
				var ln := 40.0 + (j % 3) * 14.0
				var x := fmod(_anim * (260.0 + j * 13.0) + j * 97.0, SIZE - ln)
				var y := clampf(hy * SIZE + sin(_anim * 3.0 + j) * 10.0, 4.0, SIZE - 8.0)
				draw_line(Vector2(x, y), Vector2(x + ln, y + 4.0), Color(col.lightened(0.2), 0.55 * sa), 2.0 + (j % 2))
		"pillar":
			# 빛기둥
			var pp: Vector2 = fx["pos"]
			var ha := sin(k * PI)
			draw_rect(Rect2(pp + Vector2(-10, -140), Vector2(20, 140)), Color(col, 0.3 * ha))
			draw_rect(Rect2(pp + Vector2(-3, -140), Vector2(6, 140)), Color(1, 1, 0.95, 0.75 * ha))
			draw_arc(pp, 12.0 + 10.0 * k, 0, TAU, 20, Color(col, ha), 3.0)
		"rift":
			# 공허 균열: 들쭉날쭉한 검보라 틈
			var f: Vector2 = fx["from"]
			var t: Vector2 = fx["to"]
			var pts := PackedVector2Array([f])
			for j in range(1, 8):
				pts.append(f.lerp(t, j / 8.0) + (t - f).orthogonal().normalized() * sin(fx["seed"] + j * 2.1) * 12.0)
			pts.append(t)
			draw_polyline(pts, Color(0.1, 0.0, 0.18, 0.9 * a), 8.0 * a + 2.0)
			draw_polyline(pts, Color(col.lightened(0.3), a), 2.5)
		"quake":
			# 대지 강타: 사방으로 갈라지는 땅 + 충격파
			var qc: Vector2 = fx["pos"]
			var qr: float = fx["r"]
			for j in 8:
				var ang: float = fx["seed"] + j * TAU / 8.0
				var p0 := qc
				var len := qr * minf(1.0, k * 2.5)
				var p1 := qc + Vector2.from_angle(ang) * len * 0.5 + Vector2.from_angle(ang + 0.5) * 10.0
				var p2 := qc + Vector2.from_angle(ang) * len
				draw_polyline(PackedVector2Array([p0, p1, p2]), Color(0.25, 0.15, 0.08, a), 4.0)
				draw_polyline(PackedVector2Array([p0, p1, p2]), Color(col.lightened(0.3), a * 0.8), 1.5)
			draw_arc(qc, qr * k, 0, TAU, 40, Color(col, a), 5.0 * a + 1.0)
		"bless":
			# 신성 축복: 칸에서 올라가는 빛 조각
			var bp: Vector2 = fx["pos"]
			for j in 4:
				var q := fmod(k + j * 0.25, 1.0)
				var sp := bp + Vector2((j - 1.5) * 12.0, 18.0 - q * 50.0)
				Glyphs.draw(self, "star", sp, 5.0, Color(col, (1.0 - q) * a))
			draw_arc(bp, CELL * 0.42, 0, TAU, 24, Color(col, 0.7 * a), 2.5)
		"miasma":
			# 역병: 부풀어 오르는 초록 독구름
			var mp: Vector2 = fx["pos"]
			for j in 4:
				var o := Vector2.from_angle(fx["seed"] + j * 1.6) * (8.0 + 14.0 * k)
				draw_circle(mp + o + Vector2(0, -10.0 * k), 9.0 + 8.0 * k, Color(col.darkened(0.2), 0.35 * a))
			draw_circle(mp, 6.0 + 10.0 * k, Color(col.lightened(0.3), 0.4 * a))
		"rainarrow":
			# 화살비: 위에서 비스듬히 떨어지는 화살
			var rp: Vector2 = fx["pos"]
			var drop := minf(1.0, k * 1.6)
			var head := rp + Vector2(-40, -120) * (1.0 - drop)
			draw_line(head - Vector2(-40, -120).normalized() * -18.0, head, Color(col, 0.95), 2.5)
			draw_colored_polygon(PackedVector2Array([head + Vector2(4, 10), head + Vector2(-4, -2), head + Vector2(6, -1)]), Color(1, 1, 1, 0.95))
			if drop >= 1.0:
				var ib := (k - 0.625) / 0.375
				draw_arc(rp, 6.0 + 12.0 * ib, 0, TAU, 16, Color(col, 1.0 - ib), 2.0)
		"breath":
			# 빙결 숨결: 유닛에서 한 변 전체로 퍼지는 냉기
			var bf: Vector2 = fx["from"]
			var ea: Vector2 = fx["a"]
			var eb: Vector2 = fx["b"]
			var grow := minf(1.0, k * 3.0)
			var pa := bf.lerp(ea, grow)
			var pb := bf.lerp(eb, grow)
			draw_colored_polygon(PackedVector2Array([bf, pa, pb]), Color(col, 0.28 * a))
			draw_line(bf, pa, Color(1, 1, 1, 0.6 * a), 2.0)
			draw_line(bf, pb, Color(1, 1, 1, 0.6 * a), 2.0)
			draw_line(pa, pb, Color(0.85, 1, 1, 0.9 * a), 6.0 * a + 1.0)
			for j in 6:
				var sp := ea.lerp(eb, (j + 0.5) / 6.0)
				Glyphs.draw(self, "snow", sp, 8.0 * grow, Color(1, 1, 1, a))
		"vortex":
			# 블랙홀: 빨려 들어가는 소용돌이
			var vc: Vector2 = fx["pos"]
			var vr: float = fx["r"]
			var va := sin(k * PI)
			draw_circle(vc, vr * 0.35 * va + 4.0, Color(0.05, 0.0, 0.1, 0.85 * va))
			for j in 5:
				var rr := vr * (1.0 - fmod(k * 2.0 + j * 0.2, 1.0))
				var st := k * 14.0 + j * 1.3
				draw_arc(vc, rr, st, st + PI * 1.1, 18, Color(col.lightened(j * 0.1), 0.8 * va), 3.0)
			draw_arc(vc, vr * 0.35 * va + 5.0, 0, TAU, 24, Color(col.lightened(0.4), va), 2.0)


func _draw_atk(fx: Dictionary, k: float, col: Color) -> void:
	## 유닛 종류별 공격 연출
	var from: Vector2 = fx["from"]
	var to: Vector2 = fx["to"]
	var dir := (to - from).normalized()
	var big: bool = fx["big"]
	var sc := 1.35 if big else 1.0
	var a := 1.0 - k
	var sd: float = fx["seed"]
	match fx["style"]:
		"slash":
			var a0 := dir.angle() - 1.1 + sd * 0.05
			draw_arc(to, 16.0 * sc, a0, a0 + 2.2 * minf(1.0, k * 2.2), 14, Color(1, 1, 1, a), 5.0 * a + 1.0)
			draw_arc(to, 13.0 * sc, a0, a0 + 2.2 * minf(1.0, k * 2.2), 14, Color(col.lightened(0.3), a), 3.0)
		"spin":
			var sa := k * TAU * 1.5
			draw_arc(to, 20.0 * sc, sa, sa + PI * 1.2, 16, Color(col.lightened(0.4), a), 5.0)
			draw_arc(to, 12.0 * sc, sa + PI, sa + PI * 2.0, 12, Color(1, 1, 1, a * 0.8), 3.0)
		"stab":
			var sp := to - dir * (18.0 - 20.0 * k)
			draw_line(sp - dir * 14.0, sp + dir * 6.0, Color(0.9, 0.85, 1.0, a), 3.0)
			if k > 0.5:
				var n := dir.orthogonal() * 9.0
				draw_line(to - n, to + n, Color(col, a), 2.0)
				draw_line(to - dir * 9.0, to + dir * 9.0, Color(col, a), 2.0)
		"thrust":
			var reach := minf(1.0, k * 2.0) if k < 0.6 else (1.0 - (k - 0.6) * 1.5)
			var tip := from.lerp(to, 0.35 + 0.65 * reach)
			draw_line(from + dir * 14.0, tip, Color(col.darkened(0.2), 0.9), 4.0 * sc)
			draw_colored_polygon(PackedVector2Array([tip + dir * 10.0, tip + dir.orthogonal() * 5.0, tip - dir.orthogonal() * 5.0]), Color(1, 1, 1, 0.95))
		"bash":
			draw_arc(to, 6.0 + 18.0 * k * sc, 0, TAU, 18, Color(col.lightened(0.3), a), 4.0)
			Glyphs.draw(self, "star", to, 7.0 * a + 2.0, Color(1, 1, 0.8, a))
		"arrow":
			var ap := from.lerp(to, k)
			draw_line(ap - dir * 16.0, ap, Color(col.lightened(0.2), 0.9), 2.5)
			draw_colored_polygon(PackedVector2Array([ap + dir * 7.0, ap - dir * 2.0 + dir.orthogonal() * 4.0, ap - dir * 2.0 - dir.orthogonal() * 4.0]), Color(1, 1, 1))
			if big:
				var o := dir.orthogonal() * 10.0
				draw_line(ap - dir * 12.0 + o, ap + o, Color(col, 0.7), 2.0)
				draw_line(ap - dir * 12.0 - o, ap - o, Color(col, 0.7), 2.0)
		"tracer":
			draw_line(from, to, Color(1, 1, 0.8, a), 2.0 * a + 1.0)
			draw_circle(from + dir * 12.0, 7.0 * a, Color(1, 0.9, 0.5, a))
			draw_circle(to, 9.0 * a, Color(col.lightened(0.4), a))
		"lob", "coin", "flask":
			var lp := from.lerp(to, k) + Vector2(0, -sin(k * PI) * 46.0)
			if fx["style"] == "lob":
				draw_circle(lp, 5.0 * sc, Color(0.55, 0.5, 0.45))
				draw_circle(lp + Vector2(-1.5, -1.5), 2.0, Color(0.8, 0.75, 0.7))
			elif fx["style"] == "coin":
				draw_set_transform(lp, 0.0, Vector2(maxf(0.2, absf(cos(k * 20.0))), 1.0))
				draw_circle(Vector2.ZERO, 6.0 * sc, Color(1, 0.8, 0.15))
				draw_circle(Vector2.ZERO, 3.5 * sc, Color(1, 0.95, 0.5))
				draw_set_transform(Vector2.ZERO)
			else:
				draw_rect(Rect2(lp - Vector2(2, 9), Vector2(4, 5)), Color(0.8, 0.8, 0.9))
				draw_circle(lp, 5.5, Color(0.4, 1.0, 0.45))
			if k > 0.82:
				var ib := (k - 0.82) / 0.18
				var sc_col := Color(0.4, 1.0, 0.45) if fx["style"] == "flask" else (Color(1, 0.85, 0.3) if fx["style"] == "coin" else Color(0.75, 0.7, 0.6))
				draw_circle(to, 16.0 * ib * sc + 3.0, Color(sc_col, 0.5 * (1.0 - ib)))
		"orb", "clockwork":
			var op := from.lerp(to, k)
			for tr in 4:
				draw_circle(op - dir * tr * 6.0, (6.0 - tr * 1.2) * sc, Color(col.lightened(0.3), 0.8 - tr * 0.18))
			draw_circle(op, 3.0 * sc, Color(1, 1, 1))
			if fx["style"] == "clockwork":
				draw_arc(op, 10.0 * sc, k * 12.0, k * 12.0 + PI, 10, Color(0.8, 1, 1, 0.9), 2.0)
		"fireball":
			var fp := from.lerp(to, minf(1.0, k * 1.15))
			for tr in 5:
				draw_circle(fp - dir * tr * 7.0 + Vector2(0, sin(sd + tr) * 2.0), (7.0 - tr * 1.2) * sc, Color(1, 0.35 + tr * 0.12, 0.05, 0.9 - tr * 0.16))
			draw_circle(fp, 3.5 * sc, Color(1, 0.95, 0.6))
			if k > 0.85:
				var ib := (k - 0.85) / 0.15
				draw_circle(to, 20.0 * ib * sc + 4.0, Color(1, 0.5, 0.1, 0.6 * (1.0 - ib)))
		"ice":
			var ip := from.lerp(to, k)
			var o := dir.orthogonal() * 4.0 * sc
			draw_colored_polygon(PackedVector2Array([ip + dir * 9.0 * sc, ip + o, ip - dir * 7.0 * sc, ip - o]), Color(0.75, 0.95, 1.0))
			draw_line(ip - dir * 18.0, ip - dir * 7.0, Color(0.7, 0.9, 1.0, 0.5), 2.0)
			if k > 0.8:
				var ib := (k - 0.8) / 0.2
				for j in 3:
					var d := Vector2.from_angle(j * PI / 3.0) * 11.0 * sc * (0.5 + ib)
					draw_line(to - d, to + d, Color(0.85, 1, 1, 1.0 - ib), 2.0)
		"zap":
			var zp := PackedVector2Array([from])
			for j in range(1, 5):
				zp.append(from.lerp(to, j / 5.0) + dir.orthogonal() * sin(sd * 7.0 + j * 2.3 + k * 30.0) * 9.0)
			zp.append(to)
			draw_polyline(zp, Color(0.6, 0.9, 1.0, a), 4.0 * sc)
			draw_polyline(zp, Color(1, 1, 1, a), 1.5)
		"note":
			var np := from.lerp(to, k) + dir.orthogonal() * sin(k * TAU * 1.5) * 12.0
			draw_circle(np, 4.0 * sc, Color(col.lightened(0.3), 0.95))
			draw_line(np + Vector2(3.5, 0), np + Vector2(3.5, -13), Color(col.lightened(0.3), 0.95), 2.0)
			draw_line(np + Vector2(3.5, -13), np + Vector2(9, -9), Color(col.lightened(0.3), 0.95), 2.0)
		"holy":
			var ha := sin(k * PI)
			draw_rect(Rect2(to + Vector2(-8 * sc, -120), Vector2(16 * sc, 120)), Color(1, 0.95, 0.6, 0.35 * ha))
			draw_rect(Rect2(to + Vector2(-3 * sc, -120), Vector2(6 * sc, 120)), Color(1, 1, 0.9, 0.7 * ha))
			draw_arc(to, 14.0 * sc, 0, TAU, 20, Color(1, 0.95, 0.6, ha), 3.0)
		"lance":
			var lpn := from.lerp(to, minf(1.0, k * 1.6))
			draw_line(from + dir * 10.0, lpn, Color(col.lightened(0.3), a), 5.0 * sc)
			for j in 2:
				var wo := dir.orthogonal() * (8.0 + j * 6.0) * (1 if j == 0 else -1)
				draw_line(lpn - dir * 30.0 + wo, lpn - dir * 10.0 + wo, Color(0.9, 0.95, 1, a * 0.6), 2.0)
		"scythe":
			var ca := dir.angle() + PI * 0.5 + k * 2.5
			draw_arc(to, 22.0 * sc, ca, ca + PI * 0.9, 16, Color(col.lightened(0.2), a), 6.0)
			draw_arc(to, 16.0 * sc, ca + 0.1, ca + PI * 0.8, 12, Color(0.15, 0.0, 0.25, a), 3.0)
		_:
			var p := from.lerp(to, k)
			draw_circle(p, 4.0, col)


func _draw_chests() -> void:
	for ch in chests:
		var p: Vector2 = ch["pos"] + Vector2(0, sin(_anim * 5.0) * 3.0)
		var blink: bool = ch["t"] < 2.0 and fmod(_anim, 0.3) < 0.15
		if blink:
			continue
		draw_circle(p, 20.0, Color(1, 0.85, 0.3, 0.25))
		Glyphs.draw_icon(self, "chest", p, 14.0, Color.WHITE)


func _draw_texts() -> void:
	for t in texts:
		var k: float = t["t"] / t["dur"]
		var col: Color = t["color"]
		col.a = 1.0 - k * k
		_text(t["pos"] + Vector2(0, -30.0 * k), t["text"], t["size"], col)


func _draw_reveal() -> void:
	## 가챠 연출: 가운데에서 빛줄기와 함께 커졌다가 칸으로 날아감
	for fx in effects:
		if fx["type"] != "reveal":
			continue
		var k: float = fx["t"] / fx["dur"]
		var col: Color = fx["color"]
		var rarity: int = fx["rarity"]
		var center := Vector2(SIZE / 2, SIZE / 2)
		var hold := 0.72
		var a := 1.0 if k < hold else 1.0 - (k - hold) / (1.0 - hold)
		draw_rect(Rect2(0, 0, SIZE, SIZE), Color(0, 0, 0, 0.5 * a))
		var rays := 10 + rarity * 4
		var rot: float = fx["t"] * (1.2 + rarity * 0.4)
		for n in rays:
			var ang := rot + TAU * n / rays
			var len := 260.0 * minf(1.0, k * 3.0)
			var w := 0.09
			draw_colored_polygon(PackedVector2Array([center, center + Vector2.from_angle(ang - w) * len, center + Vector2.from_angle(ang + w) * len]), Color(col, 0.22 * a))
		var grow := minf(1.0, k / 0.25)
		var bounce := 1.0 + 0.25 * sin(minf(1.0, k / 0.35) * PI)
		var pos := center
		var scale_r := 60.0 * grow * bounce
		if k > hold:
			var q := (k - hold) / (1.0 - hold)
			pos = center.lerp(fx["pos"], q * q)
			scale_r = lerpf(60.0, CELL * 0.26, q)
		draw_circle(pos, scale_r * 1.5, Color(col, 0.25 * a))
		Glyphs.draw_unit_token(self, fx["id"], pos, scale_r, _anim)
		if k < hold:
			_text(center + Vector2(0, 110), GameData.RARITY_NAMES[rarity] + "!", 34 + rarity * 4, Color(col, a))
			_text(center + Vector2(0, 150), GameData.UNITS[fx["id"]]["name"], 20, Color(1, 1, 1, a))


func _draw_combo() -> void:
	if combo < 5 or not alive:
		return
	# 전장 가운데 크게. 처치할 때마다 튀고, 콤보가 끊길 때가 다가오면 흐려진다 (유닛을 가리지 않게 반투명)
	var s := 1.0 + combo_pop * 0.4
	var col := Color(1, 0.85, 0.3).lerp(Color(1, 0.3, 0.2), clampf(combo / 100.0, 0.0, 1.0))
	var a := clampf(_combo_t / GameData.COMBO_WINDOW, 0.25, 1.0) * 0.85
	var c := Vector2(SIZE * 0.5, SIZE * (0.26 if banner_t > 0.0 else 0.44))
	_text(c + Vector2(0, -34 * s), "COMBO", int(20 * s), Color(col, a))
	_text(c + Vector2(0, 8), str(combo), int(58 * s), Color(col, a))
	# 콤보 시간 게이지
	var gw := 120.0
	draw_rect(Rect2(c + Vector2(-gw / 2, 44), Vector2(gw, 5)), Color(0, 0, 0, 0.5 * a))
	draw_rect(Rect2(c + Vector2(-gw / 2, 44), Vector2(gw * clampf(_combo_t / GameData.COMBO_WINDOW, 0.0, 1.0), 5)), Color(col, a))


func _draw_boss_warning() -> void:
	# 한도 임박: 붉은 가장자리 (심장 박동과 함께)
	var danger := float(field_count() + partner_count) / enemy_limit
	if danger >= 0.8 and alive:
		var beat := 0.5 + 0.5 * sin(_anim * 7.5)
		var da := clampf((danger - 0.8) / 0.2, 0.0, 1.0) * (0.35 + 0.35 * beat)
		for w in 5:
			draw_rect(Rect2(w * 6, w * 6, SIZE - w * 12, SIZE - w * 12), Color(1, 0.05, 0.05, da * (1.0 - w * 0.18)), false, 6.0)
	# 피버: 금빛 테두리
	if fever_t > 0.0:
		var fp := 0.5 + 0.5 * sin(_anim * 10.0)
		draw_rect(Rect2(2, 2, SIZE - 4, SIZE - 4), Color(1, 0.75, 0.2, 0.5 + 0.4 * fp), false, 5.0)
	# 진행 중인 위기: 일식은 어둡게, 폭주는 붉은 속도선
	if eclipse_t > 0.0:
		draw_rect(Rect2(0, 0, SIZE, SIZE), Color(0.08, 0.0, 0.15, 0.28))
		draw_circle(Vector2(SIZE - 60, 60), 26, Color(0.05, 0.0, 0.1, 0.9))
		draw_arc(Vector2(SIZE - 60, 60), 27, 0, TAU, 32, Color(1, 0.8, 0.4, 0.8), 3.0)
	if rush_t > 0.0 or horde:
		var pulse2 := 0.5 + 0.5 * sin(_anim * 8.0)
		draw_rect(Rect2(0, 0, SIZE, SIZE), Color(1, 0.15, 0.1, 0.25 + 0.3 * pulse2), false, 6.0)
		for j in 6:
			var ly := fmod(_anim * 400.0 + j * 97.0, SIZE)
			draw_line(Vector2(8, ly), Vector2(8, ly + 30), Color(1, 0.4, 0.3, 0.6), 3.0)
			draw_line(Vector2(SIZE - 8, SIZE - ly), Vector2(SIZE - 8, SIZE - ly - 30), Color(1, 0.4, 0.3, 0.6), 3.0)
	if boss_warn_t <= 0.0:
		return
	var pulse := 0.5 + 0.5 * sin(boss_warn_t * 14.0)
	var a := clampf(boss_warn_t, 0.0, 1.0) * (0.3 + 0.4 * pulse)
	for w in 4:
		draw_rect(Rect2(w * 6, w * 6, SIZE - w * 12, SIZE - w * 12), Color(1, 0.1, 0.15, a * (1.0 - w * 0.22)), false, 6.0)
	_text(Vector2(SIZE / 2, 32), "WARNING", 30, Color(1, 0.25, 0.3, a * 1.6))


func _draw_countdown() -> void:
	## 라운드 마지막 5초 큰 카운트다운 (유즈맵 스타일)
	if not alive or wave_timer > 5.0 or wave_timer <= 0.0 or (final_cleared_flag and mode != "pvp"):
		return
	var boss := is_boss_round(wave)
	var boss_alive := false
	if boss:
		for e in enemies:
			if e.alive and e.is_boss:
				boss_alive = true
		if not boss_alive:
			return
	var n := int(ceil(wave_timer))
	var frac := wave_timer - floorf(wave_timer)
	var col := Color(1, 0.25, 0.3) if boss else Color(1, 1, 1)
	col.a = 0.25 + 0.5 * frac
	_text(Vector2(SIZE / 2, SIZE / 2 + 60), str(n), int(90 + 40 * frac), col)
	if boss:
		_text(Vector2(SIZE / 2, SIZE / 2 + 130), "보스 제한시간!", 20, Color(1, 0.4, 0.4, 0.9))


func _draw_banner() -> void:
	if banner_t <= 0.0:
		return
	var a := clampf(banner_t / 0.4, 0.0, 1.0)
	var scale_in := 1.0 + maxf(0.0, banner_t - 2.1) * 1.5
	var y := SIZE * 0.5
	draw_rect(Rect2(56, y - 42, SIZE - 112, 84), Color(0, 0, 0, 0.55 * a))
	var col := banner_color
	col.a = a
	_text(Vector2(SIZE / 2, y - 10), banner, int(30 * scale_in), col)
	if banner_sub != "":
		_text(Vector2(SIZE / 2, y + 22), banner_sub, 17, Color(1, 1, 1, a))
