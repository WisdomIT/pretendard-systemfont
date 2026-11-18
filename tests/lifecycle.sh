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
LOG=/data/nemesis/logs/$ID/package.log
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
[ "$1" = sys.boot_completed ] && { read v < /pf/boot_completed; echo "$v"; exit 0; }
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
# 부팅 경로는 md5 를 계산하지 않아야 한다 (실차에서 11번 계산에 1.8초가 걸려 preload 와 0.6초 차이였음)
rm -f /system/bin/md5sum; printf '#!/bin/sh\necho x >> /pf/md5calls\nexec /usr/bin/md5sum "$@"\n' > /system/bin/md5sum; chmod +x /system/bin/md5sum; : > /pf/md5calls
run_svc &
SVC=$!; sleep 1
check "11개 마운트" '[ "$(nmounts)" = 11 ]'
check "부팅 경로에서 md5 계산 0회 (크기만 확인)" '[ ! -s /pf/md5calls ]'
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
check "info: 버전 정보" 'info | grep -q "^package=0.6$" && info | grep -q "^pretendard=1.3.9$"'

echo "== 3. 같은 부팅에서 서비스 재실행 (svcmgr 재시작)"
echo boot-1 > $STATE/pending
run_svc
check "실패로 세지 않음" '[ "$(cat $STATE/fails)" = 0 ] && [ ! -f $STATE/disabled ]'
check "마운트 중복 없음" '[ "$(nmounts)" = 11 ]'
rm -f $STATE/pending

echo "== 3b. 부팅 경로에서 띄우는 프로세스 (실차: fork 하나가 수십 ms)"
reboot_sim 30
for t in cat grep ls; do
    real=$(readlink -f /system/bin/$t); eval "REAL_$t=$real"; rm -f /system/bin/$t
    printf '#!/bin/sh\necho %s >> /pf/forks\nexec %s "$@"\n' "$t" "$real" > /system/bin/$t; chmod +x /system/bin/$t
done
: > /pf/forks
SLEEPS=""; for i in $(seq 1 150); do sleep 300 & SLEEPS="$SLEEPS $!"; done      # 실차처럼 프로세스가 많은 상태
PF_BOOT_WAIT=0 run_svc
check "부팅 경로에서 cat 0회 (프로세스 목록을 셸 내장 read 로)" '! grep -q "^cat$" /pf/forks'
check "부팅 경로에서 grep 0회 (마운트 목록은 한 번 읽어 재사용)" '! grep -q "^grep$" /pf/forks'
check "폰트 크기 확인은 원본 폰트 4종에 한 번씩 (ls 4회)" '[ "$(/usr/bin/grep -c "^ls$" /pf/forks)" = 4 ]'
check "그래도 11개 마운트" '[ "$(nmounts)" = 11 ]'
kill $SLEEPS 2>/dev/null; wait $SLEEPS 2>/dev/null; rm -f $STATE/pending; echo 0 > $STATE/fails
for t in cat grep ls; do rm -f /system/bin/$t; eval "ln -s \$REAL_$t /system/bin/$t"; done

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
D="mksh $APP/bin/diag.sh"
mkdir -p /usbtest
check "처음에는 idle" '$D status | grep -q "^state=idle$"'
check "USB 없으면 error no_usb" '[ "$($D start)" = "error no_usb" ]'
export PF_USB_CANDIDATES=/usbtest
check "start -> started" '$D start | grep -q "^started /usbtest"'
check "실행 중 다시 start -> running" '[ "$($D start)" = running ]'
sleep 2
check "status: running, 경과 초, 시작 시각" '$D status | grep -q "^state=running$" && $D status | grep -q "^elapsed=[0-9]" && $D status | grep -q "^started=[0-9][0-9]:[0-9][0-9]$"'
check "status: 단계 n/9 와 지금 하는 일" '$D status | grep -q "^stage=[1-9]/9 " && $D status | grep -q "^detail=."'
for i in $(seq 1 240); do $D status | grep -q "^state=done" && break; sleep 1; done
check "완료 -> state=done, dir, 걸린 시간" '$D status | grep -q "^state=done$" && $D status | grep -q "^dir=/usbtest/pfdiag-" && $D status | grep -q "^elapsed=[0-9]"'
check "summary 는 SUMMARY.txt 앞부분" '$D summary | grep -q "pretendard-systemfont 진단 결과"'
check "빠른 진단: 마운트 시험 생략" 'grep -q "skipped (MOUNT_TEST=0)" /usbtest/pfdiag-*/mounttest/result.txt'
check "빠른 진단: APK 검사·복사 없음" 'grep -q "apk scan skipped" /usbtest/pfdiag-*/run.log && [ -z "$(ls /usbtest/pfdiag-*/apks/*.apk 2>/dev/null)" ]'
check "빠른 진단: 폰트 파일 복사 없음" '[ -z "$(ls /usbtest/pfdiag-*/fonts/files/ 2>/dev/null)" ]'
check "진단 결과에 시리얼·커널 command line 없음" '! grep -rq -i -e "serialno" -e "command line" /usbtest/pfdiag-*/'
check "logcat 원본을 남기지 않음" '[ -z "$(ls /usbtest/pfdiag-*/boot/logcat.raw /usbtest/pfdiag-*/boot/logcat.txt 2>/dev/null)" ]'
check "사용자 파일 목록(/data 등)을 남기지 않음, system·vendor 만" '[ -z "$(ls /usbtest/pfdiag-*/scan/ | grep ^ls_R | grep -v -e ls_R_system.txt -e ls_R_vendor.txt)" ]'
check "MAC 주소가 든 줄 없음" '! grep -rqE "([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}" /usbtest/pfdiag-*/boot /usbtest/pfdiag-*/meta'
D1=$(ls -d /usbtest/pfdiag-*)

$D start > /dev/null; sleep 2; rm -rf /usbtest/pfdiag-* ; sleep 1
check "USB 분리(폴더 사라짐) -> error=usb_removed 로 멈춤" '$D status | grep -q "^error=usb_removed$"'
check "멈춘 뒤 진단 프로세스 없음" '! $D status | grep -q "^state=running"'

$D start > /dev/null; sleep 2; $D stop > /dev/null
check "중지 버튼 -> error=stopped" '$D status | grep -q "^state=error$" && $D status | grep -q "^error=stopped$"'
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
