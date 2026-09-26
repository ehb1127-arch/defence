#!/usr/bin/env bash
# 결계 수호대 전용 서버 설치/업데이트 (OCI Ubuntu 22.04/24.04, Oracle Linux, ARM64/x86_64)
#
# 사용법 (저장소를 서버에 받은 뒤, 저장소 루트에서):
#   sudo bash deploy/oci/install.sh            # 기본 포트 24680
#   sudo bash deploy/oci/install.sh 30000      # 포트 지정
# 다시 실행하면 최신 코드로 업데이트 + 재시작 된다.
set -euo pipefail

PORT="${1:-24680}"
GODOT_VERSION="4.3-stable"
APP_DIR="/opt/sqdefense"
SERVICE="sqdefense"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

if [ "$(id -u)" -ne 0 ]; then
	echo "sudo 로 실행하세요: sudo bash deploy/oci/install.sh" >&2
	exit 1
fi
if [ ! -f "$SRC_DIR/project.godot" ]; then
	echo "project.godot 을 찾을 수 없습니다 ($SRC_DIR). 저장소 안에서 실행하세요." >&2
	exit 1
fi

case "$(uname -m)" in
	aarch64 | arm64) GODOT_ARCH="arm64" ;;
	x86_64 | amd64) GODOT_ARCH="x86_64" ;;
	*) echo "지원하지 않는 CPU: $(uname -m)" >&2; exit 1 ;;
esac

echo "==> 필수 패키지 설치"
if command -v apt-get >/dev/null; then
	apt-get update -y -q
	DEBIAN_FRONTEND=noninteractive apt-get install -y -q unzip curl rsync
elif command -v dnf >/dev/null; then
	dnf install -y -q unzip curl rsync
fi

echo "==> 서비스 계정/폴더"
id "$SERVICE" >/dev/null 2>&1 || useradd --system --home-dir "$APP_DIR" --shell /usr/sbin/nologin "$SERVICE"
mkdir -p "$APP_DIR/game"

GODOT_BIN="$APP_DIR/godot"
if [ ! -x "$GODOT_BIN" ] || ! "$GODOT_BIN" --version 2>/dev/null | grep -q "^${GODOT_VERSION%-stable}.stable"; then
	echo "==> Godot $GODOT_VERSION ($GODOT_ARCH) 다운로드"
	ZIP="Godot_v${GODOT_VERSION}_linux.${GODOT_ARCH}.zip"
	TMP="$(mktemp -d)"
	curl -fL --retry 3 -o "$TMP/$ZIP" "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${ZIP}"
	unzip -q -o "$TMP/$ZIP" -d "$TMP"
	install -m 755 "$TMP/Godot_v${GODOT_VERSION}_linux.${GODOT_ARCH}" "$GODOT_BIN"
	rm -rf "$TMP"
fi
"$GODOT_BIN" --version

echo "==> 게임 파일 복사"
rsync -a --delete \
	--exclude ".git" --exclude ".godot" --exclude "tests" --exclude "deploy" --exclude "build" \
	"$SRC_DIR"/ "$APP_DIR/game/"
chown -R "$SERVICE:$SERVICE" "$APP_DIR"

echo "==> 리소스 임포트 (처음 한 번 수십 초 걸릴 수 있음)"
sudo -u "$SERVICE" HOME="$APP_DIR" "$GODOT_BIN" --headless --path "$APP_DIR/game" --import >/dev/null 2>&1 || true

echo "==> systemd 서비스 등록 (포트 $PORT)"
sed "s/@PORT@/$PORT/g" "$SRC_DIR/deploy/oci/sqdefense.service" > "/etc/systemd/system/$SERVICE.service"
systemctl daemon-reload
systemctl enable "$SERVICE" >/dev/null
systemctl restart "$SERVICE"

echo "==> 매일 백업 등록 (/etc/cron.daily/sqdefense-backup → /opt/sqdefense-backups)"
install -m 755 "$SRC_DIR/deploy/oci/backup.sh" /etc/cron.daily/sqdefense-backup
if [ ! -f /etc/default/sqdefense-backup ]; then
	cat > /etc/default/sqdefense-backup <<'CFG'
# 서버 밖으로도 백업하려면 rclone 을 설정하고 아래 주석을 푸세요 (예: OCI Object Storage)
#SQD_BACKUP_RCLONE="oci:sqdefense-backup/daily"
CFG
fi

echo "==> OS 방화벽 열기 (TCP $PORT)"
# OCI 기본 이미지는 OS 방화벽이 22번 외에는 막혀 있다. (클라우드 Security List 와 별개!)
if command -v firewall-cmd >/dev/null && systemctl is-active --quiet firewalld; then
	firewall-cmd --permanent --add-port="$PORT/tcp" >/dev/null
	firewall-cmd --reload >/dev/null
elif command -v iptables >/dev/null; then
	if ! iptables -C INPUT -p tcp -m state --state NEW --dport "$PORT" -j ACCEPT 2>/dev/null; then
		iptables -I INPUT 1 -p tcp -m state --state NEW --dport "$PORT" -j ACCEPT
	fi
	if command -v netfilter-persistent >/dev/null; then
		netfilter-persistent save >/dev/null
	else
		mkdir -p /etc/iptables && iptables-save > /etc/iptables/rules.v4
	fi
fi

sleep 2
if systemctl is-active --quiet "$SERVICE"; then
	echo
	echo "설치 완료! 서버가 포트 $PORT 에서 실행 중입니다."
	echo "  로그 보기 : sudo journalctl -u $SERVICE -f"
	echo "  재시작    : sudo systemctl restart $SERVICE"
	echo "  업데이트  : git pull && sudo bash deploy/oci/install.sh $PORT"
	echo "  공지/이벤트: $APP_DIR/.local/share/SquareGuardians/server_config.json (docs/OCI_DEPLOY.md)"
	echo
	echo "※ OCI 콘솔의 Security List(또는 NSG)에 TCP $PORT 인바운드 규칙도 추가해야 외부에서 접속됩니다."
	echo "  게임 클라이언트에서 접속할 주소: <서버 공인 IP>:$PORT"
else
	echo "서비스 시작 실패. 로그를 확인하세요: sudo journalctl -u $SERVICE -n 50" >&2
	exit 1
fi
