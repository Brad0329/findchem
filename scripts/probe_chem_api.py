"""공공데이터포털 15149420 '한국환경공단_화학물질 정보 조회 서비스' chemSbstnList 실호출 probe.

앱은 이 API를 쓰지 않는다(plan.md 보류 항목 '외부 원천 조사'). 조사용 — 응답을 그대로 보려는 도구다.
주소·파라미터는 포털 페이지의 Swagger 명세에서 확인했다(2026-09-14):
  https://apis.data.go.kr/B552584/kecoapi/ncissbstn/chemSbstnList
  searchGubun: 1=영문명, 2=CAS번호, 3=고유번호 / returnType: XML|JSON

키는 .env의 DATA_GO_KR_KEY. 키는 출력하지 않는다(오류 메시지에서도 가린다).

사용: python scripts/probe_chem_api.py 50-00-0          (CAS)
      python scripts/probe_chem_api.py --gubun 1 Formaldehyde
"""

from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ENDPOINT = "https://apis.data.go.kr/B552584/kecoapi/ncissbstn/chemSbstnList"
ROOT = Path(__file__).resolve().parent.parent


def read_key() -> str:
    env = ROOT / ".env"
    if not env.exists():
        sys.exit(".env가 없습니다 — DATA_GO_KR_KEY를 넣어 주세요")
    for line in env.read_text(encoding="utf-8").splitlines():
        name, sep, value = line.partition("=")
        if sep and name.strip() == "DATA_GO_KR_KEY" and value.strip():
            return value.strip().strip('"').strip("'")
    sys.exit(".env에 DATA_GO_KR_KEY가 없습니다")


def build_url(key: str, gubun: str, name: str, rows: int) -> str:
    # 포털 키는 '인코딩 키'(%가 들어 있음)와 '디코딩 키' 두 가지다. 인코딩 키를 다시 인코딩하면 인증 실패가 난다.
    service_key = key if "%" in key else urllib.parse.quote(key, safe="")
    query = urllib.parse.urlencode(
        {"pageNo": 1, "numOfRows": rows, "searchGubun": gubun, "searchNm": name, "returnType": "JSON"}
    )
    return f"{ENDPOINT}?serviceKey={service_key}&{query}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("name", help="검색어 (기본은 CAS 번호)")
    parser.add_argument("--gubun", default="2", choices=["1", "2", "3"], help="1=영문명, 2=CAS, 3=고유번호")
    parser.add_argument("--rows", type=int, default=10)
    args = parser.parse_args()

    key = read_key()
    url = build_url(key, args.gubun, args.name, args.rows)
    try:
        with urllib.request.urlopen(url, timeout=20) as resp:
            status = resp.status
            body = resp.read().decode("utf-8", errors="replace")
    except urllib.error.HTTPError as e:
        # 오류 본문은 보여 주되 키가 섞여 나오지 않게 가린다
        detail = e.read().decode("utf-8", errors="replace").replace(key, "<KEY>")
        sys.exit(f"HTTP {e.code}: {detail[:1000]}")
    except urllib.error.URLError as e:
        sys.exit(f"접속 실패: {str(e.reason).replace(key, '<KEY>')}")

    print(f"HTTP {status}")
    try:
        data = json.loads(body)
    except json.JSONDecodeError:
        # 200이어도 인증 오류가 XML로 오는 경우가 있다(포털 공통 오류 형식) — 원문을 그대로 보인다
        print("JSON이 아닌 응답:")
        print(body.replace(key, "<KEY>")[:3000])
        sys.exit(1)
    print(json.dumps(data, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
