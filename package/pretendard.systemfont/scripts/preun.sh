#!/system/bin/sh
# preuninstall: 패키지 삭제와 NEMESIS wipe 모두에서 실행된다 (서비스 정지 후, 파일 삭제 전).
#
# 마운트를 모두 풀고 상태 기록을 지운다. /system 은 처음부터 건드리지 않았으므로
# 되돌릴 파일이 없다. 마운트 해제에 실패해도 재부팅하면 풀리므로, 삭제나 wipe 를
# 막지 않도록 항상 0 으로 끝낸다.

_here="${0%/*}"
. "$_here/../lib/common.sh"

if unmount_all; then
    log "삭제: 마운트 모두 해제"
    echo "Pretendard 를 해제했습니다. 이미 열린 화면은 재부팅 후 완전히 순정으로 돌아옵니다."
else
    log "삭제: 사용 중인 마운트가 남음. 재부팅하면 해제됨."
    echo "사용 중인 폰트는 재부팅하면 순정으로 돌아옵니다. Settings > Reboot 을 권장합니다."
fi

case "$STATE" in
    /data/nemesis/state/?*|/data/*/pftest/state*) rm -rf "$STATE" ;;
esac
exit 0
