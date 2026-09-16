// MCP 서버 spike ①(plan.md '보류 항목 · MCP 서버 spike') — 질의 하나를 받아 결과 JSON을 stdout에 낸다.
//
//   dart run scripts/search_cli.dart "<질의>"
//
// - 검색·정규화·CAS 처리·우선순위 판정은 **앱과 같은 코드**(lib/search/search.dart)를 부른다.
//   여기서 다시 구현하지 않는다(CLAUDE.md '같은 규칙이 두 곳' — 재구현하면 대조 테스트가 또 필요해진다).
// - 번들 JSON 하나만 읽는다. 기기 저장본(F-002)은 보지 않는다 — spike 범위.
// - 판정(합산·초과 비교)은 하지 않는다. 조합을 LLM이 하는지 보는 것이 spike의 목적이다.
// - Flutter에 의존하는 것(lib/ui)은 import하지 않는다 — `dart run`으로 돌아야 한다.
import 'dart:convert';
import 'dart:io';

import 'package:findchem/parser/models.dart';
import 'package:findchem/search/search.dart';

const dataPath = 'assets/data/findchem_data.json';

/// 고시명의 원본은 docs/REQUIREMENTS.md '시스템 목표'다. 번들 JSON에는 고시 번호가 없다(PDF 본문에 없어서 —
/// plan.md '외부 원천 조사'). 답에 근거를 싣기 위해 CLI가 붙인다.
const notice = '화학물질안전원고시 「유해화학물질의 규정수량에 관한 규정」(2026-09-15 확인 현행: 제2025-12호, 2025-08-07 시행)';

/// CAS 형식인데 0건일 때의 안내. 원본은 `SearchPage.casNoHit`(lib/ui/search_page.dart) —
/// UI는 Flutter라 import할 수 없어 문장을 옮겨 적었다(spike 한정).
const casNoHitHint = '염류·화합물 묶음 항목에 해당할 수 있으니 물질명으로도 검색해 보세요';

/// 값의 뜻과 단위를 읽는 쪽이 잃지 않도록 응답에 함께 싣는다.
///
/// **설명 없는 필드는 버려진다** — spike ③ 실측(2026-09-16, Sonnet 5): 설명해 둔 별표(*)는 정확히
/// 해석했고(D2), 설명이 없던 `priority`/`referenceNote`는 무시한 채 "더 엄격한 쪽을 적용"이라는
/// 고시에 없는 규칙을 지어냈다(D3). 그래서 판정에 쓰이는 필드는 전부 여기에 적는다.
const legend = {
  'kind': '유해성 구분(별표2: 급성/만성/생태 등). 별표3은 빈 문자열',
  'content': '함량기준(% 이상). 고시 원문 문자열 그대로',
  'min': '최하위 규정수량(톤)',
  'low': '하위 규정수량(톤)',
  'high': '상위 규정수량(톤)',
  'priority': 'true면 이 항목(사고대비물질)의 규정수량을 적용한다 — 같은 CAS가 인체·생태 유해성 표에도 '
      '있을 때 사고대비물질이 우선한다(별표2 일반기준 가). 두 표의 값 중 작은 쪽을 고르는 것이 아니다',
  'referenceNote': 'true면 이 항목(인체·생태 유해성)은 참고값이다 — 같은 CAS가 사고대비물질 표에도 있어 '
      '그쪽 규정수량이 우선 적용된다',
  'deleted': 'true면 고시에서 (삭제)된 항목이라 적용할 규정수량이 없다',
  'note': '수량은 고시 원문 문자열 그대로다("-"는 해당 없음, "0.2*"는 별표 비고 표시). '
      '계산·반올림·단위 변환을 하지 않았다. 규정수량은 기간 처리량이 아니라 어느 순간의 최대 체류량 기준이다.',
};

/// [dataPath]를 현재 디렉토리 기준으로 찾고, 없으면 이 스크립트 위치(scripts/) 기준으로 한 번 더 찾는다.
/// MCP 서버가 다른 작업 디렉토리에서 부를 수 있어서다.
File findData() {
  final fromCwd = File(dataPath);
  if (fromCwd.existsSync()) return fromCwd;
  final fromScript = File.fromUri(Platform.script.resolve('../$dataPath'));
  if (fromScript.existsSync()) return fromScript;
  fail('번들 JSON을 찾지 못했습니다: ${fromCwd.absolute.path} / ${fromScript.path}');
}

Never fail(String message) {
  stderr.add(utf8.encode('$message\n'));
  exit(2);
}

void main(List<String> args) {
  if (args.length != 1 || args.single.trim().isEmpty) {
    fail('사용법: dart run scripts/search_cli.dart "<물질명 또는 CAS>"');
  }
  final query = args.single;

  final file = findData();
  final Dataset ds;
  try {
    ds = Dataset.fromJson((jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>());
  } on FormatException catch (e) {
    fail('번들 JSON을 읽지 못했습니다(${file.path}): $e');
  }

  final result = SearchIndex(ds).search(query);
  final out = <String, Object?>{
    'query': result.query,
    'total': result.total,
    'returned': result.hits.length,
    // 상한(SearchIndex.cap)을 넘겨 잘렸다는 사실. total과 함께 본다(조용한 절단 금지).
    'truncated': result.truncated,
    'countByeolpyo2': result.count2,
    'countByeolpyo3': result.count3,
    if (result.casQueryNoHit) 'hint': casNoHitHint,
    'hits': [
      for (final h in result.hits)
        {
          ...h.entry.toJson(),
          'srcLabel': h.entry.src.label,
          // 같은 CAS가 두 표에 있을 때: 별표3 항목이 우선 적용되고, 별표2 항목은 참고값이다.
          'priority': h.priority,
          'referenceNote': h.referenceNote,
        },
    ],
    'legend': legend,
    'source': {
      'notice': notice,
      'byeolpyo2': ds.byeolpyo2.toJson(),
      'byeolpyo3': ds.byeolpyo3.toJson(),
      'extractedAt': ds.extractedAt,
    },
  };

  stdout.add(utf8.encode('${const JsonEncoder.withIndent('  ').convert(out)}\n'));
}
