# 온라인 프로토콜

전송: WebSocket (`ws://` 또는 리버스 프록시 뒤 `wss://`), Godot High-level Multiplayer RPC.
서버는 peer id `1`. 모든 RPC 는 `/root/Net` (autoload `scripts/autoload/Net.gd`) 에 정의되어 있습니다.
버전: `Net.PROTOCOL` (현재 `5`). 다르면 서버가 `_a_error` 후 연결을 끊습니다.
RPC 번호는 이름순으로 매겨지므로 인사(`_a_hello`)와 오류(`_a_error`)는 이름을 `_a_` 로 시작해 항상 0·1번에 둡니다
(RPC 를 더하거나 빼도 옛 클라이언트가 버전 안내를 받을 수 있게). 새 RPC 이름은 `_c_`/`_s_` 로.

변경 기록
- 5: 인사/오류 RPC 이름 `_a_hello`/`_a_error`, `_c_welcome` 에 서버 시각, `_c_config`(공지·이벤트), 랭킹 종류(`_s_leaderboard(kind)`), 계정 복구 코드,
  판 표(`begin_match` 작업), 대전 결과는 두 사람 보고가 같을 때만 반영, 이벤트/스냅샷 검사와 빈도 제한
- 4: 계정 재화(`_s_op`), 결제(`_s_iap`)

## 흐름

```
클라이언트                          서버
  | --- WebSocket 연결 ---------------> |
  | _a_hello(name, protocol, device) -> |
  | <---- _c_welcome(id, rooms, time)   |   time = 서버 유닉스 초 (하루 초기화·방치 보상 기준 시계)
  | <------------------- _c_record(rec) |
  | <------------------ _c_config(cfg)  |   전용 서버만. cfg.notice 가 있으면 Net.notice_received
  | <------- _c_profile(profile, need)  |   전용 서버만. 계정 재화 (docs/ECONOMY.md)
  | _s_create(mode, name, false) ----> |   또는 _s_join(room_id) / _s_quick(mode)
  | <-------------------- _c_room(state)|
  |          (두 번째 플레이어 입장)       |
  | _s_start() ----------------------> |   방장만. 빠른 매칭 방은 2명이 되면 자동 시작
  | <--- _c_start(mode, seed, n0, n1, idx)
  | _s_op(req, "begin_match", …) ----> |   판 표 (서버가 "온라인 판"으로 기록)
  | _s_snap(snapshot)  (10Hz) -------> | ---> 상대에게 _c_snap(snapshot)   (검사 후)
  | _s_event(kind, data) ------------> | ---> 상대에게 _c_event(kind, data) (검사 후)
  | _s_report(winner, round) --------> |   두 사람 보고가 같으면 레이팅 반영
  | _s_match_end() ------------------> |   승패가 나면 (방은 유지 → 재대결 가능)
  | _s_leave() ----------------------> |   매치 중이면 상대에게 _c_partner_left()
```

## 클라이언트 → 서버

| RPC | 인자 | 설명 |
| --- | --- | --- |
| `_a_hello` | `name: String, protocol: int, device_id: String` | 접속 직후 1회. 기기 ID(영문·숫자·`_-` 40자)로 계정 식별 |
| `_s_report` | `winner: int, my_round: int` | 매치 결과 보고 (아래 "대전 결과") |
| `_s_leaderboard` | `kind: String` | 랭킹 요청. `pvp` / `endless` / `tower` / `daily` |
| `_s_list` | - | 방 목록 요청 |
| `_s_create` | `mode: "coop"/"pvp", room_name: String, quick: bool` | 방 만들기 |
| `_s_join` | `room_id: int` | 방 참가 |
| `_s_quick` | `mode` | 같은 모드의 빠른 매칭 방에 들어가거나 새로 만듦 |
| `_s_leave` | - | 방 나가기 |
| `_s_start` | - | (방장) 매치 시작 |
| `_s_match_end` | - | 매치 종료 알림 |
| `_s_event` | `kind: String, data: Variant` | 상대에게 이벤트 전달 (아래 "이벤트") |
| `_s_snap` | `snapshot: Dictionary` | 상대에게 스냅샷 전달 (unreliable_ordered) |
| `_s_migrate` | `profile: Dictionary` | (전용 서버, 첫 접속) 기기 진행을 서버 계정으로 이전. 상한 적용 |
| `_s_op` | `req_id: int, op: String, args: Array` | 계정 재화 작업 (`Profile.OPS` 만). docs/ECONOMY.md |
| `_s_iap` | `req_id: int, product_id: String, token: String` | 결제 영수증 확인 요청. docs/IAP.md |
| `_s_recovery_code` | - | 내 계정 복구 코드 요청 (계정마다 하나, 다시 요청하면 같은 코드) |
| `_s_redeem` | `code: String` | 복구 코드 입력 → 이 연결이 그 계정이 됨 |

## 서버 → 클라이언트

| RPC | 인자 | 설명 |
| --- | --- | --- |
| `_c_welcome` | `my_id: int, rooms: Array, server_time: int` | 접속 승인. 클라이언트는 `Story.clock_offset` 을 서버 시각에 맞춤 |
| `_c_config` | `{notice, event_name, coin_event_mult}` | 운영 설정. 공지가 있으면 `Net.notice_received(text)` |
| `_c_rooms` | `rooms: Array` | 방 목록 (로비에 있는 사람에게, 0.3초에 한 번까지 모아서) |
| `_c_room` | `state: Dictionary` | 내 방 상태. `{}` 면 방 없음 |
| `_a_error` | `msg: String` | 오류 안내 |
| `_c_start` | `mode, seed: int, name0, name1, my_index: int` | 매치 시작. `my_index` 0/1 = 내 전장 번호 |
| `_c_event` | `kind, data` | 상대가 보낸 이벤트 |
| `_c_snap` | `snapshot` | 상대 전장 스냅샷 |
| `_c_partner_left` | - | 매치 중 상대 이탈 (대전이면 나간 쪽 패배로 레이팅 반영) |
| `_c_record` | `record` | 내 기록 `{name, rating, wins, losses, coop_best, endless?, tower?}` |
| `_c_rating` | `record, delta` | 대전 후 레이팅 변화 (ELO, K=32) |
| `_c_leaderboard` | `kind, list, my_rank` | 랭킹 (아래) |
| `_c_profile` | `profile: Dictionary, need_upload: bool` | 계정 재화. `need_upload` 면 서버에 계정이 없음 → `_s_migrate` |
| `_c_op` | `req_id, result, profile` | 작업 결과 + 서버 기준 계정 전체 (클라이언트는 덮어씀). `req_id 0` = 서버가 먼저 보낸 변경(환불 회수 등) |
| `_c_iap` | `req_id, ok, product_id, profile, msg` | 결제 확인 결과 |
| `_c_recovery_code` | `code: String` | 복구 코드 `XXXX-XXXX-XXXX` (`""` = 아직 서버 계정 없음) |
| `_c_recovery` | `ok, msg, device_id` | 복구 결과. 성공이면 `Profile.device_id` 를 바꾸고 곧 `_c_record`, `_c_profile` 이 온다 |

방 목록 항목: `{id, name, mode, count, playing, quick, players: [이름]}`
방 상태: `{id, name, mode, owner, members: [peer_id], players: [이름], playing, quick}`

## 공개 API (Net.gd)

| 함수 / 시그널 | 설명 |
| --- | --- |
| `request_leaderboard(kind := "pvp")` → `leaderboard_received(kind, list, my_rank)` | `list` = 상위 50명 `[{name, value, sub}]`, `my_rank` 내 순위(없으면 -1) |
| `request_recovery_code()` → `recovery_code(code)` | 설정 화면에 보여 줄 복구 코드 |
| `redeem_recovery_code(code)` → `recovery_result(ok, msg)` | 새 폰/재설치에서 코드 입력. 대소문자·공백·`-` 무시 |
| `notice_received(text)` | 접속 직후(또는 서버가 설정을 바꿨을 때) 공지 |
| `config_received(cfg)`, `server_config` | 이벤트 이름 등 (`event_name`, `coin_event_mult`) |

## 랭킹

| kind | value | sub | 기록 시점 |
| --- | --- | --- | --- |
| `pvp` | 레이팅 | `"12승 3패"` | 대전 결과 반영 때 |
| `endless` | 무한 모드(솔로) 최고 라운드 | 그때 난이도 (`"지옥"`) | 판 표가 있는 검증된 정산 |
| `tower` | 결계의 탑 최고 층 | `"23층"` | 판 표가 있는 탑 층 클리어 |
| `daily` | 오늘(한국 날짜)의 결계 최고 라운드 | `"클리어"` / `"9라운드"` | 판 표가 있는 오늘의 결계 정산. 날짜가 바뀌면 새로 |

서버는 정렬 결과를 잠깐(최대 60초, 기록이 바뀌면 2초) 캐시합니다.

## 대전 결과 (레이팅)

- 두 사람의 `_s_report` 가 **같은 승자**를 말할 때만 반영. 다르면 무효.
- 한쪽만 보고하고 60초가 지나면: 그 보고가 **자기 패배(상대 승리)** 면 반영, 자기 승리 주장만 있으면 무효.
- 매치 도중(`_s_match_end` 전) 나가면 나간 쪽 패배.
- 온라인 대전 판 정산(`match_end`)의 승패는 클라이언트 주장이 아니라 이 결과를 따릅니다.

## 이벤트 (`kind`, `data`)

서버는 중계 전에 종류·자료형을 검사하고, 맞지 않으면 버립니다.

| kind | data | 의미 / 검사 |
| --- | --- | --- |
| `attack` | `"swarm"` / `"elite"` / `"curse"` (+ `":라운드"`) | (대전만) `GameData.ATTACKS` 의 id. 초당 1회, 몰아서 8회까지 |
| `gold` | `int` 1~100000 | (협동만) 골드 선물 |
| `unit` | 유닛 id `String` | (협동만) `GameData.UNITS` 에 있는 것 |
| `blast` | `0` | (협동만) 합동 폭격 |
| `defeat` | 전장 번호 `int` | 자기 전장 번호만 (남의 패배 선언 불가) |
| `gameover` | `{winner: int, text: String}` | 대전: 보낸 사람 자신을 승자로 적은 것은 불가 (진 쪽만 보냄). 무승부(-1)는 먼저 `defeat` 를 보낸 경우만, 아니면 보낸 사람의 패배로 바꿔 전달. 협동: -1/-2 |
| `emote` | 아이콘 이름 `String` (24자) | 이모티콘 |
| 그 밖 | 작은 값 (`int/float/bool`, 32자 이하 문자열) | 새 기능용 |

## 스냅샷 (`Board.snapshot()`)

| 키 | 타입 | 내용 |
| --- | --- | --- |
| `c` | `PackedInt32Array(24)` | 칸별 `유닛번호*32 + 별*4 + 마리수`, 빈 칸 `-1` (유닛번호 = `GameData.UNIT_ORDER` 순서) |
| `e` | `PackedInt32Array` | 적 1마리당 2개: `x | y<<16`, `종류 | 체력(0~255)<<8 | 상태플래그<<16` |
| `g`,`m`,`w`,`t`,`k` | int/float | 골드, 보석, 라운드, 라운드 남은 시간, 처치 수 |
| `f` | int | 필드 적 수(가중치 합) |
| `a`,`fc`,`bf` | bool | 생존, 최종 보스 격파, 보스 제한시간 실패 |
| `sc`,`u`,`ga` | int/Array/int | 소환 비용, 강화 레벨, 폭격 게이지 |

서버 검사: 위 표의 키만 허용하고 키마다 자료형 확인 (정수 키는 int, `t` 는 수, `u` 는 정수 4개 배열), `c` 는 64칸 이하이고 값이 `-1 ~ 유닛수*32-1`,
`e` 는 짝수 길이 1200 이하이고 적 종류 번호가 `GameData.ENEMY_ORDER` 범위 안.

## 빈도 제한 (peer 마다, 넘으면 버림)

| 종류 | 몰아서 | 초당 |
| --- | --- | --- |
| `_s_op` | 40 | 4 (넘으면 결과 `null` 로 응답) |
| `_s_event` | 40 | 12 (`attack` 은 따로 16 / 2.5, 보내는 쪽 `Board.request_attack` 도 0.5초 대기) |
| `_s_snap` | 40 | 20 |
| 로비 (`_s_list/_s_create/_s_quick/_s_leaderboard`) | 20 | 2 |
| `_s_iap` | 6 | 0.2 |
| `_s_redeem` 틀린 입력 | 5 | 1분에 1 (peer·계정·공인 IP 각각, 사설/루프백 IP·`SQD_BEHIND_PROXY=1` 이면 IP 제한 없음) + 서버 전체 120 / 초당 2 |
| 판 정산 `match_end` | 12 | 60초에 1 (계정마다) |

## 서버 저장

- `user://server_db.json` (systemd 설치 기준 `/opt/sqdefense/.local/share/SquareGuardians/server_db.json`):
  기기(계정)별 이름·레이팅·전적·랭킹 기록·복구 코드 + `profile`(재화 전체)
- `user://server_iap.json`: 결제 영수증 기록 `{v: 2, used: {sha256(토큰): {...}}, void_since}`
- `user://server_config.json`: 운영 설정 (직접 만드는 파일, docs/OCI_DEPLOY.md)
- 저장은 **임시 파일에 쓰고 이름 바꾸기로 교체** (쓰는 중 꺼져도 예전 파일이 온전). 바뀐 게 있을 때 최대 5초에 한 번.
- `user://backups/` 에 한 시간마다 시각이 붙은 복사본 (72개 = 사흘치). 서버 시작 때도 한 벌 (마지막 백업이 10분 넘었을 때만 → 재시작이 반복돼도 이력이 밀려나지 않음).
- 시작할 때 본 파일이 깨져 있으면 가장 최근의 온전한 백업으로 시작, 백업도 없으면 **서버가 시작을 거부**
  (`SQD_ALLOW_EMPTY_DB=1` 이면 빈 DB 로 시작).
