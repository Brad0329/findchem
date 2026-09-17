"""F-008 판정 한 질문이 쓰는 토큰과 비용을 잰다.

  python scripts/measure_assist_tokens.py          입력만 — count_tokens(무료)
  python scripts/measure_assist_tokens.py --live   실제 판정 루프를 돌린다 — **돈이 든다**

- 시스템 프롬프트ㆍ도구 정의ㆍ도구 응답은 전부 `scripts/search_cli.dart`에서 받아온다 —
  앱ㆍ웹이 실제로 보내는 그 문자열이다(여기서 베끼지 않는다).
- 도구 결과는 `session.dart`와 같이 **들여쓰기 없는** JSON으로 만든다.
- 키는 `.env`의 ANTHROPIC_API_KEY에서 읽고 **출력하지 않는다.**
- `--live`의 루프는 `lib/assist/session.dart`를 그대로 옮긴 것이다(왕복 상한 10,
  thinking 블록을 그대로 되돌려 보냄, 도구 결과는 한 user 메시지에 모음).
  스트리밍만 다르다 — 토큰 사용량은 같고 측정에는 필요 없다.
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


# ───── --live: 실제 판정 루프 ─────

MAX_ROUNDS = 10  # lib/assist/session.dart의 assistMaxRounds
MAX_TOKENS = 16000  # lib/assist/llm_client.dart
# 100만 토큰당 (입력, 출력). 캐시 쓰기 1.25배ㆍ읽기 0.1배는 입력가 기준이다.
PRICES = {"claude-opus-5": (5.0, 25.0), "claude-sonnet-5": (2.0, 10.0)}


def message(key, model, system, tools, messages):
    body = json.dumps(
        {
            "model": model,
            "max_tokens": MAX_TOKENS,
            "thinking": {"type": "adaptive", "display": "summarized"},
            "system": system,
            "tools": tools,
            "messages": messages,
            "cache_control": {"type": "ephemeral"},
        },
        ensure_ascii=False,
    ).encode("utf-8")
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=body,
        headers={
            "content-type": "application/json",
            "x-api-key": key,
            "anthropic-version": "2023-06-01",
        },
    )
    with urllib.request.urlopen(req) as resp:
        return json.load(resp)


def run_tool(name, tool_input):
    """도구 실행부. 앱의 `AssistTools.run`과 같은 함수를 CLI를 거쳐 부른다."""
    if name == "search_chemical":
        return cli(tool_input.get("query", ""))
    if name == "get_rule":
        return cli("--rule", tool_input.get("topic", "all"))
    raise SystemExit(f"알 수 없는 도구: {name}")


def live(key, system, tools):
    print(f"{'모델':<16}{'질문':<12}{'왕복':>5}{'입력':>9}{'캐시쓰기':>9}{'캐시읽기':>9}{'출력':>8}{'$/질문':>9}")
    totals = {}
    for model in PRICES:
        for label, question, _ in CASES:
            msgs = [{"role": "user", "content": [{"type": "text", "text": question}]}]
            used = {"input": 0, "write": 0, "read": 0, "output": 0}
            rounds = 0
            for _ in range(MAX_ROUNDS):
                rounds += 1
                resp = message(key, model, system, tools, msgs)
                u = resp["usage"]
                used["input"] += u.get("input_tokens", 0)
                used["write"] += u.get("cache_creation_input_tokens", 0)
                used["read"] += u.get("cache_read_input_tokens", 0)
                used["output"] += u.get("output_tokens", 0)
                msgs.append({"role": "assistant", "content": resp["content"]})
                calls = [b for b in resp["content"] if b["type"] == "tool_use"]
                if not calls:
                    break
                results = [
                    {
                        "type": "tool_result",
                        "tool_use_id": c["id"],
                        "content": json.dumps(
                            run_tool(c["name"], c.get("input", {})),
                            ensure_ascii=False, separators=(",", ":"),
                        ),
                    }
                    for c in calls
                ]
                msgs.append({"role": "user", "content": results})

            pin, pout = PRICES[model]
            cost = (
                used["input"] * pin + used["write"] * pin * 1.25 + used["read"] * pin * 0.1
                + used["output"] * pout
            ) / 1e6
            totals[(model, label)] = (used, rounds, cost)
            print(
                f"{model:<16}{label:<12}{rounds:>5}{used['input']:>9,}{used['write']:>9,}"
                f"{used['read']:>9,}{used['output']:>8,}{cost:>9.4f}"
            )

    print()
    for model in PRICES:
        costs = [v[2] for (m, _), v in totals.items() if m == model]
        outs = [v[0]["output"] for (m, _), v in totals.items() if m == model]
        avg = sum(costs) / len(costs)
        print(
            f"{model}: 질문당 평균 ${avg:.4f} (출력 평균 {sum(outs) // len(outs):,} 토큰) "
            f"→ 하루 100질문 30일 = ${avg * 3000:,.0f}/월"
        )
    print(f"\n이번 측정에 쓴 돈 = ${sum(v[2] for v in totals.values()):.2f}")


def main():
    key = api_key()
    prompt = cli("--tools")
    system, tools = prompt["systemPrompt"], prompt["tools"]

    if "--live" in sys.argv:
        live(key, system, tools)
        return

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
