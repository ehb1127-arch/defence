# 광고 연동 가이드

게임 코드는 광고를 **한 가지 방법으로만** 부릅니다.

```gdscript
Ads.show_rewarded("placement 이름", func(): 보상_지급())
```

| provider | 언제 | 동작 |
| --- | --- | --- |
| `admob` | 안드로이드/iOS + `addons/admob` 플러그인 설치됨 | 실제 AdMob 보상형 광고 (미리 불러 두고, 실패하면 20초 후 재시도) |
| `mock` | PC, 에디터, 플러그인 없음 | 테스트 광고 (5초 카운트다운 → 보상 받기) |

**광고 제거** 상품(`no_ads`)을 산 계정은 광고 없이 바로 보상을 받습니다.
하루 광고 횟수 제한과 보상은 서버 계정 기준입니다 (docs/ECONOMY.md).

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

코드는 이미 들어 있습니다 (`Ads.gd` 가 플러그인 클래스를 **이름으로** 찾아서, 플러그인이 없어도 컴파일됨).

1. Godot 에디터 → 프로젝트 → **Android 빌드 템플릿 설치** (gradle 빌드 필요, docs/ANDROID.md)
2. AssetLib 또는 GitHub 에서 **poing-studios "Godot AdMob" (Godot 4 용)** 설치 → `addons/admob` 생성
   - 에디터 플러그인 목록에서 활성화, 플러그인 문서대로 Android 라이브러리(aar) 설치
3. AdMob 콘솔에서 앱 등록 → **앱 ID** 를 플러그인 설정(AndroidManifest 의 `com.google.android.gms.ads.APPLICATION_ID`)에 입력
4. 보상형 광고 단위 ID 를 `project.godot` 의 `application/ads/android_rewarded_id` 에 입력
   (지금은 **Google 공식 테스트 ID**. 개발 중 실제 ID 로 본인 광고를 누르면 계정이 정지될 수 있습니다)
5. 내보내기 프리셋 "Android" 에서 `gradle_build/use_gradle_build = true` 로 바꾸고 빌드
6. 기기에서 광고 버튼 → 테스트 광고가 뜨면 성공. 안 뜨면 `adb logcat | grep -i ads`

사용하는 플러그인 API: `MobileAds.initialize()`, `RewardedAdLoader.load(id, AdRequest, RewardedAdLoadCallback)`,
`RewardedAd.full_screen_content_callback`, `RewardedAd.show(OnUserEarnedRewardListener)`.
다른 플러그인을 쓰면 `Ads.gd` 의 `_find_admob / _preload / _show_admob` 세 함수만 바꾸면 됩니다.

개인정보: 한국/EU 출시 시 UMP(동의 팝업) 처리와 개인정보처리방침 링크가 필요합니다.
Play Console 의 "데이터 보안" 항목에 광고 ID 수집을 표시하세요.

## 테스트

- PC 에서는 항상 테스트 광고가 뜹니다. 자동 테스트에서는 `Ads.auto_claim = true` 로 즉시 보상 처리할 수 있습니다.
- 하루 제한은 `Profile.ads_left()` (날짜가 바뀌면 초기화). 저장 위치: `user://profile.cfg`

## 주의

- 서버에 접속한 계정은 코인/아이템이 **서버에 저장**되고 기기 파일은 캐시일 뿐입니다 (docs/ECONOMY.md).
- 광고 보상은 광고 SDK 의 "보상 받음" 콜백 기준입니다. 더 강하게 막으려면 AdMob **서버 측 확인(SSV)** 을
  서버에 붙이세요 (AdMob 이 서버 URL 로 서명된 보상 알림을 보냄).
