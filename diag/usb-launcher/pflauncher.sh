#!/system/bin/sh
# 런처가 글꼴을 어떻게 불러오는지 확인하기 위한 파일 수집 (NEMESIS type=execute)
#
# 런처(Launcher_WP3)의 코드는 APK 가 아니라 /system/app/Launcher_WP3.odex 에 있다.
# 이 odex 와, 그것을 baksmali 로 풀 때 필요한 부트 클래스패스(/system/framework 의 odex/jar)를
# USB 의 pflauncher-<날짜>-<번호> 폴더에 복사한다. 자체 폰트를 쓰는 다른 앱도 함께 복사한다.
#
# 읽기만 한다. /system 에 쓰지 않는다. 복사한 파일은 기아·현대의 원본이므로
# 개인 분석에만 쓰고 GitHub 등에 올리지 않는다.

export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

SELF_TIMEOUT=300
USB_ROOT="$(pwd)"
OUT="$USB_ROOT/pflauncher-$(date +%Y%m%d-%H%M%S 2>/dev/null)-$$"
mkdir "$OUT" 2>/dev/null || exit 1
mkdir "$OUT/app" "$OUT/framework" 2>/dev/null
LOG="$OUT/run.log"

# 안전장치: 멈춰도 SELF_TIMEOUT 뒤에는 끝낸다 (NEMESIS 가 다음 USB 를 처리할 수 있게)
ME=$$
( exec </dev/null >/dev/null 2>&1
  _g=0
  while [ "$_g" -lt "$SELF_TIMEOUT" ]; do
      sleep 1; kill -0 "$ME" 2>/dev/null || exit 0; _g=$((_g + 1))
  done
  echo "### SELF_TIMEOUT" >> "$LOG"; kill -9 "$ME" 2>/dev/null ) &

log() { _u=; read _u _r < /proc/uptime; echo "[$_u] $*" >> "$LOG"; }
log "start"

# 펌웨어와 부트 클래스패스 (baksmali 가 odex 를 풀 때 같은 순서가 필요하다)
getprop ro.build.product2 > "$OUT/firmware.txt" 2>&1
getprop ro.build.version.release >> "$OUT/firmware.txt" 2>&1
echo "$BOOTCLASSPATH" > "$OUT/bootclasspath.txt"
cat /init.environ.rc > "$OUT/init.environ.rc" 2>/dev/null
ls -l /system/app /system/priv-app /system/framework > "$OUT/ls.txt" 2>&1

# 대상 앱: 런처, 그리고 APK 안에 Cube 폰트가 들어 있던 앱들
for a in Launcher_WP3 HKMC_HomeSetting_WP HKMC_Climate HKMC_BtSettings HKMC_VoiceHandler RightScreenHome; do
    for ext in odex apk; do
        f="/system/app/$a.$ext"
        [ -f "$f" ] || continue
        # APK 는 런처만 (리소스·assets 확인용). 나머지는 코드(odex)만.
        if [ "$ext" = apk ] && [ "$a" != Launcher_WP3 ]; then continue; fi
        cp "$f" "$OUT/app/" 2>> "$LOG" && log "copied $f" || log "copy fail $f"
    done
done

# 부트 클래스패스 파일 (odex 가 있으면 odex, 없으면 jar)
for f in /system/framework/*.odex /system/framework/*.jar; do
    [ -f "$f" ] || continue
    cp "$f" "$OUT/framework/" 2>> "$LOG" && log "copied $f" || log "copy fail $f"
done

log "end"
sync
exit 0
