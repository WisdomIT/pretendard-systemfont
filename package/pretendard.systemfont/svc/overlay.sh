#!/system/bin/sh
# 부팅 때 NEMESIS svcmgr 가 한 번 실행하는 서비스 (mode=background).
# 실측: svcmgr 는 부팅 약 2.95초, zygote 의 폰트 preload 는 약 5.2초.
#
# 1) 직전 부팅이 정상 완료됐는지 확인 (부팅 루프 방지)
# 2) zygote 가 아직 폰트를 읽지 않았으면 Pretendard 를 bind mount
# 3) 이번 부팅이 정상 완료되면 "정상" 기록, 아니면 다음 부팅에서 실패로 센다

_here="${0%/*}"
. "$_here/../lib/common.sh"

[ -d "$STATE" ] || mkdir -p "$STATE" 2>/dev/null
BOOT_ID=""; read -r BOOT_ID < "$BOOT_ID_FILE" 2>/dev/null
log "---- overlay start boot_id=$BOOT_ID"

# 이번 부팅에서 무엇을 했는지 남긴다. 상태 화면(bin/info.sh)이 적용 안 된 이유를 설명할 때 쓴다.
#   result: disabled | late | mounted | nothing
last_run() {
    { echo "boot_id=$BOOT_ID"; echo "result=$1"
      echo "ok=${_ok:-0}"; echo "absent=${_absent:-0}"; echo "corrupt=${_corrupt:-0}"; echo "mount_fail=${_mfail:-0}"
    } > "$STATE/last_run"
}

if [ -f "$STATE/disabled" ]; then
    log "꺼짐 상태(disabled). 마운트하지 않음. 재설치하면 다시 켜짐."
    last_run disabled
    exit 0
fi

# 1) 직전 부팅 확인
if [ -f "$STATE/pending" ]; then
    read _pb < "$STATE/pending"
    if [ "$_pb" = "$BOOT_ID" ]; then
        # 같은 부팅에서 서비스가 다시 실행된 경우 (svcmgr 재시작 등). 실패가 아님.
        log "같은 부팅에서 재실행됨. 이미 처리했으므로 종료."
        exit 0
    fi
    _f=$(( $(read_num "$STATE/fails") + 1 ))
    echo "$_f" > "$STATE/fails"
    rm -f "$STATE/pending"
    log "직전 부팅이 정상 완료되지 않음 (연속 $_f 회)"
    if [ "$_f" -ge "$FAIL_LIMIT" ]; then
        echo "boot_id=$BOOT_ID fails=$_f" > "$STATE/disabled"
        log "연속 $_f 회 실패 -> 스스로 꺼짐. 이번 부팅은 순정 폰트."
        last_run disabled
        exit 0
    fi
fi

# 2) 마운트
if zygote_preloaded; then
    log "zygote 가 이미 폰트를 읽음. 섞이지 않게 이번에는 건너뜀 (다음 재부팅에 적용)."
    last_run late
    exit 0
fi

# 이 구간은 zygote 의 폰트 로딩(실측 약 5.4초) 전에 끝나야 한다.
# fork 를 줄이려고: map.conf 는 셸이 직접 읽고, 마운트 목록은 한 번만 읽고,
# 폰트 크기 확인은 원본 폰트(4종)마다 한 번만 하고, 마운트 결과는 종료 코드로 판단한다.
_ok=0; _skip=0; _absent=0; _corrupt=0; _mfail=0
load_mounts
_checked=" "      # " 이름=1 " 확인 통과, " 이름=0 " 손상
while read -r _t _s _rest; do
    case "$_t" in ''|'#'*) continue ;; esac
    [ -n "$_s" ] || continue
    case "$_t$_s" in */*|*..*) continue ;; esac
    _tgt="$SYSFONTS/$_t"; _src="$FONTDIR/$_s"
    if [ ! -f "$_tgt" ] || [ -L "$_tgt" ]; then
        log "건너뜀: $_tgt 없음(또는 링크)"; _skip=$((_skip + 1)); _absent=$((_absent + 1)); continue
    fi
    case "$MOUNTS" in *" $_tgt "*)
        log "이미 마운트됨: $_tgt"; _ok=$((_ok + 1)); continue ;;
    esac
    case "$_checked" in
        *" $_s=1 "*) ;;
        *" $_s=0 "*) _skip=$((_skip + 1)); _corrupt=$((_corrupt + 1)); continue ;;
        *)
            if font_ok "$_s"; then _checked="$_checked$_s=1 "
            else
                _checked="$_checked$_s=0 "
                log "건너뜀: $_s 손상 (크기가 설치 때와 다름)"; _skip=$((_skip + 1)); _corrupt=$((_corrupt + 1)); continue
            fi ;;
    esac
    if "$MOUNT_BIN" -o bind "$_src" "$_tgt" 2>> "$LOG"; then
        _ok=$((_ok + 1))
    else
        log "마운트 실패: $_tgt"; _skip=$((_skip + 1)); _mfail=$((_mfail + 1))
    fi
done < "$MAP"
log "마운트 $_ok 개, 건너뜀 $_skip 개"

if [ "$_ok" -gt 0 ]; then last_run mounted; else last_run nothing; exit 0; fi
echo "$BOOT_ID" > "$STATE/pending"

# 3) 이번 부팅이 정상 완료되는지 지켜본다
_i=0
while [ "$(getprop sys.boot_completed)" != "1" ]; do
    if [ "$_i" -ge "$BOOT_WAIT_SEC" ]; then
        log "${BOOT_WAIT_SEC}초 안에 부팅이 완료되지 않음. 다음 부팅에서 실패로 셈."
        exit 0
    fi
    sleep 1; _i=$((_i + 1))
done
_z1="$(pid_of zygote)"
sleep "$STABLE_SEC"
_z2="$(pid_of zygote)"
if [ -n "$_z1" ] && [ "$_z1" = "$_z2" ] && [ "$(getprop sys.boot_completed)" = "1" ]; then
    rm -f "$STATE/pending"
    echo 0 > "$STATE/fails"
    log "정상 부팅 확인 (zygote pid $_z1 유지)"
else
    log "zygote 가 다시 시작됨 ($_z1 -> $_z2). 다음 부팅에서 실패로 셈."
fi
exit 0
