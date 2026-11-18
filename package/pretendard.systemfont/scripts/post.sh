#!/system/bin/sh
# postinstall: 복사와 서비스 등록 뒤에 실행된다 (cwd = 설치 폴더).
# 설치(또는 업데이트)는 새 출발이므로 꺼짐/실패 기록을 지운다.

_here="${0%/*}"
. "$_here/../lib/common.sh"

rm -f "$STATE/disabled" "$STATE/pending" "$STATE/fails" 2>/dev/null
mkdir -p "$STATE" 2>/dev/null
rm -f "$STATE/last_run" 2>/dev/null
# 설치한 부팅을 기록한다. 이번 부팅에 적용되지 않은 것은 "재부팅 필요"이지 문제가 아니다.
cat "$BOOT_ID_FILE" > "$STATE/installed_boot" 2>/dev/null
log "설치됨: $(grep '^package-version=' "$PKG/NEMESIS.data" 2>/dev/null)"

echo "Pretendard 설치 완료."
echo "적용하려면 NEMESIS Manager > Settings > Reboot 으로 재부팅하세요."
echo "(시동을 잠깐 껐다 켜는 것으로는 적용되지 않습니다)"
exit 0
