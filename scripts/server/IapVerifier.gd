extends RefCounted
## 전용 서버: Google Play 인앱 결제 영수증(purchase token) 검증.
##
## 환경 변수
##   SQD_GOOGLE_SA   서비스 계정 키 JSON 파일 경로 (Play Console → API 액세스에서 권한 부여)
##   SQD_PACKAGE     앱 패키지 이름 (기본 com.squaredefense.game)
##   SQD_IAP_TEST=1  개발용: "test:" 로 시작하는 가짜 토큰을 결제로 인정 (출시 서버에서는 절대 켜지 말 것)
##
## 흐름: 서비스 계정으로 JWT(RS256) 서명 → OAuth 토큰 → androidpublisher v3 purchases.products.get
## 같은 토큰(주문)은 한 번만 지급 (user://server_iap.json 에 기록)
## 설정 방법: docs/IAP.md

const TOKEN_URL := "https://oauth2.googleapis.com/token"
const SCOPE := "https://www.googleapis.com/auth/androidpublisher"
const API := "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/%s/purchases/products/%s/tokens/%s"
const USED_PATH := "user://server_iap.json"

var host: Node
var package_name := "com.squaredefense.game"
var test_mode := false
var _sa := {}             # 서비스 계정 JSON
var _key: CryptoKey
var _access := ""
var _access_exp := 0.0
var _used := {}           # 토큰 → {dev, product, t}


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
	if FileAccess.file_exists(USED_PATH):
		var u = JSON.parse_string(FileAccess.get_file_as_string(USED_PATH))
		if u is Dictionary:
			_used = u
	print("[결제 검증] %s%s" % ["Google Play 연결됨" if ready() else "서비스 계정 없음 (결제 지급 불가)", " / 테스트 토큰 허용" if test_mode else ""])


func ready() -> bool:
	return not _sa.is_empty()


func verify(product_id: String, token: String, dev: String) -> Dictionary:
	## 결과 {ok, msg}. 성공이면 토큰을 사용 처리한다
	if GameData.iap_product(product_id).is_empty():
		return {"ok": false, "msg": "없는 상품"}
	if token == "" or token.length() > 4096:
		return {"ok": false, "msg": "영수증 없음"}
	var key := token.sha256_text()
	if _used.has(key):
		return {"ok": false, "msg": "이미 사용한 영수증"}
	var ok := false
	var msg := ""
	if token.begins_with("test:"):
		ok = test_mode
		msg = "" if ok else "테스트 결제는 이 서버에서 받지 않습니다"
	elif not ready():
		msg = "서버 결제 설정 전"
	else:
		var r := await _get_purchase(product_id, token)
		if r.is_empty():
			msg = "스토어 확인 실패"
		elif int(r.get("purchaseState", 1)) != 0:
			msg = "결제 완료 상태가 아님"
		else:
			ok = true
	if ok:
		_used[key] = {"dev": dev, "product": product_id, "t": int(Time.get_unix_time_from_system())}
		var f := FileAccess.open(USED_PATH, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(_used))
	return {"ok": ok, "msg": msg}


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


func _get_purchase(product_id: String, token: String) -> Dictionary:
	var at := await _access_token()
	if at == "":
		return {}
	var url := API % [package_name, product_id.uri_encode(), token.uri_encode()]
	return await _http(url, HTTPClient.METHOD_GET, ["Authorization: Bearer " + at], "")


func _http(url: String, method: int, headers: Array, body: String) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = 15.0
	host.add_child(req)
	if req.request(url, PackedStringArray(headers), method, body) != OK:
		req.queue_free()
		return {}
	var res: Array = await req.request_completed
	req.queue_free()
	if int(res[1]) != 200:
		push_warning("결제 검증 HTTP %d: %s" % [res[1], (res[3] as PackedByteArray).get_string_from_utf8().substr(0, 300)])
		return {}
	var d = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return d if d is Dictionary else {}
