# OCI(오라클 클라우드) 서버 배포 가이드

결계 수호대의 온라인 서버를 **OCI 평생 무료(Always Free)** 인스턴스에 올리는 방법입니다.
서버는 게임과 같은 Godot 프로젝트를 화면 없이(`--headless -- --server`) 실행하며,
방 목록 / 방 만들기 / 참가 / 빠른 매칭 / 두 플레이어 사이 메시지 중계를 담당합니다.

- 통신: WebSocket, 기본 포트 **TCP 24680**
- 권장 사양: Ampere A1 (ARM) 1 OCPU / 6GB 로도 충분 (무료 한도: 4 OCPU / 24GB)
- 게임 계산은 각 플레이어 PC 가 하고 서버는 중계만 해서 CPU 부담이 매우 적습니다

---

## 1. 인스턴스 만들기

1. [OCI 콘솔](https://cloud.oracle.com) → **Compute → Instances → Create instance**
2. **Image**: Canonical Ubuntu 22.04 또는 24.04
3. **Shape**: `VM.Standard.A1.Flex` (Ampere, ARM) → OCPU 1~2, 메모리 6~12GB
   - "Out of capacity" 가 뜨면 다른 가용 도메인(AD)을 고르거나 잠시 후 재시도.
     급하면 `VM.Standard.E2.1.Micro`(x86, 무료)도 동작합니다 (설치 스크립트가 CPU 종류를 자동 감지).
4. **Networking**: 기본 VCN / 퍼블릭 서브넷, **Assign a public IPv4 address** 체크
5. **SSH keys**: 키를 생성해서 개인키를 내려받거나, 내 공개키 붙여넣기
6. 생성 후 **Public IP address** 를 메모

## 2. 클라우드 방화벽 열기 (Security List)

OCI 는 방화벽이 **두 겹**입니다. 여기서는 클라우드 쪽을 엽니다.

1. 인스턴스 상세 → **Subnet** 링크 → **Security Lists** → Default Security List
2. **Add Ingress Rules**
   - Source CIDR: `0.0.0.0/0`
   - IP Protocol: `TCP`
   - Destination Port Range: `24680`
   - Description: `square defense`

(Network Security Group(NSG)을 쓰는 경우 NSG 에 같은 규칙을 추가)

## 3. 서버에 설치

```bash
# 내 PC 에서
ssh -i <개인키 파일> ubuntu@<공인 IP>

# 서버에서
sudo apt-get update && sudo apt-get install -y git
git clone -b claude/godot-coop-defense-game-nbvf64 https://github.com/ehb1127-arch/defence.git
cd defence
sudo bash deploy/oci/install.sh          # 포트 바꾸려면: sudo bash deploy/oci/install.sh 30000
```

> 저장소가 비공개라면 `git clone` 대신 내 PC 에서 `scp -r` 로 폴더를 올리거나,
> GitHub 개인 액세스 토큰(Personal Access Token)으로 clone 하세요.

설치 스크립트가 하는 일:

- CPU(ARM64 / x86_64)에 맞는 Godot 4.3 을 `/opt/sqdefense/godot` 에 설치
- 게임 파일을 `/opt/sqdefense/game` 에 복사, 전용 계정 `sqdefense` 로 실행
- systemd 서비스 `sqdefense` 등록 (부팅 시 자동 시작, 죽으면 3초 뒤 자동 재시작)
- **OS 방화벽(iptables)** 에 TCP 포트 허용 + 재부팅 후에도 유지
  (OCI Ubuntu 이미지는 OS 안에서도 22번 외 포트를 막아두기 때문에 이 단계가 꼭 필요합니다)

## 4. 확인

```bash
sudo systemctl status sqdefense      # active (running) 이면 정상
sudo journalctl -u sqdefense -f      # 실시간 로그 (접속/방 생성/매치 시작이 찍힘)
```

게임 실행 → 메인 메뉴 오른쪽 **온라인** → 서버 칸에 `<공인 IP>` 입력 → **접속**
(포트를 생략하면 24680, 다른 포트면 `<IP>:<포트>`)

접속이 안 될 때 확인 순서:

1. `sudo systemctl status sqdefense` — 서버가 실행 중인가
2. `sudo ss -tlnp | grep 24680` — 포트를 듣고 있는가
3. Security List 에 TCP 24680 인바운드 규칙이 있는가
4. `sudo iptables -L INPUT -n --line-numbers` — ACCEPT 규칙이 REJECT 보다 위에 있는가
5. 내 PC 에서 `Test-NetConnection <IP> -Port 24680` (Windows PowerShell) 또는 `nc -vz <IP> 24680`

## 5. 업데이트

```bash
cd ~/defence
git pull
sudo bash deploy/oci/install.sh
```

게임 규칙이나 메시지 형식을 바꿨다면 `scripts/autoload/Net.gd` 의 `PROTOCOL` 숫자를 올리세요.
서버와 버전이 다른 클라이언트는 "게임 버전이 서버와 다릅니다" 안내를 받고 접속이 거절됩니다.

## 6. 플레이어에게 배포할 클라이언트 만들기

1. **서버 주소 넣기 (코드 수정 없음)**: 프로젝트 설정 `application/online/server_url`
   - 에디터: Project → Project Settings → (Advanced Settings 켜기) → 맨 위 칸에 `application/online/server_url` 입력,
     종류 String 으로 Add → 값 `wss://game.example.com` (도메인+HTTPS, 7번) 또는 `<공인 IP>` / `<IP>:<포트>`
   - 또는 `project.godot` 의 `[application]` 에 한 줄 추가:
     ```ini
     online/server_url="wss://game.example.com"
     ```
   - CI 에서 넣으려면 빌드 전에: `sed -i 's|^\[application\]$|[application]\nonline/server_url="wss://game.example.com"|' project.godot`
   - 설정이 없으면 `Net.DEFAULT_SERVER` (`127.0.0.1`, 개발용). 앱은 이 주소로 조용히 접속해 계정을 동기화하고,
     예전에 저장된 주소가 있어도 빌드의 기본 주소가 바뀌면 새 주소를 씁니다.
   - **안드로이드 출시는 `wss://` 권장** (암호화. 기기 ID 가 계정 키라서 평문 `ws://` 는 피하세요)
2. Godot 에디터 → **Editor → Manage Export Templates → Download and Install**
3. **Project → Export** → `Windows` / `Linux` / `Web` 프리셋 선택 → Export Project
   (결과물은 `build/` 폴더. 프리셋은 `export_presets.cfg` 에 이미 들어 있음)

## 7. (선택) 도메인 + HTTPS — 웹(브라우저) 버전을 낼 때

웹 빌드를 https 페이지에 올리면 브라우저가 `ws://` 접속을 막습니다. 이때는 `wss://` 가 필요합니다.

1. 도메인의 A 레코드를 서버 공인 IP 로 지정
2. Security List + OS 방화벽에 TCP 80, 443 추가
   (`sudo iptables -I INPUT 1 -p tcp -m multiport --dports 80,443 -j ACCEPT && sudo netfilter-persistent save`)
3. `sudo apt install -y caddy` → `deploy/oci/Caddyfile.example` 을 `/etc/caddy/Caddyfile` 로 복사하고 도메인 수정
   → `sudo systemctl restart caddy` (인증서 자동 발급)
4. 클라이언트 접속 주소: `wss://game.example.com` → 6번의 `application/online/server_url` 에 넣고 빌드

## 8. (대안) 서버 전용 빌드로 배포

Godot 바이너리 + 프로젝트 폴더 대신 **단일 실행 파일**로 올리고 싶다면:

1. 에디터 → Project → Export → `Server ARM64 (OCI)` 프리셋 → Export (dedicated server 모드라 그래픽 리소스 제외)
2. 서버에 업로드 후 `./sqdefense_server.arm64 --headless -- --port 24680`
   (dedicated server 빌드는 `--server` 없이도 서버로 시작합니다)
3. systemd 의 `ExecStart` 를 위 명령으로 바꾸면 됩니다.

## 알아둘 점

- 계정은 기기에서 만든 ID + **복구 코드**(새 폰/재설치용)로 식별합니다 (docs/ECONOMY.md). 로그인(구글 게임즈)은 추후.
- 게임 판정은 클라이언트가 하므로(중계 방식) 조작된 클라이언트를 완전히 막지는 못합니다. 서버는
  판 표·걸린 시간 확인·요약 상한·이벤트/스냅샷 검사·빈도 제한·대전 결과 교차 확인으로 이득을 제한합니다.
  더 필요해지면 서버가 전장을 직접 계산하는 방식으로 확장할 수 있도록 `Board.step()` 이 화면과 분리돼 있습니다.
- 하루 초기화는 코드에서 **한국 시간(UTC+9)** 으로 계산하므로 서버 시간대(TZ)를 바꿀 필요가 없습니다.
- 서버 한 대(1 OCPU)로 동시 수백 방까지 무리 없는 구조입니다 (방당 초당 20개 정도의 작은 메시지 중계).

## 계정 재화 / 결제 (서버 저장)

서버가 계정 재화와 결제 영수증을 저장합니다 (docs/ECONOMY.md, docs/IAP.md).

- 결제 확인을 켜려면 서비스 계정 키를 `/opt/sqdefense/sa.json` (권한 600, 소유자 sqdefense) 에 두고
  `sqdefense.service` 의 `SQD_GOOGLE_SA` / `SQD_PACKAGE` 줄 주석을 푼 뒤 재시작
- 서버에서 Google API 로 나가는 HTTPS(443) 가 필요 (OCI 기본 이그레스 규칙은 모두 허용)
- 저장은 임시 파일에 쓰고 교체하는 방식이라 서버가 갑자기 꺼져도 파일이 깨지지 않습니다 (최대 5초치 변경만 잃음).

### 백업

1. **자동 (서버 안)**: 서버가 한 시간마다 `.../SquareGuardians/backups/` 에 `server_db-날짜-시각.json`,
   `server_iap-….json` 을 만들고 사흘치(72개)만 남깁니다.
2. **자동 (하루 1번, 서버 밖으로)**: `install.sh` 가 `/etc/cron.daily/sqdefense-backup` (`deploy/oci/backup.sh`) 을 등록합니다.
   `/opt/sqdefense-backups/sqdefense-날짜.tgz` 로 묶고 14일치 보관. rclone 을 설정하고
   `/etc/default/sqdefense-backup` 에 `SQD_BACKUP_RCLONE="oci:버킷/경로"` 를 넣으면 **OCI Object Storage 로도 복사**합니다
   (인스턴스가 사라져도 복구 가능 — 꼭 켜세요).
3. 수동: `sudo /etc/cron.daily/sqdefense-backup`

### 복구

```bash
sudo systemctl stop sqdefense
D="/opt/sqdefense/.local/share/SquareGuardians"
ls "$D/backups"                                   # 가장 최근 것 고르기
sudo -u sqdefense cp "$D/backups/server_db-20260101-120000.json" "$D/server_db.json"
sudo systemctl start sqdefense
```

- 서버는 시작할 때 `server_db.json` 이 깨져 있으면 **가장 최근의 온전한 백업으로 자동 시작**합니다 (로그에 `경고`).
- 백업도 없으면 계정을 날리지 않도록 **시작을 거부**합니다. 정말 빈 DB 로 시작하려면 서비스에
  `Environment=SQD_ALLOW_EMPTY_DB=1` 을 잠깐 넣으세요.

## 운영 설정: 공지 · 코인 이벤트 (재배포 없이)

`/opt/sqdefense/.local/share/SquareGuardians/server_config.json` 을 만들거나 고치면 **30초 안에** 반영되고,
접속 중인 플레이어에게도 바로 보내집니다 (`deploy/oci/server_config.example.json` 참고).

```json
{"notice": "오늘 밤 12시 점검 (30분)", "event_name": "주말 코인 2배", "coin_event_mult": 2.0}
```

| 키 | 뜻 |
| --- | --- |
| `notice` | 접속하면 보여 줄 공지 (없거나 `""` 면 안 보임, 300자까지) |
| `event_name` | 진행 중인 이벤트 이름 (메뉴 표시용, 40자까지) |
| `coin_event_mult` | 판 정산 코인 배수 1~5 (서버가 계산에 적용) |

```bash
sudo -u sqdefense nano /opt/sqdefense/.local/share/SquareGuardians/server_config.json
sudo journalctl -u sqdefense -n 5      # "운영 설정: 공지 …" 가 찍히면 반영됨
```
