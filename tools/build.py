#!/usr/bin/env python3
"""pretendard.systemfont NEMESIS 패키지를 빌드한다.

  1. map.conf 가 가리키는 폰트가 모두 있는지 확인
  2. fonts/md5.txt 생성 (기기에서 손상 검사에 사용)
  3. dist/pretendard.systemfont-<ver>.zip 생성
  4. dist/usb/ 에 USB 루트 구성 (NEMESIS.data type=install + packages/<zip>)

표준 라이브러리만 사용한다. 먼저 tools/fetch_fonts.sh 로 폰트를 받아 둘 것.
"""
import hashlib
import shutil
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PKG = ROOT / "package" / "pretendard.systemfont"
DIST = ROOT / "dist"
FIXED_TIME = (2026, 1, 1, 0, 0, 0)  # 재현 가능한 zip


def read_ini_value(path: Path, key: str) -> str:
    for line in path.read_text(encoding="utf-8").splitlines():
        if line.startswith(key + "="):
            return line.split("=", 1)[1].strip().strip('"')
    raise SystemExit(f"{path.name}: {key} 없음")


def map_sources() -> set[str]:
    out = set()
    for line in (PKG / "files" / "map.conf").read_text(encoding="utf-8").splitlines():
        parts = line.split()
        if not parts or parts[0].startswith("#"):
            continue
        if len(parts) < 2:
            raise SystemExit(f"map.conf 형식 오류: {line!r}")
        out.add(parts[1])
    return out


def main() -> int:
    fonts = PKG / "fonts"
    missing = [s for s in sorted(map_sources()) if not (fonts / s).is_file()]
    if missing or not (fonts / "LICENSE.txt").is_file():
        print("폰트 또는 LICENSE 가 없습니다. 먼저 tools/fetch_fonts.sh 를 실행하세요:", missing)
        return 1

    # 패키지에는 map.conf 가 쓰는 폰트와 라이선스만 넣는다
    used = map_sources()
    sums = []
    for f in sorted(fonts.glob("*.ttf")):
        if f.name in used:
            sums.append(f"{hashlib.md5(f.read_bytes()).hexdigest()}  {f.name}")
    (fonts / "md5.txt").write_text("\n".join(sums) + "\n", encoding="utf-8")

    version = read_ini_value(PKG / "NEMESIS.data", "package-version")
    pkg_id = read_ini_value(PKG / "NEMESIS.data", "id")
    short = read_ini_value(PKG / "NEMESIS.data", "short-desc")
    detail = read_ini_value(PKG / "NEMESIS.data", "detailed-desc")
    if len(short) > 64 or len(detail) > 256:
        print(f"설명이 너무 깁니다: short={len(short)} detailed={len(detail)}")
        return 1

    DIST.mkdir(exist_ok=True)
    zpath = DIST / f"{pkg_id}-{version}.zip"
    members = []
    for p in sorted(PKG.rglob("*")):
        if p.is_dir() or p.name == ".DS_Store":
            continue
        rel = p.relative_to(PKG).as_posix()
        if rel.startswith("fonts/") and p.suffix == ".ttf" and p.name not in used:
            continue
        members.append((p, rel))
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for p, rel in members:
            data = p.read_bytes()
            if p.suffix in (".sh", ".conf", ".data", ".txt"):
                if b"\r\n" in data:
                    print(f"CRLF 금지: {rel}")
                    return 1
            info = zipfile.ZipInfo(rel, FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = (0o755 if p.suffix == ".sh" else 0o644) << 16
            z.writestr(info, data)

    usb = DIST / "usb"
    if usb.exists():
        shutil.rmtree(usb)
    (usb / "packages").mkdir(parents=True)
    shutil.copy2(zpath, usb / "packages" / zpath.name)
    (usb / "NEMESIS.data").write_text(
        "[nemesis]\nversion=1.0\ntype=install\n" f"path=packages/{zpath.name}\n", encoding="utf-8"
    )

    print(f"{zpath.relative_to(ROOT)}  {zpath.stat().st_size // 1024} KB, {len(members)} files")
    print(f"USB 루트: {usb.relative_to(ROOT)}/  (이 폴더 안의 내용을 USB 루트에 복사)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
