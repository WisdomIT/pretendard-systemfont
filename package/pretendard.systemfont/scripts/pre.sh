#!/system/bin/sh
# preinstall: 트리를 복사하기 전에 실행된다 (cwd = 스테이징 폴더).
# 0 이 아닌 값으로 끝나면 설치가 멈춘다.

_stage="$(pwd)"
. "$_stage/lib/common.sh"

# 업데이트라면 기존 버전의 마운트를 먼저 푼다. 새 파일이 마운트된 파일을
# 덮어쓰지 않도록 하기 위해서다. 실행 중인 앱은 기존 폰트를 계속 쓰므로 안전하다.
if [ -f "$MAP" ]; then
    unmount_all || log "preinstall: 일부 마운트가 남음 (재부팅하면 해제됨)"
fi

# 이제 스테이징 폴더의 파일을 검사한다.
PKG="$_stage"; MAP="$PKG/files/map.conf"; FONTDIR="$PKG/fonts"; SUMS="$PKG/fonts/md5.txt"

if [ ! -d "$SYSFONTS" ]; then
    echo "실패: $SYSFONTS 가 없습니다"; exit 1
fi

_targets=0; _bad=0
for _pair in $(map_lines | while read -r _t _s; do echo "$_t:$_s"; done); do
    _t="${_pair%%:*}"; _s="${_pair#*:}"
    [ -f "$SYSFONTS/$_t" ] && _targets=$((_targets + 1))
    if ! font_ok "$_s" full; then
        echo "실패: 패키지 안의 $_s 가 손상됐습니다"; _bad=$((_bad + 1))
    fi
done
[ "$_bad" -eq 0 ] || exit 1
if [ "$_targets" -eq 0 ]; then
    echo "실패: 바꿀 시스템 폰트를 하나도 찾지 못했습니다"; exit 1
fi
echo "확인: 바꿀 시스템 폰트 $_targets 개"
exit 0
