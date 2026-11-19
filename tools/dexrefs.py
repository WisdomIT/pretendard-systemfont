#!/usr/bin/env python3
"""dex / odex(dey) 파일에서 글꼴을 불러오는 코드를 찾는다.

  python3 tools/dexrefs.py <Launcher_WP3.odex> [다른 .odex/.dex/.apk ...]

찾는 것
  - 글꼴 파일 이름 문자열 (.ttf / .otf / .ttc) 과 그 문자열을 쓰는 메서드
  - android.graphics.Typeface 의 글꼴 생성 메서드(createFromAsset, createFromFile, create 등)를
    호출하는 메서드
  - 한 메서드 안에서 둘이 함께 쓰이면 "글꼴 로딩 지점" 으로 따로 보여 준다

KitKat odex 는 dex 를 그대로 품고 있고, 정적 메서드 호출(invoke-static)과 문자열 상수는 dexopt 뒤에도
원래 참조가 남는다. 그래서 부트 클래스패스 없이 바로 읽을 수 있다. (가상 메서드 호출은 quick 명령으로
바뀌어 이름이 사라질 수 있으므로, 그런 경우는 baksmali 로 부트 클래스패스와 함께 풀어야 한다.)

표준 라이브러리만 쓴다. OEM 파일은 읽기만 하고 아무것도 쓰지 않는다.
"""
import struct
import sys
import zipfile

# ---- dex 읽기 ---------------------------------------------------------------


def uleb(buf, pos):
    result = shift = 0
    while True:
        b = buf[pos]
        pos += 1
        result |= (b & 0x7F) << shift
        if b < 0x80:
            return result, pos
        shift += 7


def load_dex(path):
    """파일에서 dex 바이트를 꺼낸다 (odex 헤더, apk 의 classes.dex 지원)."""
    if path.endswith(".apk") or path.endswith(".jar"):
        with zipfile.ZipFile(path) as z:
            if "classes.dex" not in z.namelist():
                return None
            return z.read("classes.dex")
    data = open(path, "rb").read()
    if data[:4] == b"dey\n":                     # odex: 헤더 뒤에 dex 가 있다
        off, length = struct.unpack_from("<II", data, 8)
        return data[off:off + length]
    if data[:4] == b"dex\n":
        return data
    raise ValueError(f"{path}: dex/odex 가 아닙니다 (magic {data[:4]!r})")


class Dex:
    def __init__(self, b):
        self.b = b
        h = struct.unpack_from("<20I", b, 0x38)
        (self.str_n, self.str_off, self.type_n, self.type_off, self.proto_n, self.proto_off,
         self.field_n, self.field_off, self.meth_n, self.meth_off, self.cls_n, self.cls_off) = h[:12]
        self._strings = {}

    def string(self, i):
        if i not in self._strings:
            off = struct.unpack_from("<I", self.b, self.str_off + 4 * i)[0]
            _, p = uleb(self.b, off)
            end = self.b.index(b"\0", p)
            self._strings[i] = self.b[p:end].decode("utf-8", "replace")   # MUTF-8 은 대체로 UTF-8 로 충분
        return self._strings[i]

    def type_name(self, i):
        return self.string(struct.unpack_from("<I", self.b, self.type_off + 4 * i)[0])

    def method(self, i):
        cls, _proto, name = struct.unpack_from("<HHI", self.b, self.meth_off + 8 * i)
        return self.type_name(cls), self.string(name)

    def methods_with_code(self):
        """(클래스, 메서드 이름, code_item 오프셋) 를 차례로 낸다."""
        for c in range(self.cls_n):
            cls_idx, _, _, _, _, _, data_off, _ = struct.unpack_from("<8I", self.b, self.cls_off + 32 * c)
            if not data_off:
                continue
            p = data_off
            sf, p = uleb(self.b, p)
            inf, p = uleb(self.b, p)
            dm, p = uleb(self.b, p)
            vm, p = uleb(self.b, p)
            for _ in range(sf + inf):
                _, p = uleb(self.b, p)
                _, p = uleb(self.b, p)
            midx = 0
            for count in (dm, vm):
                midx = 0
                for _ in range(count):
                    d, p = uleb(self.b, p)
                    midx += d
                    _, p = uleb(self.b, p)          # access flags
                    code, p = uleb(self.b, p)
                    if code:
                        cname, mname = self.method(midx)
                        yield cname, mname, code


# 명령 길이 (16비트 단위). KitKat odex 의 quick/volatile 명령(0xe3~0xfe) 포함.
WIDTH = [1] * 256
def _set(lo, hi, w):
    for op in range(lo, hi + 1):
        WIDTH[op] = w
_set(0x02, 0x02, 2); _set(0x03, 0x03, 3); _set(0x05, 0x05, 2); _set(0x06, 0x06, 3)
_set(0x08, 0x08, 2); _set(0x09, 0x09, 3)
_set(0x13, 0x13, 2); _set(0x14, 0x14, 3); _set(0x15, 0x16, 2); _set(0x17, 0x17, 3)
_set(0x18, 0x18, 5); _set(0x19, 0x1a, 2); _set(0x1b, 0x1b, 3); _set(0x1c, 0x1c, 2)
_set(0x1f, 0x20, 2); _set(0x22, 0x23, 2); _set(0x24, 0x26, 3); _set(0x29, 0x29, 2)
_set(0x2a, 0x2c, 3); _set(0x2d, 0x3d, 2); _set(0x44, 0x6d, 2); _set(0x6e, 0x72, 3)
_set(0x74, 0x78, 3); _set(0x90, 0xaf, 2); _set(0xd0, 0xe2, 2)
_set(0xe3, 0xeb, 2); _set(0xed, 0xed, 2); _set(0xee, 0xf0, 3); _set(0xf2, 0xf7, 2)
_set(0xf8, 0xfb, 3); _set(0xfc, 0xfe, 2)

CONST_STRING, CONST_STRING_JUMBO = 0x1a, 0x1b
INVOKES = {0x6e: "virtual", 0x6f: "super", 0x70: "direct", 0x71: "static", 0x72: "interface",
           0x74: "virtual", 0x75: "super", 0x76: "direct", 0x77: "static", 0x78: "interface"}


def scan_code(dex, code_off):
    """한 메서드 코드에서 (문자열 index 들, (메서드 index, 호출 종류) 들) 을 모은다."""
    b = dex.b
    insns_size = struct.unpack_from("<I", b, code_off + 12)[0]
    base = code_off + 16
    strings, calls = [], []
    pc = 0
    while pc < insns_size:
        unit = struct.unpack_from("<H", b, base + 2 * pc)[0]
        op = unit & 0xFF
        if op == 0x00 and unit != 0:                      # switch / array payload
            if unit == 0x0100:
                size = struct.unpack_from("<H", b, base + 2 * pc + 2)[0]
                pc += 4 + size * 2
            elif unit == 0x0200:
                size = struct.unpack_from("<H", b, base + 2 * pc + 2)[0]
                pc += 2 + size * 4
            elif unit == 0x0300:
                ew, n = struct.unpack_from("<HI", b, base + 2 * pc + 2)
                pc += 4 + (n * ew + 1) // 2
            else:
                pc += 1
            continue
        if op == CONST_STRING:
            strings.append(struct.unpack_from("<H", b, base + 2 * pc + 2)[0])
        elif op == CONST_STRING_JUMBO:
            strings.append(struct.unpack_from("<I", b, base + 2 * pc + 2)[0])
        elif op in INVOKES:
            calls.append((struct.unpack_from("<H", b, base + 2 * pc + 2)[0], INVOKES[op]))
        pc += WIDTH[op]
    return strings, calls


FONT_EXT = (".ttf", ".otf", ".ttc", ".TTF", ".OTF", ".TTC")
TYPEFACE = "Landroid/graphics/Typeface;"


def analyze(path):
    dex_bytes = load_dex(path)
    print(f"=== {path}")
    if dex_bytes is None:
        print("  classes.dex 없음 (코드는 같은 이름의 .odex 에 있습니다)")
        return
    dex = Dex(dex_bytes)

    font_strings = {i: dex.string(i) for i in range(dex.str_n) if dex.string(i).endswith(FONT_EXT)}
    typeface_methods = {i: dex.method(i)[1] for i in range(dex.meth_n) if dex.method(i)[0] == TYPEFACE}

    print(f"  글꼴 파일 이름 문자열 {len(font_strings)}개: {', '.join(sorted(set(font_strings.values()))) or '-'}")
    print(f"  참조하는 Typeface 메서드: {', '.join(sorted(set(typeface_methods.values()))) or '-'}")

    hits = []
    for cname, mname, code in dex.methods_with_code():
        strs, calls = scan_code(dex, code)
        fs = [font_strings[s] for s in strs if s in font_strings]
        tc = [(typeface_methods[m], kind) for m, kind in calls if m in typeface_methods]
        if fs or tc:
            hits.append((cname, mname, fs, tc))

    if not hits:
        print("  글꼴 문자열이나 Typeface 호출을 쓰는 메서드를 찾지 못했습니다.")
        print("  (가상 메서드 호출이 quick 명령으로 바뀐 경우일 수 있습니다. baksmali 로 확인하세요.)")
        return
    both = [h for h in hits if h[2] and h[3]]
    if both:
        print("  ▶ 글꼴 로딩 지점 (같은 메서드에서 글꼴 이름과 Typeface 호출):")
        for cname, mname, fs, tc in both:
            calls = ", ".join(sorted({f"{n} (invoke-{k})" for n, k in tc}))
            print(f"    {cname}->{mname}: {', '.join(sorted(set(fs)))}  /  {calls}")
    others = [h for h in hits if not (h[2] and h[3])]
    if others:
        print("  그 밖에 관련 메서드:")
        for cname, mname, fs, tc in others[:40]:
            what = []
            if fs:
                what.append("문자열 " + ", ".join(sorted(set(fs))))
            if tc:
                what.append("호출 " + ", ".join(sorted({f"{n} (invoke-{k})" for n, k in tc})))
            print(f"    {cname}->{mname}: {' / '.join(what)}")
        if len(others) > 40:
            print(f"    … 그 밖에 {len(others) - 40}개")


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 1
    for path in argv[1:]:
        try:
            analyze(path)
        except Exception as e:                       # 한 파일 실패가 나머지를 막지 않게
            print(f"=== {path}\n  읽기 실패: {e}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
