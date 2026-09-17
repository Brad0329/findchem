"""F-008 판정 한 질문이 쓰는 **입력 토큰**을 count_tokens 실호출로 잰다(무료 엔드포인트).

  python scripts/measure_assist_tokens.py

- 시스템 프롬프트ㆍ도구 정의ㆍ도구 응답은 전부 `scripts/search_cli.dart`에서 받아온다 —
  앱ㆍ웹이 실제로 보내는 그 문자열이다(여기서 베끼지 않는다).
- 도구 결과는 `session.dart`와 같이 **들여쓰기 없는** JSON으로 만든다.
- 키는 `.env`의 ANTHROPIC_API_KEY에서 읽고 **출력하지 않는다.**
- 출력 토큰은 이 도구가 재지 않는다(실호출이 필요해 돈이 든다) — 입력만 실측한다.
"""

import json
import os
import shutil
import subprocess
import sys
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Windows의 dart는 .bat이라 CreateProcess가 이름만으로는 못 찾는다 — 실제 경로로 푼다.
DART = shutil.which("dart") or shutil.which("flutter")
MODEL = "claude-opus-5"  # 토큰 수는 두 모델이 같은 토크나이저를 쓴다 — 가격만 다르다.

# 화면의 예시 질문 4개(lib/ui/assist_page.dart)와 각 질문이 부를 검색어.
CASES = [
    ("암모니아 0.3톤", "암모니아 0.3톤이면 규정수량 넘나요?", ["암모니아"]),
    ("톨루엔 3톤", "톨루엔 3톤 있는데 규정수량 넘나요?", ["톨루엔"]),
    (
        "3물질 합산",
        "보관시설만 있는 창고에 톨루엔 0.01톤, 황산 0.05톤, 염화수소 0.004톤이 있습니다. 최하위 규정수량 미만인가요?",
        ["톨루엔", "황산", "염화수소"],
    ),
    ("어느 표를 보나", "메틸알코올은 어느 표 기준으로 보나요?", ["메틸알코올"]),
]


def api_key():
    path = os.path.join(ROOT, ".env")
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("ANTHROPIC_API_KEY="):
                return line.split("=", 1)[1].strip()
    sys.exit(".env에 ANTHROPIC_API_KEY가 없습니다")


def cli(*args):
    """search_cli.dart를 부르고 JSON을 돌려준다."""
    if DART is None:
        sys.exit("dart 실행 파일을 PATH에서 찾지 못했습니다")
    out = subprocess.run(
        [DART, "run", "scripts/search_cli.dart", *args],
        cwd=ROOT, capture_output=True, check=True,
    )
    return json.loads(out.stdout.decode("utf-8"))


def count(key, system, tools, messages):
    body = json.dumps(
        {
            "model": MODEL,
            "system": system,
            "tools": tools,
            "messages": messages,
            "thinking": {"type": "adaptive", "display": "summarized"},
        },
        ensure_ascii=False,
    ).encode("utf-8")
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages/count_tokens",
        data=body,
        headers={
            "content-type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)["input_tokens"]


def main():
    key = api_key()
    prompt = cli("--tools")
    system, tools = prompt["systemPrompt"], prompt["tools"]
    rule_all = json.dumps(cli("--rule", "all"), ensure_ascii=False, separators=(",", ":"))

    print(f"규칙 원문(all) 문자 수 = {len(rule_all):,}")
    print(f"{'질문':<12} {'R1':>8} {'R2':>8} {'R3':>8} {'입력 합':>10}")

    for label, question, queries in CASES:
        hits = {
            q: json.dumps(cli(q), ensure_ascii=False, separators=(",", ":")) for q in queries
        }
        msgs = [{"role": "user", "content": [{"type": "text", "text": question}]}]
        rounds = [count(key, system, tools, msgs)]

        # R2 — 물질마다 search_chemical 한 번(한 턴에 모아 부른다), 결과는 한 user 메시지에.
        uses, results = [], []
        for i, (q, payload) in enumerate(hits.items()):
            uses.append({"type": "tool_use", "id": f"t{i}", "name": "search_chemical", "input": {"query": q}})
            results.append({"type": "tool_result", "tool_use_id": f"t{i}", "content": payload})
        msgs.append({"role": "assistant", "content": uses})
        msgs.append({"role": "user", "content": results})
        rounds.append(count(key, system, tools, msgs))

        # R3 — get_rule(all) 한 번.
        msgs.append(
            {"role": "assistant", "content": [{"type": "tool_use", "id": "r0", "name": "get_rule", "input": {"topic": "all"}}]}
        )
        msgs.append({"role": "user", "content": [{"type": "tool_result", "tool_use_id": "r0", "content": rule_all}]})
        # R3의 출력이 최종 답이다 — 왕복은 셋(search → get_rule → 답).
        rounds.append(count(key, system, tools, msgs))

        print(f"{label:<12} " + " ".join(f"{r:>8,}" for r in rounds) + f" {sum(rounds):>10,}")


if __name__ == "__main__":
    main()
