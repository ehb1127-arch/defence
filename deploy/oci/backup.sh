#!/usr/bin/env bash
# 결계 수호대 서버 데이터 백업 (하루 1번, install.sh 가 /etc/cron.daily/sqdefense-backup 로 등록)
#   - /opt/sqdefense-backups/sqdefense-날짜-시각.tgz 로 묶고 14일치 보관
#   - /etc/default/sqdefense-backup 에 SQD_BACKUP_RCLONE="원격:경로" 가 있으면 rclone 으로 서버 밖에도 복사
# 서버는 파일을 "임시 파일에 쓰고 교체" 하므로 실행 중에 복사해도 반쯤 쓴 파일이 들어가지 않는다.
set -euo pipefail

[ -f /etc/default/sqdefense-backup ] && . /etc/default/sqdefense-backup
DATA="${SQD_DATA_DIR:-/opt/sqdefense/.local/share/SquareGuardians}"
OUT="${SQD_BACKUP_DIR:-/opt/sqdefense-backups}"
KEEP_DAYS="${SQD_BACKUP_DAYS:-14}"

mkdir -p "$OUT"
chmod 700 "$OUT"
FILES=()
for f in server_db.json server_iap.json server_config.json; do
	[ -f "$DATA/$f" ] && FILES+=("$f")
done
if [ ${#FILES[@]} -eq 0 ]; then
	echo "백업할 파일이 없습니다: $DATA" >&2
	exit 0
fi
ARCHIVE="$OUT/sqdefense-$(date +%F-%H%M).tgz"
tar czf "$ARCHIVE" -C "$DATA" "${FILES[@]}"
find "$OUT" -name 'sqdefense-*.tgz' -mtime +"$KEEP_DAYS" -delete

if [ -n "${SQD_BACKUP_RCLONE:-}" ]; then
	if command -v rclone >/dev/null; then
		rclone copy "$ARCHIVE" "$SQD_BACKUP_RCLONE"
	else
		echo "SQD_BACKUP_RCLONE 가 있지만 rclone 이 설치되지 않았습니다" >&2
	fi
fi
echo "백업 완료: $ARCHIVE"
