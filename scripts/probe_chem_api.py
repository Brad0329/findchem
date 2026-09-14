"""공공데이터포털 화학물질 API 실호출 probe — 응답을 그대로 보려는 조사 도구(후속 확장 작업용).

주소·파라미터는 각 포털 페이지의 Swagger 명세에서 확인했다(2026-09-14):
  chem  15149420 한국환경공단_화학물질 정보 조회   https://apis.data.go.kr/B552584/kecoapi/ncissbstn/chemSbstnList
  ghs   15149423 한국환경공단_유독물GHS 정보 조회  https://apis.data.go.kr/B552584/kecoapi/ncisghs/ghsList
  두 서비스 공통: searchGubun 1=영문명, 2=CAS번호, 3=고유번호 / searchNm / returnType XML|JSON / pageNo / numOfRows
  safety 15072442 화학물질안전원_화학물질안전관리정보  https://apis.data.go.kr/1480802/iciskischem/kischemlist
    (Swagger 없는 옛 형식 — 포털 페이지의 요청변수 표에서 확인: ServiceKey, numOfRows, pageNo, casNo. 결과 형식 파라미터 없음)

키는 .env의 DATA_GO_KR_KEY(포털 계정 키 하나를 서비스마다 활용신청해 쓴다). 키는 출력하지 않는다(오류 메시지에서도 가린다).

사용: python scripts/probe_chem_api.py 50-00-0                 (chem, CAS)
      python scripts/probe_chem_api.py --service ghs 50-00-0
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

ENDPOINTS = {
    "chem": "https://apis.data.go.kr/B552584/kecoapi/ncissbstn/chemSbstnList",
    "ghs": "https://apis.data.go.kr/B552584/kecoapi/ncisghs/ghsList",
    "safety": "https://apis.data.go.kr/1480802/iciskischem/kischemlist",
}
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


def build_url(service: str, key: str, gubun: str, name: str, rows: int) -> str:
    # 포털 키는 '인코딩 키'(%가 들어 있음)와 '디코딩 키' 두 가지다. 인코딩 키를 다시 인코딩하면 인증 실패가 난다.
    service_key = key if "%" in key else urllib.parse.quote(key, safe="")
    if service == "safety":
        # 이 서비스는 CAS로만 찾는다(searchGubun 없음). 명세 표기는 ServiceKey지만 다른 서비스와 같은 serviceKey로 보낸다
        # (2026-09-14: 활용신청 뒤에도 ServiceKey·serviceKey 둘 다 403 SERVICE_KEY_IS_NOT_REGISTERED_ERROR —
        #  파라미터 이름은 원인이 아니다. 같은 때 신청한 ghs는 200. 승인 상태·반영 지연을 확인할 것)
        query = urllib.parse.urlencode({"pageNo": 1, "numOfRows": rows, "casNo": name})
        return f"{ENDPOINTS[service]}?serviceKey={service_key}&{query}"
    query = urllib.parse.urlencode(
        {"pageNo": 1, "numOfRows": rows, "searchGubun": gubun, "searchNm": name, "returnType": "JSON"}
    )
    return f"{ENDPOINTS[service]}?serviceKey={service_key}&{query}"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("name", help="검색어 (기본은 CAS 번호)")
    parser.add_argument("--service", default="chem", choices=sorted(ENDPOINTS), help="호출할 서비스")
    parser.add_argument(
        "--endpoint",
        help="호출 주소를 직접 지정(파라미터 형식은 --service를 따른다). 주소가 틀렸을 때의 오류와 비교하는 조사용",
    )
    parser.add_argument("--gubun", default="2", choices=["1", "2", "3"], help="1=영문명, 2=CAS, 3=고유번호")
    parser.add_argument("--rows", type=int, default=10)
    args = parser.parse_args()

    key = read_key()
    if args.endpoint:
        ENDPOINTS[args.service] = args.endpoint
    url = build_url(args.service, key, args.gubun, args.name, args.rows)
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
        # XML 응답(결과 형식 파라미터가 없는 옛 서비스) 또는 200으로 오는 포털 공통 오류(XML) — 원문을 그대로 보인다.
        # 성공인지 오류인지는 본문의 resultCode·errMsg로 사람이 판단한다
        print("JSON이 아닌 응답(원문):")
        print(body.replace(key, "<KEY>"))
        return
    print(json.dumps(data, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
