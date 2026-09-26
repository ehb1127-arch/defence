extends Node
## 서버 경제 테스트: 전용 서버에 접속해 계정 이전/재화 작업/판 정산/룰렛/결제 검증/오프라인 재전송/
## 조작 방지(방치 배수·판 표·동시 영수증)/복구 코드/랭킹/한국 시간 날짜 확인.
##   서버: SQD_IAP_TEST=1 godot --headless res://scenes/Main.tscn -- --server --port 24695
##   실행: godot --headless res://tests/EconTest.tscn -- 127.0.0.1:24695

var _ok := 0
var _fail := 0
var _notice := ""


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


func _op(op: String, args: Array) -> Variant:
	## 로컬 반영 없이 서버에 작업만 보내고 결과를 기다린다 (조작된 클라이언트 흉내)
	Profile._req_id += 1
	var my: int = Profile._req_id
	Net.send_op(my, op, args)
	while true:
		var r: Array = await Profile.op_done
		if r[0] == my:
			return r[1]
		if r[0] == -1:
			return null
	return null


func _summary(won: bool, wave: int, extra := {}) -> Dictionary:
	var s := {"mode": "solo", "stage": "", "online": false, "won": won, "wave": wave, "kills": wave * 20,
		"stars": 0, "merges_done": 5, "mythics_done": 0, "bosses_killed": 0, "interrupts": 0,
		"slot_jackpots": 0, "best_combo": 0, "max_star": 1, "obtained": [], "ad_double": false, "diff": 0}
	s.merge(extra, true)
	return s


func _ready() -> void:
	var target: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "127.0.0.1:24695"
	Session.player_name = "경제테스트"
	Net.notice_received.connect(func(t): _notice = t)

	# ---- 한국 시간 날짜 (서버·클라이언트 공통 하루 기준) ----
	check("KST 날짜 계산", Story.kst_date(0) == "1970-01-01" and Story.kst_date(15 * 3600) == "1970-01-02", [Story.kst_date(0), Story.kst_date(15 * 3600)])
	var kst := Time.get_date_string_from_unix_time(int(Time.get_unix_time_from_system()) + 9 * 3600)
	check("Profile.today() = 한국 날짜", Profile.today() == kst, [Profile.today(), kst])
	check("오늘의 결계 id = 한국 날짜", Story.daily_id() == "D" + kst.replace("-", ""), Story.daily_id())

	# 새 계정 + 조작된 기기 파일 흉내 (파일에는 쓰지 않는다: 개발자 기기의 프로필·account.cfg 보호)
	Profile.ephemeral = true
	Profile.device_id = "econtest%08x" % randi()
	Profile.linked = false
	Profile.pending_ops = []
	Profile.coins = 99999
	Profile.items = {"revive": 50, "bogus": 3}
	Profile.no_ads = true
	Profile.purchases = {}
	Profile.roulette = {"date": "", "free": false, "ads": -50}
	Profile.ad_extra = {"date": Profile.today(), "result": -100, "idle": -100}
	Profile.ticket = {"mode": "solo", "stage": "", "t": 0, "online": false, "diff": 2}
	Profile.idle_last = int(Time.get_unix_time_from_system()) - 3600
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
	check("이전: 하루 횟수·판 표 초기화", Profile.ticket.is_empty() and int(Profile.ad_extra.get("result", 0)) == 0 and int(Profile.roulette.get("ads", 0)) == 0, [Profile.ticket, Profile.ad_extra, Profile.roulette])
	var cfg_notice := ""
	var cfg = JSON.parse_string(FileAccess.get_file_as_string("user://server_config.json")) if FileAccess.file_exists("user://server_config.json") else null
	if cfg is Dictionary:
		cfg_notice = str(cfg.get("notice", ""))
	if cfg_notice != "":
		check("서버 공지 받음", _notice == cfg_notice, [_notice, cfg_notice])

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

	# ---- 조작: 방치 보상 배수 (최대 2배, 2배는 하루 광고 한도 안에서) ----
	var idle := Profile.idle_amount()
	var c0 := Profile.coins
	r = await _op("claim_idle", [1000000])
	check("방치 보상 배수 조작 차단", idle > 0 and Profile.coins - c0 <= idle * 2 and int(r) <= idle * 2, [idle, Profile.coins - c0, r])
	r = await _op("claim_idle", [-7])
	check("방치 보상 음수 배수", int(r) >= 0 and Profile.coins >= c0, r)
	# ---- 조작: 이상한 인자 ----
	r = await _op("buy_item", [{"x": 1}])
	check("잘못된 인자 거절", r == null, r)
	r = await _op("claim_chest", ["a", "b"])
	check("잘못된 상자 인자", r == false, r)

	# 판 정산: 터무니없는 요약은 상한으로 잘림 (표 없음 = 오프라인 재전송으로 취급)
	var before := Profile.coins
	var s := {"mode": "solo", "stage": "", "online": false, "won": true, "wave": 999, "kills": 999999,
		"stars": 3, "merges_done": 99999, "mythics_done": 999, "bosses_killed": 999, "interrupts": 0,
		"slot_jackpots": 0, "best_combo": 0, "max_star": 99, "obtained": ["sword", "no_such_unit"], "ad_double": false}
	Profile.apply_match_end(s)
	Profile.sync("match_end", [s])
	r = await _wait_op()
	var cap := int(GameData.match_coins(60, 60 * 45 + 20, true) * 2 * 2.2 * maxf(1.0, Profile.coin_mult)) + 2000
	check("판 정산 상한", Profile.coins - before > 0 and Profile.coins - before < cap, Profile.coins - before)
	check("판 정산 도감 검증", Profile.discovered.has("sword") and not Profile.discovered.has("no_such_unit"))
	check("누적 기록 상한", int(Profile.stats.get("mythics", 0)) <= 500 + 12, Profile.stats.get("mythics"))
	check("표 없는 정산 표시", r is Dictionary and r.get("ticket", true) == false, r)

	# ---- 판 표: 시작하자마자 40라운드 승리 주장 → 걸린 시간만큼만 인정 ----
	var wins0 := int(Profile.stats.get("wins", 0))
	Profile.begin_match("solo", "")
	r = await _wait_op()
	check("판 표 발급", r == true, r)
	r = await _op("match_end", [_summary(true, 40, {"diff": 2})])
	check("너무 빠른 승리 거절", r is Dictionary and r.get("ticket", false) and r.get("won", true) == false and int(r.get("wave", 99)) <= 2, r)
	check("빠른 승리 기록 안 됨", int(Profile.stats.get("wins", 0)) == wins0, Profile.stats.get("wins"))
	r = await _op("match_end", [_summary(false, 3)])
	check("판 표는 한 번만", r is Dictionary and r.get("ticket", true) == false, r)
	# 시간이 지난 정상 판: 걸린 시간만큼의 라운드는 인정 + 무한 모드 랭킹 기록
	Profile.begin_match("solo", "")
	await _wait_op()
	# 7초 x 최대 배속 3 → 준비 8초 + 1라운드 20초는 지나갈 수 있음 (2라운드까지), 3라운드는 안 됨
	await get_tree().create_timer(7.0).timeout
	r = await _op("match_end", [_summary(false, 30)])
	check("걸린 시간만큼 라운드 인정", r is Dictionary and r.get("ticket", false) and int(r.get("wave", 0)) == 2, r)
	# 2분이면 x3 배속으로 20라운드 안쪽, 온라인(x1)은 8라운드 안쪽. 40라운드는 x3 로도 4분 넘게 걸린다
	var mw := [Profile.max_wave_for("solo", 120.0, false), Profile.max_wave_for("solo", 120.0, true), Profile.max_wave_for("solo", 240.0, false)]
	check("라운드 상한 계산 (x3 배속, 온라인 x1)", mw[0] <= 20 and mw[1] <= 8 and mw[2] < GameData.FINAL_WAVE, mw)
	# 표 없는 정산은 하루 OFFLINE_SETTLE_DAILY 번까지
	var accepted := 2   # 위에서 표 없이 2번 (조작 요약, 같은 표 두 번째 정산)
	var rejected := false
	for i in 12:
		r = await _op("match_end", [_summary(false, 1)])
		if r is Dictionary and r.get("rejected", false):
			rejected = true
			break
		if r == null:
			break
		accepted += 1
	check("표 없는 정산 하루 한도", rejected and accepted == Profile.OFFLINE_SETTLE_DAILY, [accepted, r])

	# ---- 랭킹 ----
	Net.request_leaderboard("endless")
	var lb: Array = await Net.leaderboard_received
	check("랭킹 형식 (무한)", lb[0] == "endless" and lb[1] is Array and lb[2] >= 1, [lb[0], lb[2]])
	var fmt_ok := true
	for e in lb[1]:
		if not (e is Dictionary and e.has("name") and e.has("value") and e.has("sub")):
			fmt_ok = false
	var mine: bool = lb[2] > lb[1].size() or (lb[2] >= 1 and lb[1][lb[2] - 1]["name"] == Session.player_name and int(lb[1][lb[2] - 1]["value"]) >= 2)
	check("랭킹에 내 기록", fmt_ok and mine, [lb[2], lb[1].slice(0, 3)])
	Net.request_leaderboard("pvp")
	lb = await Net.leaderboard_received
	check("랭킹 형식 (대전)", lb[0] == "pvp" and lb[1] is Array, lb[0])

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
	Net.send_iap(4, "no_ads", "test:other-%d" % randi())
	ir = await Net.iap_result
	check("1회 상품 중복 거절", ir[1] == false, ir)
	# 같은 영수증을 동시에 두 번 (확인 기다리는 사이에 또 옴) → 한 번만 지급
	var race := "test:race-%d" % randi()
	coins0 = Profile.coins
	Net.send_iap(5, "coins_m", race)
	Net.send_iap(6, "coins_m", race)
	var got := 0
	var res_a: Array = await Net.iap_result
	var res_b: Array = await Net.iap_result
	for x in [res_a, res_b]:
		if x[1]:
			got += 1
	check("동시 영수증 한 번만 지급", got == 1 and Profile.coins == coins0 + 1800, [res_a, res_b, Profile.coins - coins0])

	# ---- 계정 복구 코드: 새 폰(새 기기 ID)에서 코드로 계정·결제 되찾기 ----
	Net.request_recovery_code()
	var code: String = await Net.recovery_code
	check("복구 코드 받기", code.length() == 14 and code[4] == "-" and code[9] == "-", code)
	Net.request_recovery_code()
	var code2: String = await Net.recovery_code
	check("복구 코드는 계정마다 하나", code2 == code, [code, code2])
	var old_dev := Profile.device_id
	var old_coins := Profile.coins
	Net.close()
	Profile.device_id = "newphone%08x" % randi()
	Profile.linked = false
	Profile.pending_ops = []
	Profile.coins = 0
	Profile.no_ads = false
	Profile.purchases = {}
	Net.connect_to(target)
	await Net.account_synced
	check("새 폰은 새 계정", Profile.device_id != old_dev and not Profile.no_ads, Profile.device_id)
	Net.redeem_recovery_code("ZZZZ-ZZZZ-ZZZZ")
	var rr: Array = await Net.recovery_result
	check("틀린 복구 코드 거절", rr[0] == false, rr)
	Net.redeem_recovery_code(code.to_lower().replace("-", " "))
	rr = await Net.recovery_result
	check("복구 코드 입력", rr[0] == true and Profile.device_id == old_dev, [rr, Profile.device_id])
	await Net.account_synced
	check("복구: 진행·결제 되찾음", Profile.no_ads and Profile.coins == old_coins, [Profile.no_ads, Profile.coins, old_coins])

	# 오프라인 → 재접속 재전송
	Net.close()
	check("끊기면 로컬 모드", not Profile.econ_server)
	var c1 := Profile.coins
	Profile.buy_item("summon_ticket")
	Profile.begin_match("solo", "")
	check("오프라인 작업 대기열 (판 표는 안 쌓임)", Profile.pending_ops.size() == 1 and Profile._begin_unsent.size() == 3, [Profile.pending_ops, Profile._begin_unsent])
	Net.connect_to(target)
	await Net.account_synced
	# 대기열 작업 + 연결 전에 시작한 판의 판 표 요청까지 모두 응답을 받을 때까지
	while true:
		var rr2: Array = await Profile.op_done
		if rr2[0] >= Profile._req_id:
			break
	check("재접속 재전송 반영", Profile.coins == c1 - 25 and Profile.pending_ops.is_empty(), [Profile.coins, c1])
	check("연결 후 판 표 요청", Profile._begin_unsent.is_empty() and not Profile.ticket.is_empty(), Profile.ticket)

	print("ECON ok=%d fail=%d" % [_ok, _fail])
	get_tree().quit(1 if _fail > 0 else 0)
