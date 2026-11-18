#!/bin/bash
# 컨테이너 안에서 설치 → 부팅 → 부팅 루프 방지 → 업데이트 → 삭제를 흉내 내어 검사한다.
# 실행: tests/run.sh (호스트). 이 파일은 컨테이너 안에서 root 로 돈다.
set -u
apt-get update -qq >/dev/null && apt-get install -y -qq mksh python3 unzip >/dev/null 2>&1

PASS=0; FAIL=0
ok()   { echo "  ok   $*"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

ID=pretendard.systemfont
APP=/data/nemesis/apps/$ID
STATE=/data/nemesis/state/$ID
LOG=/data/nemesis/logs/$ID/overlay.log
ZIP=$(ls /dist/$ID-*.zip)

# ---- 가짜 Gen5W 환경 -------------------------------------------------------
mkdir -p /system/fonts /system/bin /data/nemesis/apps /data/local/tmp /pf
for n in Roboto-Regular Roboto-Italic Roboto-Bold Roboto-BoldItalic Roboto-Light Roboto-LightItalic \
         Roboto-Thin Roboto-ThinItalic RobotoCondensed-Regular Mobis-Regular Mobis-Bold NanumGothic; do
    head -c 4096 /dev/urandom > /system/fonts/$n.ttf
done
ln -s Roboto-Regular.ttf /system/fonts/DroidSans.ttf
( cd /system/fonts && md5sum *.ttf ) > /pf/stock.md5
echo 0 > /pf/boot_completed
echo boot-0 > /pf/boot_id
cat > /usr/local/bin/getprop <<'G'
#!/bin/sh
[ "$1" = sys.boot_completed ] && { cat /pf/boot_completed; exit 0; }
echo ""
G
chmod +x /usr/local/bin/getprop
for f in /usr/local/bin/* /usr/bin/* /bin/* /usr/sbin/* /sbin/*; do n=${f##*/}; [ -e /system/bin/$n ] || ln -s $f /system/bin/$n; done
for n in sed tr awk gawk mawk sort printf find head tail wc tee cut uniq xargs timeout md5; do rm -f /system/bin/$n; done
export PF_BOOT_ID_FILE=/pf/boot_id PF_STABLE_SEC=2 PF_BOOT_WAIT=3

ZPID=""
zygote_start() {  # $1=preloaded|fresh
    python3 - "$1" <<'P' &
import ctypes, mmap, sys, time
ctypes.CDLL(None).prctl(15, b"zygote", 0, 0, 0)
if sys.argv[1] == "preloaded":
    f = open("/system/fonts/Roboto-Regular.ttf", "rb")
    m = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
time.sleep(3600)
P
    ZPID=$!; sleep 0.5
}
zygote_stop() { [ -n "$ZPID" ] && kill "$ZPID" 2>/dev/null; wait "$ZPID" 2>/dev/null; ZPID=""; }

# 재부팅 흉내: 마운트를 모두 풀고 boot_id 를 바꾼다
reboot_sim() {
    zygote_stop
    for t in $(grep ' /system/fonts/' /proc/mounts | cut -d' ' -f2); do umount "$t"; done
    echo "boot-$1" > /pf/boot_id
    echo 0 > /pf/boot_completed
}
run_svc() { mksh "$APP/svc/overlay.sh" > /dev/null 2>&1; }
info() { mksh "$APP/bin/info.sh" 2>/dev/null; }
reason() { info | grep '^reason=' | cut -d= -f2; }
istate() { info | grep '^state=' | cut -d= -f2; }
font_md5() { md5sum "/system/fonts/$1" | cut -d' ' -f1; }
pkg_md5()  { md5sum "$APP/fonts/$1" | cut -d' ' -f1; }
stock_md5() { grep " $1\$" /pf/stock.md5 | cut -d' ' -f1; }
nmounts() { grep -c ' /system/fonts/' /proc/mounts; }

install_pkg() {
    rm -rf /data/local/tmp/stage && mkdir -p /data/local/tmp/stage
    unzip -q "$1" -d /data/local/tmp/stage
    ( cd /data/local/tmp/stage && mksh scripts/pre.sh ) > /pf/pre.out 2>&1; PRE_RC=$?
    [ "$PRE_RC" = 0 ] || return 1
    # NEMESIS 업데이트 순서: 기존 preuninstall -> 기존 폴더 삭제 -> 새로 복사 (덮어쓰기 없음)
    if [ -d "$APP" ]; then ( cd "$APP" && mksh scripts/preun.sh ) > /pf/old-preun.out 2>&1; fi
    rm -rf "$APP" && cp -a /data/local/tmp/stage "$APP"
    ( cd "$APP" && mksh scripts/post.sh ) > /pf/post.out 2>&1
    run_svc   # NEMESIS 는 설치 직후 서비스를 시작한다
}
uninstall_pkg() {
    ( cd "$APP" && mksh scripts/preun.sh ) > /pf/preun.out 2>&1; PREUN_RC=$?
    rm -rf "$APP"
}

echo "== 1. 설치 (Android 실행 중 = zygote 가 이미 폰트를 읽은 상태)"
zygote_start preloaded
install_pkg "$ZIP"
check "preinstall 통과" '[ "$PRE_RC" = 0 ]'
check "설치 직후에는 마운트하지 않음" '[ "$(nmounts)" = 0 ]'
check "로그에 다음 재부팅 안내" 'grep -q "다음 재부팅에 적용" "$LOG"'
check "info: 적용 전, 이유=재부팅 필요" '[ "$(istate)" = pending ] && [ "$(reason)" = reboot_needed ]'

echo "== 2. 재부팅 (서비스가 zygote preload 전에 실행)"
reboot_sim 1
run_svc &
SVC=$!; sleep 1
check "11개 마운트" '[ "$(nmounts)" = 11 ]'
check "Roboto-Regular = Pretendard-Regular" '[ "$(font_md5 Roboto-Regular.ttf)" = "$(pkg_md5 Pretendard-Regular.ttf)" ]'
check "DroidSans 링크도 Pretendard" '[ "$(font_md5 DroidSans.ttf)" = "$(pkg_md5 Pretendard-Regular.ttf)" ]'
check "Mobis-Bold = Pretendard-Bold" '[ "$(font_md5 Mobis-Bold.ttf)" = "$(pkg_md5 Pretendard-Bold.ttf)" ]'
check "NanumGothic = Pretendard-Regular" '[ "$(font_md5 NanumGothic.ttf)" = "$(pkg_md5 Pretendard-Regular.ttf)" ]'
check "RobotoCondensed 는 순정 유지" '[ "$(font_md5 RobotoCondensed-Regular.ttf)" = "$(stock_md5 RobotoCondensed-Regular.ttf)" ]'
check "/system 원본 파일은 그대로 (마운트 아래)" '[ -z "$(cd /system/fonts && umount Roboto-Regular.ttf && md5sum Roboto-Regular.ttf | cut -d" " -f1 | grep -v "$(stock_md5 Roboto-Regular.ttf)"; mount -o bind $APP/fonts/Pretendard-Regular.ttf /system/fonts/Roboto-Regular.ttf)" ]'
check "pending 기록" '[ -f $STATE/pending ]'
zygote_start preloaded; echo 1 > /pf/boot_completed
wait "$SVC"
check "정상 부팅 확인 후 pending 삭제" '[ ! -f $STATE/pending ] && [ "$(cat $STATE/fails)" = 0 ]'
check "info: applied 11/11, 이유=ok" '[ "$(istate)" = applied ] && [ "$(reason)" = ok ] && info | grep -q "^mounted=11$"'
check "info: 묶음별 상태" 'info | grep -q "^group.Roboto=applied 8/8$" && info | grep -q "^group.Mobis=applied 2/2$" && info | grep -q "^group.NanumGothic=applied 1/1$"'
check "info: 버전 정보" 'info | grep -q "^package=0.2$" && info | grep -q "^pretendard=1.3.9$"'

echo "== 3. 같은 부팅에서 서비스 재실행 (svcmgr 재시작)"
echo boot-1 > $STATE/pending
run_svc
check "실패로 세지 않음" '[ "$(cat $STATE/fails)" = 0 ] && [ ! -f $STATE/disabled ]'
check "마운트 중복 없음" '[ "$(nmounts)" = 11 ]'
rm -f $STATE/pending

echo "== 4. 부팅 루프 방지 (부팅이 완료되지 않는 상황 2회)"
reboot_sim 2; run_svc
check "boot2: 마운트했지만 완료 안 됨 -> pending 남음" '[ -f $STATE/pending ] && [ "$(nmounts)" = 11 ]'
reboot_sim 3; run_svc
check "boot3: fails=1, 다시 시도" '[ "$(cat $STATE/fails)" = 1 ] && [ "$(nmounts)" = 11 ]'
reboot_sim 4; run_svc
check "boot4: fails=2 -> 스스로 꺼짐, 순정" '[ -f $STATE/disabled ] && [ "$(nmounts)" = 0 ]'
check "info: 꺼짐, 이유=disabled" '[ "$(istate)" = disabled ] && [ "$(reason)" = disabled ]'
reboot_sim 5; run_svc
check "boot5: 꺼짐 유지" '[ "$(nmounts)" = 0 ]'

echo "== 5. 재설치(업데이트)로 다시 켜기 + 마운트 중 업데이트"
zygote_start preloaded
install_pkg "$ZIP"
check "재설치하면 disabled 해제" '[ ! -f $STATE/disabled ]'
reboot_sim 6; run_svc & SVC=$!; sleep 1; zygote_start preloaded; echo 1 > /pf/boot_completed; wait $SVC
check "다시 적용됨" '[ "$(nmounts)" = 11 ]'
install_pkg "$ZIP"
check "마운트 중 업데이트: 설치 성공" '[ "$PRE_RC" = 0 ]'
check "열려 있는 Roboto-Regular 만 남고 나머지는 해제" '[ "$(nmounts)" = 1 ] && grep -q " /system/fonts/Roboto-Regular.ttf " /proc/mounts'
check "남은 마운트는 옛 파일(삭제됨)을 계속 안전하게 제공" '[ "$(font_md5 Roboto-Regular.ttf)" = "$(pkg_md5 Pretendard-Regular.ttf)" ]'
reboot_sim 7; run_svc & SVC=$!; sleep 1; zygote_start preloaded; echo 1 > /pf/boot_completed; wait $SVC
check "업데이트 후 재부팅에 적용" '[ "$(nmounts)" = 11 ]'

echo "== 6. 손상된 패키지 폰트"
cp -a "$APP/fonts/Pretendard-Bold.ttf" /pf/bold.bak
reboot_sim 8; echo garbage >> "$APP/fonts/Pretendard-Bold.ttf"; run_svc
check "손상된 Bold 를 쓰는 3개는 건너뜀" '[ "$(nmounts)" = 8 ] && [ "$(font_md5 Roboto-Bold.ttf)" = "$(stock_md5 Roboto-Bold.ttf)" ]'
check "info: 일부 적용, 이유=corrupt" '[ "$(istate)" = partial ] && [ "$(reason)" = corrupt ]'
cp -a /pf/bold.bak "$APP/fonts/Pretendard-Bold.ttf"; rm -f $STATE/pending

echo "== 6b. 적용 안 된 이유"
reboot_sim 20
check "부팅 서비스가 이번 부팅에 안 돌았으면 service_not_run" '[ "$(reason)" = service_not_run ]'
zygote_start preloaded; run_svc
check "NEMESIS 가 zygote 보다 늦으면 late_start" '[ "$(nmounts)" = 0 ] && [ "$(reason)" = late_start ]'
reboot_sim 21; mv /system/fonts /system/fonts.bak; mkdir /system/fonts; run_svc
check "바꿀 폰트가 하나도 없으면 no_targets" '[ "$(reason)" = no_targets ] && info | grep -q "^group.Mobis=absent$"'
rmdir /system/fonts; mv /system/fonts.bak /system/fonts; rm -f $STATE/pending

echo "== 6c. 진단 버튼 (bin/diag.sh)"
mkdir -p /usbtest
check "USB 없으면 error no_usb" '[ "$(mksh $APP/bin/diag.sh start)" = "error no_usb" ]'
export PF_USB_CANDIDATES=/usbtest
check "start -> started" 'mksh $APP/bin/diag.sh start | grep -q "^started /usbtest"'
check "실행 중 다시 start -> running" '[ "$(mksh $APP/bin/diag.sh start)" = running ]'
check "status -> running <초>" 'mksh $APP/bin/diag.sh status | grep -q "^running [0-9]"'
for i in $(seq 1 240); do mksh $APP/bin/diag.sh status | grep -q "^done" && break; sleep 1; done
check "진단 완료 -> done <USB 폴더>" 'mksh $APP/bin/diag.sh status | grep -q "^done /usbtest/pfdiag-"'
check "summary 는 SUMMARY.txt 앞부분" 'mksh $APP/bin/diag.sh summary | grep -q "pretendard-systemfont 진단 결과"'
check "진단은 마운트 시험을 건너뜀 (이미 적용 중)" 'grep -q "skipped (MOUNT_TEST=0)" /usbtest/pfdiag-*/mounttest/result.txt'
check "진단 후에도 마운트 그대로" '[ "$(nmounts)" = 11 ] || [ "$(nmounts)" = 0 ]'
unset PF_USB_CANDIDATES

echo "== 7. 패키지 삭제 (wipe 도 같은 preuninstall 을 실행, zygote 가 폰트를 열고 있음)"
cp "$APP/fonts/Pretendard-Regular.ttf" /pf/pret-regular
reboot_sim 9; run_svc & SVC=$!; sleep 1; zygote_start preloaded; echo 1 > /pf/boot_completed; wait $SVC
check "삭제 전 적용 상태" '[ "$(nmounts)" = 11 ]'
uninstall_pkg
check "preuninstall 0 으로 종료" '[ "$PREUN_RC" = 0 ]'
check "열려 있지 않은 10개는 즉시 해제" '[ "$(nmounts)" = 1 ]'
check "재부팅 안내 메시지" 'grep -q "재부팅" /pf/preun.out'
check "패키지 폴더가 지워져도 열린 폰트는 계속 읽힘" '[ "$(font_md5 Roboto-Regular.ttf)" = "$(md5sum /pf/pret-regular | cut -d" " -f1)" ]'
check "상태 폴더 삭제" '[ ! -d $STATE ]'
reboot_sim 10
check "재부팅 후 마운트 없음" '[ "$(nmounts)" = 0 ]'
check "재부팅 후 모든 폰트가 순정 md5" '( cd /system/fonts && md5sum -c --quiet /pf/stock.md5 )'

echo "== 8. NEMESIS 가 통째로 사라진 경우 (/data/nemesis 삭제, preuninstall 없이)"
zygote_start preloaded; install_pkg "$ZIP"
reboot_sim 11; run_svc & SVC=$!; sleep 1; zygote_start preloaded; echo 1 > /pf/boot_completed; wait $SVC
rm -rf /data/nemesis
reboot_sim 12
check "다음 부팅부터 순정" '[ "$(nmounts)" = 0 ] && ( cd /system/fonts && md5sum -c --quiet /pf/stock.md5 )'

zygote_stop
echo
echo "결과: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" = 0 ]
