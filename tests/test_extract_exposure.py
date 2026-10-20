"""A-010 위험노출수준 추출(scripts/extract_exposure.py) — 커밋된 원천에서 다시 뽑으면 커밋된 표와 같다(원천만 바꾸고 추출을 안 돌리면 잡힌다)."""

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import extract_exposure as ex  # noqa: E402


def test_committed_table_matches_raw():
    assert ex.render(ex.build()) == ex.OUT.read_text(encoding="utf-8").replace("\r\n", "\n")


def test_erpg_errata_applied_and_no_conflicts():
    """AIHA 표의 CAS 오기 2건(2026-10-20 발견)이 정정되고, 한 CAS에 값이 다른 ERPG 행이 남지 않는다."""
    d = ex.build()
    assert d["erpgConflicts"] == []
    assert [e["correctedCas"] for e in d["erpgErrata"]] == ["7580-67-8", "108-31-6"]
    assert {r["name"] for r in d["erpg"]["101-68-8"]} == {"Methyl diphenyl diisocyanate (MDI)"}
    assert {r["name"] for r in d["erpg"]["7439-97-6"]} == {"Mercury vapor"}
    assert d["erpg"]["108-31-6"][0]["erpg2"] == "5 ppm"
    assert d["erpg"]["7580-67-8"][0]["name"] == "Lithium hydride"


def test_conflict_detector_catches_wrong_cas():
    """정정을 빼면 충돌로 잡힌다(검출기가 실제로 잡는지)."""
    saved = dict(ex.ERPG_ERRATA)
    try:
        ex.ERPG_ERRATA.clear()
        erpg = ex.extract_erpg(ex.RAW / "aiha_erpg/ERPG.html", [])
        assert {c["cas"] for c in ex.erpg_conflicts(erpg)} == {"101-68-8", "7439-97-6"}
    finally:
        ex.ERPG_ERRATA.update(saved)


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
