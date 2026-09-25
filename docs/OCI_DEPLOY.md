# OCI(오라클 클라우드) 서버 배포 가이드

사각 디펜스의 온라인 서버를 **OCI 평생 무료(Always Free)** 인스턴스에 올리는 방법입니다.
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

1. `scripts/autoload/Net.gd` 의 `DEFAULT_SERVER` 를 서버 공인 IP 로 변경
   → 플레이어는 주소 입력 없이 **접속**만 누르면 됨
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
4. 클라이언트 접속 주소: `wss://game.example.com`

## 8. (대안) 서버 전용 빌드로 배포

Godot 바이너리 + 프로젝트 폴더 대신 **단일 실행 파일**로 올리고 싶다면:

1. 에디터 → Project → Export → `Server ARM64 (OCI)` 프리셋 → Export (dedicated server 모드라 그래픽 리소스 제외)
2. 서버에 업로드 후 `./sqdefense_server.arm64 --headless -- --port 24680`
   (dedicated server 빌드는 `--server` 없이도 서버로 시작합니다)
3. systemd 의 `ExecStart` 를 위 명령으로 바꾸면 됩니다.

## 알아둘 점

- 현재 서버는 **로그인 없이** 닉네임만으로 접속합니다. 계정/랭킹이 필요해지면 서버에 인증 단계를 추가해야 합니다.
- 게임 판정은 클라이언트가 하므로(중계 방식) 조작된 클라이언트를 완전히 막지는 못합니다.
  랭크전 등이 필요해지면 서버가 전장을 직접 계산하는 방식으로 확장할 수 있도록 `Board.step()` 이 화면과 분리돼 있습니다.
- 서버 한 대(1 OCPU)로 동시 수백 방까지 무리 없는 구조입니다 (방당 초당 20개 정도의 작은 메시지 중계).

## 계정 재화 / 결제 (서버 저장)

서버가 계정 재화와 결제 영수증을 저장합니다 (docs/ECONOMY.md, docs/IAP.md).

- 결제 확인을 켜려면 서비스 계정 키를 `/opt/sqdefense/sa.json` (권한 600, 소유자 sqdefense) 에 두고
  `sqdefense.service` 의 `SQD_GOOGLE_SA` / `SQD_PACKAGE` 줄 주석을 푼 뒤 재시작
- 서버에서 Google API 로 나가는 HTTPS(443) 가 필요 (OCI 기본 이그레스 규칙은 모두 허용)
- **백업** (하루 1번 이상 권장):

```bash
D="/opt/sqdefense/.local/share/godot/app_userdata/사각 디펜스 (Square Defense)"
sudo tar czf /opt/sqdefense-backup-$(date +%F).tgz -C "$D" server_db.json server_iap.json
```

  OCI Object Storage 로 복사해 두면 인스턴스가 사라져도 복구할 수 있습니다.
