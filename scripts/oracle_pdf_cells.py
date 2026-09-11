"""pdfplumber로 두 별표 PDF의 원시 셀 격자와 표 기하를 덤프한다 (Dart 파서 대조용 정답지).

Phase 001 실측 설정 그대로: extract_tables(text_keep_blank_chars=True). 셀 안 줄바꿈('\\n')은 **그대로 둔다** —
별표3 98번처럼 줄바꿈만으로 나뉜 CAS 두 개가 있어, 지우면 정보를 잃는다(2026-09-11 실측). 줄바꿈 처리를 포함한
모든 규칙은 Dart 빌더(lib/parser/entry_builder.dart) 한 곳에만 둔다(Python 파서 금지, plan.md).

출력: test/fixtures/<src>_cells.json  (src = byeolpyo2 | byeolpyo3) — Dart 추출 층 대조 테스트의 정답지.
  {"file":..., "pages": N, "meta": {...}, "tables": [ {"page": p, "bbox": [...], "col_edges": [...],
    "rows": [[cell,...], ...]} ], "graphics": {"lines": n, "rects": n, "curves": n}}
행 하나가 JSON 한 줄이라 diff를 읽을 수 있다. 줄 끝은 LF 고정.
"""
from __future__ import annotations

import io
import json
import sys
from pathlib import Path

import pdfplumber

ROOT = Path(__file__).resolve().parent.parent
ASSETS = ROOT / "assets"
OUT = ROOT / "test" / "fixtures"

SOURCES = {
    "byeolpyo2": "[별표 2]",
    "byeolpyo3": "[별표 3]",
}


def find_pdf(prefix: str) -> Path:
    hits = [p for p in ASSETS.glob("*.pdf") if p.name.startswith(prefix)]
    if len(hits) != 1:
        raise SystemExit(f"{prefix} PDF가 정확히 1개여야 한다: {hits}")
    return hits[0]


def dump(src: str, pdf_path: Path) -> dict:
    tables_out = []
    graphics = {"lines": 0, "rects": 0, "curves": 0, "chars": 0}
    with pdfplumber.open(pdf_path) as pdf:
        meta = {k: str(v) for k, v in (pdf.metadata or {}).items()}
        for page in pdf.pages:
            graphics["lines"] += len(page.lines)
            graphics["rects"] += len(page.rects)
            graphics["curves"] += len(page.curves)
            graphics["chars"] += len(page.chars)
            # extract_tables(table_settings={'text_keep_blank_chars': True})와 같은 경로:
            # find_tables에는 표 탐지 설정만 가고, 텍스트 설정은 extract()에 따로 넘겨야 한다(2026-09-11 실사례 —
            # 안 넘기면 줄 끝 공백이 빠져 'Lead⏎2,4,6'과 'Fo⏎rmaldehyde'를 구분 못 한다).
            found = page.find_tables()
            for t in found:
                rows = t.extract(keep_blank_chars=True)
                col_edges = sorted({round(c[0], 2) for c in t.cells} | {round(c[2], 2) for c in t.cells})
                row_edges = sorted({round(c[1], 2) for c in t.cells} | {round(c[3], 2) for c in t.cells})
                tables_out.append({
                    "page": page.page_number,
                    "page_size": [round(page.width, 2), round(page.height, 2)],
                    "bbox": [round(v, 2) for v in t.bbox],
                    "col_edges": col_edges,
                    "row_edges": row_edges,
                    "rows": [[("" if c is None else c) for c in r] for r in rows],
                })
        return {
            "file": pdf_path.name,
            "pages": len(pdf.pages),
            "meta": meta,
            "graphics": graphics,
            "tables": tables_out,
        }


def to_json(data: dict) -> str:
    """표 행(rows)은 한 행 = 한 줄, 나머지는 들여쓰기 — diff 가독성용 수동 직렬화."""
    j = lambda v: json.dumps(v, ensure_ascii=False)  # noqa: E731
    lines = ["{"]
    for key in ("file", "pages", "meta", "graphics"):
        lines.append(f' {j(key)}: {j(data[key])},')
    lines.append(' "tables": [')
    for ti, t in enumerate(data["tables"]):
        lines.append("  {")
        for key in ("page", "page_size", "bbox", "col_edges", "row_edges"):
            lines.append(f'   {j(key)}: {j(t[key])},')
        lines.append('   "rows": [')
        for ri, row in enumerate(t["rows"]):
            comma = "," if ri < len(t["rows"]) - 1 else ""
            lines.append(f"    {j(row)}{comma}")
        lines.append("   ]")
        lines.append("  }" + ("," if ti < len(data["tables"]) - 1 else ""))
    lines.append(" ]")
    lines.append("}")
    return "\n".join(lines) + "\n"


def main() -> int:
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8")
    OUT.mkdir(parents=True, exist_ok=True)
    for src, prefix in SOURCES.items():
        pdf_path = find_pdf(prefix)
        data = dump(src, pdf_path)
        out = OUT / f"{src}_cells.json"
        text = to_json(data)
        json.loads(text)  # 수동 직렬화 검증
        with open(out, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
        n_rows = sum(len(t["rows"]) for t in data["tables"])
        widths = sorted({len(r) for t in data["tables"] for r in t["rows"]})
        print(f"{src}: pages={data['pages']} tables={len(data['tables'])} rows={n_rows} "
              f"row_widths={widths} graphics={data['graphics']} -> {out.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
