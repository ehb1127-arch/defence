# 안드로이드 빌드 / 모바일

## 바로 해 볼 수 있는 것: 디버그 APK (플러그인 없이)

플러그인이 없으면 광고는 테스트 광고, 결제는 "사용 불가"로 표시되지만 게임·온라인·서버 계정은 모두 동작합니다.

1. Godot 4.3 에디터 + **내보내기 템플릿** 설치 (에디터 → 내보내기 템플릿 관리)
2. Android SDK (Android Studio 설치 시 함께 설치됨) + JDK 17 이상
3. 에디터 설정 → 내보내기 → Android: `Android SDK 경로`, `Java SDK 경로`, 디버그 키스토어 지정
4. 프로젝트 → 내보내기 → **Android** 프리셋 → 프로젝트 내보내기 (`build/android/SquareDefense.apk`)
5. `adb install -r build/android/SquareDefense.apk`

명령줄:

```bash
godot --headless --path . --export-debug "Android" build/android/SquareDefense-debug.apk
```

## 출시용 (광고 + 결제 포함)

AdMob·Play Billing 은 안드로이드 라이브러리라 **gradle 빌드**가 필요합니다.

1. 프로젝트 → **Android 빌드 템플릿 설치** (`android/build` 생성)
2. 플러그인 설치: AdMob (docs/ADS.md), GodotGooglePlayBilling (docs/IAP.md)
3. 프리셋 "Android":
   - `gradle_build/use_gradle_build = true`
   - `gradle_build/export_format = 1` (AAB, Play 스토어 업로드용)
   - `gradle_build/target_sdk` = Play 요구 버전 (2025년 8월 이후 신규 앱은 35 이상)
   - `version/code` 를 업로드할 때마다 1씩 올리기, `version/name` 은 표시용
4. **업로드 키** 만들기 (한 번만, 절대 잃어버리지 말 것):

```bash
keytool -genkeypair -v -keystore upload.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

   프리셋의 `keystore/release`, `keystore/release_user`, `keystore/release_password` 에 입력.
   (비밀번호가 들어간 `export_presets.cfg` 는 커밋하지 말고, 환경 변수
   `GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD` 를 쓰는 것을 권장)
5. Play Console: 앱 만들기 → 내부 테스트 트랙에 AAB 업로드 → Play 앱 서명 사용

## 프리셋 요약 (`export_presets.cfg`)

| 항목 | 값 |
| --- | --- |
| 패키지 | `com.squaredefense.game` |
| 아키텍처 | arm64-v8a (Play 필수. 구형 32비트 기기까지 원하면 armeabi-v7a 추가) |
| 권한 | INTERNET, ACCESS_NETWORK_STATE, VIBRATE |
| 화면 | 가로(센서), 몰입 모드(상태바 숨김) |
| 아이콘 | `art/app/icon_192.png`, 적응형 `icon_fg_432.png` / `icon_bg_432.png` (교체 가능) |
| 렌더러 | GL Compatibility (구형 기기 호환), ETC2/ASTC 텍스처 |

## 모바일 대응 (`scripts/autoload/Platform.gd`)

- **뒤로 가기**: 열린 창/시트 닫기 → 게임 중이면 일시정지 → 한 번 더 누르면 메뉴 → 메뉴에서 두 번 누르면 종료
  - 장면에 `on_back() -> bool` 을 만들면 그 장면만의 처리 가능
- **앱 전환/전화 수신**: 자동 저장 + 게임 자동 일시정지 (`on_app_paused()`)
- **화면 꺼짐 방지**: 게임 중에만
- **진동**: 설정에서 끄기 가능 (`Platform.vibrate(ms)`)
- **길게 누르기**: 모든 아이콘 버튼을 길게 누르면 설명 말풍선 (터치에는 마우스 오버가 없으므로)
- **대전 화면**: 휴대폰에서는 내 전장을 크게, 상대 전장은 위쪽 ⚔ 버튼(숫자 = 상대 필드 적 수)으로 바꿔 보기
  - PC 에서 확인: 설정 > "대전: 내 전장 크게", 또는 `-- --mobile` 로 실행 (Backspace = 뒤로 가기)
- 화면 비율: 1600×900 기준 `keep` → 20:9 폰에서는 좌우에 여백(배경색). 노치 영역을 피함

## 확인한 것

- 이 저장소에서 `--export-debug "Android"` 로 서명된 디버그 APK 생성 확인 (arm64, 약 25MB)
- 실제 기기 테스트, 광고/결제 플러그인 포함 gradle 빌드는 Android SDK 가 있는 PC 에서 진행 필요
