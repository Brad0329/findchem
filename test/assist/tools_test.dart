/// F-008 2단계 수용 기준 — 도구 실행부(상한 20·실패 처리)와 근거 추출. 실제 번들 데이터에 직접 질의한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/assist/prompt.dart';
import 'package:findchem/assist/tools.dart';
import 'package:findchem/parser/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AssistTools tools;

  setUpAll(() {
    final ds = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
    tools = AssistTools(ds);
  });

  group('검색 도구', () {
    test('상한은 20건이고, 넘으면 잘랐다는 사실과 전체 건수가 함께 온다(조용한 절단 금지)', () {
      final r = tools.run(ToolName.search, {'query': 'acid'}).response;
      expect(assistSearchCap, 20);
      expect(r['returned'], 20);
      expect(r['truncated'], true);
      expect(r['total'], greaterThan(20));
      expect((r['hits']! as List).length, 20);
    });

    test('상한 안쪽이면 자르지 않는다', () {
      final r = tools.run(ToolName.search, {'query': '7664-41-7'}).response;
      expect(r['truncated'], false);
      expect(r['returned'], r['total']);
    });

    test('빈 질의는 실패로 돌려준다(예외를 밖으로 던지지 않는다)', () {
      final o = tools.run(ToolName.search, {'query': '  '});
      expect(o.isError, true);
      expect(o.error, contains('query'));
    });
  });

  group('규칙 도구', () {
    test('주제를 안 주면 전체, 모르는 주제는 실패 — 조용히 전체로 대체하지 않는다', () {
      expect(tools.run(ToolName.rule, {}).response['topic'], 'all');
      expect(tools.run(ToolName.rule, {'topic': 'byeolpyo4'}).response['topic'], 'byeolpyo4');

      final o = tools.run(ToolName.rule, {'topic': '없는주제'});
      expect(o.isError, true);
      expect(o.error, contains('알 수 없는 규칙 주제'));
    });
  });

  test('모르는 도구 이름은 실패로 돌려준다', () {
    final o = tools.run('drop_table', const {});
    expect(o.isError, true);
    expect(o.error, contains('알 수 없는 도구'));
  });

  group('근거', () {
    test('도구 호출 3건 + 규칙 1건이면 물질 줄과 규칙 줄이 나온다', () {
      final outcomes = [
        tools.run(ToolName.search, {'query': '7664-41-7'}), // 암모니아 — 두 표에 있다
        tools.run(ToolName.search, {'query': '108-88-3'}), // 톨루엔
        tools.run(ToolName.search, {'query': '7664-93-9'}), // 황산
        tools.run(ToolName.rule, {'topic': 'byeolpyo3'}),
      ];
      final e = evidenceOf(outcomes);

      expect(e.toolCalls, 4);
      expect(e.isEmpty, false);
      expect(e.ruleTopics, ['byeolpyo3']);
      expect(e.notice, contains('규정수량에 관한 규정'));
      expect(e.failures, isEmpty);

      // 물질 줄은 도구가 돌려준 항목 그대로다(암모니아는 별표 2·3 둘 다 걸린다).
      expect(e.substances.length, greaterThanOrEqualTo(3));
      final ammonia = e.substances.firstWhere((s) => s.no == 44);
      expect(ammonia.srcLabel, '사고대비물질');
      expect(ammonia.name, '암모니아');
      // 수량은 원문 문자열 그대로 — 별표(*)가 살아 있다.
      expect(ammonia.rows.map((r) => r.min), ['0.05', '0.5*']);
      expect(ammonia.rows.first.content, '10');
      expect(ammonia.rows.last.content, '');
    });

    test('도구를 한 번도 안 부르면 비어 있다(화면이 "도구를 부르지 않은 답"을 보인다)', () {
      expect(evidenceOf(const []).isEmpty, true);
      expect(evidenceOf(const []).toolCalls, 0);
    });

    test('실패한 호출은 삼키지 않고 사유를 남긴다', () {
      final e = evidenceOf([tools.run(ToolName.rule, {'topic': '없는주제'})]);
      expect(e.toolCalls, 1);
      expect(e.failures.single, contains('알 수 없는 규칙 주제'));
    });
  });
}
