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
const ROWS := 4
const CELL := 72.0
const GRID_ORIGIN := Vector2(64.0, 204.0)
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
var wave_timer := 5.0
var spawn_left := 0
var spawn_t := 0.0
var kills := 0
var free_summons := 0
var lucky_t := 0.0
var curse_t := 0.0
var frenzy := false
var gauge := 0
var alive := true
var final_cleared_flag := false
var missions := {}
var gamble_wins := 0
var gamble_lose_streak := 0
var chests_opened := 0
var dmg_by_unit := {}
var time_alive := 0.0
var selected := -1
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
	return {"id": "", "n": 0, "timers": [0.0, 0.0, 0.0], "ramp": 0, "last": null, "hits": 0, "skill_t": 0.0}


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
		if c["id"] == "" or (c["id"] == id and c["n"] < GameData.MAX_STACK):
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


func dmg_mult(rarity: int) -> float:
	var lvl := 0
	for t in 3:
		if rarity in GameData.UPGRADES[t]["rarities"]:
			lvl = upgrades[t]
	return 1.0 + GameData.UPGRADE_DMG_PER_LEVEL * lvl


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
		float_text(Vector2(SIZE / 2, 170), "골드 부족!", Color(1, 0.4, 0.4))
		return false
	var rarity := GameData.roll_summon_rarity(rng, upgrades[3])
	var id := GameData.random_unit_of(rng, rarity)
	if not has_space_for(id):
		float_text(Vector2(SIZE / 2, 170), "빈 칸이 없어요!", Color(1, 0.4, 0.4))
		return false
	if free:
		free_summons -= 1
	else:
		gold -= cost
		summon_count += 1
	var idx := add_unit(id)
	if rarity >= GameData.Rarity.EPIC:
		_rare_pull_fx(idx, rarity)
	return true


func add_unit(id: String) -> int:
	## 같은 유닛 스택(3 미만) 우선, 없으면 빈칸. 실패 시 -1
	var target := -1
	for i in cells.size():
		if cells[i]["id"] == id and cells[i]["n"] < GameData.MAX_STACK:
			target = i
			break
	if target < 0:
		var empties: Array = []
		for i in cells.size():
			if cells[i]["id"] == "":
				empties.append(i)
		if empties.is_empty():
			return -1
		target = empties[rng.randi() % empties.size()]
		cells[target] = _empty_cell()
		cells[target]["id"] = id
	var c: Dictionary = cells[target]
	c["timers"][c["n"]] = rng.randf() * 0.3
	c["n"] += 1
	var col: Color = GameData.RARITY_COLORS[GameData.UNITS[id]["rarity"]]
	_add_effect({"type": "ring", "pos": cell_center(target), "r0": 6.0, "r1": 40.0, "t": 0.0, "dur": 0.35, "color": col})
	_check_missions_now()
	return target


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
	var id := GameData.random_unit_of(rng, rarity + 1)
	var idx := add_unit(id)
	if selected == i and cells[i]["id"] == "":
		selected = idx
	float_text(cell_center(idx), "합성! %s" % GameData.UNITS[id]["name"], GameData.RARITY_COLORS[rarity + 1])
	if rarity + 1 >= GameData.Rarity.LEGEND:
		_rare_pull_fx(idx, rarity + 1)
	return true


func auto_merge() -> bool:
	## 가장 낮은 등급의 합성 가능한 칸부터 합성
	var best := -1
	for i in cells.size():
		if mergeable(i):
			if best < 0 or GameData.UNITS[cells[i]["id"]]["rarity"] < GameData.UNITS[cells[best]["id"]]["rarity"]:
				best = i
	if best < 0:
		return false
	return merge_cell(best)


func combine(mythic: String) -> bool:
	if not alive or not can_combine(mythic):
		return false
	var need := {}
	for m in GameData.RECIPES[mythic]:
		need[m] = need.get(m, 0) + 1
	for k in need:
		remove_units(k, need[k])
	var idx := add_unit(mythic)
	_rare_pull_fx(idx, GameData.Rarity.MYTHIC)
	show_banner("신화 강림!", GameData.UNITS[mythic]["name"], GameData.RARITY_COLORS[4])
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
	var d: Dictionary = GameData.GAMBLES[g]
	if gems < d["gems"]:
		float_text(Vector2(SIZE / 2, 170), "보석 부족!", Color(1, 0.4, 0.4))
		return false
	var probe: String = GameData.units_of_rarity(d["rarity"])[0]
	if used_cells() >= cells.size() and not has_space_for(probe):
		float_text(Vector2(SIZE / 2, 170), "빈 칸이 없어요!", Color(1, 0.4, 0.4))
		return false
	gems -= d["gems"]
	if rng.randf() < d["chance"]:
		var id := GameData.random_unit_of(rng, d["rarity"])
		var idx := add_unit(id)
		if idx < 0:
			gems += d["gems"]
			return false
		gamble_wins += 1
		gamble_lose_streak = 0
		_rare_pull_fx(idx, d["rarity"])
		float_text(cell_center(idx), "대박! %s" % GameData.UNITS[id]["name"], GameData.RARITY_COLORS[d["rarity"]])
		if gamble_wins >= 3:
			_complete_mission("gamble_win3")
	else:
		gamble_lose_streak += 1
		var lines := ["꽝!", "다음엔 될 거야...", "운이 없네요", "보석이 증발했다", "하... 꽝"]
		float_text(Vector2(SIZE / 2, 175), lines[rng.randi() % lines.size()], Color(0.7, 0.7, 0.75), 20)
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
	float_text(Vector2(SIZE / 2, 170), "%s 강화 Lv.%d" % [GameData.UPGRADES[track]["name"], upgrades[track]], Color(0.6, 1.0, 0.6))
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
	if not alive:
		return false
	for a in GameData.ATTACKS:
		if a["id"] == attack_id:
			if gold < a["gold"] or gems < a["gems"]:
				float_text(Vector2(SIZE / 2, 170), "재화 부족!", Color(1, 0.4, 0.4))
				return false
			gold -= a["gold"]
			gems -= a["gems"]
			float_text(Vector2(SIZE / 2, 170), "%s 발사!" % a["name"], Color(1, 0.5, 0.3), 20)
			action_attack.emit(self, attack_id)
			return true
	return false


func request_gift_gold(amount: int) -> bool:
	if not alive or gold < amount:
		return false
	gold -= amount
	float_text(Vector2(SIZE / 2, 170), "골드 %d 선물!" % amount, Color(1, 0.9, 0.3))
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
func receive_attack(attack_id: String) -> void:
	if not alive or is_remote:
		return
	var w := maxi(wave, 1)
	match attack_id:
		"swarm":
			for k in 6:
				_spawn("fast", GameData.wave_hp(w), -k * 18.0)
			show_banner("적이 몰려온다!", "상대가 잡몹 떼를 보냈습니다", Color(1, 0.5, 0.3))
		"elite":
			_spawn("elite", GameData.wave_hp(w), 0.0)
			show_banner("정예 괴수 습격!", "상대가 정예를 보냈습니다", Color(1, 0.3, 0.3))
		"curse":
			curse_t = 10.0
			show_banner("저주에 걸렸다!", "10초간 공격 속도 -30%", Color(0.7, 0.4, 1.0))
	shake = 8.0


func receive_gold(amount: int) -> void:
	if is_remote:
		return
	gold += amount
	float_text(Vector2(SIZE / 2, 170), "파트너 선물 +%dG" % amount, Color(1, 0.9, 0.3), 20)


func receive_unit(id: String) -> bool:
	if is_remote:
		return true
	var idx := add_unit(id)
	if idx < 0:
		# 자리가 없으면 판매 가격으로 환급
		var r: int = GameData.UNITS[id]["rarity"]
		gold += GameData.SELL_GOLD[r] * 2
		gems += maxi(GameData.SELL_GEMS[r], 1 if r >= 3 else 0)
		float_text(Vector2(SIZE / 2, 170), "자리 부족 - 환급받음", Color(1, 0.8, 0.4))
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
	curse_t = maxf(0.0, curse_t - dt)
	_update_waves(dt)
	_update_enemies(dt)
	_update_units(dt)
	_update_chests(dt)
	_cleanup()
	_mission_t -= dt
	if _mission_t <= 0.0:
		_mission_t = 0.5
		_check_missions_now()


func _update_waves(dt: float) -> void:
	var final_hold := mode != "pvp" and wave >= GameData.FINAL_WAVE
	if not final_hold:
		wave_timer -= dt
		if wave_timer <= 0.0:
			_end_wave()
			_start_wave(wave + 1)
	if spawn_left > 0:
		spawn_t -= dt
		if spawn_t <= 0.0:
			spawn_t = GameData.SPAWN_INTERVAL
			spawn_left -= 1
			_spawn(GameData.pick_enemy(rng, wave), GameData.wave_hp(wave), 0.0)


func _end_wave() -> void:
	frenzy = false
	if wave <= 0:
		return
	if GameData.is_boss_wave(wave):
		for e in enemies:
			if e.alive and e.is_boss and not e.enraged:
				e.enraged = true
				e.speed *= 1.3
				show_banner("보스 격노!", "처치 실패 - 필드 가중치 2배", Color(1, 0.2, 0.2))
	else:
		var bonus := 10 + wave * 2
		gold += bonus
		float_text(Vector2(SIZE / 2, 150), "웨이브 보너스 +%dG" % bonus, Color(1, 0.9, 0.3))


func _start_wave(w: int) -> void:
	wave = w
	if GameData.is_boss_wave(w):
		wave_timer = GameData.BOSS_WAVE_TIME
		spawn_left = 0
		var b: EnemyState = _spawn("boss", GameData.wave_hp(w), 0.0)
		b.boss_name = GameData.BOSS_NAMES[(w / 10 - 1) % GameData.BOSS_NAMES.size()]
		show_banner("WAVE %d - 보스!" % w, "%s 등장 (%d초 안에 처치)" % [b.boss_name, int(GameData.BOSS_WAVE_TIME)], Color(1, 0.3, 0.5))
	else:
		wave_timer = GameData.WAVE_TIME
		spawn_left = GameData.SPAWN_PER_WAVE
		spawn_t = 0.0
		if w % 5 != 0:
			show_banner("WAVE %d" % w, "", Color(0.9, 0.9, 1.0))
	if w % 5 == 0:
		_random_event()


func _random_event() -> void:
	var pool: Array = GameData.EVENTS.duplicate()
	if GameData.is_boss_wave(wave):
		pool = pool.filter(func(ev): return ev["id"] != "frenzy")
	var ev: Dictionary = pool[event_rng.randi() % pool.size()]
	show_banner(ev["name"], ev["desc"], Color(1.0, 0.85, 0.3))
	match ev["id"]:
		"goblin":
			_spawn("goblin", GameData.wave_hp(wave), 0.0)
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
		var spd: float = e.speed * (1.0 - maxf(e.slow, e.aura_slow))
		if frenzy:
			spd *= 1.3
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


func _update_units(dt: float) -> void:
	var speed_mult := 0.7 if curse_t > 0.0 else 1.0
	for i in cells.size():
		var c: Dictionary = cells[i]
		if c["id"] == "":
			continue
		var u: Dictionary = GameData.UNITS[c["id"]]
		var fx: Dictionary = u["fx"]
		var center := cell_center(i)
		var rng_sq: float = u["range"] * u["range"]
		# 수호천사: 사거리 내 적 둔화 오라
		if fx.has("slow_aura"):
			for e in enemies:
				if e.alive and e.pos.distance_squared_to(center) <= rng_sq:
					e.aura_slow = maxf(e.aura_slow, fx["slow_aura"])
		# 신화 스킬
		if u.has("skill"):
			c["skill_t"] += dt
			if c["skill_t"] >= u["skill"]["cd"] and _has_target_near(center, INF):
				c["skill_t"] = 0.0
				_cast_skill(i, c, u)
		var spd := speed_mult * (1.0 + _aura_speed(i))
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
			_attack(i, c, u, target)


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


func _attack(i: int, c: Dictionary, u: Dictionary, target: EnemyState) -> void:
	var fx: Dictionary = u["fx"]
	var center := cell_center(i)
	var id: String = c["id"]
	var base: float = u["dmg"] * dmg_mult(u["rarity"])
	var col: Color = u["color"]
	# 광전사 가속
	if fx.has("ramp"):
		if c["last"] == target:
			c["ramp"] = mini(c["ramp"] + 1, fx["ramp_max"])
		else:
			c["ramp"] = 0
		c["last"] = target
	var targets: Array = [target]
	if fx.has("multishot"):
		targets = _targets_in_range(center, u["range"] * u["range"], fx["multishot"])
	for t in targets:
		var dmg := base
		var crit := false
		if fx.has("crit") and rng.randf() < fx["crit"]:
			dmg *= fx["crit_mult"]
			crit = true
		_add_effect({"type": "shot", "from": center, "to": t.pos, "t": 0.0, "dur": 0.12, "color": col, "big": u["rarity"] >= 3})
		_hit(t, dmg, id, fx, crit)
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
				_hit(nxt, cdmg, id, {}, false)
				hit_list.append(nxt)
				prev = nxt
	# 메테오
	if fx.has("meteor_every"):
		c["hits"] += 1
		if c["hits"] >= fx["meteor_every"]:
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
	if fx.has("execute") and t.alive and not t.is_boss and t.kind != "elite" and t.hp_ratio() <= fx["execute"]:
		float_text(t.pos + Vector2(0, -16), "처형!", Color(0.8, 0.4, 1.0), 14)
		_damage(t, t.hp + t.shield + 1.0, id, false, true)
	if crit:
		float_text(t.pos + Vector2(rng.randf_range(-8, 8), -18), "치명! %d" % int(dmg), Color(1, 0.35, 0.3), 14)


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
	gauge = mini(gauge + 1, GameData.COOP_BLAST_NEED)
	var g := 1 + wave / 10
	match e.kind:
		"boss":
			g = 100 + wave * 10
			var gm := 3 + wave / 10
			gems += gm
			show_banner("보스 처치!", "+%d 골드  +%d 보석" % [g, gm], Color(1, 0.85, 0.3))
			_flash(Color(1, 0.9, 0.5), 0.5)
			shake = 14.0
			if wave >= GameData.FINAL_WAVE and mode != "pvp" and not final_cleared_flag:
				final_cleared_flag = true
				final_cleared.emit(self)
		"elite":
			g = 40
			gems += 1
		"goblin":
			g = 80 + wave * 5
			gems += 2
			show_banner("고블린 사냥 성공!", "+%d 골드  +2 보석" % g, Color(1, 0.9, 0.2))
	gold += g
	for n in e.split:
		var m := _spawn("mini", e.max_hp / GameData.ENEMIES["splitter"]["hp"], e.dist - 10.0 * n)
		m.pos = path_pos(m.dist)
	_add_effect({"type": "pop", "pos": e.pos, "r": e.size * 1.8, "t": 0.0, "dur": 0.25, "color": e.color})
	if rng.randf() < CHEST_CHANCE and chests.size() < 3:
		chests.append({"pos": e.pos, "t": 8.0})


func _cast_skill(i: int, c: Dictionary, u: Dictionary) -> void:
	var center := cell_center(i)
	var n: int = c["n"]
	var base: float = u["dmg"] * dmg_mult(u["rarity"])
	var sid: String = u["skill"]["id"]
	float_text(center + Vector2(0, -30), u["skill"]["name"] + "!", u["color"], 18)
	match sid:
		"firestorm":
			_add_effect({"type": "boom", "pos": center, "r": u["range"], "t": 0.0, "dur": 0.7, "color": Color(1, 0.4, 0.1)})
			for e in enemies:
				if e.alive and e.pos.distance_to(center) <= u["range"]:
					e.burn_dps = maxf(e.burn_dps, base)
					e.burn_t = 4.0
					_damage(e, base * 5.0 * n, c["id"], true)
			shake = 10.0
		"judgement":
			_flash(Color(1, 1, 0.6), 0.35)
			for e in enemies:
				if e.alive:
					_add_effect({"type": "bolt", "from": e.pos + Vector2(0, -80), "to": e.pos, "t": 0.0, "dur": 0.25, "color": Color(1, 1, 0.4)})
					e.stun_t = maxf(e.stun_t, 0.25 if e.is_boss else 0.5)
					_damage(e, base * 2.0 * n, c["id"], false)
			shake = 8.0
		"timestop":
			_flash(Color(0.4, 0.9, 1.0), 0.6)
			for e in enemies:
				if e.alive:
					e.stun_t = maxf(e.stun_t, 1.2 if e.is_boss else 2.5)
		"goldrain":
			var g := mini(int(gold * 0.1) + 20, 250) * n
			gold += g
			float_text(center, "황금비 +%dG" % g, Color(1, 0.9, 0.2), 20)
			_add_effect({"type": "ring", "pos": center, "r0": 10.0, "r1": 200.0, "t": 0.0, "dur": 0.7, "color": Color(1, 0.85, 0.2)})
		"reap":
			var list: Array = []
			for e in enemies:
				if e.alive:
					list.append(e)
			list.sort_custom(func(a, b): return a.hp > b.hp)
			var reaped := 0
			for e in list:
				if reaped >= 3 * n:
					break
				_add_effect({"type": "pop", "pos": e.pos, "r": 30.0, "t": 0.0, "dur": 0.5, "color": Color(0.6, 0.2, 0.8)})
				if e.is_boss or e.kind == "elite":
					_damage(e, base * 8.0, c["id"], true)
				else:
					_damage(e, e.hp + e.shield + 1.0, c["id"], false, true)
				reaped += 1


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
	if used_cells() >= 18:
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
			float_text(Vector2(SIZE / 2, 130), "과제 달성: %s %s" % [m["name"], " ".join(reward)], Color(0.5, 1.0, 0.7), 16)


# ===========================================================================
# 네트워크 스냅샷
# ===========================================================================
func snapshot() -> Dictionary:
	var c := PackedInt32Array()
	for cell in cells:
		if cell["id"] == "":
			c.append(-1)
		else:
			c.append(GameData.unit_index(cell["id"]) * 4 + cell["n"])
	# 적 1마리 = int32 2개 (위치 / 종류+체력+상태) 로 압축
	var e := PackedInt32Array()
	for en in enemies:
		if en.alive:
			e.append(int(en.pos.x) | (int(en.pos.y) << 16))
			e.append(GameData.enemy_index(en.kind) | (int(en.hp_ratio() * 255.0) << 8) | (en.status_flags() << 16))
	return {
		"c": c, "e": e, "g": gold, "m": gems, "w": wave, "t": wave_timer, "k": kills,
		"f": field_count(), "a": alive, "fc": final_cleared_flag, "sc": summon_cost(),
		"u": upgrades, "ga": gauge,
	}


func apply_snapshot(d: Dictionary) -> void:
	remote_stats = d
	gold = d.get("g", 0)
	gems = d.get("m", 0)
	wave = d.get("w", 0)
	wave_timer = d.get("t", 0.0)
	kills = d.get("k", 0)
	final_cleared_flag = d.get("fc", false)
	upgrades = d.get("u", [0, 0, 0, 0])
	gauge = d.get("ga", 0)
	var c: PackedInt32Array = d.get("c", PackedInt32Array())
	for i in mini(c.size(), cells.size()):
		if c[i] < 0:
			cells[i]["id"] = ""
			cells[i]["n"] = 0
		else:
			cells[i]["id"] = GameData.UNIT_ORDER[c[i] / 4]
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
	if alive and not d.get("a", true):
		alive = false


# ===========================================================================
# 시각 효과
# ===========================================================================
func float_text(p: Vector2, text: String, color: Color, fsize := 14) -> void:
	texts.append({"pos": p, "text": text, "color": color, "t": 0.0, "dur": 1.1, "size": fsize})
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
	if effects.size() < 220:
		effects.append(fx)


func _rare_pull_fx(idx: int, rarity: int) -> void:
	if idx < 0:
		return
	var col: Color = GameData.RARITY_COLORS[rarity]
	_add_effect({"type": "ring", "pos": cell_center(idx), "r0": 10.0, "r1": 110.0, "t": 0.0, "dur": 0.7, "color": col})
	_add_effect({"type": "beam", "pos": cell_center(idx), "t": 0.0, "dur": 0.8, "color": col})
	if rarity >= GameData.Rarity.LEGEND:
		_flash(col, 0.3)
		shake = maxf(shake, 6.0)
		show_banner("%s 등급 획득!" % GameData.RARITY_NAMES[rarity], GameData.UNITS[cells[idx]["id"]]["name"], col)


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
	draw_set_transform(off)
	_draw_field()
	_draw_info()
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
	_draw_banner()
	if not alive:
		draw_rect(Rect2(0, 0, SIZE, SIZE), Color(0, 0, 0, 0.6))
		_text(Vector2(SIZE / 2, SIZE / 2), "패배", 56, Color(1, 0.3, 0.3))
	elif final_cleared_flag and mode != "pvp":
		_text(Vector2(SIZE / 2, 110), "최종 보스 격파!", 22, Color(1, 0.9, 0.4))


func _text(center: Vector2, s: String, fsize: int, color: Color, outline := true) -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var p := center + Vector2(-w / 2.0, fsize * 0.35)
	if outline:
		draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, 4, Color(0, 0, 0, 0.85))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, color)


func _draw_field() -> void:
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
	draw_circle(Vector2(INSET, INSET), 16.0, Color(0.6, 0.1, 0.15, 0.7))
	_text(Vector2(INSET, INSET), "!", 18, Color(1, 0.8, 0.8))


func _draw_info() -> void:
	var count := field_count()
	var limit := enemy_limit
	var shown := count + (partner_count if mode == "coop" else 0)
	_text(Vector2(SIZE / 2, 74), player_name, 15, accent.lightened(0.3))
	var wave_s := "WAVE %d" % wave if wave > 0 else "준비"
	_text(Vector2(150, 102), wave_s, 22, Color(0.95, 0.95, 1.0))
	var tsec := maxi(0, int(ceil(wave_timer)))
	_text(Vector2(150, 128), "%02d:%02d" % [tsec / 60, tsec % 60], 16, Color(0.75, 0.8, 0.9))
	# 적 수 게이지
	var ratio := clampf(float(shown) / limit, 0.0, 1.0)
	var bar := Rect2(260, 90, 230, 18)
	draw_rect(bar, Color(0.05, 0.05, 0.08))
	var bc := Color(0.4, 0.85, 0.4).lerp(Color(1, 0.2, 0.2), ratio)
	if ratio > 0.8 and fmod(_anim, 0.5) < 0.25:
		bc = Color(1, 1, 1)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * ratio, bar.size.y)), bc)
	draw_rect(bar, Color(1, 1, 1, 0.3), false, 1.0)
	var label := ("적 %d / %d" % [shown, limit]) if mode != "coop" else ("합산 적 %d / %d" % [shown, limit])
	_text(bar.get_center() + Vector2(0, 0), label, 13, Color.WHITE)
	# 보스 체력바
	for e in enemies:
		if e.alive and e.is_boss:
			var r := Rect2(260, 120, 230, 12)
			draw_rect(r, Color(0.1, 0.02, 0.05))
			draw_rect(Rect2(r.position, Vector2(r.size.x * e.hp_ratio(), r.size.y)), Color(0.85, 0.15, 0.4))
			_text(r.get_center() + Vector2(0, 16), (e.boss_name if e.boss_name != "" else "보스") + (" (격노)" if e.enraged else ""), 12, Color(1, 0.6, 0.7))
			break
	# 상태 아이콘
	var status := []
	if lucky_t > 0.0:
		status.append("행운 %ds" % int(ceil(lucky_t)))
	if curse_t > 0.0:
		status.append("저주 %ds" % int(ceil(curse_t)))
	if frenzy:
		status.append("광란")
	if free_summons > 0:
		status.append("무료소환 %d" % free_summons)
	if not status.is_empty():
		_text(Vector2(SIZE / 2, 176), "  ".join(status), 13, Color(1, 0.85, 0.5))


func _draw_grid() -> void:
	for i in cells.size():
		var center := cell_center(i)
		var rect := Rect2(center - Vector2(CELL, CELL) / 2 + Vector2(3, 3), Vector2(CELL - 6, CELL - 6))
		var c: Dictionary = cells[i]
		var bg := Color(0.17, 0.19, 0.25)
		if c["id"] != "":
			var rc: Color = GameData.RARITY_COLORS[GameData.UNITS[c["id"]]["rarity"]]
			bg = bg.lerp(rc, 0.12)
		draw_rect(rect, bg)
		if not is_remote and mergeable(i):
			var pulse := 0.5 + 0.5 * sin(_anim * 6.0)
			draw_rect(rect, Color(1, 1, 0.5, 0.35 + 0.4 * pulse), false, 3.0)
		else:
			draw_rect(rect, Color(1, 1, 1, 0.08), false, 1.0)
		if c["id"] != "":
			_draw_unit_stack(center, c)
	if selected >= 0 and selected < cells.size() and cells[selected]["id"] != "":
		var sc := cell_center(selected)
		var u: Dictionary = GameData.UNITS[cells[selected]["id"]]
		draw_arc(sc, u["range"], 0, TAU, 64, Color(1, 1, 1, 0.35), 2.0)
		draw_rect(Rect2(sc - Vector2(CELL, CELL) / 2, Vector2(CELL, CELL)), Color(1, 1, 1, 0.9), false, 3.0)
	if show_cursor:
		var cc := cell_center(cursor)
		draw_rect(Rect2(cc - Vector2(CELL, CELL) / 2 + Vector2(1, 1), Vector2(CELL - 2, CELL - 2)), accent.lightened(0.4), false, 2.0)


func _draw_unit_stack(center: Vector2, c: Dictionary) -> void:
	var u: Dictionary = GameData.UNITS[c["id"]]
	var rarity: int = u["rarity"]
	var rc: Color = GameData.RARITY_COLORS[rarity]
	var n: int = c["n"]
	var offsets: Array = [[Vector2(0, -6)], [Vector2(-12, -6), Vector2(12, -6)], [Vector2(-13, -1), Vector2(13, -1), Vector2(0, -15)]][n - 1]
	var bob := sin(_anim * 3.0 + center.x * 0.1) * 1.5
	for o in offsets:
		_draw_unit_icon(center + o + Vector2(0, bob), u["color"], rc, rarity, 10.0 if n > 1 else 13.0)
	_text(center + Vector2(0, 24), u["name"], 11, rc)
	if u.has("skill"):
		var ratio := clampf(c["skill_t"] / u["skill"]["cd"], 0.0, 1.0)
		draw_arc(center + Vector2(0, -6), 26.0, -PI / 2, -PI / 2 + TAU * ratio, 24, Color(1, 1, 1, 0.5), 2.0)


func _draw_unit_icon(p: Vector2, col: Color, rc: Color, rarity: int, r: float) -> void:
	match rarity:
		0:
			draw_circle(p, r, col)
			draw_arc(p, r, 0, TAU, 20, rc.darkened(0.2), 2.0)
		1:
			var pts := PackedVector2Array([p + Vector2(0, -r * 1.15), p + Vector2(r * 1.15, 0), p + Vector2(0, r * 1.15), p + Vector2(-r * 1.15, 0)])
			draw_colored_polygon(pts, col)
			pts.append(pts[0])
			draw_polyline(pts, rc, 2.0)
		2:
			var pts := PackedVector2Array()
			for k in 6:
				pts.append(p + Vector2.from_angle(TAU * k / 6.0 - PI / 2) * r * 1.1)
			draw_colored_polygon(pts, col)
			pts.append(pts[0])
			draw_polyline(pts, rc, 2.0)
		_:
			var pts := PackedVector2Array()
			var spikes := 5 if rarity == 3 else 8
			for k in spikes * 2:
				var rr := r * (1.35 if k % 2 == 0 else 0.7)
				pts.append(p + Vector2.from_angle(TAU * k / (spikes * 2.0) - PI / 2 + (_anim if rarity == 4 else 0.0)) * rr)
			if rarity == 4:
				draw_circle(p, r * 1.5, Color(rc, 0.25 + 0.15 * sin(_anim * 5.0)))
			draw_colored_polygon(pts, col)
			pts.append(pts[0])
			draw_polyline(pts, rc, 2.0)
	draw_circle(p + Vector2(-r * 0.3, -r * 0.3), r * 0.22, Color(1, 1, 1, 0.5))


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
			if e.kind == "goblin":
				draw_arc(body, s + 4, 0, TAU, 16, Color(1, 1, 0.4, 0.8), 2.0)
			if e.shield > 0.0:
				draw_arc(body, s + 3, 0, TAU, 16, Color(0.5, 0.8, 1.0, 0.9), 2.0)
			if e.slow_t > 0.0 or e.aura_slow > 0.0:
				draw_arc(body, s + 1, 0, TAU, 16, Color(0.5, 0.9, 1.0, 0.7), 2.0)
			if e.burn_t > 0.0 or e.poison_t > 0.0:
				draw_circle(body + Vector2(0, -s - 4), 2.5, Color(1, 0.5, 0.1))
			if e.stun_t > 0.0:
				for k in 3:
					draw_circle(body + Vector2.from_angle(_anim * 6.0 + k * TAU / 3) * (s + 2) + Vector2(0, -s), 2.0, Color(1, 1, 0.4))
			var hr: float = e.hp_ratio()
			if hr < 0.999 or e.is_boss:
				var w := s * 2.2
				draw_rect(Rect2(body + Vector2(-w / 2, -s - 8), Vector2(w, 3)), Color(0, 0, 0, 0.7))
				draw_rect(Rect2(body + Vector2(-w / 2, -s - 8), Vector2(w * hr, 3)), Color(0.3, 1.0, 0.3).lerp(Color(1, 0.2, 0.2), 1.0 - hr))


func _draw_effects() -> void:
	for fx in effects:
		var k: float = fx["t"] / fx["dur"]
		var col: Color = fx["color"]
		match fx["type"]:
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
			"beam":
				var h := 200.0 * (1.0 - k)
				draw_rect(Rect2(fx["pos"] + Vector2(-8, -h), Vector2(16, h)), Color(col, 0.5 * (1.0 - k)))


func _draw_chests() -> void:
	for ch in chests:
		var p: Vector2 = ch["pos"] + Vector2(0, sin(_anim * 5.0) * 3.0)
		var blink: bool = ch["t"] < 2.0 and fmod(_anim, 0.3) < 0.15
		if blink:
			continue
		draw_circle(p, 18.0, Color(1, 0.85, 0.3, 0.25))
		draw_rect(Rect2(p - Vector2(11, 8), Vector2(22, 16)), Color(0.65, 0.4, 0.15))
		draw_rect(Rect2(p - Vector2(11, 8), Vector2(22, 6)), Color(0.85, 0.55, 0.2))
		draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), Color(1, 0.9, 0.3))


func _draw_texts() -> void:
	for t in texts:
		var k: float = t["t"] / t["dur"]
		var col: Color = t["color"]
		col.a = 1.0 - k * k
		_text(t["pos"] + Vector2(0, -30.0 * k), t["text"], t["size"], col)


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
		_text(Vector2(SIZE / 2, y + 22), banner_sub, 15, Color(1, 1, 1, a))
