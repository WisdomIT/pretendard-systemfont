#!/system/bin/sh
# 상태 화면의 "진단 실행" 버튼이 `nemesis root -c` 로 부른다.
#
#   diag.sh start    USB 를 찾아 빠른 진단(diag/pfdiag.sh)을 백그라운드로 시작
#                    -> started <USB> | running | error no_usb
#   diag.sh status   key=value 줄:
#                      state    idle | running | done | error
#                      elapsed  시작 후 초 (done 이면 걸린 시간)
#                      started  시작 시각 HH:MM
#                      stage    "4/9 다른 폰트 파일"   (running)
#                      detail   지금 하고 있는 일 한 줄 (running)
#                      dir      결과 폴더 (running, done)
#                      error    usb_removed | stopped   (error)
#   diag.sh summary  마지막 진단의 SUMMARY.txt 앞부분
#
# 빠른 진단: OEM 폰트·APK 를 복사하지 않고 APK 검사도 하지 않는다 (전체 진단은 diag/usb 방식).
# 이 패키지가 이미 마운트를 걸어 둔 상태이므로 bind mount 시험도 하지 않는다.

_here="${0%/*}"
. "$_here/../lib/common.sh"

RES="$STATE/diag.result"     # pfdiag 가 "running <폴더>" / "done <폴더>" 를 쓴다
PIDF="$STATE/diag.pid"
T0F="$STATE/diag.t0"         # 시작 uptime(초)
T1F="$STATE/diag.t1"         # 끝난 것을 처음 본 uptime(초)
CLOCKF="$STATE/diag.clock"   # 시작 시각 HH:MM
ERRF="$STATE/diag.error"
mkdir -p "$STATE" 2>/dev/null

now() { read _n _x < /proc/uptime; echo "${_n%%.*}"; }
num_of() { _v=0; [ -f "$1" ] && read _v < "$1"; case "$_v" in ''|*[!0-9]*) _v=0 ;; esac; echo "$_v"; }

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

diag_pid() { _p=""; [ -f "$PIDF" ] && read _p < "$PIDF"; echo "$_p"; }

running() {
    _p="$(diag_pid)"
    [ -n "$_p" ] && kill -0 "$_p" 2>/dev/null
}

# 진단과 그 자식 프로세스를 끝낸다
stop_diag() {
    _p="$(diag_pid)"
    [ -n "$_p" ] || return 0
    kill -STOP "$_p" 2>/dev/null
    for _d in /proc/[0-9]*; do
        _s="$(cat $_d/stat 2>/dev/null)"; _s="${_s##*) }"
        set -- $_s
        [ "$2" = "$_p" ] && kill -9 "${_d#/proc/}" 2>/dev/null
    done
    kill -9 "$_p" 2>/dev/null
}

result_line() { _r=""; [ -f "$RES" ] && read _r < "$RES"; echo "$_r"; }

case "$1" in
start)
    if running; then echo running; exit 0; fi
    _usb="$(find_usb)" || { echo "error no_usb"; exit 0; }
    rm -f "$RES" "$T1F" "$ERRF"
    now > "$T0F"
    date +%H:%M > "$CLOCKF" 2>/dev/null
    # nemesis root 세션이 끝나도 계속 돌도록 HUP 을 무시한다. exec 로 pfdiag 자체의 pid 를 기록한다.
    ( trap '' HUP
      cd "$_usb" || exit 1
      PF_DIAG_RESULT="$RES" PF_MOUNT_TEST=0 PF_SCAN_APKS=0 PF_COPY_FONTS=0 PF_COPY_FONT_APKS=0 \
          exec /system/bin/sh "$PKG/diag/pfdiag.sh"
    ) </dev/null >/dev/null 2>&1 &
    echo "$!" > "$PIDF"
    echo "started $_usb"
    ;;
status)
    _r="$(result_line)"
    _t0="$(num_of "$T0F")"
    _clock=""; [ -f "$CLOCKF" ] && read _clock < "$CLOCKF"
    case "$_r" in
    done\ *)
        [ -f "$T1F" ] || now > "$T1F"
        echo "state=done"
        echo "dir=${_r#done }"
        echo "elapsed=$(( $(num_of "$T1F") - _t0 ))"
        echo "started=$_clock"
        exit 0 ;;
    esac
    if running; then
        _dir="${_r#running }"
        # USB 를 뽑았으면 결과를 쓸 곳이 없으므로 멈춘다
        if [ -n "$_dir" ] && [ "$_dir" != "$_r" ] && [ ! -d "$_dir" ]; then
            stop_diag
            echo usb_removed > "$ERRF"
            echo "state=error"; echo "error=usb_removed"; echo "started=$_clock"
            exit 0
        fi
        echo "state=running"
        echo "elapsed=$(( $(now) - _t0 ))"
        echo "started=$_clock"
        [ "$_dir" != "$_r" ] && echo "dir=$_dir"
        if [ -n "$_dir" ] && [ -f "$_dir/stage" ]; then read _st < "$_dir/stage"; echo "stage=$_st"; fi
        if [ -n "$_dir" ] && [ -f "$_dir/run.log" ]; then
            _last=""
            while read -r _l; do _last="$_l"; done < "$_dir/run.log"
            _last="${_last#*] }"
            case "$_last" in *" :: "*) _last="${_last#* :: }" ;; esac
            echo "detail=$_last"
        fi
    elif [ -f "$PIDF" ]; then
        _e=stopped; [ -f "$ERRF" ] && read _e < "$ERRF"
        echo "state=error"; echo "error=$_e"; echo "started=$_clock"
    else
        echo "state=idle"
    fi
    ;;
stop)
    stop_diag; echo stopped > "$ERRF"; echo stopped ;;
summary)
    _r="$(result_line)"
    case "$_r" in
        done\ *) _d="${_r#done }" ;;
        *) echo "(아직 결과가 없습니다)"; exit 0 ;;
    esac
    _n=0
    while read -r _l; do
        _n=$((_n + 1)); [ "$_n" -le "${2:-80}" ] || break
        echo "$_l"
    done < "$_d/SUMMARY.txt"
    ;;
*)
    echo "usage: diag.sh start|status|stop|summary"; exit 1 ;;
esac
exit 0
