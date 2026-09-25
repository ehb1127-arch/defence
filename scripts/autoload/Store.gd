extends Node
## 인앱 결제 (Google Play Billing).
##
## provider
##   "google" : GodotGooglePlayBilling 안드로이드 플러그인이 있을 때 (docs/IAP.md)
##   "mock"   : 개발용 테스트 결제 (디버그 빌드에서만. 출시 빌드에서는 결제 불가로 표시)
##   "none"   : 결제 불가
##
## 지급은 항상 서버가 한다: 스토어 결제 → 영수증(purchase token)을 서버로 → 서버가 Google 에
## 확인하고 계정에 지급 → 클라이언트가 consume(소모성)/acknowledge(1회 상품).
## 서버에 접속하지 않은 상태의 결제는 기기에 남아 있다가 다음 접속 때 다시 확인한다.

signal products_updated
signal purchase_finished(product_id: String, ok: bool, msg: String)

const PURCHASED := 1   # 플러그인의 purchase_state 값 (0 = 알 수 없음, 1 = 결제됨, 2 = 대기)

var provider := "none"
var prices := {}          # 상품 id -> 스토어 표시 가격 ("₩1,200")
var busy := false
var _bp: Object = null    # 결제 플러그인 싱글톤
var _pending := {}        # 서버 확인 대기: req_id -> {product, token}
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


func available() -> bool:
	return provider != "none"


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
	match provider:
		"google":
			busy = true
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
			purchase_finished.emit(str(ids[0]), false, "결제는 되었어요. 서버에 접속하면 지급됩니다")


func _on_purchase_error(_code: int, msg: String) -> void:
	busy = false
	purchase_finished.emit("", false, "결제 취소/실패: %s" % msg)


func _send(id: String, token: String) -> void:
	_req += 1
	_pending[_req] = {"product": id, "token": token}
	Net.send_iap(_req, id, token)


func _on_server_result(req_id: int, ok: bool, product_id: String, msg: String) -> void:
	if not _pending.has(req_id):
		return
	var p: Dictionary = _pending[req_id]
	_pending.erase(req_id)
	# 지급됐거나 이미 지급된 영수증이면 스토어에서 정리 (소모성은 다시 살 수 있게 consume)
	if provider == "google" and (ok or msg == "이미 사용한 영수증"):
		if GameData.iap_product(product_id).get("consumable", false):
			_bp.consumePurchase(p["token"])
		else:
			_bp.acknowledgePurchase(p["token"])
	purchase_finished.emit(product_id, ok, msg)
