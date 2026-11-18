#!/bin/sh
# 패키지를 빌드하고 Linux 컨테이너(mksh, KitKat 에 없는 도구 제거)에서 수명주기 테스트를 돌린다.
set -eu
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
python3 "$ROOT/tools/build.py"
docker run --rm --privileged \
    -v "$ROOT/dist:/dist:ro" \
    -v "$ROOT/tests/lifecycle.sh:/lifecycle.sh:ro" \
    debian:bookworm-slim bash /lifecycle.sh 2>&1 | grep -v debconf
