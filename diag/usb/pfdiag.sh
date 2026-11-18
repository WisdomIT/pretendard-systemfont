#!/system/bin/sh
# pretendard-systemfont 진단 스크립트 (Gen5W / NEMESIS type=execute)
#
# 목적: Pretendard 시스템 폰트 패키지를 "언제든 순정으로 되돌릴 수 있게" 설계하기 위해
#       실차의 폰트 구성, /system 상태, 부팅 순서, bind mount 가능 여부를 수집한다.
#
# 원칙:
#   - /system 에는 아무것도 쓰지 않는다. remount rw 도 하지 않는다.
#   - setprop, am, pm install/uninstall 을 하지 않는다. 차량 신호에는 손대지 않는다.
#   - 결과는 이 USB 의 새 폴더(pfdiag-<날짜>-<pid>)에만 쓴다.
#   - 유일한 "변경"은 MOUNT_TEST 의 bind mount 시험이다. 원본과 바이트 단위로 같은
#     사본을 잠깐 덮었다가 즉시 해제한다. 화면에 보이는 변화는 없고, 해제에 실패해도
#     재부팅하면 사라진다. 끄려면 아래 MOUNT_TEST=0.
#
# 소요 시간: 보통 1~5분. 끝나면 성공/실패 다이얼로그가 뜬다. 그 전에 USB 를 뽑지 말 것.

export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

# ---- 옵션 ------------------------------------------------------------------
MOUNT_TEST="${PF_MOUNT_TEST:-1}"  # 1: bind mount 시험 수행 (원본과 동일한 사본으로, 즉시 해제)
COPY_FONTS=1          # 1: /system/fonts 전체를 USB 로 복사 (원본 폰트 기록·분석용)
COPY_FONT_APKS=1      # 1: 폰트를 품은 것으로 보이는 APK 를 복사 (MAX_APK_KB 이하만)
MAX_APK_KB=65536
LS_TIMEOUT=120        # ls -lR 한 번에 허용할 최대 초
SELF_TIMEOUT=900      # 이 시간(초)이 지나면 스크립트가 스스로 끝난다 (NEMESIS 가 멈춰 있지 않도록)
# ---------------------------------------------------------------------------

USB_ROOT="$(pwd)"
# 패키지의 진단 버튼(bin/diag.sh)이 진행 상황을 알 수 있게 출력 폴더를 기록한다
RESULT_FILE="${PF_DIAG_RESULT:-}"
OUT="$USB_ROOT/pfdiag-$(date +%Y%m%d-%H%M%S 2>/dev/null)-$$"
mkdir "$OUT" 2>/dev/null || exit 1
[ -n "$RESULT_FILE" ] && echo "running $OUT" > "$RESULT_FILE"
for d in meta storage fonts fonts/config fonts/files scan apks runtime boot nemesis mounttest; do
    mkdir "$OUT/$d" 2>/dev/null || exit 1
done

LOG="$OUT/run.log"
GUARD_LOG="$LOG"
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
SUM="$OUT/SUMMARY.txt"
TMP=/data/local/tmp/pfdiag.$$
FONT_RE_ARGS="-e .ttf -e .otf -e .ttc -e .TTF -e .OTF -e .TTC"

up() { _u=; read _u _rest < /proc/uptime 2>/dev/null; echo "${_u:-?}"; }
log() { echo "[$(up)] $*" >> "$LOG"; }
sum() { echo "$*" >> "$SUM"; }
have() { command -v "$1" >/dev/null 2>&1; }

# 실행 결과를 파일로 남기고 종료 코드를 run.log 에 기록한다.
run() {
    _f="$1"; shift
    "$@" > "$OUT/$_f" 2>&1
    log "rc=$? $_f :: $*"
}

# 오래 걸릴 수 있는 명령. 제한 시간을 넘기면 끊는다. (toolbox 에 timeout 이 없음)
run_limited() {
    _secs="$1"; _f="$2"; shift 2
    "$@" > "$OUT/$_f" 2>&1 &
    _p=$!
    _i=0
    while kill -0 "$_p" 2>/dev/null; do
        if [ "$_i" -ge "$_secs" ]; then
            kill "$_p" 2>/dev/null; sleep 1; kill -9 "$_p" 2>/dev/null
            echo "### TIMEOUT after ${_secs}s" >> "$OUT/$_f"
            log "TIMEOUT $_f :: $*"
            break
        fi
        sleep 1
        _i=$((_i + 1))
    done
    wait "$_p" 2>/dev/null
    log "done ${_i}s $_f :: $*"
}

# `ls -l` 한 줄에서 크기(KB)를 얻는다. toolbox ls -l: perms owner group size date time name
size_kb() {
    set -- $(ls -l "$1" 2>/dev/null)
    case "$4" in ''|*[!0-9]*) echo 0 ;; *) echo $(($4 / 1024)) ;; esac
}

# /proc/<pid>/stat 의 22번째 필드(부팅 후 시작 시각, clock tick)
start_ticks() {
    _s="$(cat /proc/$1/stat 2>/dev/null)"
    [ -n "$_s" ] || { echo "?"; return; }
    # comm 에 공백이 있을 수 있으므로 ") " 뒤부터 센다. 그 뒤 20번째가 starttime.
    _s="${_s##*) }"
    set -- $_s
    echo "${20:-?}"
}

# /proc/<pid>/stat 의 comm (최대 15자) 이 $1 과 같은 pid 목록
pids_of() {
    for _d in /proc/[0-9]*; do
        _s="$(cat $_d/stat 2>/dev/null)"
        _c="${_s#*\(}"; _c="${_c%%\)*}"
        [ "$_c" = "$1" ] && echo "${_d#/proc/}"
    done
}

# "/a/b" -> "_a_b" (toolbox 에 sed/tr 이 없음)
mangle() {
    _s="$1"; _o=""
    while [ -n "$_s" ]; do
        _ch="${_s%"${_s#?}"}"; _s="${_s#?}"
        [ "$_ch" = "/" ] && _ch="_"
        _o="$_o$_ch"
    done
    echo "$_o"
}

MOUNTED=""
cleanup() {
        for _m in $MOUNTED; do
        umount "$_m" 2>/dev/null && log "cleanup: umount $_m"
    done
    rm -r "$TMP" 2>/dev/null
    sync
}
trap cleanup EXIT

log "start out=$OUT"
sum "pretendard-systemfont 진단 결과"
sum "생성: $(date 2>/dev/null)  uptime=$(up)s"
sum "--------------------------------------------------------------"

# ===========================================================================
# 1. 차량/펌웨어 정보
# ===========================================================================
run meta/getprop.txt         getprop
run meta/build.prop          cat /system/build.prop
run meta/proc_version.txt    cat /proc/version
run meta/cpuinfo.txt         cat /proc/cpuinfo
run meta/id.txt              id
run meta/toolbox_bin.txt     ls -l /system/bin /system/xbin
run meta/ps.txt              ps

sum "[펌웨어]"
sum "  ro.build.display.id   = $(getprop ro.build.display.id)"
sum "  ro.build.version.release = $(getprop ro.build.version.release)  sdk=$(getprop ro.build.version.sdk)"
sum "  ro.product.model      = $(getprop ro.product.model)"
sum "  ro.board.platform     = $(getprop ro.board.platform)"
sum "  S5W 관련 prop:"
grep -i -e S5W -e swversion -e sw_ver -e navi.ver "$OUT/meta/getprop.txt" 2>/dev/null | while read -r l; do sum "    $l"; done
sum ""

# ===========================================================================
# 2. 저장공간 / 마운트 / SELinux
# ===========================================================================
run storage/df.txt            df
run storage/proc_mounts.txt   cat /proc/mounts
run storage/mountinfo.txt     cat /proc/self/mountinfo
run storage/getenforce.txt    getenforce
run storage/selinux_enforce.txt cat /sys/fs/selinux/enforce

sum "[저장공간]"
grep -e ' /system' -e '^/system' -e ' /data' -e '^/data' "$OUT/storage/df.txt" 2>/dev/null | while read -r l; do sum "  $l"; done
sum "  /system 마운트: $(grep ' /system ' /proc/mounts 2>/dev/null)"
sum "  /data   마운트: $(grep ' /data ' /proc/mounts 2>/dev/null)"
sum "  SELinux: $(getenforce 2>/dev/null || cat /sys/fs/selinux/enforce 2>/dev/null)"
sum ""

# ===========================================================================
# 3. 시스템 폰트와 설정 파일
# ===========================================================================
run fonts/ls_fonts.txt        ls -la /system/fonts
run fonts/ls_fonts_Z.txt      ls -Z /system/fonts
run fonts/ls_etc.txt          ls -la /system/etc

# 폰트 설정 XML: KitKat 은 system_fonts.xml + fallback_fonts*.xml, 이후 버전은 fonts.xml
for f in /system/etc/*font*.xml /system/etc/*fonts* /vendor/etc/*font*.xml /system/etc/fonts/*; do
    [ -f "$f" ] || continue
    _n="$(mangle "$f")"
    [ -f "$OUT/fonts/config/$_n" ] && continue
    cp "$f" "$OUT/fonts/config/$_n" 2>/dev/null && log "copied config $f"
    echo "$f" >> "$OUT/fonts/config_list.txt"
done

# 폰트별 md5 (펌웨어 지문 / 원복 검증 기준)
if have md5; then MD5=md5; elif have md5sum; then MD5=md5sum; else MD5=""; fi
: > "$OUT/fonts/md5.txt"
_nfont=0
for f in /system/fonts/*; do
    [ -f "$f" ] || continue
    _nfont=$((_nfont + 1))
    if [ -n "$MD5" ]; then $MD5 "$f" >> "$OUT/fonts/md5.txt" 2>&1; fi
    if [ "$COPY_FONTS" = 1 ]; then
        cp "$f" "$OUT/fonts/files/" 2>> "$LOG" || log "copy fail $f"
    fi
done
log "fonts counted=$_nfont copy=$COPY_FONTS md5=$MD5"

sum "[시스템 폰트]"
sum "  /system/fonts 파일 수: $_nfont  (md5 도구: ${MD5:-없음})"
sum "  폰트 설정 파일:"
if [ -f "$OUT/fonts/config_list.txt" ]; then
    while read -r l; do sum "    $l"; done < "$OUT/fonts/config_list.txt"
else
    sum "    (없음)"
fi
sum "  한글/CJK/OEM 후보 파일:"
grep -i -e nanum -e kor -e kr -e cjk -e fallback -e noto -e hyundai -e kia -e hmg -e genesis -e sandoll -e yoon -e malgun -e gothic "$OUT/fonts/ls_fonts.txt" 2>/dev/null | while read -r l; do sum "    $l"; done
sum ""

# ===========================================================================
# 4. /system/fonts 밖의 폰트 파일 (앱 전용, 내비 엔진, 클러스터 등)
# ===========================================================================
run_limited "$LS_TIMEOUT" scan/ls_R_system.txt ls -lR /system
for d in /vendor /oem /hkmc /navi /map /mapdata /appdata /product /data/app /data/app-lib /data/data /data/hkmc /data/navi; do
    [ -d "$d" ] || continue
    _n="$(mangle "$d")"
    run_limited "$LS_TIMEOUT" "scan/ls_R${_n:-_dir}.txt" ls -lR "$d"
done
# 위 목록에 없는 마운트 지점(내비 지도 파티션 등)도 훑는다. 가상 fs 와 USB 는 제외.
while read -r _dev _mp _fs _rest; do
    case "$_fs" in proc|sysfs|tmpfs|devpts|cgroup|selinuxfs|debugfs|rootfs|fuse|functionfs|configfs|usbfs) continue ;; esac
    case "$_mp" in /|/system|/data|/cache|/proc*|/sys*|/dev*|/acct*|/storage/usb*|/mnt/media_rw*|/mnt/usb*|/mnt/secure*|/mnt/asec*|/mnt/obb*|/storage/emulated*|/mnt/shell*) continue ;; esac
    case "$_mp" in "$USB_ROOT"*) continue ;; esac
    _n="$(mangle "$_mp")"
    [ -f "$OUT/scan/ls_R${_n}.txt" ] && continue
    run_limited "$LS_TIMEOUT" "scan/ls_R${_n:-_mnt}.txt" ls -lR "$_mp"
done < /proc/mounts

# ls -lR 출력에서 폰트 파일 줄만 뽑기 (디렉터리 머리줄 포함해서 위치를 알 수 있게)
: > "$OUT/scan/font_files_outside_system_fonts.txt"
for f in "$OUT"/scan/ls_R*.txt; do
    [ -f "$f" ] || continue
    _dir=""
    while read -r l; do
        case "$l" in
            /*:) _dir="${l%:}" ;;
            *.ttf|*.otf|*.ttc|*.TTF|*.OTF|*.TTC|*.fnt|*.pfb|*.bdf)
                [ "$_dir" = "/system/fonts" ] && continue
                echo "$_dir :: $l" >> "$OUT/scan/font_files_outside_system_fonts.txt" ;;
        esac
    done < "$f"
done
_nout=0
while read -r l; do _nout=$((_nout + 1)); done < "$OUT/scan/font_files_outside_system_fonts.txt"

sum "[/system/fonts 밖의 폰트 파일]  $_nout 개"
_k=0
while read -r l; do
    _k=$((_k + 1)); [ "$_k" -le 40 ] || break
    sum "  $l"
done < "$OUT/scan/font_files_outside_system_fonts.txt"
[ "$_nout" -gt 40 ] && sum "  ... (전체: scan/font_files_outside_system_fonts.txt)"
sum ""

# ===========================================================================
# 5. APK 안에 들어 있는 폰트 (assets/*.ttf 등) - zip 중앙 디렉터리의 파일명을 grep
# ===========================================================================
run apks/pm_list_packages.txt pm list packages -f
: > "$OUT/apks/apks_with_fonts.txt"
_napk=0
for f in /system/app/*.apk /system/priv-app/*.apk /system/framework/*.apk /vendor/app/*.apk /data/app/*.apk; do
    [ -f "$f" ] || continue
    _c="$(grep -c $FONT_RE_ARGS "$f" 2>/dev/null)"
    case "$_c" in ''|0) continue ;; esac
    _kb="$(size_kb "$f")"
    echo "$f matches=$_c size_kb=$_kb" >> "$OUT/apks/apks_with_fonts.txt"
    _napk=$((_napk + 1))
    if [ "$COPY_FONT_APKS" = 1 ] && [ "$_kb" -le "$MAX_APK_KB" ]; then
        cp "$f" "$OUT/apks/" 2>> "$LOG" || log "apk copy fail $f"
    fi
done
log "apks with font names=$_napk"

sum "[폰트를 품은 것으로 보이는 APK]  $_napk 개 (파일명 grep 기준, 오탐 가능)"
while read -r l; do sum "  $l"; done < "$OUT/apks/apks_with_fonts.txt"
sum ""

# ===========================================================================
# 6. 실행 중 프로세스가 실제로 열어 둔 폰트 (어떤 앱이 시스템 폰트를 쓰는가)
# ===========================================================================
: > "$OUT/runtime/mapped_fonts.txt"
: > "$OUT/runtime/open_font_fds.txt"
for _d in /proc/[0-9]*; do
    _p="${_d#/proc/}"
    _c="$(cat $_d/cmdline 2>/dev/null)"
    [ -n "$_c" ] || continue
    grep $FONT_RE_ARGS "$_d/maps" 2>/dev/null | while read -r l; do
        echo "$_p $_c :: ${l##* }" >> "$OUT/runtime/mapped_fonts.txt"
    done
    ls -l "$_d/fd" 2>/dev/null | grep $FONT_RE_ARGS | while read -r l; do
        echo "$_p $_c :: ${l##* }" >> "$OUT/runtime/open_font_fds.txt"
    done
done

sum "[실행 중 매핑된 폰트] (runtime/mapped_fonts.txt)"
for _proc in zygote system_server; do
    for _p in $(pids_of $_proc); do
        _n="$(grep -c "^$_p " "$OUT/runtime/mapped_fonts.txt" 2>/dev/null)"
        sum "  $_proc(pid $_p): 폰트 매핑 ${_n:-0}개"
    done
done
sum "  /system/fonts 가 아닌 경로에서 매핑된 폰트:"
grep -v ':: /system/fonts/' "$OUT/runtime/mapped_fonts.txt" 2>/dev/null | while read -r l; do sum "    $l"; done
sum ""

# ===========================================================================
# 7. 부팅 순서 (bind mount 를 zygote 보다 먼저 걸 수 있는가)
# ===========================================================================
for f in /init.rc /init.*.rc /ueventd*.rc /system/etc/install-recovery.sh /system/etc/qb_runtime.sh /system/etc/init.*.sh /system/etc/*.sh; do
    [ -f "$f" ] || continue
    _n="$(mangle "$f")"
    cp "$f" "$OUT/boot/$_n" 2>/dev/null && log "copied boot $f"
done
run boot/ls_root.txt          ls -la /
run boot/ns_init.txt          ls -l /proc/1/ns
run boot/ns_self.txt          ls -l /proc/self/ns
run boot/proc_stat.txt        cat /proc/stat
run boot/dmesg.txt            dmesg
run_limited 30 boot/logcat.txt logcat -d -v time -b main -b system -b events
grep -i -e typeface -e font -e preload -e zygote -e quickboot -e qb_ "$OUT/boot/logcat.txt" > "$OUT/boot/logcat_font_zygote.txt" 2>/dev/null
grep -i -e quickboot -e qb_ -e snapshot -e hibernat "$OUT/boot/dmesg.txt" > "$OUT/boot/dmesg_qb.txt" 2>/dev/null
getprop | grep -i -e init.svc -e qb -e quick -e boot > "$OUT/boot/props_boot.txt" 2>/dev/null

# 주요 프로세스 시작 시각 (clock tick, 보통 100Hz). 숫자가 작을수록 먼저 시작.
: > "$OUT/boot/start_ticks.txt"
for _proc in init ueventd servicemanager surfaceflinger zygote system_server bootanimation install-recover nemesis; do
    for _p in $(pids_of $_proc); do
        echo "$(start_ticks $_p) $_proc pid=$_p cmd=$(cat /proc/$_p/cmdline 2>/dev/null)" >> "$OUT/boot/start_ticks.txt"
    done
done
if have sort; then sort -n "$OUT/boot/start_ticks.txt" > "$OUT/boot/start_ticks_sorted.txt"; else cp "$OUT/boot/start_ticks.txt" "$OUT/boot/start_ticks_sorted.txt"; fi

sum "[부팅 순서] 시작 tick (작을수록 먼저, 100tick≈1초 가정)"
while read -r l; do sum "  $l"; done < "$OUT/boot/start_ticks_sorted.txt"
sum "  QuickBoot 관련 init 트리거:"
grep -i -n -e quickboot -e qb_ "$OUT"/boot/_init*.rc 2>/dev/null | while read -r l; do sum "    $l"; done
sum "  flash_recovery 서비스 정의:"
grep -h -A3 'service flash_recovery' "$OUT"/boot/_init*.rc 2>/dev/null | while read -r l; do sum "    $l"; done
sum "  zygote 서비스 정의:"
grep -h -A2 'service zygote' "$OUT"/boot/_init*.rc 2>/dev/null | while read -r l; do sum "    $l"; done
sum ""

# ===========================================================================
# 8. NEMESIS 상태
# ===========================================================================
if [ -x /system/xbin/nemesis ]; then
    run nemesis/version.txt   /system/xbin/nemesis version
    run nemesis/pkg_list.txt  /system/xbin/nemesis pkg-list
    run nemesis/services.txt  /system/xbin/nemesis service list
fi
cp /data/nemesis/packages.db "$OUT/nemesis/" 2>/dev/null
cp /data/nemesis/services.db "$OUT/nemesis/" 2>/dev/null
cp /data/nemesis/nemesis.log "$OUT/nemesis/" 2>/dev/null
run nemesis/ls_data_nemesis.txt ls -lR /data/nemesis
run nemesis/ls_data_nemesis_bin.txt ls -l /data/nemesis/bin
cp /data/nemesis/logs/pretendard.systemfont/overlay.log "$OUT/nemesis/pretendard_overlay.log" 2>/dev/null
run nemesis/pretendard_state.txt ls -l /data/nemesis/state/pretendard.systemfont

sum "[NEMESIS]"
sum "  version: $(/system/xbin/nemesis version 2>/dev/null)"
sum "  /data/nemesis/bin: $(ls /data/nemesis/bin 2>/dev/null)"
sum ""

# ===========================================================================
# 9. bind mount 시험 (/system 무변경 방식이 가능한지)
#    a) /data 안에서만: 파일 위에 다른 파일을 bind
#    b) /system/fonts 의 폰트 1개 위에 "바이트 단위로 같은 사본"을 bind
#       -> 다른 프로세스(zygote, 앱)의 마운트 네임스페이스에 보이는지 확인 후 즉시 해제
# ===========================================================================
MT="$OUT/mounttest/result.txt"
mt() { echo "$*" >> "$MT"; }
sum "[bind mount 시험]"
if [ "$MOUNT_TEST" = 1 ]; then
    mkdir -p "$TMP/a" "$TMP/b" 2>/dev/null
    echo "AAA" > "$TMP/a/f"; echo "BBB" > "$TMP/b/f"
    if mount -o bind "$TMP/a/f" "$TMP/b/f" 2>> "$MT"; then
        MOUNTED="$TMP/b/f $MOUNTED"
        _r="$(cat "$TMP/b/f")"
        mt "a) data file bind: OK (read=$_r, expect AAA)"
        umount "$TMP/b/f" 2>> "$MT" && mt "a) umount: OK" || mt "a) umount: FAIL"
        MOUNTED=""
    else
        mt "a) data file bind: FAIL"
    fi

    _T=""
    for c in /system/fonts/Roboto-Regular.ttf /system/fonts/DroidSans.ttf /system/fonts/*.ttf; do
        [ -f "$c" ] && { _T="$c"; break; }
    done
    if [ -n "$_T" ]; then
        cp "$_T" "$TMP/same.ttf" 2>> "$MT"
        _m1=""; _m2=""
        if [ -n "$MD5" ]; then
            set -- $($MD5 "$_T"); _m1="$1"
            set -- $($MD5 "$TMP/same.ttf"); _m2="$1"
        fi
        mt "b) target=$_T md5_orig=$_m1 md5_copy=$_m2"
        if [ -n "$MD5" ] && [ "$_m1" != "$_m2" ]; then
            mt "b) skip: copy differs from original"
        elif mount -o bind "$TMP/same.ttf" "$_T" 2>> "$MT"; then
            MOUNTED="$_T $MOUNTED"
            mt "b) system font bind: OK"
            grep " $_T " /proc/self/mounts > /dev/null 2>&1 && mt "b) visible in self ns: yes" || mt "b) visible in self ns: no"
            for _proc in zygote system_server; do
                for _p in $(pids_of $_proc); do
                    grep " $_T " /proc/$_p/mounts > /dev/null 2>&1 && mt "b) visible in $_proc($_p) ns: yes" || mt "b) visible in $_proc($_p) ns: no"
                done
            done
            # 앱 프로세스 하나 (zygote 자식) 의 네임스페이스
            _zp="$(pids_of zygote)"; _zp="${_zp%% *}"
            for _d in /proc/[0-9]*; do
                _p="${_d#/proc/}"
                _s="$(cat $_d/stat 2>/dev/null)"; _s="${_s##*) }"
                set -- $_s
                [ "$2" = "$_zp" ] || continue
                _c="$(cat $_d/cmdline 2>/dev/null)"
                [ "$_c" = "system_server" ] && continue
                grep " $_T " /proc/$_p/mounts > /dev/null 2>&1 && mt "b) visible in app $_c($_p) ns: yes" || mt "b) visible in app $_c($_p) ns: no"
                break
            done
            grep "$_T" /proc/self/mountinfo >> "$MT" 2>/dev/null
            if umount "$_T" 2>> "$MT"; then
                MOUNTED=""
                grep " $_T " /proc/self/mounts > /dev/null 2>&1 && mt "b) umount: still mounted!" || mt "b) umount: OK"
            else
                mt "b) umount: FAIL (재부팅하면 해제됨, 내용은 원본과 동일)"
            fi
        else
            mt "b) system font bind: FAIL"
        fi
    else
        mt "b) skip: no .ttf in /system/fonts"
    fi
    # 디렉터리 단위 bind 가 가능한지 (/data 안에서만)
    mkdir -p "$TMP/d1" "$TMP/d2" 2>/dev/null
    echo X > "$TMP/d1/x"
    if mount -o bind "$TMP/d1" "$TMP/d2" 2>> "$MT"; then
        [ -f "$TMP/d2/x" ] && mt "c) dir bind: OK" || mt "c) dir bind: mounted but content missing"
        umount "$TMP/d2" 2>> "$MT" && mt "c) umount: OK" || { mt "c) umount: FAIL"; MOUNTED="$TMP/d2 $MOUNTED"; }
    else
        mt "c) dir bind: FAIL"
    fi
else
    mt "skipped (MOUNT_TEST=0)"
fi
while read -r l; do sum "  $l"; done < "$MT"
sum ""

sum "--------------------------------------------------------------"
sum "끝. uptime=$(up)s  출력 폴더: ${OUT##*/}"
[ -n "$RESULT_FILE" ] && echo "done $OUT" > "$RESULT_FILE"
log "end"
sync
exit 0
