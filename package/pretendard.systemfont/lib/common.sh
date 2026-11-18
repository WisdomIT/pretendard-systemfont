#!/system/bin/sh
# pretendard.systemfont 공용 함수. 다른 스크립트에서 `. lib/common.sh` 로 읽는다.
#
# 설계 원칙
#   - /system 에는 절대 쓰지 않는다. Pretendard 는 패키지 폴더에 두고 부팅 때 원래
#     폰트 파일 위에 bind mount 한다. 패키지나 NEMESIS 가 사라지면 다음 부팅부터 순정.
#   - zygote 가 폰트를 읽기 전에만 마운트한다. 이미 읽은 뒤라면 섞이지 않게 건너뛴다.
#   - 마운트한 부팅이 정상 완료되지 않으면 다음 부팅부터 스스로 꺼진다 (부팅 루프 방지).

export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

PKG_ID=pretendard.systemfont
# 테스트에서 경로를 바꿀 수 있게 환경 변수를 먼저 본다.
PKG="${PF_PKG:-/data/nemesis/apps/$PKG_ID}"
SYSFONTS="${PF_SYSFONTS:-/system/fonts}"
STATE="${PF_STATE:-/data/nemesis/state/$PKG_ID}"
LOG="${PF_LOG:-/data/nemesis/logs/$PKG_ID/package.log}"   # overlay.log 는 NEMESIS 가 서비스 출력을 쓰는 곳
MOUNT_BIN="${PF_MOUNT:-/system/bin/mount}"
UMOUNT_BIN="${PF_UMOUNT:-/system/bin/umount}"
BOOT_ID_FILE="${PF_BOOT_ID_FILE:-/proc/sys/kernel/random/boot_id}"

MAP="$PKG/files/map.conf"
FONTDIR="$PKG/fonts"
SUMS="$PKG/fonts/md5.txt"

# 부팅 루프 방지: 마운트한 부팅이 이 횟수만큼 연달아 완료되지 않으면 끈다.
FAIL_LIMIT="${PF_FAIL_LIMIT:-2}"
# 부팅 완료 후 zygote 가 이 시간(초) 동안 바뀌지 않아야 "정상 부팅"으로 본다.
STABLE_SEC="${PF_STABLE_SEC:-60}"
# sys.boot_completed 를 기다리는 최대 시간(초)
BOOT_WAIT_SEC="${PF_BOOT_WAIT:-300}"

up() { _u=; read _u _r < /proc/uptime 2>/dev/null; echo "${_u:-?}"; }

log() {
    mkdir -p "${LOG%/*}" 2>/dev/null
    echo "[$(up)] $*" >> "$LOG" 2>/dev/null
    echo "$*"
}

# map.conf 의 유효한 줄을 "대상 원본" 형태로 내보낸다.
map_lines() {
    [ -f "$MAP" ] || return 0
    while read -r _t _s _rest; do
        case "$_t" in ''|'#'*) continue ;; esac
        [ -n "$_s" ] || continue
        case "$_t$_s" in */*|*..*) continue ;; esac
        echo "$_t $_s"
    done < "$MAP"
}

is_mounted() { grep " $1 " /proc/mounts > /dev/null 2>&1; }

# comm 이 $1 인 첫 pid
pid_of() {
    for _d in /proc/[0-9]*; do
        _s="$(cat $_d/stat 2>/dev/null)"; _c="${_s#*\(}"; _c="${_c%%\)*}"
        [ "$_c" = "$1" ] && { echo "${_d#/proc/}"; return 0; }
    done
    return 1
}

# zygote 가 이미 시스템 폰트를 읽었는가 (= 지금 마운트하면 늦음)
zygote_preloaded() {
    _z="$(pid_of zygote)" || return 1
    grep "$SYSFONTS/" "/proc/$_z/maps" > /dev/null 2>&1
}

md5_of() {
    if command -v md5 > /dev/null 2>&1; then set -- $(md5 "$1" 2>/dev/null)
    else set -- $(md5sum "$1" 2>/dev/null); fi
    echo "$1"
}

# 패키지 안 폰트가 빌드 때 기록한 것과 같은가. fonts/md5.txt 한 줄: "<md5>  <이름>  <바이트>"
#   font_ok <이름>        크기만 비교 (부팅 경로: zygote 가 폰트를 읽기 전에 끝나야 해서 빠르게)
#   font_ok <이름> full   md5 까지 비교 (설치할 때 pre.sh 가 한 번)
# 패키지 폴더는 설치 때만 바뀌므로, 설치 때 md5 를 확인했다면 부팅 때는 크기 확인으로 충분하다.
font_ok() {
    _f="$FONTDIR/$1"
    [ -s "$_f" ] || return 1
    [ -f "$SUMS" ] || return 1
    _want=""; _wsize=""
    while read -r _h _n _sz; do [ "$_n" = "$1" ] && { _want="$_h"; _wsize="$_sz"; break; }; done < "$SUMS"
    [ -n "$_want" ] || return 1
    if [ "$2" = full ]; then
        [ "$(md5_of "$_f")" = "$_want" ]
    else
        [ -n "$_wsize" ] && [ "$(size_of "$_f")" = "$_wsize" ]
    fi
}

# 파일 크기(바이트). toolbox ls -l: 권한 소유자 그룹 크기 날짜 시각 이름
size_of() {
    set -- $(ls -l "$1" 2>/dev/null)
    case "$1" in -*) ;; *) echo ""; return ;; esac
    # GNU ls 는 링크 수 열이 하나 더 있다 (테스트 환경)
    case "$2" in *[!0-9]*) echo "$4" ;; *) echo "$5" ;; esac
}

# 이 패키지가 건 마운트를 모두 푼다. 남은 개수를 돌려준다(0 이면 전부 해제).
unmount_all() {
    _left=0
    for _line in $(map_lines | while read -r _t _s; do echo "$_t"; done); do
        _tgt="$SYSFONTS/$_line"
        _n=0
        while is_mounted "$_tgt" && [ "$_n" -lt 5 ]; do
            "$UMOUNT_BIN" "$_tgt" 2>/dev/null
            _n=$((_n + 1))
        done
        if is_mounted "$_tgt"; then
            log "사용 중이라 지금은 해제 못 함(재부팅하면 해제): $_tgt"
            _left=$((_left + 1))
        fi
    done
    return "$_left"
}

count_mounted() {
    _c=0
    for _line in $(map_lines | while read -r _t _s; do echo "$_t"; done); do
        is_mounted "$SYSFONTS/$_line" && _c=$((_c + 1))
    done
    echo "$_c"
}

read_num() { _v=0; [ -f "$1" ] && read _v < "$1"; case "$_v" in ''|*[!0-9]*) _v=0 ;; esac; echo "$_v"; }
