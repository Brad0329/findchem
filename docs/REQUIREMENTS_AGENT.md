# FindChem 에이전트 트랙 요구사항 (`agent` 브랜치)

> 에이전트 트랙(원격 MCP 서버 + 스킬 + 수용 테스트)의 요구사항·수용 기준 **단일 원본**. 계획은 `work_log/plan_agent.md`.
> master 트랙의 F 번호(`docs/REQUIREMENTS.md`)와 섞지 않는다 — 번호 체계 `A-NNN`(사용자 결정 2026-10-02).
> 규칙은 REQUIREMENTS.md와 같다: 구현 전에 수용 기준, 검증 가능한 문장, 번호 재사용 금지, 상태 어휘(미착수/진행/완료/동결/중단/폐기/안 함).

## 요구사항 ID 대장 — A 번호는 여기서 받아간다

| ID | 기능 | 상태 |
|---|---|---|
| A-001 | 원격 MCP 시범 (기존 도구 2개를 공개 HTTPS로, Cowork 연결 + 서버 파일 받기 실측) | 진행(2026-10-02 착수·배포 — 커넥터 연결 확인. 남은 것: 폰 실테스트, 서버 파일 받기 실측) |
| A-002 | 데이터 출처 조사 (ERPG-2·PAC-2, 시나리오 규정수량, 별지1 규정수량 표기) | 미착수(2026-10-02) |
| A-003 | 물성 조회 도구 (KOSHA MSDS — 비중·증기압·폭발한계·TWA·GHS·H코드) | 완료(2026-10-02 — 1차 값 해석·녹화 스크립트, 2차 녹화·호출·응답, spec-checker 대조 후 보완) |
| A-004 | 계산 도구 (작성수준 판정, 함량미만·시나리오 대상 산정) | 미착수(2026-10-02) |
| A-005 | 검증 도구 `verify_draft` (초안 값·단위를 공식 데이터와 대조) | 미착수(2026-10-02) |
| A-006 | 스킬 (규정수량 판정 + 계획서 작성) | 미착수(2026-10-02) |
| A-007 | 수용 테스트 — 사례 A(2025 계획서 합본)로 실행·채점 | 미착수(2026-10-02, 설계는 plan_agent.md) |
| **다음 번호** | **A-008** | |

## 수용 기준

각 항목은 착수할 때 이 아래에 절을 만들어 수용 기준을 먼저 쓴다.

### A-001: 원격 MCP 시범
- **설명**: F-008 도구 2개(`search_chemical`·`get_rule`)를 MCP Streamable HTTP로 공개 HTTPS(Cloud Run 서울)에 올려
  Claude(Cowork·폰·PC)에 커스텀 커넥터로 붙인다. 결정은 plan_agent.md A-001(Dart·Cloud Run `asia-northeast3`·인증 없음·읽기 전용·이 세션에서 배포).
  - 구현 위치: 프로토콜 처리 `lib/mcp/`(Flutter 없음 — `dart compile exe`로 돈다), 진입점 `scripts/mcp_http_server.dart`, 배포 `scripts/deploy_mcp.sh`.
    도구 실행은 앱·웹과 **같은 `AssistTools.run`**, 설명·시스템 프롬프트는 `lib/assist/prompt.dart` — 두 번째 구현 금지
  - 새 의존성 없음(`dart:io` HttpServer). 상태 없는 서버(세션 ID 안 씀) — 요청마다 JSON 응답 하나(SSE 스트림 안 씀)
  - 범위 밖: 인증(get_msds를 올릴 때), A-004 계산 도구, 자동 배포, 캐시
- **수용 기준**
  - 프로토콜(테스트: `test/mcp/`)
    - [x] `initialize` → `protocolVersion`(클라이언트가 보낸 판이 지원 목록에 있으면 그대로, 아니면 최신) · `capabilities.tools` · `serverInfo` · `instructions` = `assistSystemPrompt`
    - [x] `tools/list` → 도구 2개, 이름·설명·`inputSchema`가 `assistToolDefinitions()`와 같다(설명 문자열 완전 일치)
    - [x] `tools/call search_chemical {query: 50-00-0}` → `content[0].text`의 JSON이 `searchResponse`와 같고 `isError` false
    - [x] `tools/call get_rule {topic: 없는토픽}` → `isError: true` + 사유(조용히 전체로 대체하지 않는다). 알 수 없는 도구도 `isError: true`
    - [x] 알림(`id` 없음, `notifications/initialized`) → HTTP 202 본문 없음. 모르는 메서드 → JSON-RPC `-32601`. JSON이 아니면 `-32700`, `ping` → 빈 결과
  - HTTP(테스트: 포트 0에 띄워 실제 요청)
    - [x] `POST /mcp` 정상 요청 → 200 `application/json`. `GET /mcp` → 405. 다른 경로 → 404
    - [x] 처리 중 예외는 500 + 사유 없는 JSON-RPC 오류, 원인은 로그에(조용한 실패 금지)
  - 배포·연결(실측)
    - [x] Cloud Run 서울에 배포되고, 공개 주소 `/mcp`에 이 세션에서 `initialize`·`tools/list`·`tools/call`이 통한다
          (2026-10-02 — 세션 프록시가 `*.run.app`을 막아 curl 대신 **사용자가 붙인 커스텀 커넥터를 이 세션에서 불러** 확인:
          initialize·tools/list(도구 2개) 통과, search_chemical 7782-50-5 정상 JSON, get_rule 없는 주제 → isError + 사유)
    - [ ] (사용자 실테스트) Claude 커스텀 커넥터로 PC·폰에서 붙여 질문 하나에 두 도구가 불린다
    - [ ] 서버가 만든 파일(PDF)을 Cowork가 받는 길 실측 — 2차(도구 2개 연결 확인 뒤)

### A-003: 물성 조회 도구 (KOSHA MSDS)
- **설명**: CAS 하나로 안전보건공단 MSDS 조회 서비스(data.go.kr 15157612, `https://apis.data.go.kr/B552468/msdschem1`, XML 전용)를 불러
  계획서 1.2 물질 목록·별지7·작성수준 판정에 필요한 물성을 돌려준다. 실측 근거: plan.md 보류 항목 'KOSHA MSDS 조회 서비스 실측'.
  - 도구가 돌려주는 넷: 원문 그대로의 값 · 출처와 판본(`chemId`·`lastDate`·조회 시각) · 적용 조건(온도·기준) · 없다는 사실
  - 호출: `getChemList001`(searchCnd=1) → `casNo` **완전 일치** → `getChemDetail021`(2절 유해성)·`081`(8절 노출기준)·`091`(9절 물리화학적 특성)
  - **결정(사용자 2026-10-02, 스펙화는 requirements-analyst)**:
    - Q1 **Dart, Flutter 없이**(`lib/msds/`) — 앱·웹·원격 MCP가 같은 코드를 쓴다. 로그는 생성자로 받는 콜백.
      F-007의 순수 함수(`maskKey`·`portalReasonCode`·`failureMessage`·`LookupText`)는 Flutter 없는 `lib/lookup/portal.dart`로 옮기고
      `chem_api.dart`가 다시 내보낸다(F-007 동작 불변 — 기존 테스트가 지킨다)
    - Q2 **실응답 녹화는 클라우드 세션에서** — 환경 변수 `DATA_GO_KR_KEY`(클라우드 환경 설정, 2026-10-02 사용자 등록)로
      녹화 스크립트 `scripts/record_msds.dart`를 돌려 `test/fixtures/msds/`에 원문 XML을 커밋한다. 키는 파일에 남기지 않는다
    - Q3 `casNo` 완전 일치가 2건 이상이면 `status: ambiguous` + 후보(chemId·국문명·lastDate)만 돌려주고, 선택 입력 `chemId`로 다시 부르게 한다
    - Q4 단위는 원문 표기를 분리하고 **종류만 분류**(`unitKind`: 밀도 / 상대밀도(물=1) / 압력 / 퍼센트 / unknown). **환산은 하지 않는다**(A-004·A-005)
    - Q5 2·8·9절은 **항목 전부를 원문으로** 돌려주고, 숫자로 해석하는 것은 비중·증기압·폭발한계(하한·상한)만. 부식성 판정·노출기준 고르기는
      하지 않는다(A-004·스킬). 농도는 사업장 입력이라 뺀다
  - 범위 밖: 앱·웹 화면, MCP 서버·호스팅·키 주입(A-001), 끝점 농도(A-002), 단위 환산·판정(A-004), `verify_draft`(A-005), 캐시,
    국문명·UN 검색, 다른 MSDS 절, H·P 문구를 NICS 문구표와 대조하는 일(KOSHA는 산안법 체계 — 원문 그대로)
- **단계**: **1차(2026-10-02)** = 공통 함수 분리 + 값 해석·그림문자 보정 + 녹화 스크립트(키 없이 가능한 것).
  **2차** = 녹화 후 호출·목록·상세·도구 응답 조립. ⟨녹화 후⟩ 표시는 녹화한 원문으로 기대값을 채운다
- **수용 기준** (테스트: 응답은 실호출 원문을 `test/fixtures/msds/`에 고정해 돈다 — 실호출은 자동 테스트에 넣지 않는다)
  - 1차 — 값 해석(원문 문자열은 plan.md 실측 기록)
    - [x] 값 끝의 `|   ※출처 : ECHA` → `origin: ECHA`로 분리, `text`에는 꼬리 없음, `raw`는 원문 그대로
    - [x] 비중 `1.15` → value 1.15, unit 없음, unitKind unknown(단위가 원문에 없으면 무차원으로 단정하지 않는다)
    - [x] 비중 `0.8623 (g/cu cm at 20℃)` → value 0.8623, unit `g/cu cm`, unitKind 밀도, condition `20℃`
    - [x] 비중 `0.79 (물=1, 20℃)` → value 0.79, unitKind 상대밀도(물=1), condition `20℃` / `1.8 (물=1, 20℃)` → 1.8, 같은 종류
    - [x] `자료없음` → `status: no_data`, 해석값 없음
    - [x] 숫자를 못 뽑으면(`해당없음` 등) `status: unparsed` + `raw` 그대로 + 사유, 로그 콜백에 한 줄
    - [x] **지어낸 숫자 0건**: 해석에 성공한 모든 값의 숫자 문자열이 `raw` 안에 그대로 있다(1차는 위 표본 전부, 2차는 녹화한 모든 필드)
    - [x] H코드 `H220 : 극인화성 가스|H280 : …` → `|`로 쪼개 `[{code: H220, phrase: 극인화성 가스}, …]`
    - [x] 그림문자 보정: KOSHA `GHS03.gif` → 표준 `GHS04`, `GHS04.gif` → `GHS03`, `GHS02.gif` → `GHS02`(그대로). 모든 항목에 KOSHA 원문 파일명이 남는다
  - 1차 — 구조
    - [x] `lib/msds/`와 `lib/lookup/portal.dart`는 Flutter를 import하지 않는다(테스트가 파일을 읽어 확인)
    - [x] F-007 기존 테스트가 `portal.dart` 분리 뒤에도 그대로 통과한다
    - [x] 녹화 스크립트는 키가 없으면(환경 변수 비었음) 호출 0회로 끝나고 이유를 출력한다. 저장한 XML에 키 문자열이 없다
  - 2차 — 호출·목록 (녹화 2026-10-02, 8물질 + 없는 CAS. 상세 응답에는 쪽 정보가 없다)
    - [x] CAS 형식(`casPattern`)이 아니거나(`50-00`, `abc`) 키가 비었으면 호출 0회, `status: failed`와 사유
    - [x] 정상 조회 = 목록 1회 + 상세 021·081·091 각 1회. 인코딩 키·디코딩 키가 같은 주소를 만든다
    - [x] 50-00-0 목록(부분 일치 `13150-00-0` 포함) → 완전 일치 1건만 쓰고 `droppedPartialMatches`가 버린 건수. chemId `001097`·국문명 `포름알데히드`
    - [x] 목록 `totalCount`가 받은 건수보다 크면 다음 쪽을 받는다. 10쪽(1,000행)을 넘기면 `status: failed`에 전체·받은 건수(조용한 절단 금지)
    - [x] 없는 CAS → `status: not_found`, 상세 호출 0회. 부분 일치만 있으면 `not_found` + 버린 건수
    - [x] 완전 일치 2건 이상 → `status: ambiguous` + 후보 목록, 상세 호출 0회. `chemId`를 주면 그것으로 상세를 부른다
  - 2차 — 응답
    - [x] `source`에 provider(15157612)·endpoint·chemId·casNo·국문명·`lastDate`(원문)·`retrievedAt`(주입한 시계)
    - [x] 021·081·091의 항목이 하나도 빠지지 않고 원문 그대로 `items`에 있다(항목 수 = fixture의 item 수)
    - [x] 비중·증기압·폭발한계(하한·상한)·성상이 녹화 원문대로 나온다 — 항목 코드 비중 `I28`·증기압 `I22`·폭발한계 `I20`·성상 `I0202`, 표본 50-00-0·108-88-3·67-56-1·7664-93-9·13516-27-3(기대값은 `test/msds/msds_client_test.dart`).
          폭발한계는 한 항목에 `상한 / 하한 단위`(`7.8 / 1.0 %`)로 온다 — 단위는 하한 뒤에만 있어 상한에 **단위만** 붙인다. `50 / 6 % (vol %)`의 괄호는 적용 조건이 아니라 단위(`vol %`). `- / -`는 둘 다 `unparsed`. 13516-27-3 비중은 `no_data`
    - [x] 8절 노출기준 하위 항목이 이름과 원문 그대로 전부 나온다(도구가 하나를 고르지 않는다)
    - [x] 그림문자 보정 실데이터: 질소(7727-37-9) → `GHS04` / 과산화수소(7722-84-1) → `GHS03` / 산소(7782-44-7) → `GHS03`·`GHS04`
    - [x] 항목 코드가 응답에 없으면 그 필드는 `item_missing` — 노출기준은 `H02` 하위 항목이 하나도 없을 때(기준 없음과 구분)
  - 2차 — 실패(예외를 던지지 않는다)
    - [x] 401 → 키 문구 / 403·포털 30 → 활용신청 문구 / 포털 22 → 한도 문구 / 접속 실패·시간 초과 → 접속 문구 / XML 아님 → 응답 형식 /
          그 밖 → `조회하지 못했습니다 (코드 N)`. 정상 결과 코드 `00`(`NORMAL SERVICE.`). 녹화: 등록 안 된 키는 401이 아니라 **HTTP 403 + 포털 코드 30**(→ 활용신청 문구)
    - [x] 상세 091만 실패하면 `status: found`, 9절 필드만 `fetch_failed`, 2·8절은 정상
    - [x] 키는 로그에 나오지 않는다(넣은 형태·인코딩 형태·대문자 %xx 표기 모두)
