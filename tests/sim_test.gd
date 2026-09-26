extends Node
## 헤드리스 밸런스/회귀 테스트: 봇끼리 게임을 빠르게 돌려 결과를 출력한다.
## 실행: godot --headless res://tests/SimTest.tscn  [-- solo|coop|pvp|<스테이지 id>|unit  level  runs  [난이도] [성장] [시작 시드]]
## unit: 시뮬레이션 없이 규칙 단위 검사 (★ 평가, 조합 재료 보호, 보스 기술 표 등)

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "solo"
	var level := int(args[1]) if args.size() > 1 else 1
	var runs := int(args[2]) if args.size() > 2 else 3
	_diff = int(args[3]) if args.size() > 3 else 0
	_growth = float(args[4]) if args.size() > 4 and float(args[4]) > 0.0 else GameData.MOB_EXTRA_GROWTH
	var seed0 := int(args[5]) if args.size() > 5 else 1000
	if mode == "unit":
		_unit_tests()
		get_tree().quit()
		return
	for r in runs:
		if mode.begins_with("C") or mode.begins_with("HC"):
			_run_chapter(int(mode.trim_prefix("H").substr(1)), mode.begins_with("H"), level, seed0 + r)
		else:
			_run(mode, level, seed0 + r)
	get_tree().quit()


func _run_chapter(ch: int, hard: bool, level: int, seed_v: int) -> void:
	## 장 이어하기 시뮬: 한 장의 스테이지를 배치를 이어받아 연속으로 (C<장> / HC<장> = 악몽)
	var n_st: int = Story.CHAPTERS[ch - 1]["stages"].size()
	var state := {}
	var total_t := 0.0
	var line := []
	for si in n_st:
		var id := ("H" if hard else "") + Story.stage_id(ch, si + 1)
		var b := Board.new()
		b.setup(0, "Bot", "solo", seed_v + si * 7, false, true)
		b.apply_stage(id, not state.is_empty())
		if not state.is_empty():
			var st := Story.get_stage(id)
			b.import_state(state, int(int(st["chapter"]["gold"]) * 0.4), int(st["chapter"]["gems"]) / 2)
		add_child(b)
		var bot := BotBrain.new(b, null, level)
		var dt := 1.0 / 30.0
		var t := 0.0
		var res := ""
		var peak := 0
		while t < 60.0 * 30:
			t += dt
			b.step(dt)
			bot.update(dt)
			peak = maxi(peak, b.rated_field_count())
			if b.final_cleared_flag:
				res = "W%d" % b.stage_stars()
				break
			if b.field_count() >= b.enemy_limit or b.boss_failed:
				res = "L" + ("boss" if b.boss_failed else "") + "@%d" % b.wave
				break
		total_t += t
		var r := [0, 0, 0, 0, 0]
		for c in b.cells:
			if c["id"] != "":
				r[GameData.UNITS[c["id"]]["rarity"]] += c["n"]
		line.append("%s[R%d-%d %s peak%d boss%s %s myth%d leg%s]" % [id, b.wave_offset + 1, b.wave_offset + b.final_wave, res, peak, str(b.boss_kill_times.values()), str(r), b.mythics_done, str(b.legend_src)])
		state = b.export_state()
		b.queue_free()
		if not res.begins_with("W"):
			break
	print("chapter %s%d seed=%d lvl=%d -> %s  (%.1f min)" % ["H" if hard else "", ch, seed_v, level, " ".join(line), total_t / 60.0])


var _diff := 0
var _growth := 1.0


func _run(mode: String, level: int, seed_v: int) -> void:
	var n := 1 if mode == "solo" or _is_stage(mode) else 2
	var boards: Array = []
	var bots: Array = []
	for i in n:
		var b := Board.new()
		b.setup(i, "Bot%d" % i, "solo" if _is_stage(mode) else mode, seed_v, false, true)
		if _is_stage(mode):
			b.apply_stage(mode)
		elif mode != "pvp":
			b.difficulty = _diff
			b.mob_growth = _growth
		add_child(b)
		boards.append(b)
	for i in n:
		bots.append(BotBrain.new(boards[i], boards[1 - i] if n > 1 else null, level))
		boards[i].action_attack.connect(func(src, aid): boards[1 - src.index].receive_attack(aid))
		boards[i].action_gift_gold.connect(func(src, amt): boards[1 - src.index].receive_gold(amt))
		boards[i].action_gift_unit.connect(func(src, uid): boards[1 - src.index].receive_unit(uid))
		boards[i].action_blast.connect(func(src): for bb in boards: bb.receive_blast())
	var dt := 1.0 / 30.0
	var t := 0.0
	var result := ""
	var last_wave := 0
	var peak := []          # 구간 최대 적 수 (보스 무게 포함 / 제외)
	var peak_mob := []
	for i in n:
		peak.append(0)
		peak_mob.append(0)
	while t < 60.0 * 60:
		t += dt
		for i in n:
			boards[i].step(dt)
			bots[i].update(dt)
			peak[i] = maxi(peak[i], boards[i].field_count())
			peak_mob[i] = maxi(peak_mob[i], boards[i].rated_field_count())
		var total := 0
		for b in boards:
			total += b.field_count()
		if boards[0].wave != last_wave and (boards[0].wave % 5 == 0 or boards[0].wave > 30):
			last_wave = boards[0].wave
			var info := []
			for i in n:
				var b: Board = boards[i]
				var r := [0, 0, 0, 0, 0]
				for c in b.cells:
					if c["id"] != "":
						r[GameData.UNITS[c["id"]]["rarity"]] += c["n"]
				info.append("peak=%d/%d g=%d gem=%d up=%s units=%s" % [peak[i], peak_mob[i], b.gold, b.gems, str(b.upgrades), str(r)])
				peak[i] = 0
				peak_mob[i] = 0
			print("  t=%4d w=%2d  %s" % [int(t), boards[0].wave, " | ".join(info)])
		if mode == "coop":
			if total >= GameData.COOP_ENEMY_LIMIT or boards.any(func(b): return b.boss_failed):
				result = "coop LOSE"
				break
			if boards.all(func(b): return b.final_cleared_flag):
				result = "coop WIN"
				break
		elif mode == "pvp":
			var dead := boards.filter(func(b): return b.field_count() >= b.enemy_limit or b.boss_failed)
			if dead.size() > 0:
				result = "pvp: Bot%d lost" % dead[0].index
				break
		else:
			if _is_stage(mode) and boards[0].final_cleared_flag:
				result = "stage WIN stars=%d peak=%d" % [boards[0].stage_stars(), boards[0].peak_field]
				break
			if boards[0].field_count() >= boards[0].enemy_limit or boards[0].boss_failed:
				result = "solo LOSE" + (" (boss)" if boards[0].boss_failed else "")
				break
			if boards[0].final_cleared_flag:
				result = "solo WIN"
				break
	var mvp := ""
	for b in boards:
		var ids: Array = b.dmg_by_unit.keys()
		var sum := 0.0
		for id in ids:
			sum += b.dmg_by_unit[id]
		ids.sort_custom(func(x, y): return b.dmg_by_unit[x] > b.dmg_by_unit[y])
		var parts: Array = []
		for id in ids.slice(0, 4):
			parts.append("%s %d%%" % [id, int(100.0 * b.dmg_by_unit[id] / maxf(sum, 1.0))])
		var myth: Array = []
		for c in b.cells:
			if c["id"] != "" and GameData.UNITS[c["id"]]["rarity"] == GameData.Rarity.MYTHIC:
				myth.append("%s%s" % [c["id"], ("x%d" % c["n"]) if c["n"] > 1 else ""])
		mvp += " [%s] mythics(%d)=%s legends=%s" % [", ".join(parts), b.mythics_done, ",".join(myth), str(b.legend_src)]
	var left := ""
	for e in boards[0].enemies:
		if e.alive and e.is_boss:
			left = "  boss_left=%d%%" % int(e.hp_ratio() * 100.0)
	print("  boss times: ", boards[0].boss_kill_times, left)
	print("%s seed=%d lvl=%d -> %s at wave %d, t=%ds (%.1f min) kills=%d mvp=%s" % [mode, seed_v, level, result, boards[0].wave, int(t), t / 60.0, boards[0].kills, mvp])
	for b in boards:
		b.queue_free()


func _is_stage(mode: String) -> bool:
	return mode.contains("-") or (mode.length() > 1 and mode[0] in ["T", "D", "H"] and mode.substr(1, 1).is_valid_int())


# ===========================================================================
# 규칙 단위 검사
# ===========================================================================
var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("  ok   " if ok else "  FAIL ") + what)
	if not ok:
		_fails += 1


func _unit_tests() -> void:
	print("unit tests")
	# 1) ★3: 보스 스테이지에서 보스가 살아 있어도 잡몹이 적으면 ★3 이 가능해야 한다
	for id in ["1-4", "5-4", "10-5", "T10"]:
		var b := Board.new()
		b.setup(0, "T", "solo", 1, false, true)
		add_child(b)
		b.apply_stage(id)
		b._start_wave(b.final_wave)
		for k in 5:
			b._spawn("normal", 10.0, -k * 20.0)
		b.step(0.1)
		b.final_cleared_flag = true
		_check(b.field_count() >= 20 and b.peak_field < 15 and b.stage_stars() == 3, "%s 보스 무게 제외 ★3 (field=%d peak=%d stars=%d)" % [id, b.field_count(), b.peak_field, b.stage_stars()])
		b.queue_free()
	# 2) 모든 보스가 고유 기술 세트를 갖는다 (2부 보스 5~9 포함)
	var seen := {}
	for i in GameData.BOSS_SKILLS.size():
		var key := str(GameData.BOSS_SKILLS[i])
		_check(not seen.has(key), "보스 %d(%s) 기술 세트 고유: %s" % [i, Story.BOSS_CHARS[i], key])
		seen[key] = true
		for sk in GameData.BOSS_SKILLS[i]:
			_check(GameData.BOSS_SKILL_NAMES.has(sk[0]), "  기술 이름 있음: %s" % sk[0])
	_check(GameData.BOSS_SKILLS.size() == Story.BOSS_CHARS.size(), "보스 기술 표 = 보스 수")
	# 보스 기술이 실제로 시전되어도 오류가 없는지 (각 기술 한 번씩)
	var bb := Board.new()
	bb.setup(0, "T", "solo", 3, false, true)
	add_child(bb)
	for k in 12:
		bb.add_unit(GameData.UNIT_ORDER[k % GameData.UNIT_ORDER.size()])
	bb._start_wave(10)
	var boss: EnemyState = null
	for e in bb.enemies:
		if e.is_boss:
			boss = e
	for sk in GameData.BOSS_SKILL_NAMES:
		bb._boss_skill(boss, sk)
		bb.step(0.05)
	_check(bb.enemies.any(func(e): return e.boss_name == "그림자 분신" and e.no_mc), "그림자 분신 소환 + 지배 불가")
	bb.queue_free()
	# 3) 신화: 10종 이상, 조합식·스킬 보유, 스킬 시전 오류 없음
	var myth := GameData.units_of_rarity(GameData.Rarity.MYTHIC)
	_check(myth.size() >= 10, "신화 %d종" % myth.size())
	var recipes_seen := {}
	for m in myth:
		_check(GameData.RECIPES.has(m) and GameData.UNITS[m].has("skill"), "%s 조합식·스킬" % m)
		var rk := str(GameData.RECIPES[m])
		_check(not recipes_seen.has(rk), "%s 조합식 고유" % m)
		recipes_seen[rk] = true
		var legends := 0
		for ing in GameData.RECIPES[m]:
			if GameData.UNITS[ing]["rarity"] == GameData.Rarity.LEGEND:
				legends += 1
		_check(legends >= 1, "%s 전설 재료 필요" % m)
	var sb := Board.new()
	sb.setup(0, "T", "solo", 5, false, true)
	add_child(sb)
	sb._start_wave(12)
	for k in 30:
		sb._spawn(["normal", "fast", "tank"][k % 3], 50000.0, -k * 30.0)
	sb.step(0.1)
	for m in myth:
		var idx := sb.add_unit(m)
		sb._cast_skill(idx, sb.cells[idx], GameData.UNITS[m])
		sb.step(0.05)
	_check(sb.dmg_by_unit.size() >= 8, "신화 스킬 피해 기록 (%d종)" % sb.dmg_by_unit.size())
	sb.queue_free()
	# 4) 합성 버튼: 가장 가까운 신화 재료는 다른 합성거리가 있으면 아껴 둔다
	var mb := Board.new()
	mb.setup(0, "T", "solo", 7, false, true)
	add_child(mb)
	for k in 3:
		mb.add_unit("knight")     # 그림자군주 재료 (기사 x2 필요)
	mb.add_unit("ranger")
	mb.add_unit("assassin")
	for k in 3:
		mb.add_unit("sword")
	_check(mb.closest_recipe() == "reaper", "가장 가까운 신화 = reaper (%s)" % mb.closest_recipe())
	mb.auto_merge()
	_check(int(mb.unit_counts().get("knight", 0)) >= 3 and not mb.unit_counts().has("sword"), "검사부터 합성, 기사는 보존")
	mb.auto_merge()
	_check(int(mb.unit_counts().get("knight", 0)) < 3, "다른 합성거리가 없으면 기사도 합성")
	mb.queue_free()
	# 5) 배치: 짧은 사거리는 바깥 칸, 긴 사거리는 안쪽
	var pb := Board.new()
	pb.setup(0, "T", "solo", 9, false, true)
	add_child(pb)
	_check(Board.cell_ring(pb.add_unit("sword")) == 0, "검사 → 바깥 칸")
	_check(Board.cell_ring(pb.add_unit("sniper")) == 2, "저격수 → 가운데 칸")
	_check(Board.cell_ring(pb.add_unit("bard")) == 2, "음유시인 → 가운데 칸")
	pb.queue_free()
	# 6) 대전: 보낸 정예는 지배 불가, 라운드가 높을수록 강함
	var vb := Board.new()
	vb.setup(0, "T", "pvp", 11, false, true)
	add_child(vb)
	vb.wave = 18
	vb.gems = 20
	vb.receive_attack("elite:18")
	var sent := vb.enemies.filter(func(e): return e.sent and e.kind == "elite")
	_check(sent.size() == 2, "18라운드 정예 2마리 (%d)" % sent.size())
	_check(vb._mc_target() == null, "보낸 정예는 지배 대상 아님")
	var cnt := vb.enemies.size()
	vb.receive_attack("swarm:99")
	_check(vb.enemies.size() - cnt == 6 + 20 / 3, "보낸 라운드는 내 라운드+2 까지만 인정 (%d)" % (vb.enemies.size() - cnt))
	vb.queue_free()
	# 7) 스테이지에서도 분열체·치유사가 나온다
	var mix4 := GameData.wave_mix(3, 3 + GameData.stage_special_offset(6, 0, false, false))
	_check(mix4.any(func(m): return m[0] == "splitter"), "6장 3라운드 분열체")
	_check(GameData.wave_mix(8, 8 + GameData.stage_special_offset(0, 0, true, false)).any(func(m): return m[0] == "healer"), "오늘의 결계 8라운드 치유사")
	_check(not GameData.wave_mix(8, 8 + GameData.stage_special_offset(1, 0, false, false)).any(func(m): return m[0] == "splitter"), "1장은 분열체 없음")
	print("unit tests: %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
