/// 추출 층(pdf_graphics)을 pdfplumber 정답지와 셀 단위로 전수 대조한다 — 두 구현의 대조 테스트(CLAUDE.md '구조').
library;

import 'package:findchem/parser/entry_builder.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/parser/pdf_extractor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf_document/pdf_document.dart';

import 'fixtures.dart';

void main() {
  for (final src in Source.values) {
    group(src.label, () {
      late ExtractedPdf extracted;
      late Map<String, Object?> fixture;

      setUpAll(() {
        final sw = Stopwatch()..start();
        extracted = PdfTableExtractor.extract(assetPdf(src).readAsBytesSync());
        // ignore: avoid_print
        print('${src.label}: ${extracted.pageCount}쪽 추출 ${sw.elapsedMilliseconds}ms');
        fixture = loadFixtureJson(src);
      });

      test('페이지 수·생성일이 정답지와 같다', () {
        expect(extracted.pageCount, fixture['pages']);
        expect(extracted.pages.length, (fixture['tables'] as List).length);
        final meta = (fixture['meta'] as Map).cast<String, Object?>();
        expect(extracted.created, pdfDateToIso(meta['CreationDate'] as String));
      });

      test('열·행 경계가 정답지와 1pt 안에서 같다', () {
        final doc = PdfDocument.open(assetPdf(src).readAsBytesSync());
        final tables = (fixture['tables'] as List).cast<Map>();
        for (final t in tables) {
          final page = t['page'] as int;
          final table = PdfTableExtractor.extractPage(doc, page - 1)!;
          final colEdges = (t['col_edges'] as List).cast<num>();
          final rowEdges = (t['row_edges'] as List).cast<num>();
          expect(table.columnEdges.length, colEdges.length, reason: '$page쪽 열 경계 수');
          for (var i = 0; i < colEdges.length; i++) {
            expect(table.columnEdges[i], closeTo(colEdges[i].toDouble(), 1.0), reason: '$page쪽 열 경계 $i');
          }
          expect(table.rowEdgesTop.length, rowEdges.length, reason: '$page쪽 행 경계 수');
          for (var i = 0; i < rowEdges.length; i++) {
            expect(table.rowEdgesTop[i], closeTo(rowEdges[i].toDouble(), 1.0), reason: '$page쪽 행 경계 $i');
          }
        }
      });

      test('모든 셀의 원문(줄바꿈·공백 포함)이 정답지와 같다', () {
        final expected = loadFixtureGrid(src);
        final mismatches = <String>[];
        for (var p = 0; p < expected.length; p++) {
          final exp = expected[p];
          final got = extracted.pages[p];
          expect(got.page, exp.page);
          if (got.rows.length != exp.rows.length) {
            mismatches.add('${exp.page}쪽: 행 수 ${got.rows.length} != ${exp.rows.length}');
            continue;
          }
          for (var r = 0; r < exp.rows.length; r++) {
            for (var c = 0; c < exp.rows[r].length; c++) {
              if (got.rows[r][c] != exp.rows[r][c]) {
                mismatches.add('${exp.page}쪽 ${r + 1}행 ${c + 1}열: "${got.rows[r][c]}" != "${exp.rows[r][c]}"');
              }
            }
          }
        }
        expect(mismatches, isEmpty, reason: '${mismatches.length}건 불일치, 처음 20건:\n${mismatches.take(20).join('\n')}');
      });

      test('빌더까지 통과해 건수 불변식을 만족한다', () {
        final built = buildEntries(src, extracted.pages);
        expect(built.entries.length, src == Source.byeolpyo2 ? 1557 : 100);
        expect(built.warnings, isEmpty);
      });
    });
  }

  test('PDF 날짜 → ISO 8601', () {
    expect(pdfDateToIso("D:20260720091624+09'00'"), '2026-07-20T09:16:24+09:00');
    expect(pdfDateToIso('D:20260720'), '2026-07-20T00:00:00Z');
    expect(pdfDateToIso('D:20260720091624Z'), '2026-07-20T09:16:24Z');
    expect(pdfDateToIso('2026-07-20'), '2026-07-20');
  });
}
