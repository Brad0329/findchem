"""agent_skills/<이름>/ 을 claude.ai에 올릴 zip으로 묶는다 → build/<이름>.zip

  python scripts/pack_skill.py msds-composition

zip 안의 최상위는 스킬 폴더 하나(<이름>/SKILL.md). __pycache__ㆍ.pyc는 넣지 않는다.
"""

import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    src = ROOT / "agent_skills" / argv[0]
    if not (src / "SKILL.md").is_file():
        print(f"오류: {src}/SKILL.md가 없다", file=sys.stderr)
        return 1
    out = ROOT / "build" / f"{argv[0]}.zip"
    out.parent.mkdir(exist_ok=True)
    files = sorted(p for p in src.rglob("*")
                   if p.is_file() and "__pycache__" not in p.parts and p.suffix != ".pyc")
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for p in files:
            z.write(p, p.relative_to(src.parent).as_posix())
    for p in files:
        print(p.relative_to(src.parent).as_posix())
    print(f"→ {out} ({len(files)}개 파일)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
