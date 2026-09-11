import 'dart:convert';

import 'package:findchem/parser/entry_builder.dart';
import 'package:findchem/parser/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

void main() {
  test('Dataset JSON 왕복: 정답지 전체가 같은 값으로 돌아온다', () {
    final b2 = buildEntries(Source.byeolpyo2, loadFixtureGrid(Source.byeolpyo2));
    final b3 = buildEntries(Source.byeolpyo3, loadFixtureGrid(Source.byeolpyo3));
    final ds = Dataset(
      byeolpyo2: const PdfInfo(file: 'a.pdf', created: '2026-07-20T09:16:24+09:00', pages: 56),
      byeolpyo3: const PdfInfo(file: 'b.pdf', created: null, pages: 3),
      extractedAt: '2026-09-11T00:00:00Z',
      entries: [...b2.entries, ...b3.entries],
    );
    final text = jsonEncode(ds.toJson());
    final back = Dataset.fromJson((jsonDecode(text) as Map).cast<String, Object?>());

    expect(back.count(Source.byeolpyo2), 1557);
    expect(back.count(Source.byeolpyo3), 100);
    expect(back.byeolpyo2.created, '2026-07-20T09:16:24+09:00');
    expect(back.byeolpyo3.created, isNull);
    expect(jsonEncode(back.toJson()), text);

    final j = (jsonDecode(text) as Map)['entries'][0] as Map;
    expect(j.keys.toSet(), {'src', 'no', 'uid', 'name', 'ko', 'en', 'cas', 'deleted', 'rows'});
    expect(j['src'], '별표2');
    expect((j['rows'] as List).first.keys.toSet(), {'kind', 'content', 'min', 'low', 'high'});
  });

  test('Source.fromId는 모르는 값에 예외', () {
    expect(Source.fromId('별표3'), Source.byeolpyo3);
    expect(() => Source.fromId('별표4'), throwsFormatException);
  });
}
