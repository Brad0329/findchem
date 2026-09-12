# 팩: PDF 표 파싱 — 후보 지형 (조사 기록)

> **이 파일은 "무엇을 검토하고 왜 버렸나"만 담는다.** FindChem이 실제로 어떻게 파싱하는지,
> 어떤 함정을 어떻게 처리했는지는 **`work_log/Phase_003.md`가 단일 원본**이다 — 여기에 옮겨 적지 않는다.
>
> 출처: 2026-09-11 `researcher` 3갈래 병렬 조사(오픈소스·상용 API·Dart 경로). 수치는 `assets/`의 실제
> 별표 PDF 2개로 측정한 것이고, 측정하지 않은 것은 "미확인"으로 적었다.
> 쓰임새: **다시 조사하지 않기 위해서**, 그리고 라이브러리를 갈아야 할 때 후보 순서를 바로 꺼내기 위해서.

## 대상 PDF의 성질 — 후보를 거르는 기준이 된 것

- **59페이지(56+3), 이미지 0개, ToUnicode CMap 내장 = 순수 텍스트 PDF.** 스캔본이 아니라 **OCR이 필요 없다.**
- **표에 괘선이 실제로 그려져 있다.** 좌표 휴리스틱으로 셀을 추측하는 부류는 애초에 필요가 없었다.
- 이 두 성질이 딥러닝 계열과 상용 OCR API를 전부 탈락시켰다. **다른 PDF를 받게 되면 이 전제부터 다시 본다.**

## 채택 (결정과 근거의 원본은 `Phase_003.md`)

- 앱 안 = **`pdf_graphics` + `pdf_document` + `pdf_cos` 4.4.0**(Apache-2.0, 순수 Dart) 정확 고정.
- 정답지 = **pdfplumber**(`scripts/oracle_pdf_cells.py` → `test/fixtures/`). 규칙이 없는 원시 셀 격자라
  "두 번째 파서"가 아니다. 대조는 `test/parser/pdf_extractor_test.dart`.
- 그 밖의 실측 수치·성능·실패한 접근·이름 분리 한계는 전부 `Phase_003.md`에 있다.

## 탈락 후보 — 왜 버렸나

**Dart/Flutter 쪽** (더 자세한 사유는 `Phase_003.md` '다음 세션이 알아야 할 것')

| 후보 | 버린 이유 |
|---|---|
| `syncfusion_flutter_pdf` | `dart:ui` 의존이라 `dart run` 불가. Community 라이선스에 오픈소스 프로젝트 바이너리 배포 금지(4.2.n.b)·AI 에이전트 사용 금지(4.2.c.ii) 조항 |
| `pdfrx` (MIT) | 최신판이 Dart 3.13 요구(현 툴체인 3.9.2), **괘선 API 없음**, 웹은 wasm 5MB |
| `betto_pdfium` | Dart 3.13 요구로 설치 불가. v0.1.0 |
| `pdf` (nfet.net) | **생성 전용.** lib 전체에 `extractText`/`TextExtractor` 0건(실측) |
| `pdf_text` / `read_pdf_text` 계열 | Android·iOS 전용 네이티브 플러그인, **웹 불가** |
| 직접 구현 | 약 800줄 |

**서버측 Python/Java** — 정답지 후보로 비교한 것들

| 후보 | 버린 이유 |
|---|---|
| **PyMuPDF `find_tables()`** | 결과가 pdfplumber와 완전 동일. 소스 헤더에 "ported from pdfplumber" 명시 — 같은 알고리즘인데 **라이선스만 AGPL-3.0**으로 나빠진다 |
| **Camelot 2.0 (lattice)** | 연번은 맞추지만 **CJK 셀에 이중 공백 삽입**("과산화  나트륨") — 21,690셀 중 1,427개. 이슈 트래커에 **보고된 적 없는 동작**(조사자 실측). 속도도 2배 느림 |
| **tabula-py 2.10.0** | **병합 셀 행에서 컬럼이 밀린다** — 1~10쪽 513행 중 68행 오정렬. JVM 의존까지 붙는다 |
| **딥러닝 계열** (docling·marker·surya·MinerU·PP-Structure·TATR) | 괘선이 다 있는 표에 과잉. 라이선스 함정: marker·surya 가중치 **OpenRAIL-M(매출 $5M 초과 시 상용 계약)**, Nougat **CC-BY-NC(비상업)** + README에 "중국어·러시아어·일본어 등은 작동 안 함". TATR은 2023-09 이후 사실상 정지 |

## 상용 API 지형 — 지금은 안 쓴다. 파생 검토용 기록

우리 PDF 1회 변환 실비는 **최대 $1.77**(Google Form Parser, 59페이지). **가격은 의사결정 변수가 아니었다.**
기록하는 이유는, 임의의 PDF(괘선 없는 표·스캔본)를 받는 제품에서는 필요해지기 때문이다.

- **AWS Textract — 탈락.** 공식 문서의 지원 언어가 영·불·독·이·포·스페인어뿐이고 **한국어가 없다.**
  $15/1,000p(서울 리전 동일가, Price List API 실측)로 가장 쌌으나 무의미.
  함정 기록: 병합 영역의 일반 `CELL`은 전부 span=1로 나오고 병합 사실은 별도 `MERGED_CELL` 블록에만 담긴다.
- **Azure AI Document Intelligence — Layout**: 셀에 `rowIndex` + `columnIndex` + `rowSpan` + `columnSpan`
  + `kind:"columnHeader"`를 **동시에** 주는 유일한 실측 스키마 — 다단 헤더·병합 셀 표현력이 가장 좋다.
  한국어 공식 지원 확인(`ko`). 동일 리전 저장 후 24시간 뒤 삭제, 즉시 삭제 API 있음.
  **Layout 컨테이너가 온프레미스 + 완전 오프라인(disconnected)까지 지원** — 국외 이전 문제를 원천 제거.
  단 disconnected는 사전 신청서 + commitment tier(DC0) 구매가 선행. 무료 F0는 요청당 앞 2페이지뿐.
  **가격 미확인**(도메인 차단).
- **Google Document AI**: Layout Parser $10/1,000p, Form Parser $30/1,000p(2026-09-11 공식 가격 페이지 실측).
  `headerRows`/`bodyRows` 분리 + `rowSpan`/`colSpan` + `caption`. **단 셀에 인덱스가 없어** 배열 순서와 span으로
  좌표를 직접 재구성해야 한다. 한국어 지원·보관정책·쿼터 **미확인**(docs 도메인 차단).
- 온프레미스 가능한 OSS: **Unstructured(Apache-2.0)** `text_as_html`로 병합 표현 가능 /
  **Chunkr(AGPL-3.0 + 상용 듀얼)** — 자체 호스팅 시 AGPL 네트워크 조항이 걸린다.

## 재확인이 필요한 구멍

조사 환경(클라우드 세션)의 egress 프록시가 벤더 도메인 상당수를 차단했다. **뚫린 망에서 확인한다.**

1. **국내 서비스 전무 조사** — Upstage Document Parse, 네이버 CLOVA OCR 모두 도메인 차단.
   **한글 표 처리에 유리할 가능성이 있어 재조사 가치가 가장 크다.**
   (Upstage는 `langchain-upstage` 2026-03-05 릴리스로 운영 중인 것만 확인.)
2. Azure Layout 실단가 + F0 한도 — `azure.microsoft.com/pricing/details/ai-document-intelligence/`
3. Google Document AI 한국어 지원 — `docs.cloud.google.com/document-ai/docs/languages`
4. LlamaParse 현행 과금 — 벤더 README(2026-02)는 "1,000p/일 무료 + 0.3¢/추가 페이지"인데 검색 요약에는
   크레딧제가 나온다. **체계가 바뀐 것으로 보이니 확정 전 재확인.**
5. Adobe PDF Extract 전반 — 도메인 차단으로 아무것도 확인 못 함

## 재조사 방법 (차단 환경에서도 통한 경로)

```
curl -sL https://pricing.us-east-1.amazonaws.com/offers/v1.0/aws/AmazonTextract/current/index.json
curl -sL https://cloud.google.com/document-ai/pricing          # /docs/ 경로는 차단됨
curl -sL 'https://documentai.googleapis.com/$discovery/rest?version=v1'
# Azure 공식 문서 원본: raw.githubusercontent.com/MicrosoftDocs/azure-ai-docs/main/articles/
#   ai-services/document-intelligence/{prebuilt/layout.md, language-support/ocr.md, containers/*.md}
# GitHub 메타데이터(API 차단 시): 저장소 HTML + /commits.atom
# 업체 생존 확인: https://pypi.org/pypi/<패키지>/json 의 releases 업로드 일자
```
