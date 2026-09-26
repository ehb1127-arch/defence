extends Node
## 인앱 결제 (Google Play Billing).
##
## provider
##   "google" : GodotGooglePlayBilling 안드로이드 플러그인이 있을 때 (docs/IAP.md)
##   "mock"   : 개발용 테스트 결제 (디버그 빌드에서만. 출시 빌드에서는 결제 불가로 표시)
##   "none"   : 결제 불가
##
## 지급은 항상 서버가 한다: 스토어 결제 → 영수증(purchase token)을 서버로 → 서버가 Google 에
## 확인하고 계정에 지급 → 클라이언트가 consume(소모성)/acknowledge(1회 상품) (서버도 직접 한다).
## 서버에 연결되지 않았으면 결제 버튼을 막는다 (can_buy / block_reason).
## 그래도 지급 전에 끊긴 결제는 기기에 남아 있다가 다음 접속 때 다시 확인한다.
## 새 폰/재설치: 서버 계정(복구 코드)으로 들어오면 1회 상품(광고 제거 등)은 영수증으로 복원된다.

signal products_updated
signal purchase_finished(product_id: String, ok: bool, msg: String)

const PURCHASED := 1   # 플러그인의 purchase_state 값 (0 = 알 수 없음, 1 = 결제됨, 2 = 대기)

var provider := "none"
var prices := {}          # 상품 id -> 스토어 표시 가격 ("₩1,200")
var busy := false
var _bp: Object = null    # 결제 플러그인 싱글톤
var _pending := {}        # 서버 확인 대기: req_id -> {product, token}
var _inflight := {}       # 서버에 보낸 영수증 토큰 (같은 토큰을 겹쳐 보내지 않게)
var _req := 1000000       # Profile 요청 번호와 겹치지 않게


func _ready() -> void:
	if Engine.has_singleton("GodotGooglePlayBilling"):
		provider = "google"
		_bp = Engine.get_singleton("GodotGooglePlayBilling")
		_connect_plugin()
		_bp.startConnection()
	elif OS.is_debug_build():
		provider = "mock"
	Net.iap_result.connect(_on_server_result)
	Net.account_synced.connect(_restore)
	Net.account_synced.connect(products_updated.emit)   # 결제 가능 여부가 바뀜 → 상점 버튼 다시 그리기
	Net.connection_changed.connect(_on_connection)


func _on_connection(c: bool) -> void:
	if not c:
		# 끊기면 확인 대기 중이던 영수증은 다음 접속 때 복원 조회로 다시 보낸다
		_inflight.clear()
		_pending.clear()
		busy = false
	products_updated.emit()


func available() -> bool:
	return provider != "none"


func can_buy() -> bool:
	## 지금 결제 버튼을 눌러도 되는지 (서버가 지급하므로 서버 연결이 필요)
	return block_reason() == ""


func block_reason() -> String:
	## 결제할 수 없는 이유 (짧은 한국어). 살 수 있으면 ""
	match provider:
		"none":
			return "이 기기에서는 결제를 쓸 수 없어요"
		"google":
			if not Net.econ_online():
				return "서버에 연결되면 살 수 있어요"
		"mock":
			# 개발용: 서버 계정과 연결된 적 있으면 서버가 지급해야 하므로 연결 필요
			if Profile.linked and not Net.econ_online():
				return "서버에 연결되면 살 수 있어요"
	if busy:
		return "결제 진행 중이에요"
	return ""


func price(id: String) -> String:
	return prices.get(id, GameData.iap_product(id).get("price", ""))


func owned(id: String) -> bool:
	## 1회 한정 상품을 이미 샀는지
	var p := GameData.iap_product(id)
	if p.get("grant", {}).get("no_ads", false) and Profile.no_ads:
		return true
	return p.get("once", false) and Profile.purchases.get(id, false)


func buy(id: String) -> void:
	if busy or owned(id) or GameData.iap_product(id).is_empty():
		return
	if not can_buy():
		purchase_finished.emit(id, false, block_reason())
		return
	match provider:
		"google":
			busy = true
			# 결제를 이 계정에 묶는다 (서버가 영수증의 계정 표시를 확인)
			if _bp.has_method("setObfuscatedAccountId"):
				_bp.setObfuscatedAccountId(Profile.account_hash())
			_bp.purchase(id)
		"mock":
			_mock_buy(id)
		_:
			purchase_finished.emit(id, false, "이 기기에서는 결제를 사용할 수 없어요")


# ---- 개발용 ----
func _mock_buy(id: String) -> void:
	if Net.econ_online():
		# 서버가 SQD_IAP_TEST=1 이면 "test:" 영수증을 인정
		_send(id, "test:%d-%d" % [Time.get_ticks_usec(), randi()])
	else:
		var ok := Profile.iap_grant(id)
		purchase_finished.emit(id, ok, "" if ok else "이미 받은 상품")


# ---- Google Play Billing 플러그인 (구버전 sku / 신버전 product API 모두 지원) ----
func _connect_plugin() -> void:
	var sigs := {
		"connected": _on_connected,
		"purchases_updated": _on_purchases_updated,
		"purchase_error": _on_purchase_error,
		"sku_details_query_completed": _on_details,
		"product_details_query_completed": _on_details,
		"query_purchases_response": _on_query_purchases,
	}
	for s in sigs:
		if _bp.has_signal(s):
			_bp.connect(s, sigs[s])


func _on_connected() -> void:
	var ids: Array = []
	for p in GameData.IAP_PRODUCTS:
		ids.append(p["id"])
	if _bp.has_method("queryProductDetails"):
		_bp.queryProductDetails(ids, "inapp")
	elif _bp.has_method("querySkuDetails"):
		_bp.querySkuDetails(ids, "inapp")
	_restore()


func _on_details(details: Array) -> void:
	for d in details:
		var id := str(d.get("product_id", d.get("sku", "")))
		var pr := str(d.get("price", ""))
		if d.has("one_time_purchase_offer_details"):
			pr = str(d["one_time_purchase_offer_details"].get("formatted_price", pr))
		if id != "" and pr != "":
			prices[id] = pr
	products_updated.emit()


func _restore() -> void:
	## 지급 전에 끊긴 결제 다시 확인
	if provider == "google" and _bp != null and Net.econ_online():
		_bp.queryPurchases("inapp")


func _on_query_purchases(res: Dictionary) -> void:
	if int(res.get("status", 0)) == 0:
		_on_purchases_updated(res.get("purchases", []))


func _on_purchases_updated(list: Array) -> void:
	busy = false
	for p in list:
		if int(p.get("purchase_state", 0)) != PURCHASED:
			continue
		var ids: Array = p.get("product_ids", p.get("skus", [p.get("sku", "")]))
		if ids.is_empty():
			continue
		var token := str(p.get("purchase_token", ""))
		if Net.econ_online():
			_send(str(ids[0]), token)
		else:
			purchase_finished.emit(str(ids[0]), false, "결제 완료! 서버에 연결되면 받아요")


func _on_purchase_error(_code: int, msg: String) -> void:
	busy = false
	purchase_finished.emit("", false, "결제 취소/실패: %s" % msg)


func _send(id: String, token: String) -> void:
	if _inflight.has(token):
		return   # 이미 서버가 확인 중 (결제 완료 알림과 복원 조회가 겹칠 때)
	_inflight[token] = true
	_req += 1
	_pending[_req] = {"product": id, "token": token}
	Net.send_iap(_req, id, token)


func _on_server_result(req_id: int, ok: bool, product_id: String, msg: String) -> void:
	if not _pending.has(req_id):
		return
	var p: Dictionary = _pending[req_id]
	_pending.erase(req_id)
	_inflight.erase(p["token"])
	# 지급·복원됐거나 이미 지급된 영수증이면 스토어에서 정리 (소모성은 다시 살 수 있게 consume)
	if provider == "google" and (ok or msg == "이미 사용한 영수증" or msg == "이미 받은 상품"):
		if GameData.iap_product(product_id).get("consumable", false):
			_bp.consumePurchase(p["token"])
		else:
			_bp.acknowledgePurchase(p["token"])
	purchase_finished.emit(product_id, ok, msg)
