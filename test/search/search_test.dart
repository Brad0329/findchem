/// F-001 수용 기준(docs/REQUIREMENTS.md) — 검색 규칙을 실제 번들 데이터에 직접 질의해 검증한다(모킹 없음).
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/parser/models.dart';
import 'package:findchem/search/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late SearchIndex index;

  setUpAll(() {
    final text = File('assets/data/findchem_data.json').readAsStringSync();
    index = SearchIndex(Dataset.fromJson((jsonDecode(text) as Map).cast<String, Object?>()));
  });

  List<(String, int)> keys(SearchResult r) => [for (final h in r.hits) (h.entry.src.id, h.entry.no)];

  test("'염화수소'(붙여 씀)와 '염화 수소'(띄어 씀) 모두 별표2 연번 306을 찾는다", () {
    for (final q in ['염화수소', '염화 수소']) {
      expect(keys(index.search(q)), contains(('별표2', 306)), reason: q);
    }
  });

  test("'GUAZATINE'·'guazatine'·'구아자틴' → 같은 2건(연번 4, 5)", () {
    final expected = [('별표2', 4), ('별표2', 5)];
    for (final q in ['GUAZATINE', 'guazatine', '구아자틴']) {
      final r = index.search(q);
      expect(keys(r), expected, reason: q);
      expect(r.total, 2);
    }
  });

  test("'13516-27-3' → 1건, 연번 5 (첫 번째 CAS). 두 번째 CAS '108173-90-6'으로도 찾힌다", () {
    expect(keys(index.search('13516-27-3')), [('별표2', 5)]);
    expect(keys(index.search('108173-90-6')), [('별표2', 5)]);
  });

  test("'50-00-0' → 2건. 사고대비물질 1이 위에 '우선 적용', 별표2 510이 아래에 참고 문구", () {
    final r = index.search('50-00-0');
    expect(keys(r), [('별표3', 1), ('별표2', 510)]);
    expect(r.hits[0].priority, isTrue);
    expect(r.hits[0].referenceNote, isFalse);
    expect(r.hits[1].priority, isFalse);
    expect(r.hits[1].referenceNote, isTrue);
    expect((r.total, r.count3, r.count2), (2, 1, 1));
  });

  test('전체·표별 건수는 상한 적용 전 값이고, 상한을 넘으면 truncated', () {
    final r = index.search('산');
    expect(r.total, greaterThan(index.cap), reason: "'산'은 상한을 넘는 표본이어야 한다");
    expect(r.hits.length, index.cap);
    expect(r.truncated, isTrue);
    expect(r.count2 + r.count3, r.total);
  });

  test('CAS 형식으로 넣어 0건이면 casQueryNoHit. 이름 0건이나 CAS 1건이면 아니다', () {
    final none = index.search('99999-99-9');
    expect(none.total, 0);
    expect(none.casQueryNoHit, isTrue);

    final deleted = index.search('123-33-1');
    expect(keys(deleted), [('별표2', 91)]);
    expect(deleted.hits.single.entry.deleted, isTrue);
    expect(deleted.casQueryNoHit, isFalse);

    final name = index.search('없는물질zzz');
    expect(name.total, 0);
    expect(name.casQueryNoHit, isFalse);
  });

  test("'톨루엔' → 사고대비물질이 맨 위, (삭제) 연번 439가 맨 아래", () {
    final r = index.search('톨루엔');
    expect(r.hits.first.entry.src, Source.byeolpyo3);
    expect(keys(r).last, ('별표2', 439));
    expect(r.hits.last.entry.deleted, isTrue);
    // 묶음 순서: 별표3 → 별표2 살아있는 항목 → 삭제. 각 묶음 안은 연번 오름차순
    final groups = [for (final h in r.hits) h.entry.src == Source.byeolpyo3 ? 0 : (h.entry.deleted ? 2 : 1)];
    expect(groups, List.of(groups)..sort());
    for (var i = 1; i < r.hits.length; i++) {
      if (groups[i] == groups[i - 1]) {
        expect(r.hits[i].entry.no, greaterThan(r.hits[i - 1].entry.no));
      }
    }
  });

  test('빈 입력·공백만 → 검색하지 않는다(0건, 안내 없음)', () {
    for (final q in ['', '   ']) {
      final r = index.search(q);
      expect(r.hits, isEmpty);
      expect(r.total, 0);
      expect(r.casQueryNoHit, isFalse);
    }
  });

  test('우선 적용·참고 문구는 살아있는 별표2 항목과 CAS가 겹칠 때만', () {
    // 별표3 톨루엔(108-88-3)의 별표2 짝은 (삭제) 항목뿐 → 우선 적용 아님
    final toluene = index.search('108-88-3');
    expect(keys(toluene), [('별표3', 28), ('별표2', 439)]);
    expect(toluene.hits[0].priority, isFalse);
    expect(toluene.hits[1].referenceNote, isFalse);
  });
}
