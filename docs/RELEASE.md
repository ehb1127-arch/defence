# 출시 빌드 (APK · AAB) 와 앱 아이콘

## 앱 이름

| 항목 | 값 |
| --- | --- |
| 게임 이름 (폰 홈 화면) | **결계 수호대** |
| 영문 이름 | Square Guardians |
| Play 스토어 제목 (추천) | **결계 수호대: 랜덤 합성 디펜스** |
| 패키지 이름 | `com.squaredefense.game` (유저에게는 안 보임. 첫 업로드 후에는 바꿀 수 없음) |

## 자동 빌드 (깃허브 Actions)

`.github/workflows/android-latest-release.yml` 이 브랜치에 푸시할 때마다(또는 Actions 탭에서 수동 실행) 돌아가며,
결과를 저장소의 **Releases > latest** 에 올립니다.

| 파일 | 용도 |
| --- | --- |
| `SquareGuardians-debug.apk` | 테스트용. 폰에 바로 설치 |
| `SquareGuardians.aab` | 출시용. Play Console 에 업로드 |

- 엔진: Godot **4.7.2** (Play 가 요구하는 16KB 페이지 크기 지원). 로컬 테스트에서 4.3 과 같은 결과로 동작 확인.
- 출시용 AAB: 그래들 빌드, 대상 SDK **36**, arm64 + armv7
- 버전 번호는 빌드마다 자동으로 올라갑니다 (`0.1.<빌드 번호>`)

## 업로드 키 (최초 1번)

Play 스토어에 올리는 AAB 는 **업로드 키**로 서명해야 합니다. 이 키는 **절대 잃어버리면 안 됩니다** (백업 필수).

1. 키 만들기 (자바가 설치된 PC 에서):
   ```bash
   keytool -genkeypair -v -keystore upload.keystore -alias upload -keyalg RSA -keysize 2048 -validity 10000
   ```
   비밀번호를 정하고, 이름 등은 아무렇게나 입력해도 됩니다.
2. base64 로 바꾸기:
   - 맥/리눅스: `base64 -w0 upload.keystore > upload.b64` (맥은 `base64 -i upload.keystore -o upload.b64`)
   - 윈도우 PowerShell: `[Convert]::ToBase64String([IO.File]::ReadAllBytes("upload.keystore")) > upload.b64`
3. 깃허브 저장소 → **Settings → Secrets and variables → Actions → New repository secret** 에 3개 등록:

   | 이름 | 값 |
   | --- | --- |
   | `ANDROID_UPLOAD_KEYSTORE_BASE64` | `upload.b64` 파일 내용 전체 |
   | `ANDROID_UPLOAD_KEY_ALIAS` | `upload` (1번에서 정한 별칭) |
   | `ANDROID_UPLOAD_KEY_PASSWORD` | 1번에서 정한 비밀번호 |

4. Actions 탭에서 워크플로우를 다시 실행 → 릴리즈 설명에 "업로드 키로 서명됨" 이 보이면 성공

시크릿이 없으면 **임시 키**로 서명한 AAB 가 만들어집니다 (빌드 확인용, 업로드 불가).

## Play Console 첫 업로드

1. Play Console 에서 앱 만들기 (앱 이름: 결계 수호대, 게임, 무료)
2. **테스트 → 내부 테스트** → 새 버전 만들기 → `SquareGuardians.aab` 업로드
3. Play 앱 서명 사용 (기본값) — 구글이 배포용 키를 관리하고, 우리는 업로드 키만 가짐
4. 스토어 등록정보(설명·스크린샷·아이콘), 콘텐츠 등급, 데이터 보안, 개인정보처리방침 URL 입력
5. 내부 테스터에게 링크 공유 → 설치 확인

> 광고(AdMob)와 결제(Play Billing)는 안드로이드 플러그인을 넣어야 실제로 동작합니다 (docs/ADS.md, docs/IAP.md).
> 플러그인 없이 올린 빌드는 광고·결제가 비활성입니다.

## 앱 아이콘 규격 (직접 만드실 파일)

| 파일 | 크기 | 설명 |
| --- | --- | --- |
| `art/app/icon_192.png` | 192×192 | 기본 아이콘 (구형 폰). 모서리까지 꽉 차게 |
| `art/app/icon_fg_432.png` | 432×432, 투명 배경 | **적응형 아이콘 전경**. 캐릭터·로고는 **가운데 지름 약 264px 원 안**에 (폰마다 원·사각·물방울로 잘림) |
| `art/app/icon_bg_432.png` | 432×432 | 적응형 아이콘 배경 (단색이나 은은한 무늬, 글자 넣지 않기) |
| Play 스토어 아이콘 | 512×512, PNG 32비트, 1MB 이하 | Play Console 에 직접 업로드 (모서리는 구글이 자동으로 둥글게) |
| Play 그래픽 이미지 | 1024×500 | 스토어 상단 배너 |

아이콘 팁 (상위 게임들 공통):
- 작게 봐도 알아보는 **캐릭터 얼굴 하나 + 강한 색 대비** (예: 불사조 얼굴 + 금빛 사각 결계 테두리)
- 글자는 넣지 않거나 아주 짧게 (작은 아이콘에서는 안 읽힘)
- 2~3개 시안을 만들어 Play Console 의 **스토어 등록정보 실험**으로 비교해 보세요
