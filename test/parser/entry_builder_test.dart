/// 셀 격자 → 항목 빌더를 pdfplumber 정답지(전수)로 검증한다. 기준은 Phase_001.md의 불변식.
library;

import 'package:findchem/parser/cas.dart';
import 'package:findchem/parser/cell_grid.dart';
import 'package:findchem/parser/entry_builder.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/parser/name_split.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures.dart';

final _hangul = RegExp(r'[가-힣]');

void main() {
  late BuildResult b2;
  late BuildResult b3;

  setUpAll(() {
    b2 = buildEntries(Source.byeolpyo2, loadFixtureGrid(Source.byeolpyo2));
    b3 = buildEntries(Source.byeolpyo3, loadFixtureGrid(Source.byeolpyo3));
  });

  Entry e2(int no) => b2.entries[no - 1];
  Entry e3(int no) => b3.entries[no - 1];

  group('건수 불변식', () {
    test('별표2 1,557건, 별표3 100건, 연번 연속', () {
      expect(b2.entries.length, 1557);
      expect(b3.entries.length, 100);
      for (var i = 0; i < b2.entries.length; i++) {
        expect(b2.entries[i].no, i + 1);
        expect(b2.entries[i].src, Source.byeolpyo2);
      }
      for (var i = 0; i < b3.entries.length; i++) {
        expect(b3.entries[i].no, i + 1);
        expect(b3.entries[i].src, Source.byeolpyo3);
      }
    });

    test('경고 0건(CAS 형식 등)', () {
      expect(b2.warnings, isEmpty);
      expect(b3.warnings, isEmpty);
    });

    test('(삭제) 19건 — 구분 (삭제), 값 전부 -', () {
      final deleted = b2.entries.where((e) => e.deleted).toList();
      expect(deleted.length, 19);
      for (final e in deleted) {
        expect(e.rows.length, 1, reason: '${e.no}');
        expect(e.rows.single, const QuantityRow(kind: '(삭제)', content: '-', min: '-', low: '-', high: '-'));
      }
      expect(b3.entries.where((e) => e.deleted), isEmpty);
    });

    test('2행 이상 항목은 별표2 625건, 행마다 수량이 다르다', () {
      final multi = b2.entries.where((e) => e.rows.length > 1).toList();
      expect(multi.length, 625);
      for (final e in multi) {
        final quantities = e.rows.map((r) => '${r.content}|${r.min}|${r.low}|${r.high}').toSet();
        expect(quantities.length, e.rows.length, reason: '연번 ${e.no}');
      }
    });
  });

  group('CAS', () {
    test('없음 77건, 복수 별표2 55건·별표3 1건(최대 7개), 전부 형식 일치', () {
      // 55는 정답지의 CAS 열에 쉼표가 있는 행 수와 같다(Phase_001.md의 54는 1건 오차 — 2026-09-11 재실측).
      final all = [...b2.entries, ...b3.entries];
      expect(all.where((e) => e.cas.isEmpty).length, 77);
      expect(b2.entries.where((e) => e.cas.length > 1).length, 55);
      expect(b3.entries.where((e) => e.cas.length > 1).length, 1);
      expect(all.map((e) => e.cas.length).reduce((a, b) => a > b ? a : b), 7);
      final pattern = RegExp(r'^\d{2,7}-\d{2}-\d$');
      for (final e in all) {
        for (final c in e.cas) {
          expect(c, matches(pattern), reason: '${e.src.id} ${e.no}');
        }
      }
    });

    test('셀 줄바꿈으로 끊긴 CAS는 이어 붙이고(별표2 16건), 줄바꿈만으로 나뉜 CAS는 나눈다(별표3 98)', () {
      expect(e2(191).cas, ['3084-48-0', '78-50-2', '31160-64-2']);
      final wrapped = b2.entries.where((e) => e.cas.any((c) => c.length >= 12)).toList();
      expect(wrapped.length, greaterThanOrEqualTo(16), reason: '7자리 CAS는 셀 폭에 안 맞아 끊긴다');
      expect(e3(98).cas, ['1330-20-7', '95-47-6', '106-42-3', '108-38-3']);
    });

    test('줄바꿈으로 나뉜 CAS 두 개를 하나로 붙이지 않는다 (직접 입력)', () {
      final w = <String>[];
      expect(parseCasCell('95-47-6 \n106-42-3', warnings: w, where: 't'), ['95-47-6', '106-42-3']);
      expect(parseCasCell('1233844-88-\n6', warnings: w, where: 't'), ['1233844-88-6']);
      expect(parseCasCell('-', warnings: w, where: 't'), isEmpty);
      expect(w, isEmpty);
      expect(parseCasCell('abc', warnings: w, where: 't'), ['abc']);
      expect(w, hasLength(1));
    });

    test("이름 속 '제외' CAS(118·180)는 CAS로 뽑히지 않는다", () {
      expect(e2(118).cas, isEmpty);
      expect(e2(118).en, contains('14038-43-8'));
      expect(e2(180).cas, isEmpty);
      expect(e2(180).en, contains('15606-95-8'));
    });

    test('체크디지트 틀린 원문 2건은 원문 그대로 둔다', () {
      expect(e2(191).cas.first, '3084-48-0');
      expect(e2(1016).cas, ['57235-57-7']);
    });
  });

  group('이름', () {
    test('국문에 한글이 있고 영문에는 없다(전수). 별표2·3 본항목은 영문이 있다', () {
      for (final e in [...b2.entries, ...b3.entries]) {
        expect(e.ko, isNotEmpty, reason: '${e.src.id} ${e.no}');
        expect(_hangul.hasMatch(e.ko), isTrue, reason: '${e.src.id} ${e.no}: ${e.ko}');
        expect(_hangul.hasMatch(e.en), isFalse, reason: '${e.src.id} ${e.no}: ${e.en}');
        expect(e.en, isNotEmpty, reason: '${e.src.id} ${e.no}: ${e.name}');
        expect(e.ko, isNot(endsWith('[')), reason: '${e.src.id} ${e.no}: ${e.ko}');
        expect(e.name, isNot(contains('\n')), reason: '${e.src.id} ${e.no}');
      }
    });

    test('영문의 대괄호 짝이 안 맞는 항목은 원문 오류 3건(341·654·1083)뿐이다', () {
      int count(String s, String ch) => ch.allMatches(s).length;
      final unbalanced = [...b2.entries, ...b3.entries]
          .where((e) => count(e.en, '[') != count(e.en, ']'))
          .map((e) => '${e.src.id} ${e.no}')
          .toSet();
      expect(unbalanced, {'별표2 341', '별표2 654', '별표2 1083'});
      expect(e2(654).ko, endsWith('크롬산(2-) 이나트륨'));
      expect(e2(654).en, startsWith('Disodium [3-hydroxy'));
    });

    test('별표3 33: 영문 뒤 국문 단서는 국문명에 이어 붙는다', () {
      expect(e3(33).en, 'Sodium cyanide');
      expect(e3(33).ko, startsWith('시안화나트륨(사이안화나트륨) 다만, 베를린청'));
      expect(e3(33).ko, endsWith('혼합물질은 제외'));
    });

    test('셀 줄바꿈 복원: 단어 경계는 공백 유지, 단어 중간은 붙인다', () {
      expect(e2(13).en, 'Lead styphinate; Lead 2,4,6-trinitroresorcinoxide');
      expect(e2(10).ko, '납과 그 화합물. 다만, 본 고시에서 별도로 규정한 것은 제외');
      expect(e3(1).en, 'Formalin;Formaldehyde');
      expect(e2(615).ko, "1,1'-메틸렌비스[4-이소시아나토시클로헥산]");
      expect(e2(615).en, "1,1'-Methylenebis[4-isocyanatocyclohexane]");
    });

    test('원문 괄호 짝 오류 3건(341·1083·1429)', () {
      expect(e2(341).ko, endsWith('피리디늄'));
      expect(e2(341).en, endsWith('pyridinium dichloride'));
      expect(e2(1083).ko, endsWith('2-(O-아세틸옥심)'));
      expect(e2(1083).en, startsWith('1-4-[[4-(2-Hydroxyethoxy)'));
      expect(e2(1429).ko, '5-데신');
      expect(e2(1429).en, '5-Decyne');
    });

    test('손으로 만든 예외 목록은 전부 실제로 쓰인다(자동 검증)', () {
      expect({...b2.exceptionsUsed, ...b3.exceptionsUsed}, nameSplitExceptions.keys.toSet());
    });

    test('띄어 쓴 원문은 그대로(306 염화 수소)', () {
      expect(e2(306).name, '염화 수소 [Hydrogen chloride]');
      expect(e2(306).ko, '염화 수소');
    });

    test('별표3 신·구 표기 병기와 ; 동의어는 원문 그대로', () {
      expect(e3(1).ko, '포르말린 또는 포름알데히드(폼알데하이드)');
      expect(e3(1).en, 'Formalin;Formaldehyde');
    });
  });

  group('구분 행', () {
    test('별표2 5번 구아자틴: 고유번호 97-1-4, 급성·생태 2행', () {
      final e = e2(5);
      expect(e.uid, '97-1-4');
      expect(e.cas, ['13516-27-3', '108173-90-6']);
      expect(e.rows, [
        const QuantityRow(kind: '급성', content: '1', min: '0.125', low: '5', high: '200'),
        const QuantityRow(kind: '생태', content: '25', min: '0.125', low: '5', high: '200'),
      ]);
      expect(e2(4).name, '구아자틴 염류 [Guazatine salts]');
      expect(e2(4).rows.single.kind, '급성,생태');
    });

    test("별표3 42~44 둘째 행 '용액' 구분은 물질명 열에서 온다", () {
      expect(e3(42).uid, isNull);
      expect(e3(42).rows.length, 2);
      expect(e3(42).rows[0].kind, '');
      expect(e3(42).rows[1].kind, '염화수소 용액');
      expect(e3(42).rows[1].min, '0.2*');
      expect(e3(43).rows[1].kind, '플루오린화 수소 용액');
      expect(e3(44).rows[1].kind, '암모니아 용액');
    });

    test('별표3 46 질산 둘째 행 함량 70% 초과', () {
      expect(e3(46).rows[1].content, '70% 초과');
      expect(e3(46).rows[1].kind, '');
    });

    test('별표2 (삭제) 항목: 439 톨루엔, 91 말레산히드라지드', () {
      expect(e2(439).deleted, isTrue);
      expect(e2(439).name, '톨루엔 [Toluene]');
      expect(e2(91).deleted, isTrue);
      expect(e2(91).cas, ['123-33-1']);
    });
  });

  group('검증 실패는 사유와 함께 던진다', () {
    List<List<String>> copy(List<List<String>> rows) => rows.map((r) => [...r]).toList();

    test('별표3 격자를 별표2로 읽으면(파일 뒤바뀜) 머리글 오류', () {
      expect(
        () => buildEntries(Source.byeolpyo2, loadFixtureGrid(Source.byeolpyo3)),
        throwsA(isA<ParseException>().having((e) => e.reason, 'reason', contains('열이 9개여야'))),
      );
      expect(
        () => buildEntries(Source.byeolpyo3, loadFixtureGrid(Source.byeolpyo2)),
        throwsA(isA<ParseException>().having((e) => e.reason, 'reason', contains('열이 7개여야'))),
      );
    });

    test('머리글 글자가 다르면 오류', () {
      final grid = loadFixtureGrid(Source.byeolpyo3);
      final rows = copy(grid.first.rows);
      rows[0][1] = '물질명';
      expect(
        () => buildEntries(Source.byeolpyo3, [PageGrid(page: 1, rows: rows), ...grid.skip(1)]),
        throwsA(isA<ParseException>().having((e) => e.reason, 'reason', contains('머리글이 아닙니다'))),
      );
    });

    test('연번이 건너뛰면 오류', () {
      final grid = loadFixtureGrid(Source.byeolpyo3);
      final rows = copy(grid.first.rows);
      rows[3][0] = '4'; // 3 → 4
      expect(
        () => buildEntries(Source.byeolpyo3, [PageGrid(page: 1, rows: rows), ...grid.skip(1)]),
        throwsA(isA<ParseException>().having((e) => e.reason, 'reason', contains('연번이 3이어야 하는데 4'))),
      );
    });

    test('연번 없는 행에 CAS가 있으면 오류', () {
      final grid = loadFixtureGrid(Source.byeolpyo2);
      final rows = copy(grid.first.rows);
      final cont = rows.indexWhere((r) => r[0].isEmpty);
      rows[cont][3] = '50-00-0';
      expect(
        () => buildEntries(Source.byeolpyo2, [PageGrid(page: 1, rows: rows), ...grid.skip(1)]),
        throwsA(isA<ParseException>().having((e) => e.reason, 'reason', contains('CAS가 있습니다'))),
      );
    });

    test('빈 표는 오류', () {
      expect(() => buildEntries(Source.byeolpyo2, const []), throwsA(isA<ParseException>()));
    });
  });
}
