"""`git commit -m` 훅(`.claude/hooks/no_commit_m.py`) 검증.

**반례가 이 테스트의 존재 이유다.** 이 훅이 `git commit -F .commit_msg.txt`를 막으면 커밋할 방법이
없어진다 — 허용 규칙이 그 한 형태뿐이다.

실행: python -m pytest tests/test_no_commit_m.py
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
HOOK = ROOT / ".claude" / "hooks" / "no_commit_m.py"
sys.path.insert(0, str(HOOK.parent))
from no_commit_m import blocked  # noqa: E402


# ── 막아야 하는 것 — findchem 2026-09-15 실측 형태 ─────────────────────────────

@pytest.mark.parametrize("command", [
    # 실측 428.5초 등 — PowerShell here-string
    "git commit -m @'\nF-007 기록\n\n- 사용자 확인\n'@",
    "git add work_log/plan.md; git commit -m @'\nplan.md 갱신\n'@",   # 앞에 add가 붙어도
    'git commit -m "한 줄"',
    "git commit -am 'x'",                    # m이 든 짧은 플래그 묶음
    "git commit --message=x",
    "git commit --message x",
    "git commit --no-verify -m x",           # 다른 인자가 앞에 있어도
    'git -C app commit -m "x"',
])
def test_m_커밋을_막는다(command):
    assert blocked(command)


# ── 막으면 안 되는 것 (반례) ─────────────────────────────────────────────────

@pytest.mark.parametrize("command", [
    "git commit -F .commit_msg.txt",                   # 허용 규칙의 형태 — 막으면 커밋할 길이 없다
    "git commit --amend -F .commit_msg.txt",           # --amend의 m은 긴 플래그 안이다
    "git commit --amend --no-edit",
    "git commit -F .commit_msg.txt; git log -m -1",    # 뒤 명령의 -m
    "git log -m --oneline",
    "git show -m HEAD",
    "git add -A",
    "git status --short",
    "echo commit -m",                                  # git이 아니다
])
def test_정상_호출은_막지_않는다(command):
    assert not blocked(command)


def test_빈_명령은_막지_않는다():
    assert not blocked("")


# ── 훅을 실제로 파이프로 돌려 본다 ───────────────────────────────────────────

def _run(payload: dict) -> str:
    p = subprocess.run(
        [sys.executable, str(HOOK)],
        input=json.dumps(payload),
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    assert p.returncode == 0, p.stderr
    return p.stdout


def test_훅이_deny를_돌려준다():
    out = _run({"tool_input": {"command": 'git commit -m "x"'}})
    decision = json.loads(out)["hookSpecificOutput"]
    assert decision["permissionDecision"] == "deny"
    assert ".commit_msg.txt" in decision["permissionDecisionReason"]


def test_훅이_F_커밋에는_아무_말도_안_한다():
    assert _run({"tool_input": {"command": "git commit -F .commit_msg.txt"}}).strip() == ""


def test_입력이_깨져도_막지_않는다():
    """훅 결함이 도구 사용을 봉쇄하면 안 된다."""
    p = subprocess.run(
        [sys.executable, str(HOOK)],
        input="{깨진 json",
        capture_output=True,
        text=True,
        encoding="utf-8",
        # 자식의 stderr 인코딩을 고정한다 — 이유는 test_no_output_filter.py 같은 자리 참조.
        env={**os.environ, "PYTHONIOENCODING": "utf-8"},
    )
    assert p.returncode == 0
    assert p.stdout.strip() == ""
