"""MCP 서버 spike ②(plan.md '보류 항목 · MCP 서버 spike') — stdio MCP 서버 한 파일.

도구 2개:
  search_chemical(query) — scripts/search_cli.dart를 subprocess로 불러 stdout JSON을 **그대로** 돌려준다.
                           서버는 가공·요약하지 않는다.
  get_rule(topic)        — 별표 4(최대보유량 산정 방법) 전문과 별표 1 비고를 원문 텍스트 상수로 돌려준다.

**판정(합산·초과 비교)은 서버가 하지 않는다.** 조합을 LLM이 해내는지 보는 것이 이 spike의 목적이라
(확인 ①), 서버가 대신 계산하면 확인할 것이 사라진다.

설치·실행
  python -m pip install mcp        # 2026-09-16 실측: mcp 2.2.0 (v1의 FastMCP가 MCPServer로 바뀐 버전)
  python scripts/mcp_server.py --selftest   # 도구 2개를 프로토콜 없이 직접 돌려 본다
  python scripts/mcp_server.py              # stdio MCP 서버로 기동(데스크톱 Claude가 이렇게 부른다)

데스크톱 Claude 등록(claude_desktop_config.json):
  "mcpServers": { "findchem": { "command": "python",
                                "args": ["C:/Users/user/Documents/findchem/scripts/mcp_server.py"] } }

주의: stdio 서버는 **stdout이 프로토콜 전용**이다. 진단 출력은 전부 stderr로 보낸다(print 금지).
"""

from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = "scripts/search_cli.dart"


def find_pdf(prefix: str) -> Path | None:
    """assets/에서 접두사로 원문 PDF를 찾는다(파일명에 '·'ㆍ'¸' 같은 특수문자가 섞여 있어 리터럴로 박지 않는다 —
    build_data.dart의 findPdf와 같은 방식)."""
    hits = sorted(p for p in (ROOT / "assets").glob("*.pdf") if p.name.startswith(prefix))
    if len(hits) != 1:
        return None
    return hits[0]

NOTICE = "화학물질안전원고시 「유해화학물질의 규정수량에 관한 규정」(2026-09-15 확인 현행: 제2025-12호, 2025-08-07 시행)"

# ── 원문 텍스트 상수 ───────────────────────────────────────────────────────────
# assets/의 별표 PDF에서 옮겨 적었다(2026-09-16). 줄바꿈만 다시 흘렸고 글자는 손대지 않았다.
# 손으로 옮긴 데이터이므로 --selftest가 PDF 원문(pdfplumber 추출)과 줄 단위로 대조한다
# (CLAUDE.md '손으로 만든 데이터에는 자동 검증을 붙인다').
# 번들 JSON(assets/data/findchem_data.json)에는 넣지 않는다 — 스키마 변경은 일반 트랙이고,
# 쓸모가 확인되면 그때 F-008에서 정식 자산화한다(plan.md '별표 1·4 취급' 1안).

BYEOLPYO4 = """[별표 4] 최대보유량 산정 방법

1. 유해화학물질별 최대보유량 산정은 사업장 내에서 해당 유해화학물질을 취급하는 모든 제조ㆍ사용시설 및
저장ㆍ보관시설에서 해당 물질이 어느 순간 최대로 체류할 수 있는 양의 합으로 산정한다. 또한, 취급시설별
최대보유량(탱크로리 등 운송ㆍ운반차량, 사외배관, 규칙 제39조제1항 및 제2항에 따라 취급중단을 신고한
시설은 제외)은 취급시설의 설계용량과 순수 유해화학물질의 상온에서의 비중 값 등을 고려하여 산정하는
것을 원칙으로 한다.

2. 제조ㆍ사용시설의 경우
  가. 제조ㆍ사용 시설에서 유해화학물질이 함량기준 이상으로 존재하는 경우 취급시설의 설계용량과
  유해화학물질의 비중을 고려하여 산정한다. 다만, 단순 혼합의 경우에는 투입완료 후 최종함량을 기준으로
  산정하고, 투입 후 반응이 일어나는 경우에는 반응이 일어나기 전 최종함량을 기준으로 산정한다.
  나. 탑조류 또는 냉각기 등과 같이 서로 다른 물질의 성상이 두 개 이상으로 존재하여 사업장에서 근거를 들어
  증빙하는 경우, 각각의 성상이 차지하는 부피를 고려하여 용량을 산정할 수 있다. 다만, 증빙이 불가능 할 경우
  설계용량과 액상의 비중을 이용하여 산정한다.

3. 저장ㆍ보관시설의 경우
  가. 저장탱크의 경우에는 저장탱크의 설계용량과 유해화학물질의 상온에서의 비중값을 이용하여 산정한다.
  나. 보관시설의 경우에는 유해화학물질의 보관 구획도를 기준으로 최대보유량을 산정한다. 다만, 보관시설의
  일일최대보관량을 고려하여 일일최대보관량 이상으로 산정하여야 한다.
  다. 나목에도 불구하고 유해화학물질 보관시설만을 설치ㆍ운영하는 사업장의 모든 보관물질의 최대보유량이
  최하위 규정수량 미만인 경우에는 보관물질별 최대보유량과 최하위 규정수량기준으로 아래 공식에 따라
  R값을 산출한다. 이때 R값이 1미만에 해당하는 경우에만 최하위 규정수량기준 미만인 것으로 본다.

      R = Q1/QLLT1 + Q2/QLLT2 + Q3/QLLT3 + ...... + Qn/QLLTn
      주) Qn : 유해화학물질 최대보유량
          QLLTn : 유해화학물질 최하위 규정수량
      [옮긴이 주: 원문에서 이 공식은 수식 이미지라 PDF 텍스트 층에 없다. 그림을 보고 옮겨 적었다.]

비고
1. 기상물질의 경우
  가. 제조ㆍ사용시설에서 기상으로 존재하는 유해화학물질의 취급량은 운전조건(온도, 압력)을 고려하여
  산정한다.
  나. 고압가스 사용시설의 경우 압축 및 액화 등의 저장 방식을 고려하여 물질의 성상에 따라 설계용량과
  유해화학물질의 비중을 고려하여 최대보유량을 산정한다.

2. 혼합물의 경우
  가. 유해화학물질을 함유한 혼합물의 취급 규모를 산정할 경우에는 규제대상 함량(농도) 이상의
  유해화학물질을 모두 고려하여야 한다.
  나. 이 경우 유해화학물질의 양은 해당 유해화학물질을 포함한 전체혼합물의 총량으로 산정하되 혼합물
  비중 값에 대한 시험값이나 계산값 등 증빙이 가능한 경우 혼합물 비중을 고려할 수 있다.

3. 이 고시에서 저확산 구분으로 표시되어 있는 하위 규정수량이 400톤인 물질은 상위 규정수량이 없으므로
최대보유량을 아래와 같이 산정한다.
  가. 저확산 구분으로 표시되어 있는 물질만 취급하는 사업장 : 해당물질의 양을 기준으로 최대보유량을
  산정한다.
  나. 저확산 구분으로 표시되어 있는 물질과 다른 유해화학물질을 같이 취급하는 사업장 : 이 고시 별표 2 또는
  별표 3에서 상위 규정수량이 규정되어 있는 물질로 최대보유량을 산정한다.
"""

BYEOLPYO1 = """[별표 1] 유해ㆍ위험성 그룹별 규정수량 — 비고

비고
1. 유해성 그룹별로 규정수량 산정표를 적용하되, 유해화학물질별로 달리 적용할 수 있다.
2. 유해화학물질이 2가지 이상의 유해성 그룹을 가진 경우에는 가장 작은 수량을 적용한다.

[옮긴이 주: 별표 1의 본문인 '유해성 그룹별 규정수량 산정표'(급성/만성/물리ㆍ화학적/생태 그룹의 구분별
하위ㆍ상위 수량)는 이 도구에 싣지 않았다. 그 표는 물질별 규정수량을 정하는 산정 근거이고, 물질별
결론값은 별표 2ㆍ3에 이미 있어 search_chemical이 돌려준다. 산정표 자체가 필요하면 원문
'assets/[별표 1] …pdf'를 볼 것.]
"""

RULES = {"byeolpyo1": BYEOLPYO1, "byeolpyo4": BYEOLPYO4}


# ── 도구 본체(프로토콜과 분리 — --selftest가 이 함수들을 직접 부른다) ──────────
def search_chemical_text(query: str) -> str:
    """scripts/search_cli.dart를 돌려 stdout(JSON)을 그대로 돌려준다."""
    dart = shutil.which("dart")
    if dart is None:
        raise RuntimeError("dart 실행 파일을 PATH에서 찾지 못했습니다. Flutter SDK의 bin이 PATH에 있어야 합니다.")
    try:
        p = subprocess.run(
            [dart, "run", CLI, query],
            cwd=ROOT,
            capture_output=True,
            timeout=180,
        )
    except subprocess.TimeoutExpired as e:
        raise RuntimeError(f"검색 CLI가 180초 안에 끝나지 않았습니다: {e}") from e
    out = p.stdout.decode("utf-8", errors="replace")
    err = p.stderr.decode("utf-8", errors="replace")
    if p.returncode != 0:
        raise RuntimeError(f"검색 CLI 실패(exit {p.returncode}): {err.strip() or '(stderr 없음)'}")
    if err.strip():
        # 경고는 삼키지 않는다(CLAUDE.md '조용한 실패 금지'). stdout은 프로토콜 전용이라 stderr로 보낸다.
        print(f"[search_cli stderr] {err.strip()}", file=sys.stderr)
    return out


def get_rule_text(topic: str = "all") -> str:
    """규정 원문 텍스트 상수를 돌려준다."""
    if topic == "all":
        body = "\n\n".join(RULES[k] for k in ("byeolpyo4", "byeolpyo1"))
    elif topic in RULES:
        body = RULES[topic]
    else:
        raise ValueError(f"알 수 없는 topic: {topic!r}. 쓸 수 있는 값: all, byeolpyo4, byeolpyo1")
    return f"출처: {NOTICE}\n\n{body}"


# ── MCP 서버 ─────────────────────────────────────────────────────────────────
def build_server():
    from mcp.server.mcpserver import MCPServer  # mcp 2.x (1.x에서는 mcp.server.fastmcp.FastMCP였다)

    mcp = MCPServer(
        name="findchem",
        version="0.1.0-spike",
        instructions=(
            "유해화학물질 규정수량 조회 도구다. 규정수량·함량기준·물질 존재 여부는 **반드시 도구로 확인하고** "
            "기억으로 답하지 않는다. 답에는 도구가 돌려준 수량 문자열을 그대로 인용하고 단위(톤)와 "
            "출처(별표 구분·연번·고시명)를 함께 적는다."
        ),
    )

    @mcp.tool()
    def search_chemical(query: str) -> str:
        """물질명(국문ㆍ영문, 부분 일치, 띄어쓰기 무시) 또는 CAS 번호로 규정수량을 조회한다.

        「유해화학물질의 규정수량에 관한 규정」 별표 2(인체ㆍ생태 유해성)ㆍ별표 3(사고대비물질)이 원천이다.
        결과 JSON의 rows에 구분ㆍ함량기준(%)과 최하위(min)ㆍ하위(low)ㆍ상위(high) 규정수량이 톤 단위
        원문 문자열로 들어 있다. 값을 계산ㆍ반올림하지 말고 그대로 인용한다.
        여러 물질을 다루는 질문이면 물질마다 한 번씩 부른다.
        """
        return search_chemical_text(query)

    @mcp.tool()
    def get_rule(topic: str = "all") -> str:
        """규정수량 판정 규칙의 원문을 돌려준다(topic: all | byeolpyo4 | byeolpyo1).

        byeolpyo4 = 별표 4 '최대보유량 산정 방법' 전문. 최대보유량을 무엇으로 산정하는지(설계용량ㆍ비중),
        보관시설만 운영하는 사업장의 합산 판정 공식(R = Σ Qn/QLLTn, R<1), 기상물질ㆍ혼합물ㆍ저확산 물질의
        비고가 들어 있다.
        byeolpyo1 = 별표 1의 비고(2가지 이상 유해성 그룹이면 가장 작은 수량).
        보유량이 규정수량을 넘는지, 여러 물질을 합산해야 하는지 판단하기 전에 이 도구를 먼저 부른다.
        """
        return get_rule_text(topic)

    return mcp


# ── 자체 점검 ────────────────────────────────────────────────────────────────
def _norm(s: str) -> str:
    return re.sub(r"\s+", "", s)


# 별표 4의 R값 공식은 수식 글꼴로 그려져 있어 PDF 텍스트 층에 사설영역(PUA) 글리프로 들어간다 —
# 문자로 복원할 수 없다. 그 줄들은 대조에서 빼고, 뺐다는 사실을 보고한다(조용한 절단 금지).
# 공식 자체는 페이지 그림을 보고 옮겼다(2026-09-16). 아래 두 줄은 아래첨자(Qn의 n, QLLTn의 LLTn)가
# 같은 수식 글꼴이라 추출에서 통째로 빠진 줄이다.
_PUA = re.compile(r"[-]")
_SUBSCRIPT_DROPPED = {"주)Q:유해화학물질최대보유량", "Q:유해화학물질최하위규정수량"}


def _pdf_lines(path: Path) -> list[str]:
    import pdfplumber

    with pdfplumber.open(path) as pdf:
        text = "\n".join(page.extract_text() or "" for page in pdf.pages)
    return [ln for ln in text.splitlines() if ln.strip()]


def _check_transcription(
    name: str, const: str, prefix: str, only_after_bigo: bool
) -> tuple[list[str], list[str]]:
    """PDF 원문의 각 줄이 텍스트 상수 안에 그대로 있는지 본다(공백 무시). 옮겨 적다 생긴 탈자ㆍ오타를 잡는다.

    돌려주는 것: (문제 목록, 대조에서 뺀 줄 목록).
    """
    pdf_path = find_pdf(prefix)
    if pdf_path is None:
        return ([f"{name}: assets/에서 '{prefix}'로 시작하는 PDF를 정확히 1개 찾지 못했습니다"], [])
    lines = _pdf_lines(pdf_path)
    if only_after_bigo:  # 별표 1은 비고만 싣는다 → 산정표 줄은 대조 대상이 아니다
        idx = next((i for i, ln in enumerate(lines) if _norm(ln) == "비고"), None)
        if idx is None:
            return ([f"{name}: 원문에서 '비고' 줄을 찾지 못했습니다"], [])
        lines = lines[idx:]
    haystack = _norm(const)
    problems, skipped = [], []
    for ln in lines:
        if _PUA.search(ln) or _norm(ln) in _SUBSCRIPT_DROPPED:
            skipped.append(f"{name}: 수식 영역이라 대조 제외 → {ln!r}")
        elif _norm(ln) not in haystack:
            problems.append(f"{name}: 상수에 없는 원문 줄 → {ln!r}")
    return (problems, skipped)


def selftest() -> int:
    sys.stdout.reconfigure(encoding="utf-8")  # 콘솔이 cp949여도 한글이 깨지지 않게(selftest 경로 전용)
    problems: list[str] = []
    skipped: list[str] = []

    for name, const, prefix, bigo in (
        ("별표 4", BYEOLPYO4, "[별표 4]", False),
        ("별표 1", BYEOLPYO1, "[별표 1]", True),
    ):
        p, s = _check_transcription(name, const, prefix, only_after_bigo=bigo)
        problems += p
        skipped += s

    rule = get_rule_text("all")
    for must in ("R = Q1/QLLT1", "가장 작은 수량을 적용한다", NOTICE):
        if must not in rule:
            problems.append(f"get_rule('all') 결과에 빠진 문장: {must!r}")
    try:
        get_rule_text("없는토픽")
    except ValueError:
        pass
    else:
        problems.append("get_rule이 알 수 없는 topic을 조용히 받아들였습니다")

    try:
        data = json.loads(search_chemical_text("50-00-0"))
        # 앱 검색과 같은 답인지(test/search/search_test.dart의 기댓값): 별표3 1 · 별표2 510
        got = [(h["src"], h["no"], h["priority"], h["referenceNote"]) for h in data["hits"]]
        if got != [("별표3", 1, True, False), ("별표2", 510, False, True)]:
            problems.append(f"search_chemical('50-00-0') 결과가 다릅니다: {got}")
        if data["source"]["notice"] != NOTICE:
            problems.append("CLI와 서버의 고시명이 어긋납니다(둘 다 손으로 적은 값이다)")
    except Exception as e:  # noqa: BLE001 — 원인을 그대로 보고하고 실패로 남긴다
        problems.append(f"search_chemical 호출 실패: {e!r}")

    for s in skipped:
        print(f"SKIP {s}")
    for p in problems:
        print(f"FAIL {p}")
    if problems:
        print(f"\n자체 점검 실패 {len(problems)}건")
        return 1
    print(
        f"\n자체 점검 통과: 원문 대조(별표 4 전문ㆍ별표 1 비고, 대조 제외 {len(skipped)}줄은 위 SKIP)"
        " · get_rule · search_chemical"
    )
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    build_server().run()
