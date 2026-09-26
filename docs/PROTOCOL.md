# 온라인 프로토콜

전송: WebSocket (`ws://` 또는 리버스 프록시 뒤 `wss://`), Godot High-level Multiplayer RPC.
서버는 peer id `1`. 모든 RPC 는 `/root/Net` (autoload `scripts/autoload/Net.gd`) 에 정의되어 있습니다.
버전: `Net.PROTOCOL` (현재 `4`). 다르면 서버가 `_c_error` 후 연결을 끊습니다.

## 흐름

```
클라이언트                          서버
  | --- WebSocket 연결 ---------------> |
  | _s_hello(name, protocol) --------> |
  | <------------- _c_welcome(id, rooms)|
  | _s_create(mode, name, false) ----> |   또는 _s_join(room_id) / _s_quick(mode)
  | <-------------------- _c_room(state)|
  |          (두 번째 플레이어 입장)       |
  | _s_start() ----------------------> |   방장만. 빠른 매칭 방은 2명이 되면 자동 시작
  | <--- _c_start(mode, seed, n0, n1, idx)
  |                                     |
  | _s_snap(snapshot)  (10Hz) -------> | ---> 상대에게 _c_snap(snapshot)
  | _s_event(kind, data) ------------> | ---> 상대에게 _c_event(kind, data)
  | _s_match_end() ------------------> |   승패가 나면 (방은 유지 → 재대결 가능)
  | _s_leave() ----------------------> |   매치 중이면 상대에게 _c_partner_left()
```

## 클라이언트 → 서버

| RPC | 인자 | 설명 |
| --- | --- | --- |
| `_s_hello` | `name: String, protocol: int, device_id: String` | 접속 직후 1회. 기기 ID 로 계정(레이팅) 식별 |
| `_s_report` | `winner: int, my_round: int` | 매치 결과 보고. 자기 패배는 즉시 인정, 자기 승리 주장은 상대 보고와 일치해야 인정 |
| `_s_leaderboard` | - | 랭킹 요청 (상위 20명 + 내 순위) |
| `_s_list` | - | 방 목록 요청 |
| `_s_create` | `mode: "coop"/"pvp", room_name: String, quick: bool` | 방 만들기 |
| `_s_join` | `room_id: int` | 방 참가 |
| `_s_quick` | `mode` | 같은 모드의 빠른 매칭 방에 들어가거나 새로 만듦 |
| `_s_leave` | - | 방 나가기 |
| `_s_start` | - | (방장) 매치 시작 |
| `_s_match_end` | - | 매치 종료 알림 |
| `_s_event` | `kind: String, data: Variant` | 상대에게 이벤트 전달 |
| `_s_snap` | `snapshot: Dictionary` | 상대에게 스냅샷 전달 (unreliable_ordered) |
| `_s_migrate` | `profile: Dictionary` | (전용 서버, 첫 접속) 기기 진행을 서버 계정으로 이전. 상한 적용 |
| `_s_op` | `req_id: int, op: String, args: Array` | 계정 재화 작업 (`Profile.OPS` 만 허용). docs/ECONOMY.md |
| `_s_iap` | `req_id: int, product_id: String, token: String` | 결제 영수증 확인 요청. docs/IAP.md |

## 서버 → 클라이언트

| RPC | 인자 | 설명 |
| --- | --- | --- |
| `_c_welcome` | `my_id: int, rooms: Array` | 접속 승인 |
| `_c_rooms` | `rooms: Array` | 방 목록 (로비에 있는 사람에게 변경 시마다) |
| `_c_room` | `state: Dictionary` | 내 방 상태. `{}` 면 방 없음 |
| `_c_error` | `msg: String` | 오류 안내 |
| `_c_start` | `mode, seed: int, name0, name1, my_index: int` | 매치 시작. `my_index` 0/1 = 내 전장 번호 |
| `_c_event` | `kind, data` | 상대가 보낸 이벤트 |
| `_c_snap` | `snapshot` | 상대 전장 스냅샷 |
| `_c_partner_left` | - | 매치 중 상대 이탈 (대전이면 남은 쪽 승리로 레이팅 반영) |
| `_c_record` | `record` | 내 계정 기록 `{name, rating, wins, losses, coop_best}` |
| `_c_rating` | `record, delta` | 대전 후 레이팅 변화 (ELO, K=32) |
| `_c_leaderboard` | `list, my_rank` | 랭킹 |
| `_c_profile` | `profile: Dictionary, need_upload: bool` | 접속 직후 계정 재화. `need_upload` 면 서버에 계정이 없음 → `_s_migrate` |
| `_c_op` | `req_id, result, profile` | 작업 결과 + 서버 기준 계정 전체 (클라이언트는 덮어씀) |
| `_c_iap` | `req_id, ok, product_id, profile, msg` | 결제 확인 결과 |

방 목록 항목: `{id, name, mode, count, playing, quick, players: [이름]}`
방 상태: `{id, name, mode, owner, members: [peer_id], players: [이름], playing, quick}`

## 이벤트 (`kind`, `data`)

| kind | data | 의미 |
| --- | --- | --- |
| `attack` | `"swarm"` / `"elite"` / `"curse"` | (대전) 상대 전장에 적/저주 |
| `gold` | `int` | (협동) 골드 선물 |
| `unit` | 유닛 id `String` | (협동) 유닛 선물 |
| `blast` | `0` | (협동) 합동 폭격 |
| `defeat` | 전장 번호 `int` | (대전) 내 전장이 무너짐 |
| `gameover` | `{winner: int, text: String}` | 결과 확정 (-1 모두 패배, -2 모두 승리) |
| `emote` | 아이콘 이름 `String` | 이모티콘 |

## 스냅샷 (`Board.snapshot()`)

| 키 | 타입 | 내용 |
| --- | --- | --- |
| `c` | `PackedInt32Array(24)` | 칸별 `유닛번호*4 + 마리수`, 빈 칸 `-1` (유닛번호 = `GameData.UNIT_ORDER` 순서) |
| `e` | `PackedInt32Array` | 적 1마리당 2개: `x | y<<16`, `종류 | 체력(0~255)<<8 | 상태플래그<<16` |
| `g`,`m`,`w`,`t`,`k` | int/float | 골드, 보석, 라운드, 라운드 남은 시간, 처치 수 |
| `f` | int | 필드 적 수(가중치 합) |
| `a`,`fc`,`bf` | bool | 생존, 최종 보스 격파, 보스 제한시간 실패 |
| `sc`,`u`,`ga` | int/Array/int | 소환 비용, 강화 레벨, 폭격 게이지 |

## 서버 저장

계정 기록은 서버의 `user://server_db.json` (systemd 설치 기준 `/opt/sqdefense/.local/share/SquareGuardians/server_db.json`) 에 JSON 으로 저장됩니다.
계정 재화(`profile` 키)도 같은 파일에 들어 있고, 사용한 결제 영수증은 `server_iap.json` 에 저장됩니다.
백업은 이 두 파일을 복사하면 됩니다.
