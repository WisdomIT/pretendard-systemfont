#!/bin/sh
# 릴리스 파일을 만들고, --publish 를 주면 태그와 GitHub 릴리스까지 만든다.
#
#   tools/release.sh             dist/release/ 에 릴리스 파일만 만든다 (확인용)
#   tools/release.sh --publish   main 브랜치에서: 태그 v<버전> 생성·푸시, GitHub 릴리스 생성
#
# 만드는 파일 (<v> = NEMESIS.data 의 package-version)
#   pretendard-systemfont-<v>-usb.zip       USB 맨 위에 풀면 바로 설치되는 묶음 (대부분의 사용자)
#   pretendard.systemfont-<v>.zip           NEMESIS 패키지 하나 (직접 설치하는 사람용)
#   pretendard-systemfont-<v>-diag-usb.zip  USB 직접 진단 (Android 가 켜지지 않을 때 등)
#   SHA256SUMS.txt
#
# 절차 전체는 docs/RELEASING.md 참고.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PUBLISH=0
[ "${1:-}" = "--publish" ] && PUBLISH=1

V="$(sed -n 's/^package-version=//p' package/pretendard.systemfont/NEMESIS.data)"
[ -n "$V" ] || { echo "package-version 을 읽지 못했습니다"; exit 1; }
TAG="v$V"
OUT="$ROOT/dist/release"

if [ "$PUBLISH" = 1 ]; then
    branch="$(git rev-parse --abbrev-ref HEAD)"
    [ "$branch" = main ] || { echo "릴리스는 main 에서만 합니다 (지금: $branch)"; exit 1; }
    [ -z "$(git status --porcelain)" ] || { echo "커밋되지 않은 변경이 있습니다"; exit 1; }
    git fetch -q origin main --tags
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo "origin/main 과 다릅니다. push 또는 pull 먼저"; exit 1; }
    if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
        echo "태그 $TAG 가 이미 있습니다. NEMESIS.data 의 package-version 을 올리세요"; exit 1
    fi
fi

# 빌드와 테스트
sh tools/fetch_fonts.sh >/dev/null
python3 tools/build.py
if [ "${PF_SKIP_TESTS:-0}" != 1 ]; then
    sh tests/run.sh | tail -1 | grep -q "FAIL=0" || { echo "테스트 실패. 릴리스를 멈춥니다"; exit 1; }
fi

rm -rf "$OUT" && mkdir -p "$OUT"
cp "dist/pretendard.systemfont-$V.zip" "$OUT/"

# USB 설치 묶음: 압축을 풀면 NEMESIS.data 와 packages/ 가 바로 나오게 (폴더로 한 번 더 감싸지 않음)
(cd dist/usb && zip -q -X -r "$OUT/pretendard-systemfont-$V-usb.zip" NEMESIS.data packages)

# USB 직접 진단 묶음
(cd diag/usb && zip -q -X "$OUT/pretendard-systemfont-$V-diag-usb.zip" NEMESIS.data pfdiag.sh)

(cd "$OUT" && shasum -a 256 *.zip > SHA256SUMS.txt)
ls -l "$OUT"

[ "$PUBLISH" = 1 ] || { echo "확인용 빌드 완료. 게시하려면 main 에서 tools/release.sh --publish"; exit 0; }

NOTES="$ROOT/dist/release-notes.md"
{
    echo "## 설치"
    echo
    echo "1. 아래 **\`pretendard-systemfont-$V-usb.zip\`** 을 받아 압축을 풀고, 안에 있는 \`NEMESIS.data\` 와 \`packages\` 폴더를 USB **맨 위**에 복사합니다."
    echo "2. 차에 꽂고 NEMESIS 가 물으면 **예** → NEMESIS Manager → Settings → **Reboot**."
    echo
    echo "처음이라면 [README 의 설치 안내](https://github.com/WisdomIT/pretendard-systemfont#설치)를 따라 하세요. NEMESIS 가 먼저 설치되어 있어야 합니다."
    echo
    echo "| 파일 | 용도 |"
    echo "|---|---|"
    echo "| \`pretendard-systemfont-$V-usb.zip\` | **대부분은 이것.** USB 에 풀면 바로 설치 |"
    echo "| \`pretendard.systemfont-$V.zip\` | 패키지 파일만 (직접 설치하는 경우) |"
    echo "| \`pretendard-systemfont-$V-diag-usb.zip\` | USB 직접 진단 (상태 화면을 열 수 없을 때) |"
    echo "| \`SHA256SUMS.txt\` | 파일 검증용 |"
    echo
    if [ -f "docs/changes/$TAG.md" ]; then
        echo "## 바뀐 점"
        echo
        cat "docs/changes/$TAG.md"
    fi
} > "$NOTES"

git tag -a "$TAG" -m "pretendard-systemfont $V"
git push -q origin "$TAG"
gh release create "$TAG" "$OUT"/*.zip "$OUT/SHA256SUMS.txt" --title "pretendard-systemfont $V" --notes-file "$NOTES"
echo "릴리스 $TAG 게시 완료"
