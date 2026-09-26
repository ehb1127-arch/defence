extends RefCounted
## 전용 서버: Google Play 인앱 결제 영수증(purchase token) 검증.
##
## 환경 변수
##   SQD_GOOGLE_SA   서비스 계정 키 JSON 파일 경로 (Play Console → API 액세스에서 권한 부여)
##   SQD_PACKAGE     앱 패키지 이름 (기본 com.squaredefense.game)
##   SQD_IAP_TEST=1  개발용: "test:" 로 시작하는 가짜 토큰을 결제로 인정 (출시 서버에서는 절대 켜지 말 것)
##
## 흐름: 서비스 계정으로 JWT(RS256) 서명 → OAuth 토큰 → androidpublisher v3 purchases.products.get
##  - 같은 토큰은 한 번만 지급. 확인(await) 전에 "확인 중"으로 먼저 적어서 동시에 두 번 와도 한 번만 지급
##  - 소모성: consumptionState == 0 (아직 소비 안 됨) 이어야 지급. 1회 상품: 이미 확인(acknowledge)된 결제는 "복원"만
##  - 결제에 붙은 계정 표시(obfuscatedExternalAccountId)가 다른 계정이면 소모성은 거절, 1회 상품은 복원만
##  - 지급 후 서버가 직접 consume/acknowledge (앱이 그 전에 꺼져도 3일 뒤 자동 환불되지 않게)
##  - 6시간마다 무효 구매(Voided Purchases: 환불·취소) 목록을 조회해 지급한 것을 회수 (host.revoke_purchase)
## 기록: user://server_iap.json (임시 파일 + 교체로 저장, 백업은 Net 이 한 시간마다)
## 설정 방법: docs/IAP.md

const TOKEN_URL := "https://oauth2.googleapis.com/token"
const SCOPE := "https://www.googleapis.com/auth/androidpublisher"
const APP_API := "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/%s"
const USED_PATH := "user://server_iap.json"
const BACKUP_DIR := "user://backups"
const VOID_EVERY := 6 * 3600.0     # 무효 구매 조회 간격 (초)
const VOID_LOOKBACK_MS := 30 * 24 * 3600 * 1000   # 처음 조회할 때 30일 전부터
const MAX_RESTORES := 3            # 한 영수증으로 복원해 줄 수 있는 다른 계정 수
const SafeFile := preload("res://scripts/server/SafeFile.gd")

var host: Node
var package_name := "com.squaredefense.game"
var test_mode := false
var _sa := {}             # 서비스 계정 JSON
var _key: CryptoKey
var _access := ""
var _access_exp := 0.0
var _used := {}           # sha256(토큰) → {state: pending/done, dev, product, t, order, restored: [dev], revoked}
var _orders := {}         # 주문 번호 → 토큰 키
var _void_since := 0      # 무효 구매를 어디(ms)부터 봤는지
var _void_timer := 120.0  # 서버 시작 2분 뒤 첫 조회
var _void_busy := false


func _init(p_host: Node) -> void:
	host = p_host
	package_name = OS.get_environment("SQD_PACKAGE") if OS.get_environment("SQD_PACKAGE") != "" else package_name
	test_mode = OS.get_environment("SQD_IAP_TEST") == "1"
	var sa_path := OS.get_environment("SQD_GOOGLE_SA")
	if sa_path != "" and FileAccess.file_exists(sa_path):
		var d = JSON.parse_string(FileAccess.get_file_as_string(sa_path))
		if d is Dictionary and d.has("private_key") and d.has("client_email"):
			_sa = d
			_key = CryptoKey.new()
			if _key.load_from_string(str(d["private_key"])) != OK:
				push_error("서비스 계정 비밀키를 읽지 못했습니다")
				_sa = {}
	_load()
	print("[결제 검증] %s%s, 기록 %d건" % ["Google Play 연결됨" if ready() else "서비스 계정 없음 (결제 지급 불가)", " / 테스트 토큰 허용" if test_mode else "", _used.size()])


func ready() -> bool:
	return not _sa.is_empty()


# ---- 기록 파일 ----
func _load() -> void:
	var res := SafeFile.load_json_with_backup(USED_PATH, BACKUP_DIR)
	var data = res["data"]
	if res["corrupt"]:
		push_error("server_iap.json 이 깨졌습니다. %s" % ("백업 %s 사용" % res["source"] if data != null else "복구할 백업 없음!"))
	if not data is Dictionary:
		return
	if data.has("v"):
		_used = data.get("used", {})
		_void_since = int(data.get("void_since", 0))
	else:
		_used = data   # 예전 형식: 토큰 → {dev, product, t}
	for k in _used.keys():
		var u: Dictionary = _used[k]
		if str(u.get("state", "done")) == "pending":
			_used.erase(k)   # 확인 도중 서버가 꺼진 것 → 다시 확인하게
			continue
		u["state"] = "done"
		if str(u.get("order", "")) != "":
			_orders[str(u["order"])] = k


func save() -> void:
	SafeFile.write_text(USED_PATH, JSON.stringify({"v": 2, "used": _used, "void_since": _void_since}))


func backup(dir: String, keep: int) -> void:
	SafeFile.backup(USED_PATH, dir, keep)


# ---- 검증 ----
func verify(product_id: String, token: String, dev: String) -> Dictionary:
	## 결과 {ok, msg, grant}. grant = "full"(처음 지급) / "restore"(1회 상품 권리만 복원)
	var p := GameData.iap_product(product_id)
	if p.is_empty():
		return {"ok": false, "msg": "없는 상품"}
	if token == "" or token.length() > 4096:
		return {"ok": false, "msg": "영수증 없음"}
	var key := token.sha256_text()
	if _used.has(key):
		var u: Dictionary = _used[key]
		if u.get("state", "") == "pending":
			return {"ok": false, "msg": "확인 중인 영수증"}
		if u.get("revoked", false):
			return {"ok": false, "msg": "환불된 결제"}
		if p.get("once", false) and u.get("product", "") == product_id:
			return _restore(u, dev)
		return {"ok": false, "msg": "이미 사용한 영수증"}
	# 확인(비동기)하는 동안 같은 토큰이 또 오면 위에서 "확인 중"으로 거절된다
	_used[key] = {"state": "pending", "dev": dev, "product": product_id, "t": int(Time.get_unix_time_from_system())}
	var r: Dictionary = await _check(product_id, token, dev)
	if not r.get("ok", false):
		_used.erase(key)
		return r
	var order := str(r.get("order", ""))
	if order != "" and _orders.has(order) and _orders[order] != key:
		_used.erase(key)
		return {"ok": false, "msg": "이미 사용한 영수증"}
	_used[key] = {"state": "done", "dev": dev, "product": product_id, "t": int(Time.get_unix_time_from_system()),
		"order": order, "grant": r.get("grant", "full")}
	if order != "":
		_orders[order] = key
	save()
	if r.get("google", false) and r.get("grant", "full") == "full":
		_finish_on_store(product_id, token, p.get("consumable", false))
	return r


func _restore(u: Dictionary, dev: String) -> Dictionary:
	## 이미 지급한 1회 상품 영수증이 다시 옴 (재설치·새 폰): 권리만 복원. 다른 계정은 MAX_RESTORES 개까지
	if u.get("dev", "") == dev:
		return {"ok": true, "grant": "restore", "msg": ""}
	var list: Array = u.get("restored", [])
	if not dev in list:
		if list.size() >= MAX_RESTORES:
			return {"ok": false, "msg": "복원 한도를 넘었어요 (고객센터 문의)"}
		list.append(dev)
		u["restored"] = list
		save()
	return {"ok": true, "grant": "restore", "msg": ""}


func _check(product_id: String, token: String, dev: String) -> Dictionary:
	if token.begins_with("test:"):
		if not test_mode:
			return {"ok": false, "msg": "테스트 결제는 이 서버에서 받지 않습니다"}
		# 실제 스토어 확인처럼 잠깐 기다린다 (동시 요청 중복 지급 시험용)
		await host.get_tree().create_timer(0.3).timeout
		return {"ok": true, "grant": "full", "order": "", "msg": ""}
	if not ready():
		return {"ok": false, "msg": "서버 결제 설정 전"}
	var r := await _get_purchase(product_id, token)
	if r.is_empty():
		return {"ok": false, "msg": "스토어 확인 실패"}
	if int(r.get("purchaseState", 1)) != 0:
		return {"ok": false, "msg": "결제 완료 상태가 아님"}
	var acc := str(r.get("obfuscatedExternalAccountId", ""))
	var mine := acc == "" or acc == dev.sha256_text().substr(0, 64)
	var grant := "full"
	if GameData.iap_product(product_id).get("consumable", false):
		if int(r.get("consumptionState", 0)) != 0:
			return {"ok": false, "msg": "이미 소비된 결제"}
		if not mine:
			return {"ok": false, "msg": "다른 계정의 결제"}
	elif int(r.get("acknowledgementState", 0)) != 0 or not mine:
		# 이미 확인된(다른 곳에서 지급된) 1회 상품 → 권리만 복원
		grant = "restore"
	return {"ok": true, "grant": grant, "order": str(r.get("orderId", "")), "google": true, "msg": ""}


# ---- 환불(무효 구매) ----
func tick() -> void:
	## Net 이 1초마다 부른다
	if not ready() or _void_busy:
		return
	_void_timer -= 1.0
	if _void_timer <= 0.0:
		_void_timer = VOID_EVERY
		poll_voided()


func poll_voided() -> void:
	_void_busy = true
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var start := _void_since if _void_since > 0 else now_ms - VOID_LOOKBACK_MS
	var at := await _access_token()
	if at == "":
		_void_busy = false
		return
	var base := (APP_API % package_name) + "/purchases/voidedpurchases?maxResults=1000&startTime=%d" % start
	var page := ""
	var newest := start
	var n := 0
	for _i in 20:
		var url := base + ("&token=" + page.uri_encode() if page != "" else "")
		var r := await _http(url, HTTPClient.METHOD_GET, ["Authorization: Bearer " + at], "")
		if r.is_empty():
			break
		for v in r.get("voidedPurchases", []):
			if apply_voided(str(v.get("purchaseToken", "")), str(v.get("orderId", ""))):
				n += 1
			newest = maxi(newest, int(v.get("voidedTimeMillis", 0)))
		page = str(r.get("tokenPagination", {}).get("nextPageToken", ""))
		if page == "":
			break
	_void_since = newest
	save()
	_void_busy = false
	if n > 0:
		print("[결제 검증] 환불 회수 %d건" % n)


func apply_voided(token: String, order := "") -> bool:
	## 무효 구매 하나 반영: 지급한 계정에서 회수 (복원만 받은 계정은 권리만 회수). 처음 반영이면 true
	var key := token.sha256_text() if token != "" else ""
	if not _used.has(key) and order != "" and _orders.has(order):
		key = _orders[order]
	if not _used.has(key):
		return false
	var u: Dictionary = _used[key]
	if u.get("revoked", false) or u.get("state", "") != "done":
		return false
	u["revoked"] = true
	u["revoked_t"] = int(Time.get_unix_time_from_system())
	if host != null and host.has_method("revoke_purchase"):
		host.revoke_purchase(str(u.get("dev", "")), str(u.get("product", "")), u.get("grant", "full") == "full")
		for d in u.get("restored", []):
			host.revoke_purchase(str(d), str(u.get("product", "")), false)
	save()
	return true


# ---- Google API ----
static func b64url(data: PackedByteArray) -> String:
	return Marshalls.raw_to_base64(data).replace("+", "-").replace("/", "_").replace("=", "")


func make_jwt(now: int) -> String:
	var header := {"alg": "RS256", "typ": "JWT"}
	var claims := {"iss": _sa["client_email"], "scope": SCOPE, "aud": TOKEN_URL, "iat": now, "exp": now + 3600}
	var body := b64url(JSON.stringify(header).to_utf8_buffer()) + "." + b64url(JSON.stringify(claims).to_utf8_buffer())
	var sig := Crypto.new().sign(HashingContext.HASH_SHA256, body.sha256_buffer(), _key)
	return body + "." + b64url(sig)


func _access_token() -> String:
	var now := Time.get_unix_time_from_system()
	if _access != "" and now < _access_exp - 60.0:
		return _access
	var form := "grant_type=%s&assertion=%s" % ["urn:ietf:params:oauth:grant-type:jwt-bearer".uri_encode(), make_jwt(int(now))]
	var r := await _http(TOKEN_URL, HTTPClient.METHOD_POST, ["Content-Type: application/x-www-form-urlencoded"], form)
	if r.has("access_token"):
		_access = r["access_token"]
		_access_exp = now + float(r.get("expires_in", 3600))
	return _access


func _product_url(product_id: String, token: String) -> String:
	return (APP_API % package_name) + "/purchases/products/%s/tokens/%s" % [product_id.uri_encode(), token.uri_encode()]


func _get_purchase(product_id: String, token: String) -> Dictionary:
	var at := await _access_token()
	if at == "":
		return {}
	return await _http(_product_url(product_id, token), HTTPClient.METHOD_GET, ["Authorization: Bearer " + at], "")


func _finish_on_store(product_id: String, token: String, consumable: bool) -> void:
	## 서버에서 직접 consume(소모성)/acknowledge(1회 상품). 실패해도 앱이 다시 시도한다
	var at := await _access_token()
	if at == "":
		return
	var url := _product_url(product_id, token) + (":consume" if consumable else ":acknowledge")
	var code := await _http_code(url, HTTPClient.METHOD_POST, ["Authorization: Bearer " + at, "Content-Type: application/json"], "{}")
	if code < 200 or code >= 300:
		push_warning("결제 %s 실패 (HTTP %d): %s" % ["consume" if consumable else "acknowledge", code, product_id])


func _http(url: String, method: int, headers: Array, body: String) -> Dictionary:
	var res := await _request(url, method, headers, body)
	if res.is_empty():
		return {}
	if int(res[1]) != 200:
		push_warning("결제 서버 HTTP %d: %s" % [res[1], (res[3] as PackedByteArray).get_string_from_utf8().substr(0, 300)])
		return {}
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return d if d is Dictionary else {}


func _http_code(url: String, method: int, headers: Array, body: String) -> int:
	var res := await _request(url, method, headers, body)
	return -1 if res.is_empty() else int(res[1])


func _request(url: String, method: int, headers: Array, body: String) -> Array:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	host.add_child(req)
	if req.request(url, PackedStringArray(headers), method, body) != OK:
		req.queue_free()
		return []
	var res: Array = await req.request_completed
	req.queue_free()
	return res
