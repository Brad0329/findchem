/// A-008 수용 기준 — CAS 일괄 분류 도구. 실제 번들 데이터에 직접 질의한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/classify/classify_cas.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/search/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Dataset ds;

  setUpAll(() {
    ds = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
  });

  List<Map<String, Object?>> items(List<Object?> cas) {
    final out = classifyCas(ds, {'cas': cas});
    expect(out.isError, false, reason: out.error);
    return (out.response['items']! as List).cast<Map<String, Object?>>();
  }

  Map<String, Object?> one(String cas) => items([cas]).single;

  List<Map<String, Object?>> entriesOf(Map<String, Object?> item) =>
      (item['entries']! as List).cast<Map<String, Object?>>();

  List<(String, String)> rowsOf(Map<String, Object?> entry) =>
      [for (final r in (entry['rows']! as List).cast<Map>()) (r['kind'] as String, r['content'] as String)];

  group('입력', () {
    test('배열이 아니거나 비었으면 요청 오류', () {
      expect(classifyCas(ds, {}).isError, true);
      expect(classifyCas(ds, {'cas': '107-13-1'}).isError, true);
      expect(classifyCas(ds, {'cas': <Object?>[]}).isError, true);
    });

    test('상한 200개 — 넘으면 조회하지 않고 받은 개수와 상한을 돌려준다', () {
      expect(classifyCas(ds, {'cas': List.filled(classifyCasCap, '107-13-1')}).isError, false);
      final over = classifyCas(ds, {'cas': List.filled(classifyCasCap + 1, '107-13-1')});
      expect(over.isError, true);
      expect(over.error, allOf(contains('${classifyCasCap + 1}'), contains('$classifyCasCap')));
      expect(over.response, isEmpty);
    });

    test('입력과 같은 순서ㆍ같은 개수 — 중복도 그대로, 잘못된 항목이 있어도 나머지는 조회된다', () {
      final out = classifyCas(ds, {
        'cas': ['123-86-4', '107131', '107-13-1', 'abc', '', 42, '107-13-1'],
      });
      final list = (out.response['items']! as List).cast<Map<String, Object?>>();
      expect(list.map((i) => i['status']),
          ['not_listed', 'invalid', 'listed', 'invalid', 'invalid', 'invalid', 'listed']);
      expect(list.map((i) => i['input']), ['123-86-4', '107131', '107-13-1', 'abc', '', 42, '107-13-1']);
      for (final i in list.where((i) => i['status'] == 'invalid')) {
        expect(i['reason'], isA<String>());
        expect(i.containsKey('classes'), false);
      }
      expect(out.response['total'], 7);
      expect(out.response['counts'], {'listed': 2, 'not_listed': 1, 'invalid': 4});
    });

    test('앞자리 0은 지우고 조회한다 — input에는 원래 표기', () {
      final i = one('000065-85-0');
      expect(i['input'], '000065-85-0');
      expect(i['cas'], '65-85-0');
      expect(i['status'], 'listed');
    });
  });

  group('분류', () {
    test('107-13-1 — 두 표 모두, 별표3 우선ㆍ별표2 참고, 행마다 구분과 함량기준 원문', () {
      final i = one('107-13-1');
      expect(i['status'], 'listed');
      expect(i['classes'], ['사고대비물질', '인체급성유해성', '인체만성유해성']);
      final es = entriesOf(i);
      expect(es.map((e) => (e['src'], e['no'])), [('별표3', 24), ('별표2', 261)]);
      expect(es[0]['priority'], true);
      expect(es[0].containsKey('reference_note'), false);
      expect(es[1]['reference_note'], true);
      expect(rowsOf(es[0]), [('', '0.1')]);
      expect(rowsOf(es[1]), [('급성', '1'), ('만성', '0.1')]);
    });

    test('123-86-4 — 개별 항목 없음', () {
      final i = one('123-86-4');
      expect(i['status'], 'not_listed');
      expect(i['classes'], isEmpty);
      expect(i['entries'], isEmpty);
      expect(i['checksum_ok'], true);
      expect(i.containsKey('notes'), false);
    });

    test('65-85-0 — 저확산 행은 행으로만 싣고 분류에는 넣지 않는다', () {
      final i = one('65-85-0');
      expect(i['classes'], ['인체만성유해성']);
      expect(rowsOf(entriesOf(i).single), [('만성', '10'), ('저확산', '')]);
      expect((i['notes']! as List).join(), contains('저확산'));
    });

    test('묶인 구분(급성,생태)은 두 분류로 나뉜다', () {
      final e = ds.entries.firstWhere(
          (e) => !e.deleted && e.cas.isNotEmpty && e.rows.length == 1 && e.rows.single.kind == '급성,생태');
      final other = ds.entries.where((o) => !identical(o, e) && !o.deleted && o.cas.contains(e.cas.first));
      expect(other, isEmpty, reason: '표본 CAS가 다른 항목에도 있으면 기대값이 달라진다');
      expect(one(e.cas.first)['classes'], ['인체급성유해성', '생태유해성']);
    });

    test('26471-62-5(TDI 혼합) — 이 CAS는 별표2에만, 항목은 참고 표시', () {
      final i = one('26471-62-5');
      expect(i['classes'], ['인체급성유해성']);
      final e = entriesOf(i).single;
      expect((e['src'], e['no']), ('별표2', 805));
      expect(e['reference_note'], true);
    });

    test('(삭제) 항목만 걸리는 CAS — not_listed + 안내(번들에 없으면 그 사실을 확인)', () {
      final liveCas = {
        for (final e in ds.entries)
          if (!e.deleted) ...e.cas,
      };
      final deletedOnly = {
        for (final e in ds.entries)
          if (e.deleted) ...e.cas.where((c) => !liveCas.contains(c)),
      };
      if (deletedOnly.isEmpty) {
        // 현재 번들의 (삭제) 항목에는 CAS가 없다 — 생기면 아래 갈래가 돈다.
        expect(ds.entries.where((e) => e.deleted).expand((e) => e.cas), isEmpty);
        return;
      }
      final i = one(deletedOnly.first);
      expect(i['status'], 'not_listed');
      expect((i['notes']! as List).join(), contains('(삭제)'));
    });
  });

  group('체크섬', () {
    test('casChecksumOk', () {
      expect(casChecksumOk('107-13-1'), true);
      expect(casChecksumOk('7732-18-5'), true);
      expect(casChecksumOk('107-13-2'), false);
    });

    test('203-466-5(EC 번호)는 가운데가 3자리라 형식에서 걸린다', () {
      expect(one('203-466-5')['status'], 'invalid');
    });

    test('107-13-2(끝자리 오독) — 없음 + 체크섬 불일치 안내', () {
      final i = one('107-13-2');
      expect(i['status'], 'not_listed');
      expect(i['checksum_ok'], false);
      expect((i['notes']! as List).join(), contains('오독'));
    });

    test('3084-48-0 — 체크섬은 틀리지만 고시 원문 표기라 조회된다', () {
      final i = one('3084-48-0');
      expect(i['status'], 'listed');
      expect(i['checksum_ok'], false);
      expect((i['notes']! as List).join(), contains('고시 원문'));
    });
  });

  test('대조 — 번들의 모든 CAS에서 검색(SearchIndex)의 완전 일치 항목과 같은 항목 집합', () {
    final allCas = {for (final e in ds.entries) ...e.cas}.toList();
    expect(allCas.length, greaterThan(1000));
    final index = SearchIndex(ds, cap: ds.entries.length);
    var checked = 0;
    for (var start = 0; start < allCas.length; start += classifyCasCap) {
      final chunk = allCas.sublist(start, (start + classifyCasCap).clamp(0, allCas.length));
      final got = items(chunk);
      for (var k = 0; k < chunk.length; k++) {
        final expected = {
          for (final h in index.search(chunk[k]).hits)
            if (!h.entry.deleted && h.entry.cas.contains(chunk[k])) (h.entry.src.id, h.entry.no),
        };
        expect({for (final e in entriesOf(got[k])) (e['src'], e['no'])}, expected, reason: chunk[k]);
        expect(got[k]['status'], expected.isEmpty ? 'not_listed' : 'listed', reason: chunk[k]);
        checked++;
      }
    }
    expect(checked, allCas.length);
  });

  test('lib/classify는 Flutter를 import하지 않는다', () {
    final files = Directory('lib/classify').listSync().whereType<File>().toList();
    expect(files, isNotEmpty);
    for (final f in files) {
      expect(f.readAsStringSync(), isNot(contains('package:flutter')), reason: f.path);
    }
  });
}
