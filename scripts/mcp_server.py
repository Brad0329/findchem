"""F-008 개발 하네스 — PC 데스크톱 Claude에 거는 stdio MCP 서버 한 파일.

도구 2개. 둘 다 `scripts/search_cli.dart`를 subprocess로 불러 stdout JSON을 **그대로** 돌려준다.
서버는 가공ㆍ요약ㆍ판정을 하지 않는다.

  search_chemical(query) — 규정수량 조회 + 행별 적용 조건ㆍ배타적 선택지ㆍ커버리지 선언
  get_rule(topic)        — 별표 2ㆍ3 일반기준, 별표 4 전문, 별표 1 비고의 원문

**규칙 원문도 조건 문장도 이 파일에 없다.** 원본은 Dart 층(`lib/assist/`)이다 — 앱ㆍ웹의 tool use가
같은 코드를 쓰기 때문이다(REQUIREMENTS F-008 '구현 위치 원칙 — 두 번째 구현 금지').
손으로 옮긴 원문과 PDF의 대조도 거기서 한다(`test/assist/rules_test.dart`,
정답지 `test/fixtures/rule_text.json` ← `scripts/oracle_rule_text.py`).

**판정(합산ㆍ초과 비교)은 서버가 하지 않는다.** 조합을 LLM이 해내는지 보는 것이 목적이라
(spike 확인 ①), 서버가 대신 계산하면 확인할 것이 사라진다.

설치ㆍ실행
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
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CLI = "scripts/search_cli.dart"

RULE_TOPICS = ("all", "byeolpyo2", "byeolpyo3", "byeolpyo4", "byeolpyo1")


def run_cli(args: list[str]) -> str:
    """scripts/search_cli.dart를 돌려 stdout(JSON)을 그대로 돌려준다."""
    dart = shutil.which("dart")
    if dart is None:
        raise RuntimeError("dart 실행 파일을 PATH에서 찾지 못했습니다. Flutter SDK의 bin이 PATH에 있어야 합니다.")
    try:
        p = subprocess.run([dart, "run", CLI, *args], cwd=ROOT, capture_output=True, timeout=180)
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


def search_chemical_text(query: str) -> str:
    return run_cli([query])


def get_rule_text(topic: str = "all") -> str:
    return run_cli(["--rule", topic])


def tool_spec() -> dict:
    """시스템 프롬프트와 도구 설명을 Dart 층에서 읽어 온다.

    **여기에 문구를 베껴 두지 않는다** — 원본은 `lib/assist/prompt.dart` 하나이고 앱ㆍ웹이 같은 것을 쓴다
    (REQUIREMENTS F-008 2단계 '프롬프트ㆍ도구 설명의 원본은 코드 한 곳'). 베끼면 하네스와 앱이 어긋나
    "MCP에서는 되는데 앱에서는 안 된다"가 생긴다.
    """
    return json.loads(run_cli(["--tools"]))


def description_of(spec: dict, name: str) -> str:
    for tool in spec["tools"]:
        if tool["name"] == name:
            return tool["description"]
    raise RuntimeError(f"도구 정의에 {name}이 없습니다 — lib/assist/prompt.dart를 확인하세요")


# ── MCP 서버 ─────────────────────────────────────────────────────────────────
def build_server():
    from mcp.server.mcpserver import MCPServer  # mcp 2.x (1.x에서는 mcp.server.fastmcp.FastMCP였다)

    # 시스템 프롬프트ㆍ도구 설명은 Dart 층에서 읽어 온다 — **이 파일에는 그 문구가 없다**
    # (REQUIREMENTS F-008 2단계 '원본은 코드 한 곳'. 베끼면 하네스와 앱이 어긋나 "MCP에서는 되는데
    # 앱에서는 안 된다"가 생긴다).
    spec = tool_spec()
    mcp = MCPServer(name="findchem", version="0.3.0-f008", instructions=spec["systemPrompt"])

    def search_chemical(query: str) -> str:
        """물질명(국문ㆍ영문, 부분 일치, 띄어쓰기 무시) 또는 CAS 번호로 규정수량을 조회한다.

        「유해화학물질의 규정수량에 관한 규정」 별표 2(인체ㆍ생태 유해성)ㆍ별표 3(사고대비물질)이 원천이다.
        결과 JSON의 rows에 구분ㆍ함량기준(%)과 최하위(min)ㆍ하위(low)ㆍ상위(high) 규정수량이 톤 단위
        원문 문자열로 들어 있고, 행마다 **언제 그 행을 적용하는지(condition)**가 붙어 있다.
        값을 계산ㆍ반올림하지 말고 그대로 인용한다.
        coverage.status로 이 고시가 그 물질을 덮는지 알 수 있다 — exact(정확 일치) /
        partial_only(부분 일치만 — 별개 물질일 수 있다) / none(0건, 지어내지 말 것).
        여러 물질을 다루는 질문이면 물질마다 한 번씩 부른다.
        """
        return search_chemical_text(query)

    def get_rule(topic: str = "all") -> str:
        """규정수량 판정 규칙의 원문을 돌려준다(topic: all | byeolpyo2 | byeolpyo3 | byeolpyo4 | byeolpyo1).

        byeolpyo2 = 별표 2 일반기준. 사고대비물질에 해당하면 별표 3을 적용(가), 제282호ㆍ제557호의 용액
        구분(나), 저확산 구분(다)과 그 함량기준 해석.
        byeolpyo3 = 별표 3 일반기준. 제42ㆍ43ㆍ44호가 액체이면 * 표시된 값을 적용.
        byeolpyo4 = 별표 4 '최대보유량 산정 방법' 전문. 어느 순간 최대 체류량, 보관시설만 운영하는 사업장의
        합산 판정 공식(R = Σ Qn/QLLTn, R<1), 기상물질ㆍ혼합물ㆍ저확산 물질의 비고.
        byeolpyo1 = 별표 1의 비고(2가지 이상 유해성 그룹이면 가장 작은 수량).
        보유량이 규정수량을 넘는지, 어느 행ㆍ어느 표를 적용하는지, 여러 물질을 합산해야 하는지 판단하기 전에
        이 도구를 먼저 부른다.
        """
        return get_rule_text(topic)

    # 위 docstring은 자리만 잡아 둔 것이고, 실제 설명은 Dart 층에서 읽은 것으로 덮는다.
    search_chemical.__doc__ = description_of(spec, "search_chemical")
    get_rule.__doc__ = description_of(spec, "get_rule")
    mcp.tool()(search_chemical)
    mcp.tool()(get_rule)

    return mcp


# ── 자체 점검 ────────────────────────────────────────────────────────────────
def selftest() -> int:
    """서버가 **통과만 시키는지**를 본다. 원문 대조ㆍ조건 문장 검증은 Dart 테스트(`flutter test`)가 한다."""
    sys.stdout.reconfigure(encoding="utf-8")  # 콘솔이 cp949여도 한글이 깨지지 않게(selftest 경로 전용)
    problems: list[str] = []

    try:
        rule = json.loads(get_rule_text("all"))
        for must in ("R = Q1/QLLT1", "가장 작은 수량을 적용한다", "별표 3의 사고대비물질별 규정수량을 적용한다"):
            if must not in rule["text"]:
                problems.append(f"get_rule('all') 원문에 빠진 문장: {must!r}")
        for topic in RULE_TOPICS[1:]:
            one = json.loads(get_rule_text(topic))
            if one["topic"] != topic or not one["text"].strip():
                problems.append(f"get_rule({topic!r})가 빈 응답을 돌려줬습니다")
    except Exception as e:  # noqa: BLE001 — 원인을 그대로 보고하고 실패로 남긴다
        problems.append(f"get_rule 호출 실패: {e!r}")

    try:
        get_rule_text("없는토픽")
    except RuntimeError as e:
        if "알 수 없는 규칙 주제" not in str(e):
            problems.append(f"알 수 없는 topic의 오류 문구가 다릅니다: {e}")
    else:
        problems.append("get_rule이 알 수 없는 topic을 조용히 받아들였습니다")

    try:
        data = json.loads(search_chemical_text("50-00-0"))
        # 앱 검색과 같은 답인지(test/search/search_test.dart의 기댓값): 별표3 1 · 별표2 510
        got = [(h["src"], h["no"], h["priority"], h["referenceNote"]) for h in data["hits"]]
        if got != [("별표3", 1, True, False), ("별표2", 510, False, True)]:
            problems.append(f"search_chemical('50-00-0') 결과가 다릅니다: {got}")
        if data["coverage"]["status"] != "exact":
            problems.append(f"coverage.status가 exact가 아닙니다: {data['coverage']['status']}")
        if any(not r.get("condition") for h in data["hits"] for r in h["rows"]):
            problems.append("condition이 빈 행이 있습니다")
        if data["source"]["notice"] != rule["notice"]:
            problems.append("검색 응답과 규칙 응답의 고시명이 어긋납니다")
    except Exception as e:  # noqa: BLE001
        problems.append(f"search_chemical 호출 실패: {e!r}")

    # 프롬프트ㆍ도구 설명이 Dart 층에서 오는지. 여기에 문구를 베껴 두면 하네스와 앱이 어긋난다.
    try:
        spec = tool_spec()
        names = [t["name"] for t in spec["tools"]]
        if names != ["search_chemical", "get_rule"]:
            problems.append(f"--tools가 돌려준 도구 이름이 다릅니다: {names}")
        if "도구가 준 것 이상을 말하지 않는다" not in spec["systemPrompt"]:
            problems.append("systemPrompt에 spike 설계 조건이 없습니다")
        for name in ("search_chemical", "get_rule"):
            if not description_of(spec, name).strip():
                problems.append(f"{name}의 설명이 비어 있습니다")
    except Exception as e:  # noqa: BLE001
        problems.append(f"--tools 호출 실패: {e!r}")

    for p in problems:
        print(f"FAIL {p}")
    if problems:
        print(f"\n자체 점검 실패 {len(problems)}건")
        return 1
    print("\n자체 점검 통과: get_rule(전체ㆍ주제별ㆍ알 수 없는 주제) · search_chemical(값ㆍcoverageㆍcondition) · --tools(프롬프트ㆍ도구 설명)")
    print("  ※ 원문 PDF 대조와 조건 문장 전수 검증은 Dart 테스트(flutter test)가 한다 — 원본이 lib/assist/다")
    return 0


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        sys.exit(selftest())
    build_server().run()
