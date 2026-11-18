#!/system/bin/sh
# pretendard-systemfont QuickBoot 확인 스크립트 (NEMESIS type=execute)
#
# 시동을 끄기 전에 한 번, 다시 켠 뒤에 한 번 실행한다. 실행할 때마다 USB 의
# pfqb-log.txt 에 한 블록씩 덧붙이므로 두 블록을 비교하면 된다.
#
# 확인하는 것
#   - boot_id / 부팅 시각(btime) / uptime : 실제로 다시 부팅했는가
#   - 표식 마운트 : 커널 상태(마운트 표)가 꺼졌다 켜진 뒤에도 남아 있는가
#   - zygote 시작 시각, logcat boot_progress, dmesg 의 suspend/resume/hibernate 흔적
#
# 바꾸는 것: /data/pfqb/ 안의 작은 파일 두 개와, 그 둘 사이의 bind mount 하나.
#   /system 과 /data/nemesis 는 건드리지 않는다. 마운트는 재부팅하면 사라진다.
#   시험이 끝나면 CLEANUP=1 로 한 번 더 실행하면 흔적을 지운다.

export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

CLEANUP=0
SELF_TIMEOUT=90       # 이 시간(초)이 지나면 스크립트가 스스로 끝난다 (NEMESIS 가 멈춰 있지 않도록)

USB_ROOT="$(pwd)"
LOGF="$USB_ROOT/pfqb-log.txt"
RUN="$USB_ROOT/pfqb-$(date +%Y%m%d-%H%M%S 2>/dev/null)-$$"
MK=/data/pfqb
SRC="$MK/src"
DST="$MK/dst"

mkdir "$RUN" 2>/dev/null || exit 1

GUARD_LOG="$LOGF"
# 안전장치: 어떤 명령이 멈춰도 SELF_TIMEOUT 초 뒤에는 이 스크립트와 그 자식 프로세스를 끝낸다.
# NEMESIS USB Handler 는 스크립트가 끝날 때까지 기다리므로, 멈추면 다음 USB 를 처리하지 못한다.
# 감시자는 1초마다 본 스크립트가 살아 있는지 보고, 본 스크립트가 끝나면 같이 끝난다.
ME=$$
( exec </dev/null >/dev/null 2>&1
  read _self _rest < /proc/self/stat
  _g=0
  while [ "$_g" -lt "$SELF_TIMEOUT" ]; do
      sleep 1
      kill -0 "$ME" 2>/dev/null || exit 0
      _g=$((_g + 1))
  done
  echo "### SELF_TIMEOUT ${SELF_TIMEOUT}s - 강제 종료" >> "$GUARD_LOG"
  kill -STOP "$ME" 2>/dev/null
  for _d in /proc/[0-9]*; do
      _p="${_d#/proc/}"
      [ "$_p" = "$_self" ] && continue
      _s="$(cat $_d/stat 2>/dev/null)"; _s="${_s##*) }"
      set -- $_s
      [ "$2" = "$ME" ] && kill -9 "$_p" 2>/dev/null
  done
  kill -9 "$ME" 2>/dev/null
  sync ) &

# 제한 시간 안에만 실행 (toolbox 에 timeout 이 없음)
lim() {
    _secs="$1"; _f="$2"; shift 2
    "$@" > "$_f" 2>&1 &
    _p=$!; _i=0
    while kill -0 "$_p" 2>/dev/null; do
        if [ "$_i" -ge "$_secs" ]; then
            kill "$_p" 2>/dev/null; sleep 1; kill -9 "$_p" 2>/dev/null
            echo "### TIMEOUT ${_secs}s" >> "$_f"; break
        fi
        sleep 1; _i=$((_i + 1))
    done
    wait "$_p" 2>/dev/null
}
w() { echo "$*" >> "$LOGF"; }

read UP _r < /proc/uptime
BOOT_ID="$(cat /proc/sys/kernel/random/boot_id 2>/dev/null)"
BTIME="$(grep '^btime' /proc/stat 2>/dev/null)"

start_ticks() {
    [ -n "$1" ] || { echo "-"; return; }
    _s="$(cat /proc/$1/stat 2>/dev/null)"; _s="${_s##*) }"
    set -- $_s
    echo "${20:-?}"
}
pid_of() {
    for _d in /proc/[0-9]*; do
        _s="$(cat $_d/stat 2>/dev/null)"; _c="${_s#*\(}"; _c="${_c%%\)*}"
        [ "$_c" = "$1" ] && { echo "${_d#/proc/}"; return; }
    done
}
mounted() { grep " $DST " /proc/mounts > /dev/null 2>&1; }

w "=================================================================="
w "실행 시각      : $(date 2>/dev/null)"
w "uptime(초)     : $UP"
w "boot_id        : $BOOT_ID"
w "$BTIME          (부팅 시각, epoch)"
w "sys.boot_completed=$(getprop sys.boot_completed)  dev.bootcomplete=$(getprop dev.bootcomplete)"
_z="$(pid_of zygote)"; _ss="$(pid_of system_server)"
w "zygote pid=$_z start_tick=$(start_ticks $_z)   system_server pid=$_ss start_tick=$(start_ticks $_ss)"

# 표식 마운트: 이전 실행이 걸어 둔 마운트가 지금도 살아 있는가
if [ -f "$DST" ]; then
    if mounted; then
        w "표식 마운트    : 살아 있음 -> $(cat "$DST")"
    else
        w "표식 마운트    : 없음 (dst 내용: $(cat "$DST"))"
    fi
else
    w "표식 마운트    : 첫 실행 (이전 표식 없음)"
fi

# 증거 수집
lim 15 "$RUN/dmesg.all" dmesg
# 커널 command line 에는 시리얼과 BT/Wi-Fi 주소가 있으므로 빼고 저장한다
grep -v -i -e 'command line' -e serialno -e btaddr -e wifimac "$RUN/dmesg.all" > "$RUN/dmesg.txt" 2>/dev/null
rm -f "$RUN/dmesg.all"
grep -i -e 'PM:' -e suspend -e resume -e hibernat -e snapshot -e restore -e quickboot -e 'qb_' -e 'Freezing' -e 'Restarting tasks' "$RUN/dmesg.txt" > "$RUN/dmesg_pm.txt" 2>/dev/null
lim 20 "$RUN/logcat_events.txt" logcat -d -v time -b events
grep -e boot_progress -e power_sleep -e power_screen "$RUN/logcat_events.txt" > "$RUN/boot_progress.txt" 2>/dev/null
lim 10 "$RUN/getprop.all" getprop
grep -v -i -e serial -e btaddr -e bdaddr -e macaddr -e wifimac -e imei "$RUN/getprop.all" > "$RUN/getprop.txt" 2>/dev/null
rm -f "$RUN/getprop.all"
for _tok in $(cat /proc/cmdline 2>/dev/null); do
    case "$_tok" in
        androidboot.qb_prebuilt_mode=*|resume=*|androidboot.hardware=*|active_partition=*) echo "$_tok" >> "$RUN/cmdline.txt" ;;
    esac
done
lim 5 "$RUN/power_state.txt" cat /sys/power/state
lim 15 "$RUN/cp_err.txt" cp /data/nemesis/nemesis.log "$RUN/nemesis.log"
grep -e 'watchdog start' -e 'svcmgr start' "$RUN/nemesis.log" > "$RUN/nemesis_starts.txt" 2>/dev/null

_n=0; while read -r l; do _n=$((_n + 1)); done < "$RUN/dmesg_pm.txt"
w "dmesg 전원 관련 줄 수: $_n  (자세히: ${RUN##*/}/dmesg_pm.txt)"
_k=0
while read -r l; do _k=$((_k + 1)); [ "$_k" -le 8 ] && w "   $l"; done < "$RUN/dmesg_pm.txt"
w "logcat boot_progress:"
while read -r l; do w "   $l"; done < "$RUN/boot_progress.txt"
w "NEMESIS 시작 기록(최근 6건):"
_t=0; while read -r l; do _t=$((_t + 1)); done < "$RUN/nemesis_starts.txt"
_k=0
while read -r l; do _k=$((_k + 1)); [ "$_k" -gt $((_t - 6)) ] && w "   $l"; done < "$RUN/nemesis_starts.txt"
_wd=0
while read -r l; do case "$l" in *"watchdog start"*) _wd=$((_wd + 1)) ;; esac; done < "$RUN/nemesis_starts.txt"
w "NEMESIS watchdog 시작 누적: ${_wd}회 (직전 실행과의 차이 = 그 사이 부팅 횟수, watchdog 재시작 포함)"

# 다음 비교를 위해 표식 마운트를 다시 건다 (이번 boot_id 를 기록)
if [ "$CLEANUP" = 1 ]; then
    mounted && umount "$DST" 2>/dev/null
    rm -r "$MK" 2>/dev/null
    w "CLEANUP: 표식 마운트와 $MK 삭제 $( [ -d "$MK" ] && echo 실패 || echo 완료)"
else
    mounted && umount "$DST" 2>/dev/null
    mkdir -p "$MK" 2>/dev/null
    echo "NOT-MOUNTED" > "$DST"
    echo "MOUNTED boot_id=$BOOT_ID uptime=$UP" > "$SRC"
    if mount -o bind "$SRC" "$DST" 2>> "$RUN/mount_err.txt"; then
        w "표식 마운트 새로 걸음: boot_id=$BOOT_ID"
    else
        w "표식 마운트 실패: $(cat "$RUN/mount_err.txt" 2>/dev/null)"
    fi
fi
w ""
sync
exit 0
