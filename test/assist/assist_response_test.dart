/// F-008 1단계 수용 기준 — 도구 응답 조립(커버리지 선언ㆍ조용한 절단 금지ㆍlegend).
/// 실제 번들 데이터에 직접 질의한다(모킹 없음).
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/assist/assist_response.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/search/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Dataset ds;
  late SearchIndex index;

  setUpAll(() {
    ds = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map)
          .cast<String, Object?>(),
    );
    index = SearchIndex(ds);
  });

  Map<String, Object?> ask(String q) => searchResponse(index.search(q), ds);
  Map<String, Object?> coverage(Map<String, Object?> r) =>
      (r['coverage'] as Map).cast<String, Object?>();

  test('모든 응답에 커버리지 선언이 있다 — "별표 2ㆍ3만 덮는다"', () {
    for (final q in ['황산', '아세톤', '67-64-1', '납']) {
      expect(coverage(ask(q))['statement'], coverageStatement);
      expect(coverageStatement, contains('별표 2(인체ㆍ생태 유해성)와 별표 3(사고대비물질)만 덮는다'));
    }
  });

  test("'황산' → exact", () {
    final r = ask('황산');
    expect(coverage(r)['status'], 'exact');
    expect(r['total'], greaterThan(1)); // 부분 일치도 함께 걸리지만 정확 일치가 있으면 exact다
  });

  test("'아세톤' → partial_only 2건 + '별개 물질일 수 있다' 문장", () {
    final r = ask('아세톤');
    expect(coverage(r)['status'], 'partial_only');
    expect(r['total'], 2);
    expect(coverage(r)['note'], contains('별개 물질'));
    final names = [for (final h in (r['hits'] as List)) (h as Map)['ko']];
    expect(names, contains('아세톤 시아노히드린'));
  });

  test("'67-64-1'(아세톤 CAS) → none + 묶음 안내(hint)", () {
    final r = ask('67-64-1');
    expect(coverage(r)['status'], 'none');
    expect(r['total'], 0);
    expect(r['hint'], casNoHitHint);
    expect(coverage(r)['note'], contains('지어내지 말고'));
  });

  test('CAS 정확 일치도 exact다', () {
    expect(coverage(ask('7664-41-7'))['status'], 'exact');
    expect(coverage(ask('76644 1 7'))['status'], 'exact'); // 공백ㆍ부분 하이픈 무시
  });

  test('조용한 절단 금지: 상한을 넘으면 truncated와 전체 건수가 함께 온다', () {
    final r = ask('메틸'); // 100건을 훌쩍 넘는 질의
    expect(r['truncated'], isTrue);
    expect(r['returned'], 100);
    expect(r['total'], greaterThan(100));
    expect(coverage(r)['truncationNote'], isNotNull);
    expect((legend['truncated'] as String), contains('전체 건수는 total'));
  });

  test('응답에 쓰인 필드는 legend에 설명이 있다 — 설명 없는 필드는 버려진다(spike ③)', () {
    final r = ask('암모니아');
    final hit = ((r['hits'] as List).first as Map).cast<String, Object?>();
    final row = ((hit['rows'] as List).first as Map).cast<String, Object?>();
    for (final k in [...row.keys, 'priority', 'referenceNote', 'deleted', 'selection']) {
      expect(legend[k], isNotNull, reason: '$k에 설명이 없다');
    }
    expect(hit['selection'], isNotNull);
    expect(row['condition'], isNotEmpty);
  });

  test('규칙 주제 목록과 고시명이 응답에 실려 있다', () {
    final r = ask('톨루엔');
    final rules = (r['rules'] as Map).cast<String, Object?>();
    expect((rules['topics'] as Map).keys, containsAll(['byeolpyo2', 'byeolpyo3', 'byeolpyo4']));
    expect(((r['source'] as Map)['notice'] as String), contains('제2025-12호'));
  });

  test('빈 질의는 0건이고 none이다(정확 일치로 오판하지 않는다)', () {
    expect(coverage(ask(''))['status'], 'none');
  });
}
