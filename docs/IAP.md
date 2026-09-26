# 인앱 결제 (Google Play Billing)

## 상품

`GameData.IAP_PRODUCTS` — Play Console 의 **인앱 상품 ID 와 똑같이** 등록합니다.

| ID | 이름 | 종류 | 지급 |
| --- | --- | --- | --- |
| `coins_s` | 코인 한 줌 | 소모성 | 코인 300 |
| `coins_m` | 코인 자루 | 소모성 | 코인 1800 |
| `coins_l` | 코인 금고 | 소모성 | 코인 4200 |
| `starter_pack` | 초보자 꾸러미 | 1회 | 코인 800 + 부활 깃털 3 + 소환권 5 + 행운 부적 2 |
| `no_ads` | 광고 제거 | 1회 | 광고 없이 보상 + 코인 500 |

가격은 Play Console 에서 정합니다. 게임은 스토어에서 받은 현지 가격을 표시합니다 (못 받으면 표의 기본 문구).

## 흐름 (지급은 항상 서버)

```
상점 [충전] → Store.can_buy()? (서버 연결 필요, 아니면 block_reason() 안내)
  → Store.buy(id) → (결제에 계정 표시 setObfuscatedAccountId(해시)) → Google 결제창
  → purchases_updated(구매 토큰)
  → Net.send_iap(상품, 토큰) ──▶ 서버 IapVerifier
                                   ① 토큰을 "확인 중"으로 먼저 기록 (같은 토큰이 동시에 와도 한 번만)
                                   ② Google Play Developer API 로 확인
                                      purchaseState == 0, 소모성은 consumptionState == 0,
                                      1회 상품이 이미 acknowledge 됐거나 다른 계정 표시면 "복원"만
                                   ③ 계정에 지급 → 저장 → 서버가 직접 consume/acknowledge
  ◀── _c_iap(성공, 계정 전체)
  → 앱도 consumePurchase / acknowledgePurchase (서버가 먼저 했으면 무시됨)
```

- 결제 버튼은 **서버에 연결됐을 때만** 누를 수 있습니다 (`Store.can_buy()`, 안 되면 `Store.block_reason()` 을 보여 주세요).
- 그래도 지급 전에 끊긴 결제는 기기에 남아 있다가, **다음 접속 때 자동으로 다시 확인·지급**합니다 (`queryPurchases`).
- Google 은 3일 안에 acknowledge/consume 되지 않은 결제를 **자동 환불**합니다 → 서버가 지급 직후 직접 처리합니다.
- 같은 토큰은 한 번만 지급 (`server_iap.json`, 주문 번호로도 확인).
- **구매 복원**: 이미 지급한 1회 상품 영수증이 다른 계정(재설치·새 폰)에서 오면 권리(광고 제거·구매 기록)만 되살립니다.
  코인·아이템은 다시 주지 않고, 영수증 하나로 최대 3개 계정까지. 진행 전체를 옮기려면 복구 코드 (docs/ECONOMY.md).
- **환불 회수**: 서버가 6시간마다 Voided Purchases API 를 조회해, 환불·취소된 결제로 준 코인·아이템을 빼고
  광고 제거를 끕니다 (코인은 마이너스가 될 수 있음). 복원만 받은 계정은 권리만 회수.

## 클라이언트 설정 (안드로이드)

1. gradle 빌드 사용 (docs/ANDROID.md)
2. **GodotGooglePlayBilling** 플러그인 설치 (godot-sdk-integrations/godot-google-play-billing, Godot 4 용)
   - `Store.gd` 는 싱글톤 이름 `GodotGooglePlayBilling` 을 찾고, 구버전(sku)/신버전(product) API 모두 지원
3. 내보내기 프리셋에서 플러그인 체크, 권한 `com.android.vending.BILLING` 은 플러그인이 추가
4. Play Console 에 **비공개 테스트 트랙**으로 AAB 업로드 → 라이선스 테스터 계정으로 결제 테스트

## 서버 설정 (OCI)

1. Google Cloud 콘솔에서 **서비스 계정** 만들기 → JSON 키 다운로드
2. Play Console → 설정 → **API 액세스** → 그 서비스 계정에 "재무 데이터 보기 / 주문 관리" 권한
   (주문 관리 = consume/acknowledge, 무효 구매 조회에 필요)
3. 서버에 키 파일 복사 (예: `/opt/sqdefense/sa.json`, 권한 600) 후 서비스 환경 변수:

```ini
# /etc/systemd/system/sqdefense.service 의 [Service]
Environment=SQD_GOOGLE_SA=/opt/sqdefense/sa.json
Environment=SQD_PACKAGE=com.squaredefense.game
```

4. `sudo systemctl daemon-reload && sudo systemctl restart sqdefense`
   → 로그에 `[결제 검증] Google Play 연결됨` 이 나오면 준비 완료

서버는 서비스 계정 키로 JWT(RS256)를 서명해 OAuth 토큰을 받고 다음을 호출합니다.
- `GET  androidpublisher/v3/applications/{패키지}/purchases/products/{상품}/tokens/{토큰}` (확인)
- `POST …/tokens/{토큰}:consume` (소모성) / `:acknowledge` (1회 상품)
- `GET  androidpublisher/v3/applications/{패키지}/purchases/voidedpurchases?startTime=…` (6시간마다, 환불 회수)
서버에서 `oauth2.googleapis.com`, `androidpublisher.googleapis.com` 으로 나가는 HTTPS 가 열려 있어야 합니다.

## 개발 / 테스트

- PC(디버그 빌드)에서는 `Store.provider = "mock"`: 오프라인이면 바로 지급, 서버 접속 중이면 `test:` 영수증을 보냄
- 테스트 서버만: `SQD_IAP_TEST=1` 로 켜면 `test:` 영수증을 인정 (**출시 서버에서는 절대 켜지 말 것**)
- `test:` 영수증은 실제 확인처럼 0.3초 기다린 뒤 인정 (동시 요청 시험용)
- 자동 테스트: `tests/econ_test.gd` (지급, 영수증 재사용 거절, 1회 상품 중복 거절, **같은 영수증 동시 2번 → 1번만 지급**)

## 출시 체크

- [x] 환불 처리: **무효 구매(Voided Purchases) API** 6시간마다 조회 → 회수 (`IapVerifier.poll_voided`)
- [x] 서버에서 consume/acknowledge, 결제에 계정 표시(obfuscatedAccountId) 붙이고 서버에서 확인
- [ ] 실제 결제로 환불 회수 한 번 확인 (라이선스 테스터로 결제 → Play Console 에서 환불 → 6시간 안에 로그 `환불 회수`)
- [ ] 청소년 결제 한도/확률형 아이템 표기 (룰렛은 무료·광고 보상만 → 확률 공개 권장)
- [ ] 개인정보처리방침, 환불 정책 문구
