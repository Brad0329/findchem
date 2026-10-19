"""A-010 위험노출수준 추출(scripts/extract_exposure.py) — 커밋된 원천에서 다시 뽑으면 커밋된 표와 같다(원천만 바꾸고 추출을 안 돌리면 잡힌다)."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import extract_exposure as ex  # noqa: E402


def test_committed_table_matches_raw():
    assert ex.render(ex.build()) == ex.OUT.read_text(encoding="utf-8").replace("\r\n", "\n")


def test_nothing_skipped_and_samples():
    d = ex.build()
    assert d["skipped"] == []
    assert d["erpg"]["108-88-3"][0]["erpg2"] == "300 ppm"
    tol = d["aegl"]["108-88-3"][0]
    assert (tol["status"], tol["unit"], tol["aegl2_60"]) == ("Final", "ppm", "560")
    # 표 첫 칸에 제목이 있는 쪽(페놀)·제목이 없는 쪽(아크릴로니트릴 — 목록 페이지의 CAS)·괄호 단위 줄(1,3-부타디엔)
    assert d["aegl"]["108-95-2"][0]["aegl2_60"] == "23"
    assert d["aegl"]["107-13-1"][0]["status"] == "unstated"
    assert d["aegl"]["106-99-0"][0]["unit"] == "ppm"
    assert "non-commercial" in d["aihaNotice"]
