r"""`git commit -m ...`(here-string 포함)을 막는다. `.commit_msg.txt`에 쓰고 `-F`로 커밋할 것.

**왜 훅인가**: findchem 2026-09-15 `/approval-audit` 실측(5세션).

허용 규칙은 `git commit -F .commit_msg.txt*` 한 형태로 열려 있고 플레이북 §4·스킬 문서에도 그 형태가
적혀 있는데, PowerShell 도구에서 `git commit -m @' … '@` here-string으로 24건을 불렀다.
그 형태는 규칙에 안 걸려 호출마다 3.8~428초로 갈렸고 65초를 넘은 것이 5건이었다(같은 기간 `-F`
형태는 대부분 5초 이하). 문서로 안 막히는 습관이라 구조로 강제해 형태를 하나로 고정한다(플레이북 §6).

**막는 것**: `git commit` 뒤 인자에 `-m`·`-am`처럼 m이 든 짧은 플래그 묶음, 또는 `--message`.

**막지 않는 것** (반례 — 테스트에 들어 있다):
  - `git commit -F .commit_msg.txt` (허용 규칙의 형태)
  - `git commit --amend -F .commit_msg.txt` (`--amend`의 m은 긴 플래그 안이다)
  - `git log -m`·`git show -m`처럼 commit이 아닌 git 명령
  - `git add -A`
  - `git commit -F .commit_msg.txt; git log -m` (뒤 명령의 -m — `;`·`&`·`|`를 넘어 보지 않는다)

**훅이 고장 나면 막지 않고 통과시킨다** — 훅 결함이 도구 사용을 봉쇄하면 안 된다
(`no_redundant_cd.py`·`no_inline_python.py`와 같은 원칙).
"""

import re
import sys

from hook_io import deny, read_command

# `git [전역 옵션…] commit … -m` / `-am` / `--message`.
# - 전역 옵션: `-C <경로>`·`-c k=v`·`--no-pager`처럼 대시로 시작하는 낱말(+값 하나)만 git과 commit 사이에 허용한다.
# - 짧은 플래그는 대시 하나로 시작하는 묶음만 본다(`--amend`의 m을 잡지 않도록).
# - 플래그 뒤에는 공백·`=`·끝 말고도 **따옴표·`@`가 바로 붙을 수 있다** — `-m"msg"`는 git이 `-m msg`와 똑같이 받는다.
COMMIT_M = re.compile(
    r"(?:^|[\s;&|])git(?:\s+-{1,2}[^\s;&|]+(?:\s+[^\s;&|\-][^\s;&|]*)?)*?\s+commit\b"
    r"(?:\s+[^\s;&|]+)*?\s+(?:-(?!-)[A-Za-z]*m[A-Za-z]*|--message)(?=[\s=\"'@]|$)"
)

REASON = (
    "`git commit -m`(here-string 포함)을 쓰지 말 것 — 허용 규칙은 `-F .commit_msg.txt` 한 형태다.\n"
    "  -m 형태는 규칙에 안 걸려 승인을 묻는다(실측: 65~428초 호출 5건).\n"
    "  → 메시지를 저장소 루트 `.commit_msg.txt`에 Write(허용됨)하고\n"
    "     `git commit -F .commit_msg.txt`로 부른다."
)


def blocked(command: str) -> bool:
    """이 명령을 막아야 하는가. 테스트가 이 함수를 직접 부른다."""
    return bool(COMMIT_M.search(command or ""))


def main() -> int:
    command = read_command("no_commit_m")
    if command is None:
        return 0
    if blocked(command):
        deny(REASON)
    return 0


if __name__ == "__main__":
    sys.exit(main())
