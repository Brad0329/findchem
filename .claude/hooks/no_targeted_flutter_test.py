r"""`flutter test`에 인자를 붙이면 막는다 — 맨몸 전체 실행이 더 싸다 (PreToolUse 훅).

**왜 훅인가**: 2026-08-20 `/approval-audit`에서 **사용자가 직접 짚어 준 관측**이 발단이다 —
*"커밋 직전에 8번 정도 허용 요청이 나왔고, 처음 2~3개 빼고 다 flutter test였다.
그중 내가 판단할 이유가 있는 건 하나도 없었다."* 기록과 시계가 정확히 그것을 뒷받침했다.

**무엇이 문제인가**: `PowerShell(flutter test)`는 있지만 `flutter test test/foo_test.dart`는
**다른 문자열이라 없다.** (~~와일드카드가 무효라 규칙으로 덮을 수 없다~~ → **2026-08-22 정정**:
와일드카드는 작동한다. 그래도 **여기는 일부러 열지 않는다** — 아래 표대로 개별 실행이
전체보다 6~8배 느려서, 규칙 문제가 아니라 **호출 습관 자체를 막는 것**이 목적이다.
`docs/playbooks/노하우_승인_대기_최소화.md`.)

| 호출 | 규칙 | 벽시계 |
|---|---|---|
| `flutter test` (450건 전체) | 있음 | **23~27초** |
| `flutter test <파일> --plain-name "…"` | 없음 | **158~206초** |
| 같은 명령 재호출(승인이 기록된 뒤) | 생김 | 8초 |

**전체를 다 돌리는 것이 하나만 고르는 것보다 싸다.** 차이는 전부 사람이 클릭하기를
기다린 시간이다. F-032에서만 개별 실행에 약 11분을 썼고, 맨몸으로 돌렸으면 4분이었다.
**그보다 큰 비용은 사용자가 8번 방해받은 것이고, 그중 판단할 것은 하나도 없었다.**

**막지 않는 것**:
  - 맨몸 `flutter test` — **이것이 권장하는 대체 수단이다.**
  - `flutter analyze`·`flutter build apk …` 등 다른 하위 명령. 여기서 재지 않았으므로
    건드리지 않는다(YAGNI — 이 저장소 규칙).

**정말 인자가 필요하면** 사용자에게 말하고 승인을 받는다. 훅을 우회하지 않는다 —
확인 절차는 사용자가 이 에이전트를 통제하는 장치다(CLAUDE.md '우회하지 않는다').

**훅이 고장 나면 막지 않고 통과시킨다** — 훅 결함이 도구 사용을 봉쇄하면 안 된다.

**★ 전제 (템플릿 주): 전체 실행이 수십 초일 때 성립하는 정책이다** (출처 실측: 450건 23~27초).
테스트가 늘어 전체 실행이 확인 대기보다 비싸지는 규모가 되면 이 훅을 다시 판단한다.
**재판단 2026-09-18(findchem 330건)**: `measure_wait.py` 실측 41~61초(analyze와 겹치면 2~4분) — 아직 파일 하나(158~206초)보다
싸다. 전제 유지. 그날 느렸던 진짜 원인은 표시 테스트를 만들어 8회 반복한 것(`노하우_검증.md` '표시 변경은 사용자가 본다').
Flutter를 안 쓰는 프로젝트면 이 훅과 settings.json의 등록을 지운다.
"""

import re
import sys

from hook_io import deny, read_command

# `flutter test` 뒤에 **무언가 더 있는** 형태. 맨몸(뒤에 공백뿐)은 통과시킨다.
TARGETED = re.compile(r"^\s*flutter\s+test\s+\S")

# **딱 하나 판 예외** (2026-08-20 F-034 후속): 실패한 것만 출력하는 리포터.
#
# 전체 실행 출력이 68KB라 **어느 테스트가 실패했는지 읽기 어려웠다** — F-033·F-034의
# 변이 확인을 exit 코드와 "직전에 green이었다"로 판정해야 했다.
# 이 형태는 **문자열이 고정**이라 정확 일치 규칙으로 덮이고, 그래서 프롬프트를 새로
# 만들지 않는다. 파일명·`--plain-name`이 매번 달라지는 것과 정반대 성질이다.
#
# **예외를 늘리지 말 것.** 하나가 고정 문자열이라 안전한 것이지,
# `--reporter <아무거나>`를 열면 다시 매번 달라진다.
ALLOWED_EXACT = {"flutter test --reporter failures-only"}

REASON = (
    "`flutter test`에 인자를 붙이지 말 것 — **맨몸 전체 실행이 더 싸다.**\n"
    "  파일명·`--plain-name`은 매번 달라지고 그 형태를 덮는 규칙은 일부러 두지 않아\n"
    "  **호출마다 새 확인 창**이 뜬다 (실측: 전체 450건 27초 vs 파일 하나 158~206초).\n"
    "  → 그냥 `flutter test`를 부른다. 실패한 테스트는 전체 실행에도 그대로 나온다.\n"
    "  출력이 길어 실패만 보고 싶으면 **`flutter test --reporter failures-only`** —\n"
    "  이 한 형태만 예외로 열려 있다(문자열이 고정이라 프롬프트를 안 만든다).\n"
    "  정말 다른 인자가 필요하면 **사용자에게 말하고 승인을 받는다.**"
)


def blocked(command: str) -> bool:
    """이 명령을 막아야 하는가. 테스트가 이 함수를 직접 부른다."""
    if (command or "").strip() in ALLOWED_EXACT:
        return False
    return bool(TARGETED.match(command or ""))


def main() -> int:
    command = read_command("no_targeted_flutter_test")
    if command is None:
        return 0
    if blocked(command):
        deny(REASON)
    return 0


if __name__ == "__main__":
    sys.exit(main())
