#!/bin/sh
# Pretendard 공식 릴리스에서 패키지에 넣을 TTF 와 라이선스를 내려받는다.
# 받은 zip 은 sha256 으로 검증하고, 폰트는 수정하지 않고 그대로 쓴다 (OFL RFN 준수).
set -eu

VERSION=1.3.9
SHA256=04be351a74d6bf7d60c480a3087e51d185485d35a52023142af1df19eb8c428a
URL="https://github.com/orioncactus/pretendard/releases/download/v$VERSION/Pretendard-$VERSION.zip"
WEIGHTS="Thin Light Regular Bold"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/package/pretendard.systemfont/fonts"
CACHE="$ROOT/build/cache"
ZIP="$CACHE/Pretendard-$VERSION.zip"

mkdir -p "$CACHE" "$DEST"
if [ ! -f "$ZIP" ]; then
    echo "download $URL"
    curl -fsSL -o "$ZIP.part" "$URL"
    mv "$ZIP.part" "$ZIP"
fi
got="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
if [ "$got" != "$SHA256" ]; then
    echo "sha256 mismatch: $got" >&2
    rm -f "$ZIP"
    exit 1
fi

# zip 안의 경로를 고정해서 꺼낸다 (다른 파일은 풀지 않음)
for w in $WEIGHTS; do
    unzip -p "$ZIP" "public/static/alternative/Pretendard-$w.ttf" > "$DEST/Pretendard-$w.ttf"
done
unzip -p "$ZIP" "LICENSE.txt" > "$DEST/LICENSE.txt"
echo "$VERSION" > "$DEST/VERSION"
ls -l "$DEST"
