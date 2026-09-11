/// F-003 공유 텍스트 수용 기준 — 실제 번들 데이터로 검색해 나온 카드의 공유 텍스트를 문자열 그대로 대조한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/parser/models.dart';
import 'package:findchem/search/search.dart';
import 'package:findchem/share/share_text.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Dataset ds;
  late SearchIndex index;

  setUpAll(() {
    final text = File('assets/data/findchem_data.json').readAsStringSync();
    ds = Dataset.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
    index = SearchIndex(ds);
  });

  Hit hitOf(String query, Source src, int no) =>
      index.search(query).hits.singleWhere((h) => h.entry.src == src && h.entry.no == no);

  PdfInfo pdfOf(Source src) => src == Source.byeolpyo3 ? ds.byeolpyo3 : ds.byeolpyo2;

  String textOf(String query, Source src, int no) => shareText(hitOf(query, src, no), pdfOf(src));

  test('인체·생태 유해성 연번 510 — 수용 기준 예시와 한 글자도 다르지 않다', () {
    expect(
      textOf('50-00-0', Source.byeolpyo2, 510),
      '[인체·생태 유해성] 포르말린; 포름알데히드\n'
      'Formalin; Formaldehyde\n'
      '연번 510 · 고유번호 97-1-345\n'
      'CAS 50-00-0\n'
      '\n'
      '규정수량(톤) 최하위 / 하위 / 상위\n'
      '· 급성, 함량기준 1%: 0.05 / 2 / 400\n'
      '· 만성, 함량기준 0.1%: 0.125 / 5 / 400\n'
      '\n'
      '※ 사고대비물질은 사고대비물질 규정수량을 적용합니다(별표2 일반기준 가)\n'
      '\n'
      'FindChem · 「유해화학물질의 규정수량에 관한 규정」 (PDF 2026-07-20 기준)',
    );
  });

  test('참고 문구가 없는 카드에는 ※ 줄이 없다', () {
    expect(textOf('13516-27-3', Source.byeolpyo2, 5), isNot(contains('※')));
  });

  test('사고대비물질 42(염화수소) — 우선 적용 머리, 구분 없는 행은 함량기준만, 용액 행은 원문 그대로', () {
    final lines = textOf('7647-01-0', Source.byeolpyo3, 42).split('\n');
    expect(lines.first, '[사고대비물질 · 우선 적용] 염화수소');
    expect(lines[2], '번호 42');
    expect(lines, containsAllInOrder(['· 함량기준 10%: 0.02 / 0.8 / 4', '· 염화수소 용액: 0.2* / 8* / 40*']));
  });

  test("사고대비물질 46(질산) — 함량기준에 %가 있으면 붙이지 않는다", () {
    expect(textOf('7697-37-2', Source.byeolpyo3, 46).split('\n'), contains('· 함량기준 70% 초과: 0.025 / 1 / 20'));
  });

  test('삭제 항목(연번 91)은 수량 줄 대신 삭제 표시, CAS 없는 항목(연번 4)은 CAS 줄 대신 묶음 표시', () {
    final deleted = textOf('123-33-1', Source.byeolpyo2, 91);
    expect(deleted, contains('\n\n삭제된 항목 · 규정수량 없음\n\n'));
    expect(deleted, isNot(contains('규정수량(톤)')));

    final group = textOf('구아자틴', Source.byeolpyo2, 4).split('\n');
    expect(group, contains('묶음 항목 · CAS 없음'));
    expect(group.where((l) => l.startsWith('CAS ')), isEmpty);
  });

  test('마지막 줄 날짜는 그 표 PDF의 생성일, 생성일이 없으면 고시명까지만', () {
    final hit = hitOf('7647-01-0', Source.byeolpyo3, 42);
    final dated = shareText(hit, const PdfInfo(file: 'x.pdf', created: '2027-01-02T00:00:00+09:00', pages: 1));
    expect(dated.split('\n').last, 'FindChem · 「유해화학물질의 규정수량에 관한 규정」 (PDF 2027-01-02 기준)');
    final undated = shareText(hit, const PdfInfo(file: 'x.pdf', created: null, pages: 1));
    expect(undated.split('\n').last, 'FindChem · 「유해화학물질의 규정수량에 관한 규정」');
  });
}
