#!/system/bin/sh
# 부팅 때 NEMESIS svcmgr 가 한 번 실행하는 서비스 (mode=background).
# 실측: svcmgr 는 부팅 약 2.95초, zygote 의 폰트 preload 는 약 5.2초.
#
# 1) 직전 부팅이 정상 완료됐는지 확인 (부팅 루프 방지)
# 2) zygote 가 아직 폰트를 읽지 않았으면 Pretendard 를 bind mount
# 3) 이번 부팅이 정상 완료되면 "정상" 기록, 아니면 다음 부팅에서 실패로 센다

_here="${0%/*}"
. "$_here/../lib/common.sh"

mkdir -p "$STATE" 2>/dev/null
BOOT_ID="$(cat "$BOOT_ID_FILE" 2>/dev/null)"
log "---- overlay start boot_id=$BOOT_ID"

if [ -f "$STATE/disabled" ]; then
    log "꺼짐 상태(disabled). 마운트하지 않음. 재설치하면 다시 켜짐."
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
        exit 0
    fi
fi

# 2) 마운트
if zygote_preloaded; then
    log "zygote 가 이미 폰트를 읽음. 섞이지 않게 이번에는 건너뜀 (다음 재부팅에 적용)."
    exit 0
fi

_ok=0; _skip=0
for _pair in $(map_lines | while read -r _t _s; do echo "$_t:$_s"; done); do
    _t="${_pair%%:*}"; _s="${_pair#*:}"
    _tgt="$SYSFONTS/$_t"; _src="$FONTDIR/$_s"
    if [ ! -f "$_tgt" ] || [ -L "$_tgt" ]; then
        log "건너뜀: $_tgt 없음(또는 링크)"; _skip=$((_skip + 1)); continue
    fi
    if is_mounted "$_tgt"; then
        log "이미 마운트됨: $_tgt"; _ok=$((_ok + 1)); continue
    fi
    if ! font_ok "$_s"; then
        log "건너뜀: $_s 손상 또는 md5 불일치"; _skip=$((_skip + 1)); continue
    fi
    if "$MOUNT_BIN" -o bind "$_src" "$_tgt" 2>> "$LOG" && is_mounted "$_tgt"; then
        _ok=$((_ok + 1))
    else
        log "마운트 실패: $_tgt"; _skip=$((_skip + 1))
    fi
done
log "마운트 $_ok 개, 건너뜀 $_skip 개"

[ "$_ok" -gt 0 ] || exit 0
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
