"""F-007 GHS H·P 문구: assets/유해위험문구(HCODE).xlsx·예방조치문구(PCODE).xlsx(사용자 제공 2026-09-15) → Dart 대응표.

엑셀은 사용자가 「화학물질의 분류 및 표시 등에 관한 규정」 [별표 3] PDF를 옮긴 것이다. 첫 시트 1행이 머리글이고
A열 '코드', 마지막 열이 문구다('비고' 시트의 (주1)~(주7) 설명은 쓰지 않는다).

원문 그대로 두되 예외 둘(REQUIREMENTS F-007 AI 기본값 — 2026-09-15 실측):
  - 문구 안의 줄바꿈은 앞뒤 공백과 함께 지운다(P250 `…마시오\n.`)
  - `P370+P380+P375[+P378]`처럼 `[+코드]`가 붙은 행은 붙인 코드(`P370+P380+P375+P378`)로 등록한다. 괄호를 뺀 코드는
    자기 행이 따로 있으면 그 행 문구를 쓰고(실측: 108행 `P370+P380+P375`가 있다), 없을 때만 이 문구로 등록한다
    — 그래서 `[+코드]` 행은 일반 행을 다 읽은 뒤에 처리한다
키 형식(`H123`을 `+`로 이은 것)이 아니거나 코드가 겹치면 멈춘다 — 조용히 덮어쓰지 않는다.

출력: lib/lookup/ghs_phrase_data.dart (생성물 — 손으로 고치지 않는다, 커밋한다)
실행: python scripts/extract_ghs_phrases.py
"""
import re
import sys
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent.parent
SOURCES = {
    "H": ROOT / "assets" / "유해위험문구(HCODE).xlsx",
    "P": ROOT / "assets" / "예방조치문구(PCODE).xlsx",
}
DART_OUT = ROOT / "lib" / "lookup" / "ghs_phrase_data.dart"
OPTIONAL = re.compile(r"^(?P<base>.+)\[\+(?P<extra>[HP]\d{3})\]$")


def read_table(kind: str, path: Path) -> tuple[dict[str, str], int]:
    ws = openpyxl.load_workbook(path).worksheets[0]
    rows = list(ws.iter_rows(values_only=True))
    if rows[0][0] != "코드":
        raise SystemExit(f"{path.name}: 첫 칸 머리글이 '코드'가 아니다: {rows[0]}")
    key = re.compile(rf"{kind}\d{{3}}(\+{kind}\d{{3}})*")
    entries = []
    for row in rows[1:]:
        code, phrase = row[0], row[len(rows[0]) - 1]
        if code is None and phrase is None:
            continue
        code = str(code).strip()
        phrase = re.sub(r"\s*\n\s*", "", str(phrase or "")).strip()
        if not phrase:
            raise SystemExit(f"{path.name}: {code} 문구가 비어 있다")
        entries.append((code, phrase))

    table: dict[str, str] = {}

    def put(c: str, phrase: str, original: str) -> None:
        if not key.fullmatch(c):
            raise SystemExit(f"{path.name}: 코드 형식이 아니다: {original!r}")
        if c in table:
            raise SystemExit(f"{path.name}: 코드가 겹친다: {c}")
        table[c] = phrase

    optional = [(OPTIONAL.match(c), c, p) for c, p in entries]
    for m, code, phrase in optional:
        if not m:
            put(code, phrase, code)
    for m, code, phrase in optional:
        if m:
            put(f"{m['base']}+{m['extra']}", phrase, code)
            if m["base"] not in table:
                put(m["base"], phrase, code)
    return table, len(entries)


def dart_string(s: str) -> str:
    return "'" + s.replace("\\", "\\\\").replace("'", "\\'").replace("$", "\\$") + "'"


def main() -> None:
    sys.stdout.reconfigure(encoding="utf-8")
    sys.stderr.reconfigure(encoding="utf-8")  # 멈출 때 문구(SystemExit)가 한글이라 콘솔 기본 인코딩이면 깨진다
    parts = [
        "// 생성물: scripts/extract_ghs_phrases.py (원본 assets/유해위험문구(HCODE).xlsx·예방조치문구(PCODE).xlsx) — 손으로 고치지 않는다.",
        "",
    ]
    for kind, name, doc in [
        ("H", "ghsHPhrases", "유해·위험문구"),
        ("P", "ghsPPhrases", "예방조치문구"),
    ]:
        table, rows = read_table(kind, SOURCES[kind])
        print(f"{kind}: 엑셀 {rows}행 → 키 {len(table)}개 (합성 {sum('+' in c for c in table)}개)")
        parts.append(f"/// {kind}코드 → {doc}. 엑셀 {rows}행, 키 {len(table)}개. 찾기 규칙은 ghs_phrases.dart.")
        parts.append(f"const {name} = <String, String>{{")
        parts += [f"  '{c}': {dart_string(p)}," for c, p in table.items()]
        parts += ["};", ""]
    DART_OUT.write_text("\n".join(parts), encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
