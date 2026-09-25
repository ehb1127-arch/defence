extends Node
## 서버 경제 테스트: 전용 서버에 접속해 계정 이전/재화 작업/판 정산/룰렛/결제 검증/오프라인 재전송 확인.
##   서버: SQD_IAP_TEST=1 godot --headless res://scenes/Main.tscn -- --server --port 24695
##   실행: godot --headless res://tests/EconTest.tscn -- 127.0.0.1:24695

var _ok := 0
var _fail := 0


func check(name: String, cond: bool, info: Variant = "") -> void:
	if cond:
		_ok += 1
		print("  ok   ", name)
	else:
		_fail += 1
		print("  FAIL ", name, "  ", info)


func _wait_op() -> Variant:
	var r: Array = await Profile.op_done
	return r[1]


func _ready() -> void:
	var target: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "127.0.0.1:24695"
	Session.player_name = "경제테스트"
	# 새 계정 + 조작된 기기 파일 흉내
	Profile.device_id = "econtest%08x" % randi()
	Profile.linked = false
	Profile.pending_ops = []
	Profile.coins = 99999
	Profile.items = {"revive": 50, "bogus": 3}
	Profile.no_ads = true
	Profile.purchases = {}
	Profile.roulette = {"date": "", "free": false, "ads": 0}
	for k in Profile.stats:
		Profile.stats[k] = 0
	Profile.stats["mythics"] = 999999
	Net.connect_to(target)
	await Net.account_synced
	check("계정 연결", Profile.econ_server and Profile.linked)
	check("이전 상한 (코인)", Profile.coins == 5000, Profile.coins)
	check("이전 상한 (아이템)", Profile.item_count("revive") == 10 and not Profile.items.has("bogus"), Profile.items)
	check("결제 상품은 이전 안 됨", not Profile.no_ads)
	check("이전 상한 (기록)", int(Profile.stats["mythics"]) <= 500, Profile.stats["mythics"])

	# 재화 작업: 로컬 즉시 반영 → 서버 결과로 덮어쓰기
	Profile.buy_item("start_gold")
	check("로컬 즉시 반영", Profile.coins == 4970, Profile.coins)
	var r: Variant = await _wait_op()
	check("서버 구매 결과", r == true and Profile.coins == 4970, [r, Profile.coins])

	# 조작: 로컬 코인을 바꿔도 서버 값으로 돌아감
	Profile.coins = 999999
	Profile.buy_item("start_gold")
	r = await _wait_op()
	check("조작된 로컬 코인 무시", Profile.coins == 4940, Profile.coins)

	# 판 정산: 터무니없는 요약은 상한으로 잘림
	var before := Profile.coins
	var s := {"mode": "solo", "stage": "", "online": false, "won": true, "wave": 999, "kills": 999999,
		"stars": 3, "merges_done": 99999, "mythics_done": 999, "bosses_killed": 999, "interrupts": 0,
		"slot_jackpots": 0, "best_combo": 0, "max_star": 99, "obtained": ["sword", "no_such_unit"], "ad_double": false}
	Profile.apply_match_end(s)
	Profile.sync("match_end", [s])
	r = await _wait_op()
	var cap := GameData.match_coins(60, 60 * 45 + 20, true) * 2 + 2000
	check("판 정산 상한", Profile.coins - before > 0 and Profile.coins - before < cap, Profile.coins - before)
	check("판 정산 도감 검증", Profile.discovered.has("sword") and not Profile.discovered.has("no_such_unit"))
	check("누적 기록 상한", int(Profile.stats.get("mythics", 0)) <= 500 + 12, Profile.stats.get("mythics"))

	# 서버 난수 작업
	var idx: Variant = await Profile.request("roulette", [false])
	check("룰렛 (서버 결과)", idx is int and idx >= 0 and idx < GameData.ROULETTE.size(), idx)
	idx = await Profile.request("roulette", [false])
	check("룰렛 무료 1회 제한", idx == -1, idx)
	var item: Variant = await Profile.request("ad_reward", ["shop_item"])
	check("광고 랜덤 아이템", item is String and item != "", item)

	# 결제 (서버가 SQD_IAP_TEST=1 로 떠 있어야 함)
	var same := "test:same-%d" % randi()
	var coins0 := Profile.coins
	Net.send_iap(1, "coins_s", "test:tok-%d" % randi())
	var ir: Array = await Net.iap_result
	check("테스트 결제 지급", ir[1] == true and Profile.coins == coins0 + 300, [ir, Profile.coins - coins0])
	Net.send_iap(2, "no_ads", same)
	ir = await Net.iap_result
	check("광고 제거 지급", ir[1] == true and Profile.no_ads, ir)
	Net.send_iap(3, "coins_s", same)
	ir = await Net.iap_result
	check("영수증 재사용 거절", ir[1] == false, ir)
	Net.send_iap(4, "no_ads", "test:other-token")
	ir = await Net.iap_result
	check("1회 상품 중복 거절", ir[1] == false, ir)

	# 오프라인 → 재접속 재전송
	Net.close()
	check("끊기면 로컬 모드", not Profile.econ_server)
	var c1 := Profile.coins
	Profile.buy_item("summon_ticket")
	check("오프라인 작업 대기열", Profile.pending_ops.size() == 1, Profile.pending_ops)
	Net.connect_to(target)
	await Net.account_synced
	r = await _wait_op()
	check("재접속 재전송 반영", Profile.coins == c1 - 25 and Profile.pending_ops.is_empty(), [Profile.coins, c1])

	print("ECON ok=%d fail=%d" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
