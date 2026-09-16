/// F-008 2단계 — LLM이 부르는 **도구의 실행부**와, 그 결과에서 뽑은 **근거**.
///
/// 도구 응답 JSON은 1단계의 [searchResponse]ㆍ[ruleResponse]를 그대로 쓴다 —
/// `scripts/search_cli.dart`(개발 하네스)와 **같은 함수**라 대조 테스트가 필요 없다(구현이 하나다).
///
/// 근거는 모델의 문장이 아니라 **도구가 돌려준 값**에서 만든다(REQUIREMENTS F-008 결정 5) —
/// 화면이 이것을 그리므로 모델이 인용을 빠뜨려도 근거가 사라지지 않는다.
library;

import 'package:flutter/foundation.dart';

import '../parser/models.dart';
import '../search/search.dart';
import 'assist_response.dart';
import 'prompt.dart';
import 'rules.dart';

/// 판정 도구의 검색 상한. **F-001 검색 화면(100)과 다르다** — 넓은 질의 한 번이 55,211 입력 토큰이었고
/// 대화는 왕복마다 재전송된다(2026-09-16 `count_tokens` 실측, REQUIREMENTS F-008 2단계 수용 기준).
/// 상한을 넘으면 `truncated`ㆍ`total`이 응답에 남는다 — 조용한 절단이 아니다.
const assistSearchCap = 20;

/// 도구 실행 결과 한 건. 실패해도 루프는 이어진다(모델에 `is_error`로 알린다).
class ToolOutcome {
  const ToolOutcome({required this.name, required this.response, this.error});

  final String name;

  /// 모델에 돌려줄 JSON. 실패면 사유만 담는다.
  final Map<String, Object?> response;

  /// 실패 사유(모델에는 `is_error: true`로 간다).
  final String? error;

  bool get isError => error != null;
}

/// 도구 실행부. 데이터셋 하나를 잡고 산다(화면이 데이터를 바꾸면 새로 만든다).
class AssistTools {
  AssistTools(this.dataset) : _index = SearchIndex(dataset, cap: assistSearchCap);

  final Dataset dataset;
  final SearchIndex _index;

  /// [name] 도구를 [input]으로 실행한다. **예외를 밖으로 던지지 않는다** — 실패도 결과로 돌려준다.
  ToolOutcome run(String name, Map<String, Object?> input) {
    try {
      switch (name) {
        case ToolName.search:
          final query = input['query'];
          if (query is! String || query.trim().isEmpty) {
            return ToolOutcome(name: name, response: const {}, error: 'query는 비어 있지 않은 문자열이어야 합니다');
          }
          return ToolOutcome(name: name, response: searchResponse(_index.search(query), dataset));
        case ToolName.rule:
          final topic = input['topic'];
          if (topic != null && topic is! String) {
            return ToolOutcome(name: name, response: const {}, error: 'topic은 문자열이어야 합니다');
          }
          return ToolOutcome(name: name, response: ruleResponse((topic as String?) ?? 'all'));
        default:
          return ToolOutcome(name: name, response: const {}, error: '알 수 없는 도구: $name');
      }
    } on UnknownRuleTopic catch (e) {
      // 알 수 없는 주제를 전체로 조용히 대체하지 않는다(1단계 수용 기준) — 모델에 사유를 돌려주고 다시 부르게 한다.
      return ToolOutcome(name: name, response: const {}, error: e.toString());
    } catch (e, st) {
      debugPrint('F-008 도구 실행 실패($name): $e\n$st');
      return ToolOutcome(name: name, response: const {}, error: '도구 실행에 실패했습니다: ${e.runtimeType}');
    }
  }
}

// ───── 근거 ─────

/// 근거 칸의 수량 행 한 줄.
class EvidenceRow {
  const EvidenceRow({
    required this.kind,
    required this.content,
    required this.min,
    required this.low,
    required this.high,
  });

  final String kind;
  final String content;
  final String min;
  final String low;
  final String high;

  static EvidenceRow? fromJson(Object? j) {
    if (j is! Map) return null;
    String s(String k) => j[k] is String ? j[k] as String : '';
    return EvidenceRow(kind: s('kind'), content: s('content'), min: s('min'), low: s('low'), high: s('high'));
  }
}

/// 근거 칸의 물질 한 줄(검색 도구가 돌려준 항목 하나).
class EvidenceSubstance {
  const EvidenceSubstance({
    required this.srcLabel,
    required this.no,
    required this.name,
    required this.rows,
  });

  /// 화면 용어('사고대비물질' / '인체·생태 유해성'). 도구 응답의 `srcLabel`을 그대로 쓴다.
  final String srcLabel;
  final int no;
  final String name;
  final List<EvidenceRow> rows;
}

/// 이번 답을 만들며 호출된 도구 결과. 화면이 이것을 그린다.
class Evidence {
  const Evidence({
    required this.substances,
    required this.ruleTopics,
    required this.notice,
    required this.toolCalls,
    required this.failures,
  });

  static const empty = Evidence(
    substances: [],
    ruleTopics: [],
    notice: null,
    toolCalls: 0,
    failures: [],
  );

  final List<EvidenceSubstance> substances;

  /// 쓰인 규칙 주제(호출 순서, 중복 없음).
  final List<String> ruleTopics;

  /// 고시명. 도구를 한 번이라도 불렀으면 응답에서 온다.
  final String? notice;

  /// 도구 호출 횟수. **0이면 화면이 "도구를 부르지 않은 답"을 보인다**(REQUIREMENTS F-008 결정 5).
  final int toolCalls;

  /// 실패한 도구 호출의 사유(조용히 삼키지 않는다).
  final List<String> failures;

  bool get isEmpty => toolCalls == 0;
}

/// 도구 결과들을 근거로 모은다. 같은 항목이 여러 번 걸리면 한 줄로 합친다(같은 표ㆍ같은 연번).
Evidence evidenceOf(Iterable<ToolOutcome> outcomes) {
  final substances = <String, EvidenceSubstance>{};
  final topics = <String>[];
  final failures = <String>[];
  String? notice;
  var calls = 0;

  for (final o in outcomes) {
    calls++;
    if (o.isError) {
      failures.add('${o.name}: ${o.error}');
      continue;
    }
    final r = o.response;
    final n = r['notice'] ?? (r['source'] is Map ? (r['source'] as Map)['notice'] : null);
    if (n is String) notice ??= n;

    if (o.name == ToolName.rule) {
      final topic = r['topic'];
      if (topic is String && !topics.contains(topic)) topics.add(topic);
      continue;
    }

    final hits = r['hits'];
    if (hits is! List) continue;
    for (final h in hits) {
      if (h is! Map) continue;
      final src = h['srcLabel'] is String ? h['srcLabel'] as String : '';
      final no = h['no'] is int ? h['no'] as int : -1;
      final key = '$src/$no';
      if (substances.containsKey(key)) continue;
      final rows = <EvidenceRow>[];
      if (h['rows'] case final List list) {
        for (final row in list) {
          final e = EvidenceRow.fromJson(row);
          if (e != null) rows.add(e);
        }
      }
      substances[key] = EvidenceSubstance(
        srcLabel: src,
        no: no,
        name: (h['ko'] is String && (h['ko'] as String).isNotEmpty)
            ? h['ko'] as String
            : (h['name'] is String ? h['name'] as String : ''),
        rows: rows,
      );
    }
  }

  return Evidence(
    substances: substances.values.toList(growable: false),
    ruleTopics: topics,
    notice: notice,
    toolCalls: calls,
    failures: failures,
  );
}
