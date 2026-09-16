"""pdfplumber로 별표 1·2·3·4 PDF의 **표 밖 규칙 텍스트**를 줄 단위로 덤프한다 (Dart 규칙 자산 대조용 정답지).

왜 따로 있나: `oracle_pdf_cells.py`는 **표 안 셀**의 정답지다. 규정수량을 지배하는 일반기준(별표 2·3)·
최대보유량 산정 방법(별표 4)·유해성 그룹 비고(별표 1)는 **표 밖 문단**이라 그 정답지에 없다.
F-008 1단계에서 이 문단들을 `lib/assist/rules.dart`에 손으로 옮겼고, 손으로 만든 데이터에는
자동 검증을 붙인다(CLAUDE.md 불변 규칙) — 그 대조의 정답지가 이 파일의 출력이다.

출력: test/fixtures/rule_text.json
  {"<topic>": {"file":..., "range": {...}, "lines": [원문 줄...], "excluded": [{"line":..., "why":...}]}}
대조는 Dart 쪽(test/assist/rules_test.dart)이 한다 — 공백을 지운 원문 줄이 상수 안에 그대로 있는지 본다.
그래서 줄바꿈만 다시 흘린 상수는 통과하고, 글자가 바뀌면 걸린다.

  python scripts/oracle_rule_text.py        # 다시 굽는다(PDF가 바뀌었을 때만)
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pdfplumber

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
OUT = ROOT / "test" / "fixtures" / "rule_text.json"

# topic → (PDF 접두사, 시작 줄, 끝 줄(이 줄 앞까지. None이면 끝까지))
# 시작·끝은 **공백을 지운 값으로 정확히 같은 줄**을 찾는다.
REGIONS = {
    # 별표 1은 산정표(표 본문)를 싣지 않는다 — 물질별 결론값은 별표 2ㆍ3에 이미 있다. 비고만.
    "byeolpyo1": ("[별표 1]", "비고", None),
    "byeolpyo2": ("[별표 2]", "[별표2]", "2.수량기준"),
    "byeolpyo3": ("[별표 3]", "[별표3]", "2.수량기준"),
    "byeolpyo4": ("[별표 4]", None, None),
}

# 별표 4의 R값 공식은 수식 글꼴로 그려져 있어 PDF 텍스트 층에 사설영역(PUA) 글리프로 들어간다 —
# 문자로 복원할 수 없다. 공식 자체는 페이지 그림을 보고 옮겼다(2026-09-16).
_PUA = re.compile(r"[-]")
# 아래첨자(Qn의 n, QLLTn의 LLTn)가 같은 수식 글꼴이라 본문에서 떨어져 나온 줄들.
_SUBSCRIPT = {"n", "LLTn"}
# 그 아래첨자가 떨어져 나가면서 갈라진 본문 줄. 상수에는 'Qn'ㆍ'QLLTn'으로 합쳐 적었으므로 줄 대조가 안 된다 —
# 대신 test/assist/rules_test.dart가 합쳐진 형태를 직접 확인한다(구멍을 열어 두지 않는다).
_SUBSCRIPT_SPLIT = {"주)Q:유해화학물질최대보유량", "Q:유해화학물질최하위규정수량"}


def find_pdf(prefix: str) -> Path:
    hits = [p for p in ASSETS.glob("*.pdf") if p.name.startswith(prefix)]
    if len(hits) != 1:
        raise SystemExit(f"{prefix} PDF가 정확히 1개여야 한다: {hits}")
    return hits[0]


def norm(s: str) -> str:
    return re.sub(r"\s+", "", s)


def dump(topic: str, prefix: str, start: str | None, end: str | None) -> dict:
    path = find_pdf(prefix)
    with pdfplumber.open(path) as pdf:
        pages = len(pdf.pages)
        raw = "\n".join(page.extract_text() or "" for page in pdf.pages)
    lines = [ln for ln in raw.splitlines() if ln.strip()]

    if start is not None:
        i = next((k for k, ln in enumerate(lines) if norm(ln) == start), None)
        if i is None:
            raise SystemExit(f"{topic}: 시작 줄 {start!r}을 원문에서 찾지 못했다")
        lines = lines[i:]
    if end is not None:
        j = next((k for k, ln in enumerate(lines) if norm(ln) == end), None)
        if j is None:
            raise SystemExit(f"{topic}: 끝 줄 {end!r}을 원문에서 찾지 못했다")
        lines = lines[:j]

    kept, excluded = [], []
    for ln in lines:
        if _PUA.search(ln):
            excluded.append({"line": ln, "why": "수식 글꼴(PUA 글리프) — 문자로 복원 불가"})
        elif norm(ln) in _SUBSCRIPT:
            excluded.append({"line": ln, "why": "수식 아래첨자가 본문에서 떨어져 나온 줄"})
        elif norm(ln) in _SUBSCRIPT_SPLIT:
            excluded.append({"line": ln, "why": "아래첨자가 떨어져 나가 갈라진 줄 — 상수에는 Qnㆍ QLLTn으로 합쳐 적었다"})
        else:
            kept.append(ln)
    return {
        "file": path.name,
        "pages": pages,
        "range": {"start": start, "end": end},
        "lines": kept,
        "excluded": excluded,
    }


def main() -> int:
    sys.stdout.reconfigure(encoding="utf-8")
    out = {t: dump(t, *args) for t, args in REGIONS.items()}
    OUT.write_text(
        json.dumps(out, ensure_ascii=False, indent=1) + "\n", encoding="utf-8", newline="\n"
    )
    for t, d in out.items():
        print(f"{t}: {len(d['lines'])}줄 (대조 제외 {len(d['excluded'])}줄) ← {d['file']}")
    print(f"→ {OUT.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
