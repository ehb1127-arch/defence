# 그림 교체 가이드 (art/)

이 폴더에 **정해진 이름의 PNG** 를 넣으면 게임이 코드로 그린 임시 그림 대신 자동으로 그 이미지를 씁니다.
파일이 없으면 지금처럼 임시 그림이 나오므로, **한 장씩 순서대로 교체**해도 됩니다. 코드 수정은 필요 없습니다.

- 형식: PNG (투명 배경 권장). 파일을 넣고 Godot 에디터를 한 번 열면 자동 임포트됩니다.
- 경로 규칙: `art/<폴더>/<이름>.png` → 코드에서는 `Art.tex("<폴더>/<이름>")`
- 전장 좌표계: 전장 560×560, 트랙 폭 56, 안쪽 격자 448×448 (6×6 칸, 한 칸 약 75px). 화면에서는 최대 1.41배로 확대됩니다.

## units/ — 유닛 (권장 256×256, 정사각형, 캐릭터가 가운데)

칸 안에서는 초상화가 칸의 약 70% 크기로 그려집니다. 등급 테두리/마릿수 점은 게임이 따로 그리므로 **캐릭터만** 그리면 됩니다.

| 파일 | 이름 | 등급 |
| --- | --- | --- |
| `units/sword.png` | 검사 | 일반 |
| `units/archer.png` | 궁수 | 일반 |
| `units/mage.png` | 견습마법사 | 일반 |
| `units/spear.png` | 창병 | 일반 |
| `units/slinger.png` | 투석병 | 일반 |
| `units/knight.png` | 기사 | 희귀 |
| `units/sniper.png` | 저격수 | 희귀 |
| `units/frost.png` | 얼음술사 | 희귀 |
| `units/pyro.png` | 화염술사 | 희귀 |
| `units/rogue.png` | 도적 | 희귀 |
| `units/storm.png` | 번개술사 | 영웅 |
| `units/berserk.png` | 광전사 | 영웅 |
| `units/alch.png` | 연금술사 | 영웅 |
| `units/bard.png` | 음유시인 | 영웅 |
| `units/ranger.png` | 사냥꾼 | 영웅 |
| `units/dragoon.png` | 용기사 | 전설 |
| `units/archmage.png` | 대마법사 | 전설 |
| `units/assassin.png` | 암살자 | 전설 |
| `units/guardian.png` | 수호천사 | 전설 |
| `units/phoenix.png` | 불사조 | 신화 |
| `units/thunder.png` | 뇌신 | 신화 |
| `units/chrono.png` | 시간술사 | 신화 |
| `units/midas.png` | 황금왕 | 신화 |
| `units/reaper.png` | 그림자군주 | 신화 |

## enemies/ — 적 (권장 128×128, 보스는 256×256)

적 크기(반지름)의 약 2.8배 사각형에 그려집니다. 피격 시 밝게, 기절 시 노랗게, 둔화 시 파랗게 색이 곱해집니다.

| 파일 | 설명 |
| --- | --- |
| `enemies/normal.png` | 일반 적 |
| `enemies/fast.png` | 빠른 적 |
| `enemies/tank.png` | 탱커(사각형) |
| `enemies/shield.png` | 보호막 |
| `enemies/splitter.png` | 분열 |
| `enemies/mini.png` | 분열된 작은 적 |
| `enemies/healer.png` | 치유 |
| `enemies/boss.png` | 보스 |
| `enemies/elite.png` | 정예(대전 공격) |
| `enemies/goblin.png` | 황금 고블린 |
| `enemies/bonus.png` | 보물 돼지(보너스 라운드) |

## icons/ — 아이콘 (권장 128×128)

| 파일 | 쓰이는 곳 |
| --- | --- |
| `icons/gold.png` | 골드 |
| `icons/gem.png` | 보석 |
| `icons/coin.png` | 코인(상점 재화) |
| `icons/summon.png` | 소환 |
| `icons/merge.png` | 합성 |
| `icons/gamble.png` | 운명 소환 |
| `icons/upgrade.png` | 강화 |
| `icons/luck.png` | 소환 행운 |
| `icons/recipe.png` | 신화 조합 / 게임 방법 |
| `icons/attack.png` | 공격(대전) |
| `icons/gift.png` | 협동 / 선물 |
| `icons/blast.png` | 합동 폭격 |
| `icons/mission.png` | 도전 과제 |
| `icons/shop.png` | 상점 |
| `icons/ad.png` | 광고 |
| `icons/pause.png` | 일시정지 |
| `icons/play.png` | 재생 / 다시하기 |
| `icons/speed.png` | 배속 |
| `icons/home.png` | 메인 메뉴 |
| `icons/sound.png` | 소리 켬 |
| `icons/mute.png` | 소리 끔 |
| `icons/gear.png` | 설정 |
| `icons/revive.png` | 부활 |
| `icons/heart.png` | 협동 2인 카드 |
| `icons/sell.png` | 판매 |
| `icons/close.png` | 닫기 |
| `icons/back.png` | 뒤로 |
| `icons/check.png` | 완료 / 조합 가능 |
| `icons/lock.png` | 잠김 |
| `icons/chest.png` | 보물상자 |
| `icons/swarm.png` | 잡몹 떼 |
| `icons/elite.png` | 정예 괴수 |
| `icons/curse.png` | 저주 |
| `icons/star.png` | 등급 / 난이도 / 솔로 카드 |
| `icons/spawn.png` | 적 출현 지점 |
| `icons/defeat.png` | 패배 표시 |
| `icons/slot.png` | 럭키 슬롯 |
| `icons/emote.png` | 이모티콘 (온라인) |
| `icons/book.png` | 도감 |
| `icons/help.png` | 게임 방법 |
| `icons/wheel.png` | 룰렛 |
| `icons/skull.png` | 해골 (슬롯 꽝, 보스 미션) |
| `icons/mode_solo.png` | 메뉴 카드: 솔로 (없으면 star) |
| `icons/mode_coop_ai.png` | 메뉴 카드: 협동 AI |
| `icons/mode_pvp_ai.png` | 메뉴 카드: 대전 AI |
| `icons/mode_coop_2p.png` | 메뉴 카드: 협동 2인 |
| `icons/mode_pvp_2p.png` | 메뉴 카드: 대전 2인 |
| `icons/mode_online.png` | 메뉴 카드: 온라인 |

## board/ — 전장

| 파일 | 크기 | 설명 |
| --- | --- | --- |
| `board/background.png` | 1120×1120 (560 의 2배) | 전장 전체(트랙 + 안쪽). 트랙은 바깥 56px(×2=112px) 띠 |
| `board/cell.png` | 150×150 | 격자 한 칸 바닥 |

## ui/ — 화면/패널 (9-slice: 모서리 16px 는 늘어나지 않음)

| 파일 | 설명 |
| --- | --- |
| `ui/button_normal.png` | 버튼 기본 |
| `ui/button_hover.png` | 버튼 마우스 오버 |
| `ui/button_pressed.png` | 버튼 눌림 |
| `ui/button_disabled.png` | 버튼 비활성 |
| `ui/hud_panel.png` | 조작 패널 배경 |
| `ui/hud_inner.png` | 조작 패널 안쪽 칸(선택 카드, 조합표) |
| `ui/sheet_panel.png` | 운명 소환/강화/조합 팝업 |
| `ui/result_panel.png` | 결과 화면 |
| `ui/popup_panel.png` | 메인 메뉴 팝업 창 (온라인·설정·업적·랭킹 등) |
| `ui/card.png` | 상점 카드 |
| `ui/menu_bg.png` | 메인 메뉴 배경 (1600×900, 9-slice 아님) |
| `ui/shop_bg.png` | 상점 배경 (1600×900, 9-slice 아님) |
| `ui/logo.png` | (현재 로비에서는 쓰지 않음 - 로딩/타이틀 화면용으로 예약) |

## portraits/ — 스토리 초상화 (권장 640×720, 투명 배경)

| 파일 | 인물 |
| --- | --- |
| `portraits/arka.png` | 아르카 (스승) |
| `portraits/rina.png` | 리나 (동료 궁수) |
| `portraits/kael.png` | 카엘 (라이벌) |
| `portraits/lord.png` | 사각의 군주 (최종 보스) |
| `portraits/ogre.png` / `lich.png` / `golem.png` / `eye.png` | 장 보스 |

스토리 배경: `ui/chapter_1.png` ~ `ui/chapter_5.png` (1600×900), 대화창: `ui/dialogue_panel.png` (9-slice)

## 글자 표시

- 전장 칸에는 유닛 이름을 쓰지 않습니다. 마우스를 올리거나 선택했을 때만 이름표가 뜹니다.
- 버튼 이름은 설정의 **"버튼 이름 표시"** 를 켰을 때만 작게 표시됩니다 (기본 꺼짐, 설명은 마우스를 올리면 툴팁으로).
- 폰트 교체: `fonts/` 에 새 폰트를 넣고 `project.godot` 의 `gui/theme/custom_font` 와 `GameData.ui_theme()` 경로를 바꾸면 됩니다.

### 색 버튼 (코드로 그리는 입체 버튼)

로비·상점·전투 조작 버튼 중 색이 있는 버튼(전투 시작, 구매, 소환 등)은 `ActionButton.tone` 색으로
`UIKit.draw_gloss()` 가 그립니다. 이미지로 바꾸려면 해당 버튼의 `tone` 을 지우고
`art/ui/button_*.png` 스킨을 쓰거나, `UIKit.draw_gloss` 안에서 텍스처를 그리도록 바꾸면 됩니다.
