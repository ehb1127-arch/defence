# 광고 연동 가이드

게임 코드는 광고를 **한 가지 방법으로만** 부릅니다.

```gdscript
Ads.show_rewarded("placement 이름", func(): 보상_지급())
```

지금은 `provider = "mock"` 으로 **테스트 광고**(5초 카운트다운 → 보상 받기)가 뜹니다.
실제 광고를 붙일 때는 `scripts/autoload/Ads.gd` 의 `_show_native()` 만 채우면 됩니다.

## 광고 위치 (placement)

| placement | 위치 | 보상 | 제한 |
| --- | --- | --- | --- |
| `shop_coins` | 상점 > 무료 보상 | 코인 +40 | 하루 8회 (두 상점 광고 합산) |
| `shop_item` | 상점 > 무료 보상 | 랜덤 상점 아이템 1개 | 위와 합산 |
| `match_summon` | 게임 중 광고 버튼 | 무료 소환 3회 | 판당 1회, 솔로/협동(로컬)만 |
| `match_revive` | 패배 화면 | 부활 (적 절반 제거, 보스 재도전 30초) | 판당 1회, 솔로/협동(로컬)만 |
| `result_double` | 결과 화면 | 판 보상 코인 2배 | 판당 1회 |

대전과 온라인에서는 공정성과 동기화 때문에 게임 중 광고(무료 소환/부활)를 띄우지 않습니다.
광고가 떠 있는 동안 게임은 일시정지됩니다 (`get_tree().paused`).

## Android + AdMob 붙이는 순서

1. Godot 에디터 → Project → Install Android Build Template
2. Godot 4 용 AdMob 플러그인 설치 (예: Asset Library 의 "Godot AdMob" 계열 플러그인). 플러그인마다 API 이름이 다르므로 해당 문서를 따릅니다.
3. `Ads.gd` 의 `_ready()` 에서 플러그인 싱글톤을 감지하도록 이름을 맞추고 `provider = "native"` 로 설정
4. `_show_native(placement, finish)` 구현:
   - 보상형 광고 로드 → 표시
   - 사용자가 보상을 받으면 `finish.call(true)`, 닫거나 실패하면 `finish.call(false)`
5. 광고 단위 ID: `ANDROID_REWARDED_ID` / `IOS_REWARDED_ID` 는 현재 **Google 공식 테스트 ID** 입니다. 출시 직전에 AdMob 콘솔의 실제 ID 로 바꾸세요. (개발 중 실제 ID 로 본인 광고를 누르면 계정이 정지될 수 있습니다)
6. 개인정보: 한국/EU 출시 시 UMP(동의 팝업) 처리와 개인정보처리방침 링크가 필요합니다.

## 테스트

- PC 에서는 항상 테스트 광고가 뜹니다. 자동 테스트에서는 `Ads.auto_claim = true` 로 즉시 보상 처리할 수 있습니다.
- 하루 제한은 `Profile.ads_left()` (날짜가 바뀌면 초기화). 저장 위치: `user://profile.cfg`

## 주의

- 코인/아이템은 현재 **기기(로컬 파일)에 저장**됩니다. 파일을 고치면 재화를 조작할 수 있으므로,
  유료 결제(인앱)나 랭킹을 붙일 때는 서버 저장(OCI 서버에 계정/재화 API)으로 옮기는 것을 권장합니다.
