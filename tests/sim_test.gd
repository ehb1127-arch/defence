extends Node
## 헤드리스 밸런스/회귀 테스트: 봇끼리 게임을 빠르게 돌려 결과를 출력한다.
## 실행: godot --headless res://tests/SimTest.tscn  [-- solo|coop|pvp  level  runs]

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var mode := args[0] if args.size() > 0 else "solo"
	var level := int(args[1]) if args.size() > 1 else 1
	var runs := int(args[2]) if args.size() > 2 else 3
	for r in runs:
		_run(mode, level, 1000 + r)
	get_tree().quit()


func _run(mode: String, level: int, seed_v: int) -> void:
	var n := 1 if mode == "solo" else 2
	var boards: Array = []
	var bots: Array = []
	for i in n:
		var b := Board.new()
		b.setup(i, "Bot%d" % i, mode, seed_v, false, true)
		add_child(b)
		boards.append(b)
	for i in n:
		bots.append(BotBrain.new(boards[i], boards[1 - i] if n > 1 else null, level))
		boards[i].action_attack.connect(func(src, aid): boards[1 - src.index].receive_attack(aid))
		boards[i].action_gift_gold.connect(func(src, amt): boards[1 - src.index].receive_gold(amt))
		boards[i].action_blast.connect(func(src): for bb in boards: bb.receive_blast())
	var dt := 1.0 / 30.0
	var t := 0.0
	var result := ""
	var last_wave := 0
	while t < 60.0 * 60:
		t += dt
		for i in n:
			boards[i].step(dt)
			bots[i].update(dt)
		var total := 0
		for b in boards:
			total += b.field_count()
		if boards[0].wave != last_wave and boards[0].wave % 5 == 0:
			last_wave = boards[0].wave
			var info := []
			for b in boards:
				var r := [0, 0, 0, 0, 0]
				for c in b.cells:
					if c["id"] != "":
						r[GameData.UNITS[c["id"]]["rarity"]] += c["n"]
				info.append("f=%d g=%d gem=%d up=%s units=%s" % [b.field_count(), b.gold, b.gems, str(b.upgrades), str(r)])
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
			if boards[0].field_count() >= boards[0].enemy_limit or boards[0].boss_failed:
				result = "solo LOSE" + (" (boss)" if boards[0].boss_failed else "")
				break
			if boards[0].final_cleared_flag:
				result = "solo WIN"
				break
	var mvp := ""
	for b in boards:
		var ids: Array = b.dmg_by_unit.keys()
		ids.sort_custom(func(x, y): return b.dmg_by_unit[x] > b.dmg_by_unit[y])
		mvp += " [%s]" % ", ".join(ids.slice(0, 4))
	print("  boss times: ", boards[0].boss_kill_times)
	print("%s seed=%d lvl=%d -> %s at wave %d, t=%ds kills=%d mvp=%s" % [mode, seed_v, level, result, boards[0].wave, int(t), boards[0].kills, mvp])
	for b in boards:
		b.queue_free()
