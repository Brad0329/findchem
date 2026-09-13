"""번들 JSON에서 **항목을 가리키는 키 후보**가 실제로 유일한지 전수로 센다.

## 왜 있나
F-005(자주보는 Chem 목록)는 항목을 참조로 저장한다. 그런데 **연번(`no`)은 키가 아니다** —
고시가 개정돼 항목이 추가·삭제되면 뒤 번호가 밀린다(사용자 지적 2026-09-13). 그래서
"연번 말고 무엇을 저장해야 개정 뒤에도 같은 물질을 찾는가"를 **추정하지 말고 세어서** 정한다.
(CLAUDE.md 부채 A3: 실측은 커밋되는 `scripts/oracle_*` 형태로만 — 일회성 스크립트는 남지 않아
다음 세션이 같은 측정을 다시 한다.)

## 쓰는 법
    python scripts/oracle_key_candidates.py
    python scripts/oracle_key_candidates.py --data <다른 JSON 경로>   # update 저장본으로도 잴 수 있다

## 읽는 법
후보마다 "몇 개 항목이 같은 키를 공유하는가"를 낸다. **중복 0건이어야 키로 쓸 수 있다.**
중복이 있으면 예시를 함께 찍는다 — 그 예시가 곧 반례다.
"""

from __future__ import annotations

import argparse
import collections
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_DATA = ROOT / "assets" / "data" / "findchem_data.json"


def utf8_stdout() -> None:
    """콘솔 인코딩과 무관하게 찍는다 (cp949 콘솔에서 죽지 않게 — measure_approvals와 같은 이유)."""
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


def load(path: Path) -> list[dict]:
    if not path.exists():
        raise SystemExit(f"데이터 파일이 없다: {path}")
    obj = json.loads(path.read_text(encoding="utf-8"))
    entries = obj.get("entries")
    if not entries:
        raise SystemExit(f"entries가 비어 있다: {path}")  # 조용히 0건으로 넘어가지 않는다
    return entries


def cas_key(e: dict) -> str:
    """CAS 배열을 키로 쓸 수 있는 문자열로. 순서에 흔들리지 않게 정렬해서 잇는다."""
    return "|".join(sorted(e.get("cas") or []))


# 후보 키: (이름, 항목 → 키 튜플). None이 섞이면 그대로 키의 일부로 둔다(없음도 정보다).
CANDIDATES: list[tuple[str, object]] = [
    ("no", lambda e: (e["no"],)),
    ("src+no  (지금 SCHEMA의 키)", lambda e: (e["src"], e["no"])),
    ("uid", lambda e: (e.get("uid"),)),
    ("cas", lambda e: (cas_key(e),)),
    ("uid+cas", lambda e: (e.get("uid"), cas_key(e))),
    ("src+uid+cas", lambda e: (e["src"], e.get("uid"), cas_key(e))),
    ("ko  (국문명)", lambda e: (e.get("ko"),)),
    ("src+ko", lambda e: (e["src"], e.get("ko"))),
    ("name  (원문 물질명 전체)", lambda e: (e.get("name"),)),
    ("src+name", lambda e: (e["src"], e.get("name"))),
    ("src+uid+cas+ko", lambda e: (e["src"], e.get("uid"), cas_key(e), e.get("ko"))),
    ("src+uid+cas+name", lambda e: (e["src"], e.get("uid"), cas_key(e), e.get("name"))),
]


def report(entries: list[dict], scope: str) -> None:
    print(f"\n{'=' * 72}\n{scope} — {len(entries)}건\n{'=' * 72}")
    for label, keyfn in CANDIDATES:
        groups = collections.defaultdict(list)
        for e in entries:
            groups[keyfn(e)].append(e)
        dups = {k: v for k, v in groups.items() if len(v) > 1}
        dup_entries = sum(len(v) for v in dups.values())
        verdict = "유일" if not dups else f"중복 {len(dups)}조 / {dup_entries}건"
        print(f"\n  [{label}]  서로 다른 키 {len(groups)}개 → {verdict}")
        for k, v in list(dups.items())[:3]:   # 반례는 3조까지만 보여준다
            names = " / ".join(f"{x['src']} {x['no']} {x.get('ko')}" for x in v[:4])
            more = f" …외 {len(v) - 4}건" if len(v) > 4 else ""
            print(f"      예: {k} → {names}{more}")


def main() -> int:
    utf8_stdout()
    ap = argparse.ArgumentParser(description="키 후보의 유일성을 전수로 센다")
    ap.add_argument("--data", type=Path, default=DEFAULT_DATA)
    args = ap.parse_args()

    entries = load(args.data)
    report(entries, "전체(두 별표 합)")
    for src in ("별표2", "별표3"):
        part = [e for e in entries if e["src"] == src]
        report(part, src)

    # 별표3에 uid가 있는지 — 있으면 uid 기반 키를 두 별표에 같이 쓸 수 있다
    b3 = [e for e in entries if e["src"] == "별표3"]
    with_uid = sum(1 for e in b3 if e.get("uid"))
    no_cas = sum(1 for e in entries if not (e.get("cas") or []))
    print(f"\n{'=' * 72}\n요약")
    print(f"  별표3에서 uid가 있는 항목: {with_uid} / {len(b3)}")
    print(f"  CAS가 하나도 없는 항목(두 별표 합): {no_cas} / {len(entries)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
