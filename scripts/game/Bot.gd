class_name BotBrain
extends RefCounted
## AI 플레이어. 사람과 똑같이 Board 의 공개 API 만 사용한다.

var board: Board
var other: Board        # 협동 파트너 또는 대전 상대 (없을 수 있음)
var level := 1          # 0 쉬움 / 1 보통 / 2 어려움
var _t := 0.0
var _rng := RandomNumberGenerator.new()


func _init(b: Board, o: Board, lvl: int) -> void:
	board = b
	other = o
	level = lvl
	_rng.seed = b.rng.seed + 99


func update(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = [1.1, 0.6, 0.3][level] * _rng.randf_range(0.8, 1.2)
	if not board.alive:
		return
	_think()


func _think() -> void:
	var b := board
	if not b.chests.is_empty():
		b.open_chest(0)
		return
	var m := b.first_combinable()
	if m != "":
		b.combine(m)
		return
	if b.auto_merge():
		return
	var pressure := float(b.field_count()) / b.enemy_limit
	# 협동
	if b.mode == "coop" and other != null:
		if b.gauge >= GameData.COOP_BLAST_NEED and b.field_count() + other.field_count() > 45:
			b.request_blast()
			return
		if other.alive and other.field_count() > b.field_count() + 35 and b.gold > 350:
			b.request_gift_gold(100)
			return
	# 대전: 여유 있을 때 공격
	if b.mode == "pvp" and other != null and level >= 1 and b.wave >= 4 and pressure < 0.5:
		if b.gems >= 4 and other.curse_t <= 0.0 and _rng.randf() < 0.3:
			b.request_attack("curse")
			return
		if b.gold > 420 + b.summon_cost():
			b.request_attack("elite")
			return
		if b.gold > 220 + b.summon_cost() and _rng.randf() < 0.4:
			b.request_attack("swarm")
			return
	# 도박
	if level >= 1:
		if b.gems >= 4 and b.wave >= 6:
			if b.gamble(1):
				return
		elif b.gems >= 2 and b.wave < 6:
			if b.gamble(0):
				return
	# 강화
	var track := _pick_upgrade()
	if track >= 0 and _should_upgrade(track):
		b.upgrade(track)
		return
	# 소환
	if b.free_summons > 0 or b.gold >= b.summon_cost():
		if b.summon():
			return
		_make_room()
		return
	if level >= 1:
		_reposition()


func _is_outer(i: int) -> bool:
	var c := i % Board.COLS
	var r := i / Board.COLS
	return c == 0 or r == 0 or c == Board.COLS - 1 or r == Board.ROWS - 1


func _range_of(i: int) -> float:
	var id: String = board.cells[i]["id"]
	return 9999.0 if id == "" else GameData.UNITS[id]["range"]


func _reposition() -> void:
	## 사거리 짧은 유닛은 트랙과 가까운 바깥 칸으로, 긴 유닛은 안쪽으로
	var b := board
	var worst_inner := -1
	for i in b.cells.size():
		if not _is_outer(i) and b.cells[i]["id"] != "":
			if worst_inner < 0 or _range_of(i) < _range_of(worst_inner):
				worst_inner = i
	if worst_inner < 0:
		return
	var best_outer := -1
	for i in b.cells.size():
		if _is_outer(i) and _range_of(i) > _range_of(worst_inner) + 40.0:
			if best_outer < 0 or _range_of(i) > _range_of(best_outer):
				best_outer = i
	if best_outer >= 0:
		b.swap_cells(worst_inner, best_outer)


func _count_by_rarity() -> Array:
	var r := [0, 0, 0, 0, 0]
	for c in board.cells:
		if c["id"] != "":
			r[GameData.UNITS[c["id"]]["rarity"]] += c["n"]
	return r


func _pick_upgrade() -> int:
	var b := board
	var r := _count_by_rarity()
	if b.upgrades[3] < 2 and b.wave >= 3 and b.can_afford_upgrade(3):
		return 3
	if r[3] + r[4] > 0 and b.can_afford_upgrade(2) and b.gems >= 3:
		return 2
	# 주력 등급에 맞춰 강화
	var low_power: float = r[0] * 1.0 + r[1] * 3.0
	var mid_power: float = r[2] * 8.0
	if mid_power > low_power * 0.8 and b.can_afford_upgrade(1):
		return 1
	if b.can_afford_upgrade(0):
		return 0
	return -1


func _should_upgrade(track: int) -> bool:
	var b := board
	if GameData.UPGRADES[track]["cur"] == "gems":
		return true
	var cost := GameData.upgrade_cost(track, b.upgrades[track])
	# 소환이 비싸졌거나 칸이 가득하면 강화 우선
	var units := 0
	for c in b.cells:
		units += c["n"]
	# 유닛이 어느 정도 모이면 소환보다 강화 효율이 좋아진다
	if units >= 14 or b.used_cells() >= 18:
		return true
	return b.summon_cost() > cost * 0.6 or b.gold > cost + b.summon_cost() * 3


func _make_room() -> void:
	## 칸이 없으면 가장 낮은 등급의 외톨이 유닛을 판매
	var b := board
	var best := -1
	for i in b.cells.size():
		var c: Dictionary = b.cells[i]
		if c["id"] == "":
			continue
		var r: int = GameData.UNITS[c["id"]]["rarity"]
		if r >= 3:
			continue
		if best < 0:
			best = i
			continue
		var br: int = GameData.UNITS[b.cells[best]["id"]]["rarity"]
		if r < br or (r == br and c["n"] < b.cells[best]["n"]):
			best = i
	if best >= 0:
		b.sell_one(best)
