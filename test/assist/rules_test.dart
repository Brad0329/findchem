/// F-008 1단계 수용 기준 — 규칙 원문 자산(`lib/assist/rules.dart`)이 PDF 원문과 줄 단위로 같은지.
///
/// 손으로 옮긴 데이터에는 자동 검증을 붙인다(CLAUDE.md 불변 규칙). 정답지는 pdfplumber가 굽는다 —
/// `python scripts/oracle_rule_text.py` → `test/fixtures/rule_text.json`.
/// 대조 방식: **공백을 지운 원문 줄이 상수 안에 그대로 있는가.** 줄바꿈만 다시 흘린 상수는 통과하고,
/// 글자가 빠지거나 바뀌면 걸린다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/assist/rules.dart';
import 'package:findchem/parser/models.dart';
import 'package:flutter_test/flutter_test.dart';

String norm(String s) => s.replaceAll(RegExp(r'\s+'), '');

void main() {
  late Map<String, Object?> oracle;
  late Dataset ds;

  setUpAll(() {
    oracle = (jsonDecode(File('test/fixtures/rule_text.json').readAsStringSync()) as Map)
        .cast<String, Object?>();
    ds = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map)
          .cast<String, Object?>(),
    );
  });

  Map<String, Object?> region(String topic) => (oracle[topic] as Map).cast<String, Object?>();

  test('정답지와 자산이 같은 주제 집합을 덮는다', () {
    expect(oracle.keys.toSet(), rules.keys.toSet());
    expect(ruleTopics.toSet(), rules.keys.toSet());
    for (final t in ruleTopics) {
      expect(ruleTopicSummaries[t], isNotNull, reason: '$t에 설명이 없다 — 설명 없는 필드는 버려진다');
    }
  });

  for (final topic in ['byeolpyo2', 'byeolpyo3', 'byeolpyo4', 'byeolpyo1']) {
    test('$topic: PDF 원문의 모든 줄이 상수 안에 그대로 있다', () {
      final lines = (region(topic)['lines'] as List).cast<String>();
      expect(lines, isNotEmpty);
      final haystack = norm(rules[topic]!);
      for (final ln in lines) {
        expect(
          haystack.contains(norm(ln)),
          isTrue,
          reason: '$topic 상수에 없는 원문 줄 → ${jsonEncode(ln)} (${region(topic)['file']})',
        );
      }
    });
  }

  test('대조에서 뺀 줄은 별표 4의 수식 영역 16줄뿐이고, 그 내용은 여기서 직접 확인한다', () {
    // 수식 글꼴(PUA 글리프)은 문자로 복원할 수 없어 공식을 그림 보고 옮겼고, 아래첨자가 떨어져 나가
    // 갈라진 줄 2개는 상수에서 합쳐 적었다. 줄 대조가 못 덮는 그 자리를 아래에서 직접 건다 —
    // 제외가 소리 없이 늘면 이 수가 먼저 틀린다(조용한 절단 금지).
    for (final topic in ['byeolpyo2', 'byeolpyo3', 'byeolpyo1']) {
      expect(region(topic)['excluded'], isEmpty, reason: topic);
    }
    expect((region('byeolpyo4')['excluded'] as List).length, 16);
    final b4 = norm(rules['byeolpyo4']!);
    expect(b4, contains(norm('R = Q1/QLLT1 + Q2/QLLT2 + Q3/QLLT3 + ...... + Qn/QLLTn')));
    expect(b4, contains(norm('주) Qn : 유해화학물질 최대보유량')));
    expect(b4, contains(norm('QLLTn : 유해화학물질 최하위 규정수량')));
    expect(rules['byeolpyo4']!, contains('그림을 보고 옮겨 적었다'));
  });

  // ── 줄 대조가 못 잡는 종류의 오류: 일반기준이 가리키는 **연번**이 데이터와 어긋나는 것 ──────────
  test('별표 2 일반기준 나의 연번(제282호ㆍ제557호) = 용액 구분 행을 가진 별표2 항목 전부', () {
    final fromData = {
      for (final e in ds.entries)
        if (e.src == Source.byeolpyo2 && e.rows.any((r) => r.kind == '용액')) e.no,
    };
    final fromText = RegExp(r'제(\d+)호')
        .allMatches(rules['byeolpyo2']!)
        .map((m) => int.parse(m.group(1)!))
        .toSet();
    expect(fromText, fromData);
    expect(fromData, {282, 557});
  });

  test('별표 3 일반기준 가의 연번(제42ㆍ43ㆍ44호) = * 표시 행을 가진 별표3 항목 전부', () {
    final fromData = {
      for (final e in ds.entries)
        if (e.src == Source.byeolpyo3 && e.rows.any((r) => r.min.contains('*'))) e.no,
    };
    final fromText = RegExp(r'제(\d+)호')
        .allMatches(rules['byeolpyo3']!)
        .map((m) => int.parse(m.group(1)!))
        .toSet();
    expect(fromText, fromData);
    expect(fromData, {42, 43, 44});
  });

  // ── getRule ────────────────────────────────────────────────────────────────
  test("getRule('all')은 네 주제를 모두 담고 고시명을 머리에 붙인다", () {
    final all = getRule('all');
    expect(all, startsWith('출처: $notice'));
    for (final t in ruleTopics) {
      expect(all, contains(rules[t]!.trim().split('\n').first));
    }
  });

  test('알 수 없는 주제는 오류다 — 조용히 전체로 대체하지 않는다', () {
    expect(() => getRule('byeolpyo9'), throwsA(isA<UnknownRuleTopic>()));
    expect(() => getRule(''), throwsA(isA<UnknownRuleTopic>()));
    expect(ruleResponse('byeolpyo3')['topic'], 'byeolpyo3');
  });
}
