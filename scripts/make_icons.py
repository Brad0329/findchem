"""앱 아이콘 생성 — 원본 docs/design/findchem_icon.svg 하나에서 Android·웹 아이콘 PNG를 모두 굽는다.

사용: python scripts/make_icons.py
- 래스터화는 설치된 Chrome 헤드리스 스크린숏으로 한다(새 의존성을 들이지 않기 위해).
- 원본 SVG의 그라데이션·도형을 읽어 변형 3종을 만든다:
  full      둥근 모서리 아이콘 그대로 (Android 7 이하 런처 아이콘, 웹 일반 아이콘·favicon)
  maskable  모서리 없는 정사각 배경 + 안전 영역(반지름 40%) 안으로 줄인 글리프 (웹 maskable)
  adaptive  Android 8+ 적응형 아이콘의 전경(투명 배경 글리프)·배경(그라데이션) 두 겹.
            글리프는 안전 영역(지름 66dp) 안으로 줄이고, 배경 그라데이션은 보이는 가운데 72dp에 맞춘다.
- 구운 뒤 PNG 크기와 모서리 픽셀 알파(투명이어야 할 곳이 투명한가)를 직접 읽어 대조한다. 어긋나면 실패로 끝낸다.
"""

import re
import struct
import subprocess
import sys
import tempfile
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC_SVG = ROOT / "docs" / "design" / "findchem_icon.svg"
CHROME = Path("C:/Program Files/Google/Chrome/Application/chrome.exe")
RES = ROOT / "android" / "app" / "src" / "main" / "res"
WEB = ROOT / "web"

# 원본 viewBox 200 기준. 글리프의 중심(100,100)에서 가장 먼 점(플라스크 바닥 모서리)까지 약 84.
MASKABLE_SCALE = 0.88   # 84 * 0.88 = 74 < 80 (웹 maskable 안전 영역 반지름 40%)
ADAPTIVE_SCALE = 0.72   # 84 * 0.72 = 60.5 < 61.1 (적응형 안전 영역 지름 66dp / 캔버스 108dp를 200 단위 반지름으로 환산)

DENSITIES = {"mdpi": 1.0, "hdpi": 1.5, "xhdpi": 2.0, "xxhdpi": 3.0, "xxxhdpi": 4.0}


def read_source():
    text = SRC_SVG.read_text(encoding="utf-8")
    stops = re.findall(r'<stop offset="([\d.]+)" stop-color="(#[0-9A-Fa-f]{6})"/>', text)
    glyph = re.findall(r"^\s*(<(?:path|circle)\b.*?/>)\s*$", text, flags=re.M)
    if len(stops) != 2 or not glyph:
        sys.exit(f"원본 SVG 구조가 예상과 다르다: stop {len(stops)}개, 글리프 요소 {len(glyph)}개 — {SRC_SVG}")
    return stops, "\n".join(glyph)


def gradient(stops, lo=0.0, hi=1.0):
    s = "".join(f'<stop offset="{o}" stop-color="{c}"/>' for o, c in stops)
    return (f'<defs><linearGradient id="bg" x1="{lo}" y1="{lo}" x2="{hi}" y2="{hi}">{s}'
            f"</linearGradient></defs>")


def scaled(glyph, scale):
    return f'<g transform="translate(100 100) scale({scale}) translate(-100 -100)">{glyph}</g>'


def variants(stops, glyph):
    return {
        "full": gradient(stops) + '<rect width="200" height="200" rx="44" fill="url(#bg)"/>' + glyph,
        "maskable": gradient(stops) + '<rect width="200" height="200" fill="url(#bg)"/>'
                    + scaled(glyph, MASKABLE_SCALE),
        "adaptive_fg": scaled(glyph, ADAPTIVE_SCALE),
        # 108dp 중 가운데 72dp(1/6~5/6)가 보이는 영역 — 그 구간에서 원본과 같은 양 끝 색이 나오게 한다.
        "adaptive_bg": gradient(stops, 1 / 6, 5 / 6) + '<rect width="200" height="200" fill="url(#bg)"/>',
    }


def targets():
    out = []
    for name, f in DENSITIES.items():
        d = RES / f"mipmap-{name}"
        out.append(("full", round(48 * f), d / "ic_launcher.png"))
        out.append(("adaptive_fg", round(108 * f), d / "ic_launcher_foreground.png"))
        out.append(("adaptive_bg", round(108 * f), d / "ic_launcher_background.png"))
    out += [
        ("full", 32, WEB / "favicon.png"),
        ("full", 192, WEB / "icons" / "Icon-192.png"),
        ("full", 512, WEB / "icons" / "Icon-512.png"),
        ("maskable", 192, WEB / "icons" / "Icon-maskable-192.png"),
        ("maskable", 512, WEB / "icons" / "Icon-maskable-512.png"),
    ]
    return out


def png_size(path):
    with open(path, "rb") as fh:
        head = fh.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        return None
    return struct.unpack(">II", head[16:24])


def corner_alpha(path):
    """왼쪽 위 픽셀의 알파. 첫 행 첫 픽셀은 PNG 필터 5종 모두에서 원값 그대로라 복원 없이 읽힌다."""
    data = Path(path).read_bytes()
    pos, idat, ctype = 8, b"", None
    while pos < len(data):
        length, tag = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + length]
        if tag == b"IHDR":
            depth, ctype = chunk[8], chunk[9]
            if depth != 8:
                return None
        elif tag == b"IDAT":
            idat += chunk
        pos += 12 + length
    if ctype == 2:  # RGB — 알파 채널이 없으면 불투명(Chrome은 꽉 찬 이미지를 이 형식으로 저장한다)
        return 255
    if ctype != 6:  # 그 밖의 형식은 이 방식으로 못 본다
        return None
    return zlib.decompress(idat)[4]


def render(body, size, out, tmp):
    html = tmp / f"icon_{size}.html"
    html.write_text(
        '<!doctype html><html><head><meta charset="utf-8"><style>'
        "html,body{margin:0;padding:0;background:transparent;overflow:hidden}svg{display:block}"
        f'</style></head><body><svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200" '
        f'width="{size}" height="{size}">{body}</svg></body></html>',
        encoding="utf-8",
    )
    out.parent.mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [str(CHROME), "--headless", "--disable-gpu", "--hide-scrollbars",
         "--default-background-color=00000000", f"--window-size={size},{size}",
         f"--screenshot={out}", html.as_uri()],
        capture_output=True, text=True, timeout=60,
    )
    got = png_size(out) if out.exists() else None
    if result.returncode != 0 or got != (size, size):
        sys.exit(f"렌더 실패: {out} — 기대 {size}x{size}, 실제 {got}, exit {result.returncode}\n{result.stderr}")


# 모서리가 투명해야 하는 변형(둥근 모서리·전경)과 꽉 차야 하는 변형. 투명 배경 플래그가 안 먹으면 흰 모서리가 된다.
CORNER_ALPHA = {"full": 0, "adaptive_fg": 0, "maskable": 255, "adaptive_bg": 255}


def check_corner(kind, out):
    got = corner_alpha(out)
    if got != CORNER_ALPHA[kind]:
        sys.exit(f"모서리 알파 불일치: {out} — {kind}는 {CORNER_ALPHA[kind]}여야 하는데 {got}")


def main():
    if not CHROME.exists():
        sys.exit(f"Chrome이 없다: {CHROME}")
    stops, glyph = read_source()
    bodies = variants(stops, glyph)
    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        for kind, size, out in targets():
            render(bodies[kind], size, out, tmp)
            check_corner(kind, out)
            print(f"{kind:12} {size:4}px  {out.relative_to(ROOT).as_posix()}")


if __name__ == "__main__":
    main()
