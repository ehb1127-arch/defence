class_name BotBrain
extends RefCounted
## AI 플레이어. 사람과 똑같이 Board 의 공개 API 만 사용한다.

var board: Board
var other: Board        # 협동 파트너 또는 대전 상대 (없을 수 있음)
var level := 1          # 0 쉬움 / 1 보통 / 2 어려움
var _t := 0.0
var _gift_t := 0.0
var _rng := RandomNumberGenerator.new()


func _init(b: Board, o: Board, lvl: int) -> void:
	board = b
	other = o
	level = lvl
	_rng.seed = b.rng.seed + 99


func update(dt: float) -> void:
	_gift_t -= dt
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
	if not b.pending_pick.is_empty():
		if b.choose_pick(_best_pick()):
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
		# 파트너의 신화 조합에 필요한 유닛을 선물 (내 조합에 안 쓰는 것만)
		if level >= 1 and other.alive and _gift_t <= 0.0 and _gift_recipe_unit():
			_gift_t = 15.0
			return
	# 대전: 어려움은 상대가 위험할 때(보스 라운드·적이 많을 때) 몰아서 공격
	if b.mode == "pvp" and other != null and level >= 2 and b.wave >= 4 and pressure < 0.6:
		var o_pressure := float(other.field_count()) / other.enemy_limit
		var o_boss := other.is_boss_round(other.wave) and other.wave_timer > 10.0
		if o_pressure > 0.45 or o_boss:
			if b.gems >= 2 and other.curse_t <= 0.0 and o_boss:
				b.request_attack("curse")
				return
			if b.gold >= 150 + b.summon_cost():
				b.request_attack("elite")
				return
			if b.gold >= 40 + b.summon_cost():
				b.request_attack("swarm")
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
	# 지배: 중간보스/적 영웅이 나오면 빼앗기
	if level >= 1 and b.can_mind_control():
		var tgt := b._mc_target()
		if tgt != null and tgt.kind in ["midboss", "hero"]:
			b.mind_control()
			return
	# 운명 소환 (어려움: 중간보스 라운드 전에는 지배용 보석을 남긴다)
	var keep := GameData.MC_GEMS if level >= 2 and b.wave % 10 in [5, 6, 7] else 0
	if level >= 1:
		if b.gems - keep >= GameData.GAMBLES[1]["gems"] and b.wave >= 6:
			if b.gamble(1):
				return
		elif b.gems >= 2 and b.wave < 6:
			if b.gamble(0):
				return
	# ★ 강화 시도: 여유 골드로 가장 강한 칸을 ★3 까지
	if level >= 1 and b.pending_enhance.is_empty() and b.wave >= 8:
		var best := -1
		for i in b.cells.size():
			var c: Dictionary = b.cells[i]
			if c["id"] == "" or c["star"] >= 3:
				continue
			if best < 0 or GameData.UNITS[c["id"]]["rarity"] > GameData.UNITS[b.cells[best]["id"]]["rarity"]:
				best = i
		if best >= 0 and GameData.UNITS[b.cells[best]["id"]]["rarity"] >= 2 and b.gold > b.enhance_cost_of(best) + b.summon_cost() * 3:
			b.enhance_try(best)
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


func _best_pick() -> int:
	## 골라 뽑기: 보통 이상은 가장 가까운 신화 조합에 모자란 재료를 우선, 아니면 가장 높은 등급
	var b := board
	var bi := 0
	var recipe := b.closest_recipe() if level >= 1 else ""
	var have := b.unit_counts()
	var best_score := -1.0
	for i in b.pending_pick.size():
		var id: String = b.pending_pick[i]
		var score: float = GameData.UNITS[id]["rarity"]
		if recipe != "" and GameData.RECIPES[recipe].count(id) > int(have.get(id, 0)):
			score += 2.5
		if score > best_score:
			best_score = score
			bi = i
	return bi


func _gift_recipe_unit() -> bool:
	## 협동: 파트너의 가장 가까운 신화에 모자란 재료를 내가 남는 만큼 가지고 있으면 한 마리 선물
	var b := board
	# 내가 더 급하면 선물하지 않는다 (한쪽에만 신화가 몰리고 다른 쪽이 무너지는 것 방지)
	var my_p := float(b.field_count()) / b.enemy_limit
	var their_p := float(other.field_count()) / other.enemy_limit
	if my_p > their_p + 0.05 or my_p > 0.6:
		return false
	var theirs := other.closest_recipe()
	if theirs == "":
		return false
	var mine := b.closest_recipe()
	var their_have := other.unit_counts()
	var my_have := b.unit_counts()
	for id in GameData.RECIPES[theirs]:
		if GameData.UNITS[id]["rarity"] < GameData.Rarity.RARE or GameData.UNITS[id]["rarity"] >= GameData.Rarity.LEGEND:
			continue   # 전설은 선물하지 않는다
		if GameData.RECIPES[theirs].count(id) <= int(their_have.get(id, 0)):
			continue
		var my_need: int = GameData.RECIPES[mine].count(id) if mine != "" else 0
		if int(my_have.get(id, 0)) <= my_need:
			continue
		for i in b.cells.size():
			if b.cells[i]["id"] == id and b.cells[i]["star"] == 0:
				return b.request_gift_unit(i)
	return false


func _reposition() -> void:
	## 자리 정리: 선호 줄(Board.preferred_ring - 짧은 사거리는 바깥, 긴 사거리·버프는 안쪽)이 아닌 유닛을
	## 그 줄의 빈 칸으로 옮기거나, 서로 자리가 바뀐 유닛끼리 맞바꾼다
	var b := board
	for i in b.cells.size():
		var id: String = b.cells[i]["id"]
		if id == "":
			continue
		var want := Board.preferred_ring(id)
		var ring := Board.cell_ring(i)
		if ring == want:
			continue
		for j in b.cells.size():
			if Board.cell_ring(j) != want:
				continue
			var other_id: String = b.cells[j]["id"]
			if other_id == "" or (other_id != id and Board.preferred_ring(other_id) != want and absi(Board.preferred_ring(other_id) - ring) < absi(Board.preferred_ring(other_id) - want)):
				b.swap_cells(i, j)
				return


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
