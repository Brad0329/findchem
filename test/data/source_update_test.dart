/// F-002 수용 기준 1·2·3 중 파싱 판정 — 실제 assets/ PDF로 [parseSourcePdfs]를 돌린다(모킹 없음).
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:findchem/data/source_update.dart';
import 'package:findchem/parser/models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../parser/fixtures.dart';

void main() {
  late Dataset bundled;
  late PickedPdf pdf2;
  late PickedPdf pdf3;

  setUpAll(() {
    bundled = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
    PickedPdf picked(Source src) {
      final f = assetPdf(src);
      return PickedPdf(name: f.uri.pathSegments.last, bytes: f.readAsBytesSync());
    }

    pdf2 = picked(Source.byeolpyo2);
    pdf3 = picked(Source.byeolpyo3);
  });

  Matcher failure(Matcher message) =>
      throwsA(isA<UpdateFailure>().having((f) => f.message, 'message', message));

  test('현재 assets/의 PDF 2개 → 1,557건과 100건, 앱에 들어 있는 데이터와 같다', () {
    final r = parseSourcePdfs(
      {Source.byeolpyo2: pdf2, Source.byeolpyo3: pdf3},
      now: DateTime.utc(2026, 9, 12, 1, 2, 3),
    );
    final ds = r.dataset;
    expect(ds.count(Source.byeolpyo2), 1557);
    expect(ds.count(Source.byeolpyo3), 100);
    expect(ds.entries.length, bundled.entries.length);
    for (var i = 0; i < ds.entries.length; i++) {
      expect(jsonEncode(ds.entries[i].toJson()), jsonEncode(bundled.entries[i].toJson()), reason: '$i번째');
    }
    // 파일명·생성일·쪽수도 번들 머리와 같다(파일명은 고른 파일의 이름)
    expect(ds.byeolpyo2.toJson(), bundled.byeolpyo2.toJson());
    expect(ds.byeolpyo3.toJson(), bundled.byeolpyo3.toJson());
    expect(ds.extractedAt, '2026-09-12T01:02:03.000Z', reason: '적용 시각이 저장본 extractedAt');
  });

  test('하나만 고르면 적용하지 않고 무엇이 빠졌는지 알린다', () {
    expect(
      () => parseSourcePdfs({Source.byeolpyo2: pdf2, Source.byeolpyo3: null}),
      failure(allOf(startsWith('사고대비물질 PDF를 고르지 않았습니다'), isNot(contains('인체')))),
    );
    expect(
      () => parseSourcePdfs({Source.byeolpyo2: null, Source.byeolpyo3: pdf3}),
      failure(startsWith('인체·생태 유해성 PDF를 고르지 않았습니다')),
    );
    expect(() => parseSourcePdfs({}), failure(startsWith('인체·생태 유해성·사고대비물질 PDF를 고르지 않았습니다')));
  });

  test('두 파일을 서로 바꿔 고르거나 같은 파일을 두 자리에 고르면 적용하지 않는다(표 형식 검증)', () {
    // 둘 다 틀렸으면 두 사유를 함께
    expect(
      () => parseSourcePdfs({Source.byeolpyo2: pdf3, Source.byeolpyo3: pdf2}),
      failure(allOf(
        startsWith('인체·생태 유해성 자리의 "${pdf3.name}": 인체·생태 유해성 1쪽: 열이 9개여야 하는데 7개입니다'),
        contains(' / 사고대비물질 자리의 "${pdf2.name}": 사고대비물질 1쪽: 열이 7개여야 하는데 9개입니다'),
      )),
    );
    expect(
      () => parseSourcePdfs({Source.byeolpyo2: pdf2, Source.byeolpyo3: pdf2}),
      failure(allOf(startsWith('사고대비물질 자리의 "${pdf2.name}": '), contains('열이 7개여야'))),
    );
  });

  test('PDF가 아닌 파일이면 적용하지 않고 사유를 돌려준다', () {
    final junk = PickedPdf(name: 'memo.pdf', bytes: Uint8List.fromList(utf8.encode('이것은 PDF가 아니다')));
    expect(
      () => parseSourcePdfs({Source.byeolpyo2: pdf2, Source.byeolpyo3: junk}),
      // 라이브러리 예외 문구(CosParseException …)는 로그에만 — 화면 사유는 상태만
      failure(equals('사고대비물질 자리의 "memo.pdf"을 PDF로 읽지 못했습니다')),
    );
  });
}
