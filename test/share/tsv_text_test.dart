/// F-004 TSV 수용 기준 — 실제 번들 데이터로, Excel에 붙였을 때 열이 갈리는 모양인지 본다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/parser/models.dart';
import 'package:findchem/share/tsv_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Dataset ds;

  setUpAll(() {
    final text = File('assets/data/findchem_data.json').readAsStringSync();
    ds = Dataset.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
  });

  Entry entryOf(Source src, int no) => ds.entries.firstWhere((e) => e.src == src && e.no == no);

  test('구아자틴(연번 5, 수량 행 2개): 머리글 없이 2줄, 열 9개, 앞 4칸은 매 줄 반복', () {
    final lines = tsvText(entryOf(Source.byeolpyo2, 5)).split('\n');
    expect(lines, hasLength(2)); // 머리글 줄은 넣지 않는다(2026-09-12 사용자 요청)
    for (final line in lines) {
      expect('\t'.allMatches(line), hasLength(8), reason: line); // 열 9개 = 탭 8개
    }
    expect(lines.first, isNot(startsWith('연번\t')));
    // '표'·'영문명' 열은 넣지 않는다(2026-09-12 사용자 요청).
    expect(lines[0], isNot(contains('Guazatine')));
    expect(lines[0], '5\t구아자틴\t13516-27-3, 108173-90-6\t97-1-4\t급성\t1\t0.125\t5\t200');
    // 앞 4칸(연번~고유번호)이 두 줄 모두 같다 — Excel에서 정렬·필터가 바로 되게(2026-09-12 사용자 결정).
    expect(lines[0].split('\t').take(4), lines[1].split('\t').take(4));
    expect(lines[1].split('\t').skip(4), ['생태', '25', '0.125', '5', '200']);
  });

  test("'50-00-0' 두 행의 TSV: 화학물질명 칸이 비지 않는다(2026-09-12 사용자 지적으로 고정)", () {
    final b3 = tsvText(entryOf(Source.byeolpyo3, 1));
    final b2 = tsvText(entryOf(Source.byeolpyo2, 510));
    expect(b3, '1\t포르말린 또는 포름알데히드(폼알데하이드)\t50-00-0\t\t\t1\t0.05\t2\t400');
    expect(b2.split('\n')[1], '510\t포르말린; 포름알데히드\t50-00-0\t97-1-345\t만성\t0.1\t0.125\t5\t400');
    for (final line in [...b3.split('\n'), ...b2.split('\n')]) {
      expect(line.split('\t')[1], isNotEmpty, reason: line);
    }
  });

  test('CAS 없는 항목(연번 4)은 CAS 칸이 빈칸이다(화면 문구를 넣지 않는다)', () {
    final lines = tsvText(entryOf(Source.byeolpyo2, 4)).split('\n');
    expect(lines[0].split('\t')[2], '');
    expect(lines[0], isNot(contains('묶음 항목')));
  });

  test('삭제 항목(연번 91)도 값은 원문 그대로', () {
    final lines = tsvText(entryOf(Source.byeolpyo2, 91)).split('\n');
    expect(lines[0].split('\t').skip(6), ['-', '-', '-']);
  });

  test('사고대비물질 번호 42: 원문 값(0.2*)이 그대로, 구분 빈칸도 칸을 지킨다', () {
    final lines = tsvText(entryOf(Source.byeolpyo3, 42)).split('\n');
    expect(lines[0].split('\t')[0], '42');
    expect(lines[0].split('\t')[4], ''); // 별표3 첫 행은 구분이 없다
    expect(lines[1].split('\t').skip(4), ['염화수소 용액', '', '0.2*', '8*', '40*']);
  });
}
