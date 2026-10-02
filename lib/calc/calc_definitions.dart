/// A-004 계산 도구의 **설명과 입력 스키마** — MCP `tools/list`가 이것을 싣는다.
/// 설명한 필드는 쓰이고 설명 안 한 필드는 버려진다(spike ③) — 응답 필드도 여기서 설명한다.
library;

import 'calc.dart';

const _facilityCommon = <String, Object?>{
  'src': {'type': 'string', 'enum': ['별표2', '별표3'], 'description': 'search_chemical 결과의 표(srcLabel이 아니라 src 값)'},
  'no': {'type': 'integer', 'description': 'search_chemical 결과의 연번ㆍ번호'},
  'content_pct': {'type': 'number', 'description': '함량(%). 순물질이면 100. 함량기준 비교에만 쓰고 양에 곱하지 않는다'},
  'capacity_m3': {'type': 'number', 'description': '설계용량(m³). specific_gravity와 함께'},
  'specific_gravity': {
    'type': 'number',
    'description': '비중(물=1 상대밀도, 상온). g/L이면 1000으로 나눠 넣는다. 혼합물 비중은 시험값ㆍ계산값 증빙이 있을 때만',
  },
  'basis': {'type': 'string', 'description': '양을 직접 줄 때의 산정 근거(예: 실린더 충전량 50kg × 2, 보관구획도)'},
  'low_diffusion': {
    'type': 'boolean',
    'description': "저확산 행이 있는 물질에서만 — 취급 과정 성상이 액체ㆍ고체라 '저확산' 행을 적용하면 true(별표 2 일반기준 다)",
  },
};

const levelToolDescription = '''사업장의 작성수준(1군ㆍ2군)을 계산한다 — 별지 제1호서식 '사업장의 작성수준 구분'.
설비마다 취급량(톤) = 설계용량(m³) × 비중을 내고, 물질별로 합해 규정수량 고시의 하위ㆍ상위 규정수량과 비교한다(경계는 이상).
규정수량은 넣지 않는다 — 물질을 src+no로 주면 데이터에서 읽는다. 먼저 search_chemical로 src와 no를 확인할 것.
- 함량은 곱하지 않는다(혼합물도 전체 양). 함량이 그 행의 함량기준 미만이면 그 설비는 그 행에서 빠진다(status 함량미만).
- 유해성 구분 행(급성ㆍ만성ㆍ생태)이 여럿이면 행마다 따로 합해 비교하고 가장 높은 판정을 쓴다.
- 용액ㆍ* 행이 있는 물질은 ambient_liquid, 저확산 행이 있는 물질은 low_diffusion을 정해 줘야 한다 — 없으면 그 설비는
  selection_required로 돌아오고 판정은 incomplete다. 임의로 고르지 말고 사용자에게 성상을 확인할 것.
- 기상물질(운전조건 환산)ㆍ보관시설은 quantity_ton + basis로 양을 직접 준다. 탱크로리ㆍ사외배관ㆍ취급중단 신고 시설은 넣지 않는다.
응답: level(1군|2군|미해당, incomplete면 null), issues(오류ㆍ선택 필요 설비), facilities(설비별 amount_ton, formula, status,
rows_applied, notes), substances(물질별 max_holding_ton, 행별 total_ton과 판정, decisive_row, low/high = 별지 1 구분 근거,
excluded_from_level = 별표 4 비고 3 나로 결정에서 뺀 저확산 물질). 숫자는 응답 값을 그대로 옮긴다.''';

const scenarioToolDescription = '''설비별로 예비시나리오 대상인지 가린다 — 작성 규정 제23조ㆍ별표 2(장외평가 시나리오 대상 산정표).
취급량(kg) = 설계용량(m³) × 비중 × 1000을 운전조건 성상의 예비시나리오 규정수량과 비교한다
(고체 2,000kg / 액체 400kg / 기체 독성구분 1ㆍ2 5kg, 3 100kg, 구분 없음 100kg / 액화가스는 기체 규정수량).
판정 verdict: 표준시설(규정수량 이상 — 대상) / 소량시설(미만) / 함량미만(그 물질의 가장 낮은 함량기준 미만) /
미대상(low_diffusion: true — 저확산물질 설비는 선정하지 않는다) / selection_required(저확산 행이 있는 물질인데
low_diffusion을 안 줌 — 성상을 확인해 다시 부를 것) / error. 하나라도 error·selection_required면 status incomplete. 탱크로리도 대상 설비다.
가스처럼 용량×비중이 아니면 quantity_kg + basis로 양을 직접 준다. 급성독성 구분은 MSDS(get_msds 2절)에서 확인해 넣는다.
영향범위(장외 여부 = 사고시나리오)는 이 도구가 정하지 않는다 — KORA 결과를 쓴다.''';

List<Map<String, Object?>> calcToolDefinitions() => [
      {
        'name': CalcToolName.level,
        'description': levelToolDescription,
        'input_schema': {
          'type': 'object',
          'properties': {
            'facilities': {
              'type': 'array',
              'description': '취급시설 목록(한 설비에 물질이 여럿이면 물질마다 한 줄). 최대 $calcFacilityCap개',
              'items': {
                'type': 'object',
                'properties': {
                  'unit_plant': {'type': 'string', 'description': '단위공장'},
                  'facility': {'type': 'string', 'description': '취급시설 이름ㆍ구분기호'},
                  ..._facilityCommon,
                  'quantity_ton': {'type': 'number', 'description': '용량×비중이 아닐 때 직접 준 양(톤). basis 필수'},
                  'ambient_liquid': {
                    'type': 'boolean',
                    'description': '용액ㆍ* 행이 있는 물질에서만 — 상온ㆍ상압 성상이 액체면 true(별표 2 일반기준 나 / 별표 3 일반기준 가)',
                  },
                },
                'required': ['src', 'no', 'content_pct'],
              },
            },
          },
          'required': ['facilities'],
        },
      },
      {
        'name': CalcToolName.scenario,
        'description': scenarioToolDescription,
        'input_schema': {
          'type': 'object',
          'properties': {
            'facilities': {
              'type': 'array',
              'description': '예비시나리오 후보 설비 목록(고정 설비ㆍ탱크로리). 최대 $calcFacilityCap개',
              'items': {
                'type': 'object',
                'properties': {
                  'facility': {'type': 'string', 'description': '설비 이름ㆍ구분기호'},
                  ..._facilityCommon,
                  'quantity_kg': {'type': 'number', 'description': '용량×비중이 아닐 때 직접 준 양(kg). basis 필수'},
                  'phase': {
                    'type': 'string',
                    'enum': ['고체', '액체', '기체', '액화가스'],
                    'description': '운전조건의 성상(상온ㆍ상압 아님 — 별표 2 비고 1)',
                  },
                  'acute_toxicity_category': {
                    'type': 'integer',
                    'description': '기체ㆍ액화가스의 급성독성 구분(1~5). 없으면 생략 — 100kg 적용',
                  },
                },
                'required': ['src', 'no', 'content_pct', 'phase'],
              },
            },
          },
          'required': ['facilities'],
        },
      },
    ];
