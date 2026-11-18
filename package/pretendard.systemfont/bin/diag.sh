#!/system/bin/sh
# 상태 화면의 "진단 실행" 버튼이 `nemesis root -c` 로 부른다.
#
#   diag.sh start    USB 를 찾아 진단(diag/pfdiag.sh)을 백그라운드로 시작
#                    -> started <폴더> | running | error no_usb
#   diag.sh status   -> idle | running <초> | done <폴더> | error <이유>
#   diag.sh summary  마지막 진단의 SUMMARY.txt 앞부분
#
# 진단은 읽기만 하고 결과를 USB 에만 쓴다. 이 패키지가 이미 마운트를 걸어 둔 상태이므로
# bind mount 시험(PF_MOUNT_TEST)은 끈다.

_here="${0%/*}"
. "$_here/../lib/common.sh"

RES="$STATE/diag.result"     # pfdiag 가 "running <폴더>" / "done <폴더>" 를 쓴다
PIDF="$STATE/diag.pid"
T0F="$STATE/diag.t0"
mkdir -p "$STATE" 2>/dev/null

# 쓸 수 있는 USB 루트 하나
find_usb() {
    for _u in /storage/usb0 /storage/usb1 /storage/usb2 /mnt/media_rw/usb0 /mnt/media_rw/usb1 /mnt/media_rw/usb2 ${PF_USB_CANDIDATES:-}; do
        [ -d "$_u" ] || continue
        grep " $_u " /proc/mounts > /dev/null 2>&1 || [ -n "${PF_USB_CANDIDATES:-}" ] || continue
        _probe="$_u/.pfdiag-write-test.$$"
        if echo x > "$_probe" 2>/dev/null; then
            rm -f "$_probe"
            echo "$_u"; return 0
        fi
    done
    return 1
}

running() {
    [ -f "$PIDF" ] || return 1
    read _p < "$PIDF"
    [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null
}

case "$1" in
start)
    if running; then echo running; exit 0; fi
    _usb="$(find_usb)" || { echo "error no_usb"; exit 0; }
    rm -f "$RES"
    read _t0 _x < /proc/uptime; echo "${_t0%%.*}" > "$T0F"
    # nemesis root 세션이 끝나도 계속 돌도록 HUP 을 무시하고 떼어 낸다
    ( trap '' HUP
      cd "$_usb" && PF_DIAG_RESULT="$RES" PF_MOUNT_TEST=0 /system/bin/sh "$PKG/diag/pfdiag.sh"
    ) </dev/null >/dev/null 2>&1 &
    echo "$!" > "$PIDF"
    echo "started $_usb"
    ;;
status)
    _r=""; [ -f "$RES" ] && read _r < "$RES"
    case "$_r" in
        done\ *) echo "$_r"; exit 0 ;;
    esac
    if running; then
        _t0=0; [ -f "$T0F" ] && read _t0 < "$T0F"
        read _now _x < /proc/uptime
        echo "running $(( ${_now%%.*} - _t0 ))"
    elif [ -f "$PIDF" ]; then
        echo "error stopped"      # 결과 없이 끝남 (USB 분리, 시간 초과 등)
    else
        echo idle
    fi
    ;;
summary)
    _r=""; [ -f "$RES" ] && read _r < "$RES"
    case "$_r" in
        done\ *) _d="${_r#done }" ;;
        *) echo "(아직 결과가 없습니다)"; exit 0 ;;
    esac
    _n=0
    while read -r _l; do
        _n=$((_n + 1)); [ "$_n" -le "${2:-60}" ] || break
        echo "$_l"
    done < "$_d/SUMMARY.txt"
    ;;
*)
    echo "usage: diag.sh start|status|summary"; exit 1 ;;
esac
exit 0
