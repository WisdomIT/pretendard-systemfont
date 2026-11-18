#!/system/bin/sh
# NEMESIS Manager 에서 Launch 하면 실행된다. 출력은 토스트로 보인다.

_here="${0%/*}"
. "$_here/../lib/common.sh"

_total=0
for _l in $(map_lines | while read -r _t _s; do echo "$_t"; done); do
    [ -f "$SYSFONTS/$_l" ] && _total=$((_total + 1))
done
_m="$(count_mounted)"
_ver="$(grep '^package-version=' "$PKG/NEMESIS.data" 2>/dev/null)"

if [ -f "$STATE/disabled" ]; then
    echo "Pretendard ${_ver#*=}: 꺼짐 (부팅 실패가 반복되어 스스로 끔). 재설치하면 다시 켜집니다."
elif [ "$_m" -eq 0 ]; then
    echo "Pretendard ${_ver#*=}: 아직 적용 전. Settings > Reboot 으로 재부팅하세요."
elif [ "$_m" -lt "$_total" ]; then
    echo "Pretendard ${_ver#*=}: 일부 적용 ($_m/$_total). 로그: $LOG"
else
    echo "Pretendard ${_ver#*=}: 적용됨 ($_m/$_total)"
fi
exit 0
