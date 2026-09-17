/// F-008 규정수량 판정 도우미 — **도구 응답 조립**.
///
/// 검색 결과(`lib/search/`)에 판정에 필요한 것을 얹어 JSON 한 덩어리로 만든다:
/// 행별 적용 조건([conditionOf])ㆍ배타적 선택지([selectionOf])ㆍ커버리지 선언ㆍ값의 뜻([legend]).
///
/// **이 함수가 원본이다** — `scripts/search_cli.dart`(개발 하네스)와 2단계의 앱ㆍ웹 tool use가
/// 같은 함수를 부른다(REQUIREMENTS F-008 '구현 위치 원칙 — 두 번째 구현 금지').
library;

import '../parser/models.dart';
import '../search/search.dart';
import 'conditions.dart';
import 'rules.dart';

/// CAS 형식인데 0건일 때의 안내. 원본은 `SearchPage.casNoHit`(lib/ui/search_page.dart) —
/// UI는 Flutter라 `dart run`으로 도는 CLI가 import할 수 없어 문장을 옮겨 적었다.
const casNoHitHint = '염류·화합물 묶음 항목에 해당할 수 있으니 물질명으로도 검색해 보세요';

/// 판정 도구의 검색 상한. **F-001 검색 화면(100)과 다르다** — 넓은 질의 한 번이 55,211 입력 토큰이었고
/// 대화는 왕복마다 재전송된다(2026-09-16 `count_tokens` 실측, REQUIREMENTS F-008 2단계 수용 기준).
/// 상한을 넘으면 `truncated`ㆍ`total`이 응답에 남는다 — 조용한 절단이 아니다.
///
/// **20 → 10 (2026-09-17 사용자 결정).** 정확 일치 우선 정렬을 넣은 뒤 `scripts/rank_probe.dart`로
/// 재면 살아있는 1,638건의 자기 순위가 전부 2위 이내라, 10으로 잘라도 찾는 물질이 사라지지 않는다.
/// **정렬을 되돌리면 이 값도 되돌려야 한다** — 정렬 없이 10이면 칠 건(칼륨ㆍ황산ㆍ붕산ㆍ염소ㆍ나프탈렌ㆍ
/// 코발트ㆍ아세트산)이 자기 이름으로 검색해도 안 보인다.
///
/// **응답 조립과 같은 파일에 둔다** — 앱(`lib/assist/tools.dart`)과 개발 하네스(`scripts/search_cli.dart`)가
/// 같은 상수를 봐야 같은 건수를 돌려준다. `tools.dart`는 Flutter를 import해서 CLI가 읽어갈 수 없다.
const assistSearchCap = 10;

/// 이 도구가 덮는 범위. **모든 응답에 싣는다** — "없으면 없다"고 빠져나갈 수 있어야 한다.
const coverageStatement =
    '이 도구는 「유해화학물질의 규정수량에 관한 규정」의 별표 2(인체ㆍ생태 유해성)와 별표 3(사고대비물질)만 덮는다. '
    '여기 없는 물질은 이 고시의 규정수량 대상이 아니다. '
    '다만 개별 CAS 없이 묶음으로 규정된 항목(염류ㆍ"~와 그 화합물")이 있어, CAS로 0건이면 물질명으로도 찾아본다.';

/// 커버리지 상태. 0건과 "부분 일치만 걸림"을 서로 다른 상태로 돌려준다(spike C1).
enum Coverage {
  /// 질의가 물질명(국문ㆍ영문ㆍ원문) 또는 CAS와 정확히 일치하는 항목이 있다.
  exact('exact', '질의와 정확히 일치하는(이름 전체 또는 CAS) 항목이 있다.'),

  /// 정확 일치 없이 부분 일치만 있다.
  partialOnly(
    'partial_only',
    '정확히 일치하는 항목이 없고 부분 일치만 있다 — 부분 일치는 이름 일부만 같은 **별개 물질**일 수 있다. '
        '질문한 물질 자체의 항목인지 이름을 확인해야 한다.',
  ),

  /// 0건.
  none('none', '별표 2ㆍ3에서 0건이다. 규정수량을 지어내지 말고 "이 고시 별표 2ㆍ3에 개별 항목이 없다"고 답한다.');

  const Coverage(this.id, this.note);

  /// JSON 값.
  final String id;

  /// 읽는 쪽에 주는 설명.
  final String note;
}

/// 값의 뜻과 단위를 읽는 쪽이 잃지 않도록 응답에 함께 싣는다.
///
/// **설명 없는 필드는 버려진다** — spike ③ 실측(2026-09-16, Sonnet 5): 설명해 둔 별표(*)는 정확히
/// 해석했고(D2), 설명이 없던 `priority`/`referenceNote`는 무시한 채 "더 엄격한 쪽을 적용"이라는
/// 고시에 없는 규칙을 지어냈다(D3). 그래서 판정에 쓰이는 필드는 전부 여기에 적는다.
const legend = {
  'kind': '유해성 구분(별표2: 급성/만성/생태/저확산/용액 등). 별표3은 구분 열이 없어 빈 문자열이거나 '
      "물질명 원문('암모니아 용액')이다",
  'content': '함량기준(% 이상). 고시 원문 문자열 그대로. 빈 문자열이면 그 행의 condition을 읽는다',
  'min': '최하위 규정수량(톤)',
  'low': '하위 규정수량(톤)',
  'high': '상위 규정수량(톤)',
  'condition': '**이 행을 언제 적용하는가.** 그 행의 원문 필드와 별표 1ㆍ2ㆍ3ㆍ4 원문에서만 만든 문장이다 '
      '— 값을 고르기 전에 반드시 읽는다. 규칙 전문은 get_rule로 본다',
  'selection': '이 항목에 수량 행이 둘 이상일 때만 있다. required=true면 성상ㆍ구분을 확인해야 행이 정해진다 '
      '— 확인할 수 없으면 **하나를 고르지 말고 되묻거나 갈래를 모두 제시한다**. choices의 row는 rows 배열의 첨자',
  'priority': 'true면 이 항목(사고대비물질)의 규정수량을 적용한다 — 같은 CAS가 인체·생태 유해성 표에도 '
      '있을 때 사고대비물질이 우선한다(별표2 일반기준 가). 두 표의 값 중 작은 쪽을 고르는 것이 아니다',
  'referenceNote': 'true면 이 항목(인체·생태 유해성)은 참고값이다 — 같은 CAS가 사고대비물질 표에도 있어 '
      '그쪽 규정수량이 우선 적용된다',
  'deleted': 'true면 고시에서 (삭제)된 항목이라 적용할 규정수량이 없다',
  'coverage': '이 도구가 덮는 범위와 이번 질의의 일치 상태(exact / partial_only / none)',
  'truncated': 'true면 결과를 상한까지만 돌려줬다는 뜻이다 — 전체 건수는 total이다',
  'note': '수량은 고시 원문 문자열 그대로다("-"는 해당 없음, "0.2*"는 별표 비고 표시). '
      '계산·반올림·단위 변환을 하지 않았다. 규정수량은 기간 처리량이 아니라 어느 순간의 최대 체류량 기준이다.',
};

bool _isExactHit(String query, Entry e) {
  final q = SearchIndex.normalize(query);
  if (q.isEmpty) return false;
  if (SearchIndex.normalize(e.ko) == q ||
      SearchIndex.normalize(e.en) == q ||
      SearchIndex.normalize(e.name) == q) {
    return true;
  }
  final digits = SearchIndex.casDigits(q);
  return e.cas.any((c) => SearchIndex.casDigits(c) == digits);
}

/// 이번 질의의 커버리지 상태.
Coverage coverageOf(SearchResult result) {
  if (result.total == 0) return Coverage.none;
  return result.hits.any((h) => _isExactHit(result.query, h.entry))
      ? Coverage.exact
      : Coverage.partialOnly;
}

/// 검색 도구의 응답 JSON. CLIㆍ앱ㆍ웹이 모두 이것을 쓴다.
Map<String, Object?> searchResponse(SearchResult result, Dataset ds) {
  final coverage = coverageOf(result);
  return {
    'query': result.query,
    'total': result.total,
    'returned': result.hits.length,
    // 상한(SearchIndex.cap)을 넘겨 잘렸다는 사실. total과 함께 본다(조용한 절단 금지).
    'truncated': result.truncated,
    'countByeolpyo2': result.count2,
    'countByeolpyo3': result.count3,
    if (result.casQueryNoHit) 'hint': casNoHitHint,
    'coverage': {
      'status': coverage.id,
      'statement': coverageStatement,
      'note': coverage.note,
      if (result.truncated)
        'truncationNote': '결과가 상한까지만 왔다 — 정확 일치 항목이 상한 밖에 있을 수 있으니 질의를 좁혀 다시 찾는다',
    },
    'hits': [
      for (final h in result.hits)
        {
          ...h.entry.toJson(),
          'srcLabel': h.entry.src.label,
          'rows': [
            for (final r in h.entry.rows) {...r.toJson(), 'condition': conditionOf(h.entry, r)},
          ],
          if (selectionOf(h.entry) case final s?) 'selection': s,
          // 같은 CAS가 두 표에 있을 때: 별표3 항목이 우선 적용되고, 별표2 항목은 참고값이다.
          'priority': h.priority,
          'referenceNote': h.referenceNote,
        },
    ],
    'legend': legend,
    'rules': {
      'howToRead': '행을 고르는 규칙의 원문은 get_rule로 본다. 주제는 아래와 같다',
      'topics': {for (final t in ruleTopics) t: ruleTopicSummaries[t]},
    },
    'source': {
      'notice': notice,
      'byeolpyo2': ds.byeolpyo2.toJson(),
      'byeolpyo3': ds.byeolpyo3.toJson(),
      'extractedAt': ds.extractedAt,
    },
  };
}
