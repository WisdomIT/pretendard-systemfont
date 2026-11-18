#!/bin/sh
# 상태 화면 앱(app/)을 APK 로 빌드해 package/pretendard.systemfont/app/ 에 넣는다.
#
# Android SDK 설치 없이, 공개 Maven 저장소의 도구를 버전과 sha256 을 고정해 받는다.
#   aapt2  (com.android.tools.build:aapt2, Apache-2.0)  매니페스트 컴파일
#   r8/d8  (com.android.tools:r8, BSD-3)                 .class -> classes.dex
#   android-all 4.4 (org.robolectric, Apache-2.0)        API 19 컴파일 기준 + 프레임워크 리소스
# 서명은 JDK 의 keytool/jarsigner (v1 서명; KitKat 이 읽는 방식).
#
# 서명 키: $PF_APP_KEY (기본 ~/.pretendard-systemfont/app-release.p12, 비밀번호는 같은 이름의 .pass).
# 없으면 새로 만든다. 업데이트 설치는 같은 키로 서명해야 하므로 꼭 백업해 둘 것.
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TC="$ROOT/build/toolchain"
W="$ROOT/build/apk"
OUT="$ROOT/package/pretendard.systemfont/app/PretendardStatus.apk"
KEY="${PF_APP_KEY:-$HOME/.pretendard-systemfont/app-release.p12}"
PASSF="${KEY%.p12}.pass"

case "$(uname -s)" in
    Darwin) AAPT2_OS=osx ;;
    Linux)  AAPT2_OS=linux ;;
    *) echo "지원하지 않는 OS"; exit 1 ;;
esac

fetch() {   # 파일 URL sha256
    if [ ! -f "$TC/$1" ]; then
        echo "download $2"
        curl -fsSL -o "$TC/$1.part" "$2"
        mv "$TC/$1.part" "$TC/$1"
    fi
    got="$(shasum -a 256 "$TC/$1" | cut -d' ' -f1)"
    if [ "$got" != "$3" ]; then echo "sha256 불일치: $1 ($got)" >&2; rm -f "$TC/$1"; exit 1; fi
}

mkdir -p "$TC"
G=https://dl.google.com/android/maven2
if [ "$AAPT2_OS" = osx ]; then
    fetch aapt2-osx.jar "$G/com/android/tools/build/aapt2/8.7.3-12006047/aapt2-8.7.3-12006047-osx.jar" \
        8cfca8d3fcb8ad45cf46e3780cdd4a64cb38c70ca45b442655de9f3e7d19efc1
else
    fetch aapt2-linux.jar "$G/com/android/tools/build/aapt2/8.7.3-12006047/aapt2-8.7.3-12006047-linux.jar" \
        "${PF_AAPT2_LINUX_SHA256:?Linux 에서는 PF_AAPT2_LINUX_SHA256 를 지정하세요}"
fi
fetch r8.jar "$G/com/android/tools/r8/8.7.18/r8-8.7.18.jar" \
    58366f77067207c39a17d469de7b05701d2877212a9c55201bcb0af43e59e903
fetch android-all.jar "https://repo1.maven.org/maven2/org/robolectric/android-all/4.4_r1-robolectric-r2/android-all-4.4_r1-robolectric-r2.jar" \
    5c68ab0a11d6f46e303505e75da62215f45b6a46ff7877441a31d527899359f9
if [ ! -x "$TC/aapt2" ]; then
    (cd "$TC" && unzip -o -q "aapt2-$AAPT2_OS.jar" aapt2 && chmod +x aapt2)
    xattr -d com.apple.quarantine "$TC/aapt2" 2>/dev/null || true
fi
ANDROID_JAR="$TC/android-all.jar"

# 패키지 버전 -> versionName, versionCode (0.1 -> 100, 1.2.3 -> 10203)
VNAME="$(sed -n 's/^package-version=//p' "$ROOT/package/pretendard.systemfont/NEMESIS.data")"
VCODE="$(echo "$VNAME" | awk -F. '{printf "%d", ($1*10000)+($2*100)+$3}')"
[ "$VCODE" -gt 0 ] || VCODE=1

rm -rf "$W" && mkdir -p "$W/classes"
"$TC/aapt2" link -o "$W/base.apk" -I "$ANDROID_JAR" --manifest "$ROOT/app/AndroidManifest.xml" \
    --min-sdk-version 19 --target-sdk-version 19 --version-code "$VCODE" --version-name "$VNAME"

javac --release 8 -encoding UTF-8 -Xlint:-options -nowarn -cp "$ANDROID_JAR" -d "$W/classes" \
    $(find "$ROOT/app/src" "$ROOT/app/third_party" -name '*.java')
JHOME="$(java -XshowSettings:properties -version 2>&1 | sed -n 's/^ *java.home = //p')"
java -cp "$TC/r8.jar" com.android.tools.r8.D8 --release --min-api 19 --lib "$ANDROID_JAR" --lib "$JHOME" \
    --output "$W" $(find "$W/classes" -name '*.class')

cp "$W/base.apk" "$W/unsigned.apk"
(cd "$W" && zip -q -X unsigned.apk classes.dex)

if [ ! -f "$KEY" ]; then
    echo "서명 키가 없어 새로 만듭니다: $KEY  (백업해 두세요)"
    mkdir -p "$(dirname "$KEY")" && chmod 700 "$(dirname "$KEY")"
    head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$PASSF" && chmod 600 "$PASSF"
    keytool -genkeypair -keystore "$KEY" -storetype PKCS12 -storepass "$(cat "$PASSF")" \
        -alias app -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=WisdomIT pretendard-systemfont" >/dev/null 2>&1
    chmod 600 "$KEY"
fi
jarsigner -keystore "$KEY" -storepass "$(cat "$PASSF")" -sigalg SHA256withRSA -digestalg SHA-256 \
    -signedjar "$W/signed.apk" "$W/unsigned.apk" app >/dev/null
jarsigner -verify "$W/signed.apk" >/dev/null

mkdir -p "$(dirname "$OUT")"
cp "$W/signed.apk" "$OUT"
echo "$OUT  $(($(wc -c < "$OUT") / 1024)) KB  version $VNAME ($VCODE)"
