#!/system/bin/sh
# 상태 화면 앱이 `nemesis root -c` 로 부른다. key=value 줄만 내보낸다.
#
#   state     applied | partial | pending | disabled
#   mounted   걸린 마운트 수 / total 대상 수 (이 차에 실제로 있는 파일 기준)
#   fails     연속으로 정상 완료되지 않은 부팅 수
#   group.<이름>  applied | partial | pending | absent   (Roboto, Mobis, NanumGothic)
#   firmware, nemesis, package, pretendard  버전 문자열

_here="${0%/*}"
. "$_here/../lib/common.sh"

kv() { echo "$1=$2"; }

_total=0; _m=0
_rt=0; _rm=0; _mt=0; _mm=0; _nt=0; _nm=0
for _t in $(map_lines | while read -r _a _b; do echo "$_a"; done); do
    [ -f "$SYSFONTS/$_t" ] || continue
    _total=$((_total + 1))
    _on=0; is_mounted "$SYSFONTS/$_t" && { _on=1; _m=$((_m + 1)); }
    case "$_t" in
        Roboto*)      _rt=$((_rt + 1)); _rm=$((_rm + _on)) ;;
        Mobis*)       _mt=$((_mt + 1)); _mm=$((_mm + _on)) ;;
        NanumGothic*) _nt=$((_nt + 1)); _nm=$((_nm + _on)) ;;
    esac
done

group() {   # 이름 대상수 적용수
    if [ "$2" -eq 0 ]; then kv "group.$1" absent
    elif [ "$3" -eq "$2" ]; then kv "group.$1" "applied $3/$2"
    elif [ "$3" -eq 0 ]; then kv "group.$1" "pending 0/$2"
    else kv "group.$1" "partial $3/$2"; fi
}

if [ -f "$STATE/disabled" ]; then _st=disabled
elif [ "$_m" -eq 0 ]; then _st=pending
elif [ "$_m" -lt "$_total" ]; then _st=partial
else _st=applied; fi

# 적용 안 된 이유 (화면에서 사람 말로 바꿔 보여 준다)
#   ok | reboot_needed | late_start | service_not_run | disabled | no_targets
#   corrupt | mount_fail | mount_lost | partial
_boot="$(cat "$BOOT_ID_FILE" 2>/dev/null)"
_inst=""; [ -f "$STATE/installed_boot" ] && read _inst < "$STATE/installed_boot"
_lb=""; _lr=""; _corrupt=0; _mfail=0
if [ -f "$STATE/last_run" ]; then
    while IFS='=' read -r _k _v; do
        case "$_k" in
            boot_id) _lb="$_v" ;; result) _lr="$_v" ;;
            corrupt) _corrupt="$_v" ;; mount_fail) _mfail="$_v" ;;
        esac
    done < "$STATE/last_run"
fi
case "$_corrupt$_mfail" in *[!0-9]*) _corrupt=0; _mfail=0 ;; esac

if [ "$_st" = disabled ]; then _why=disabled
elif [ "$_total" -eq 0 ]; then _why=no_targets
elif [ "$_st" = applied ]; then _why=ok
elif [ "$_corrupt" -gt 0 ] && [ "$_lb" = "$_boot" ]; then _why=corrupt
elif [ "$_mfail" -gt 0 ] && [ "$_lb" = "$_boot" ]; then _why=mount_fail
elif [ "$_st" = partial ]; then _why=partial
elif [ -n "$_boot" ] && [ "$_inst" = "$_boot" ]; then _why=reboot_needed
elif [ "$_lb" != "$_boot" ] || [ -z "$_lb" ]; then _why=service_not_run
elif [ "$_lr" = late ]; then _why=late_start
elif [ "$_lr" = mounted ]; then _why=mount_lost
else _why=no_targets; fi

kv state "$_st"
kv reason "$_why"
kv mounted "$_m"
kv total "$_total"
kv fails "$(read_num "$STATE/fails")"
group Roboto "$_rt" "$_rm"
group Mobis "$_mt" "$_mm"
group NanumGothic "$_nt" "$_nm"
_v="$(grep '^package-version=' "$PKG/NEMESIS.data" 2>/dev/null)"
kv package "${_v#*=}"
_pv=""; [ -f "$FONTDIR/VERSION" ] && read _pv < "$FONTDIR/VERSION"
kv pretendard "$_pv"
kv nemesis "$(/system/xbin/nemesis version 2>/dev/null)"
_fw="$(getprop ro.build.product2)"
[ -n "$_fw" ] || _fw="$(getprop ro.build.display.id)"
kv firmware "$_fw"
kv android "$(getprop ro.build.version.release)"
exit 0
