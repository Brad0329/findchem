/// 번들 JSON(assets/data/findchem_data.json)이 파서 결과와 같고 Phase_001.md 불변식·원문 오류 예외를 만족하는지.
/// 데이터에 직접 질의한다(모킹 없음).
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/parser/entry_builder.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/parser/name_split.dart';
import 'package:findchem/parser/pdf_extractor.dart';
import 'package:flutter_test/flutter_test.dart';

import '../parser/fixtures.dart';

void main() {
  late Dataset ds;

  setUpAll(() {
    final text = File('assets/data/findchem_data.json').readAsStringSync();
    ds = Dataset.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
  });

  Entry entry(Source src, int no) => ds.entries.firstWhere((e) => e.src == src && e.no == no);

  test('건수: 별표2 1,557 + 별표3 100 = 1,657, 연번 연속, 별표2가 앞', () {
    expect(ds.entries.length, 1657);
    expect(ds.count(Source.byeolpyo2), 1557);
    expect(ds.count(Source.byeolpyo3), 100);
    for (var i = 0; i < 1557; i++) {
      expect(ds.entries[i].src, Source.byeolpyo2);
      expect(ds.entries[i].no, i + 1);
    }
    for (var i = 0; i < 100; i++) {
      expect(ds.entries[1557 + i].src, Source.byeolpyo3);
      expect(ds.entries[1557 + i].no, i + 1);
    }
  });

  test('파일 머리: 원본 파일명·생성일·쪽수·추출일', () {
    expect(ds.byeolpyo2.file, startsWith('[별표 2]'));
    expect(ds.byeolpyo3.file, startsWith('[별표 3]'));
    expect(ds.byeolpyo2.created, '2026-07-20T09:16:24+09:00');
    expect(ds.byeolpyo3.created, '2026-07-20T09:16:36+09:00');
    expect(ds.byeolpyo2.pages, 56);
    expect(ds.byeolpyo3.pages, 3);
    expect(DateTime.tryParse(ds.extractedAt), isNotNull);
  });

  test('번들이 현재 파서 결과와 같다(낡은 번들 방지)', () {
    final fresh = <Entry>[];
    for (final src in Source.values) {
      final extracted = PdfTableExtractor.extract(assetPdf(src).readAsBytesSync());
      fresh.addAll(buildEntries(src, extracted.pages).entries);
    }
    expect(fresh.length, ds.entries.length);
    for (var i = 0; i < fresh.length; i++) {
      expect(jsonEncode(ds.entries[i].toJson()), jsonEncode(fresh[i].toJson()), reason: '$i번째');
    }
  });

  test('(삭제) 19건, CAS 없음 77건, 복수 CAS 56건', () {
    expect(ds.entries.where((e) => e.deleted).length, 19);
    expect(ds.entries.where((e) => e.cas.isEmpty).length, 77);
    expect(ds.entries.where((e) => e.cas.length > 1).length, 56);
  });

  test('원문 오류 예외 목록(손으로 만든 데이터의 자동 검증)', () {
    // 괄호 짝 오류 4건: 1429는 예외 목록, 341·654·1083은 일반 규칙으로 맞는다
    final e1429 = entry(Source.byeolpyo2, 1429);
    expect(e1429.name, '5-데신 [5-Decyne]]');
    expect((ko: e1429.ko, en: e1429.en), nameSplitExceptions[e1429.name]);
    for (final name in nameSplitExceptions.keys) {
      expect(ds.entries.any((e) => e.name == name), isTrue, reason: '예외 "$name"이 데이터에 없다 — 목록이 낡았다');
    }
    expect(entry(Source.byeolpyo2, 341).en, endsWith('pyridinium dichloride'));
    expect(entry(Source.byeolpyo2, 654).en, startsWith('Disodium [3-hydroxy'));
    expect(entry(Source.byeolpyo2, 1083).en, startsWith('1-4-[[4-(2-Hydroxyethoxy)'));
    // 체크디지트 틀린 원문 2건은 그대로
    expect(entry(Source.byeolpyo2, 191).cas.first, '3084-48-0');
    expect(entry(Source.byeolpyo2, 1016).cas, ['57235-57-7']);
  });

  test('F-001 수용 기준이 기대는 항목들이 그 값으로 있다', () {
    expect(entry(Source.byeolpyo2, 306).name, '염화 수소 [Hydrogen chloride]');
    expect(entry(Source.byeolpyo2, 4).ko, '구아자틴 염류');
    expect(entry(Source.byeolpyo2, 5).cas, contains('13516-27-3'));
    expect(entry(Source.byeolpyo3, 1).cas, ['50-00-0']);
    expect(entry(Source.byeolpyo2, 510).cas, ['50-00-0']);
    expect(entry(Source.byeolpyo2, 439).deleted, isTrue);
    expect(entry(Source.byeolpyo2, 91).cas, ['123-33-1']);
  });
}
