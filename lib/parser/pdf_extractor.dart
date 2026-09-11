/// PDF → 셀 격자([PageGrid]) 추출 층. pdf_graphics(순수 Dart)로 텍스트 런과 괘선을 받아 표를 복원한다.
///
/// 방법(2026-09-11 실측 근거는 test/fixtures의 pdfplumber 정답지):
/// 1. 페이지 내용을 인터프리터로 돌려 텍스트 런(`drawText`)과 경로(`strokePath`/`fillPath`)를 모은다.
///    괘선은 페이지 좌표(y-up)로 온다.
/// 2. 수직 선분의 x, 수평 선분의 y를 1pt 안에서 군집해 열 경계·행 경계로 삼는다.
/// 3. 텍스트 런을 중심점으로 (행, 열)에 배정한다. 행 경계에 그 열을 가로지르는 수평선이 없으면 위아래 셀이
///    병합된 것이므로 위쪽 행에 붙인다(pdfplumber와 같은 결과: 병합 셀 글은 첫 행, 아래 행은 빈 문자열).
/// 4. 셀 안에서는 기준선 y로 줄을 나누고(줄 간격 8.4pt, 허용 2pt) x 순서로 잇는다. 런 사이 간격이 글자 폭
///    이상이면(3pt, pdfplumber x_tolerance) 공백 하나를 넣는다. 줄은 `\n`으로 잇는다 — 줄바꿈 규칙은 빌더가 적용한다.
library;

import 'dart:typed_data';

import 'package:pdf_cos/pdf_cos.dart' show CosDictionary, CosString;
import 'package:pdf_document/pdf_document.dart';
import 'package:pdf_graphics/pdf_graphics.dart';

import 'cell_grid.dart';

/// 추출 결과: 페이지별 격자와 PDF 정보.
class ExtractedPdf {
  const ExtractedPdf({required this.pages, required this.pageCount, required this.created});

  /// 표가 있는 페이지의 격자(페이지 순). 표가 없는 페이지는 빠진다.
  final List<PageGrid> pages;
  final int pageCount;

  /// PDF 메타데이터 `/CreationDate`(ISO 8601). 없거나 못 읽으면 null.
  final String? created;
}

/// 페이지 좌표의 수평/수직 선분.
class _Segment {
  const _Segment(this.a, this.b, this.c);

  /// 고정 좌표(수평선이면 y, 수직선이면 x)와 구간 [a, b].
  final double a;
  final double b;
  final double c;
}

/// 텍스트 한 조각(런)과 그 페이지 좌표. [order]는 내용 스트림 순서 — 폭 0 런(U+200B 등)의 x 정렬 동률을 가른다.
class _Piece {
  const _Piece(this.text, this.left, this.right, this.baseline, this.order);
  final String text;
  final double left;
  final double right;
  final double baseline;
  final int order;
}

class _CollectingDevice implements PdfDevice {
  final List<_Piece> pieces = [];
  final List<_Segment> horizontal = [];
  final List<_Segment> vertical = [];

  static const _straight = 0.5; // 이만큼보다 덜 기울면 수평/수직으로 본다

  /// 이보다 짧은 선분은 괘선이 아니다 — 1쪽 서문의 Type3 글리프 획(7pt 글자)이 경로로 들어온다(2026-09-11 실측).
  static const _minLength = 8.0;

  void _addLine(double x1, double y1, double x2, double y2) {
    if ((y1 - y2).abs() <= _straight && (x1 - x2).abs() > _minLength) {
      horizontal.add(_Segment(x1 < x2 ? x1 : x2, x1 < x2 ? x2 : x1, (y1 + y2) / 2));
    } else if ((x1 - x2).abs() <= _straight && (y1 - y2).abs() > _minLength) {
      vertical.add(_Segment(y1 < y2 ? y1 : y2, y1 < y2 ? y2 : y1, (x1 + x2) / 2));
    }
  }

  void _addPath(PdfPath path, {required bool filled}) {
    double? startX, startY, curX, curY;
    final points = <(double, double)>[];
    void flushSubpath() {
      // 채운 경로는 얇은 직사각형(괘선)이면 선분으로, 그 외(머리글 배경 등)는 무시한다.
      if (filled && points.length >= 4) {
        final xs = points.map((p) => p.$1);
        final ys = points.map((p) => p.$2);
        final minX = xs.reduce((a, b) => a < b ? a : b);
        final maxX = xs.reduce((a, b) => a > b ? a : b);
        final minY = ys.reduce((a, b) => a < b ? a : b);
        final maxY = ys.reduce((a, b) => a > b ? a : b);
        if (maxY - minY <= 1.5 && maxX - minX > _minLength) {
          horizontal.add(_Segment(minX, maxX, (minY + maxY) / 2));
        } else if (maxX - minX <= 1.5 && maxY - minY > _minLength) {
          vertical.add(_Segment(minY, maxY, (minX + maxX) / 2));
        }
      }
      points.clear();
    }

    for (final seg in path.segments) {
      switch (seg) {
        case PdfMoveTo(:final x, :final y):
          flushSubpath();
          startX = curX = x;
          startY = curY = y;
          points.add((x, y));
        case PdfLineTo(:final x, :final y):
          if (!filled && curX != null && curY != null) _addLine(curX, curY, x, y);
          curX = x;
          curY = y;
          points.add((x, y));
        case PdfCubicTo(:final x3, :final y3):
          curX = x3;
          curY = y3;
          points.add((x3, y3));
        case PdfClosePath():
          if (!filled && curX != null && curY != null && startX != null && startY != null) {
            _addLine(curX, curY, startX, startY);
          }
          if (startX != null && startY != null) {
            curX = startX;
            curY = startY;
          }
      }
    }
    flushSubpath();
  }

  @override
  void drawText(PdfTextRun run) {
    if (run.text.isEmpty) return;
    final t = run.transform;
    final left = t.transformX(0, 0);
    final right = t.transformX(run.width, 0);
    pieces.add(_Piece(
      run.text,
      left < right ? left : right,
      left < right ? right : left,
      t.transformY(0, 0),
      pieces.length,
    ));
  }

  @override
  void strokePath(PdfPath path, PdfColor color, PdfStroke stroke, double alpha) =>
      _addPath(path, filled: false);

  @override
  void fillPath(PdfPath path, PdfColor color, PdfFillRule rule, double alpha) =>
      _addPath(path, filled: true);

  @override
  void save() {}
  @override
  void restore() {}
  @override
  void fillPathGradient(PdfPath path, PdfFillRule rule, PdfGradient gradient, double alpha) {}
  @override
  void fillMesh(PdfMesh mesh, double alpha) {}
  @override
  void clipPath(PdfPath path, PdfFillRule rule) {}
  @override
  void drawImage(PdfImageRequest request) {}
  @override
  void setBlendMode(PdfBlendMode mode) {}
  @override
  void setOverprint({required bool fill, required bool stroke, required int mode}) {}
  @override
  void beginGroup(double alpha, {bool knockout = false}) {}
  @override
  void endGroup() {}
  @override
  void beginSoftMasked() {}
  @override
  void endSoftMasked({
    required bool luminosity,
    required PdfRect backdrop,
    required void Function() drawMask,
    double backdropLuminance = 0,
    double transferScale = 1,
    double transferOffset = 0,
  }) {}
}

/// 선분의 고정 좌표를 [tolerance] 안에서 군집해 대표값(평균)의 오름차순 목록으로.
/// 군집의 선분 길이 합이 [minTotalLength]보다 작으면 괘선 경계가 아니라고 보고 버린다.
List<double> _clusterEdges(List<_Segment> segments, double tolerance, double minTotalLength) {
  final sorted = [...segments]..sort((a, b) => a.c.compareTo(b.c));
  final out = <double>[];
  var sum = 0.0;
  var length = 0.0;
  var n = 0;
  void flush() {
    if (n > 0 && length >= minTotalLength) out.add(sum / n);
    sum = 0;
    length = 0;
    n = 0;
  }

  for (final s in sorted) {
    if (n > 0 && s.c - sum / n > tolerance) flush();
    sum += s.c;
    length += s.b - s.a;
    n++;
  }
  flush();
  return out;
}

int _bandOf(List<double> edges, double v) {
  // edges 오름차순. v가 [edges[i], edges[i+1]) 이면 i. 밖이면 -1.
  for (var i = 0; i + 1 < edges.length; i++) {
    if (v >= edges[i] && v < edges[i + 1]) return i;
  }
  return -1;
}

/// 한 페이지의 표 기하(테스트·진단용으로도 노출).
class PageTable {
  const PageTable({required this.page, required this.columnEdges, required this.rowEdgesTop, required this.grid});

  final int page;

  /// 열 경계 x(오름차순).
  final List<double> columnEdges;

  /// 행 경계를 위에서부터(pdfplumber의 top 좌표, 페이지 높이 - y).
  final List<double> rowEdgesTop;
  final PageGrid grid;
}

class PdfTableExtractor {
  PdfTableExtractor._();

  static const _edgeTolerance = 1.0;
  static const _lineTolerance = 2.0;
  static const _wordGap = 3.0;

  /// 경계 하나가 되려면 그 좌표의 선분 길이 합이 이만큼은 돼야 한다(가장 좁은 열 ≈ 22pt, 가장 낮은 행 ≈ 12pt).
  static const _minEdgeLength = 10.0;

  /// 페이지 하나의 표를 복원한다. 괘선 격자가 없으면(열 2개 미만·행 2개 미만) null.
  static PageTable? extractPage(PdfDocument doc, int pageIndex) {
    final page = doc.page(pageIndex);
    final device = _CollectingDevice();
    PdfInterpreter(cos: doc.cos, device: device, resolveOverprint: false).drawPage(page);

    final pageHeight = page.mediaBox.top;
    final columnEdges = _clusterEdges(device.vertical, _edgeTolerance, _minEdgeLength);
    if (columnEdges.length < 2) return null;

    // 표의 세로 범위 = 열 경계에 속한 수직 괘선의 y 범위. 그 밖의 수평선(1쪽 서문의 밑줄 등)은 행 경계가 아니다.
    var tableBottom = double.infinity;
    var tableTop = double.negativeInfinity;
    for (final s in device.vertical) {
      if (columnEdges.any((x) => (s.c - x).abs() <= _edgeTolerance)) {
        if (s.a < tableBottom) tableBottom = s.a;
        if (s.b > tableTop) tableTop = s.b;
      }
    }
    final tableLeft = columnEdges.first;
    final tableRight = columnEdges.last;
    final tableLines = device.horizontal
        .where((s) =>
            s.c >= tableBottom - _edgeTolerance &&
            s.c <= tableTop + _edgeTolerance &&
            s.b >= tableLeft - _edgeTolerance &&
            s.a <= tableRight + _edgeTolerance)
        .toList();
    final rowEdgesY = _clusterEdges(tableLines, _edgeTolerance, _minEdgeLength); // y-up 오름차순
    if (rowEdgesY.length < 2) return null;

    final columns = columnEdges.length - 1;
    final rows = rowEdgesY.length - 1;

    // 행 경계 k(아래에서 k번째 수평 경계)가 열 j를 가로지르는가 — 아니면 병합 셀.
    bool crosses(int k, int j) {
      final y = rowEdgesY[k];
      final x0 = columnEdges[j];
      final x1 = columnEdges[j + 1];
      final mid = (x0 + x1) / 2;
      return tableLines.any((s) => (s.c - y).abs() <= _edgeTolerance && s.a <= mid && s.b >= mid);
    }

    // cells[row][col] — row는 위에서부터(0 = 맨 위). 각 셀은 줄(기준선별) 조각 목록.
    final cells = List.generate(rows, (_) => List.generate(columns, (_) => <_Piece>[]));
    for (final p in device.pieces) {
      final cx = (p.left + p.right) / 2;
      final col = _bandOf(columnEdges, cx);
      var band = _bandOf(rowEdgesY, p.baseline + 2.0); // 기준선은 글자 아래쪽 — 살짝 올려 잰다
      if (col < 0 || band < 0) continue; // 표 밖 텍스트(서문·쪽번호)
      // 병합 셀이면 위쪽(y가 큰 쪽) 행으로 올린다
      while (band + 1 < rows && !crosses(band + 1, col)) {
        band++;
      }
      final rowFromTop = rows - 1 - band;
      cells[rowFromTop][col].add(p);
    }

    final gridRows = <List<String>>[];
    for (final row in cells) {
      gridRows.add([for (final cell in row) _cellText(cell)]);
    }

    return PageTable(
      page: pageIndex + 1,
      columnEdges: columnEdges,
      rowEdgesTop: rowEdgesY.reversed.map((y) => pageHeight - y).toList(),
      grid: PageGrid(page: pageIndex + 1, rows: gridRows),
    );
  }

  static String _cellText(List<_Piece> pieces) {
    if (pieces.isEmpty) return '';
    final sorted = [...pieces]..sort((a, b) => b.baseline.compareTo(a.baseline));
    final lines = <List<_Piece>>[];
    for (final p in sorted) {
      if (lines.isNotEmpty && (lines.last.first.baseline - p.baseline).abs() <= _lineTolerance) {
        lines.last.add(p);
      } else {
        lines.add([p]);
      }
    }
    final out = <String>[];
    for (final line in lines) {
      line.sort((a, b) {
        final byX = a.left.compareTo(b.left);
        return byX != 0 ? byX : a.order.compareTo(b.order);
      });
      final buf = StringBuffer();
      _Piece? prev;
      for (final p in line) {
        if (prev != null &&
            p.left - prev.right > _wordGap &&
            !prev.text.endsWith(' ') &&
            !p.text.startsWith(' ')) {
          buf.write(' ');
        }
        buf.write(p.text);
        prev = p;
      }
      out.add(buf.toString());
    }
    return out.join('\n');
  }

  /// 문서 전체. 표가 있는 페이지만 담는다.
  static ExtractedPdf extract(Uint8List bytes) {
    final doc = PdfDocument.open(bytes);
    final pages = <PageGrid>[];
    for (var i = 0; i < doc.pageCount; i++) {
      final table = extractPage(doc, i);
      if (table != null) pages.add(table.grid);
    }
    return ExtractedPdf(pages: pages, pageCount: doc.pageCount, created: creationDate(doc));
  }

  /// `/Info /CreationDate`(`D:20260720091624+09'00'`)를 ISO 8601로. 형식이 다르면 원문 그대로, 없으면 null.
  static String? creationDate(PdfDocument doc) {
    final info = doc.cos.resolve(doc.cos.trailer['Info']);
    if (info is! CosDictionary) return null;
    final raw = doc.cos.resolve(info['CreationDate']);
    if (raw is! CosString) return null;
    return pdfDateToIso(raw.text);
  }
}

final _pdfDate = RegExp(r"^D:(\d{4})(\d{2})(\d{2})(\d{2})?(\d{2})?(\d{2})?([+\-Z])?(\d{2})?'?(\d{2})?'?");

/// PDF 날짜 문자열(§7.9.4)을 ISO 8601로. 맞지 않으면 원문 그대로 돌려준다(버리지 않는다).
String pdfDateToIso(String s) {
  final m = _pdfDate.firstMatch(s);
  if (m == null) return s;
  final date = '${m[1]}-${m[2]}-${m[3]}T${m[4] ?? '00'}:${m[5] ?? '00'}:${m[6] ?? '00'}';
  final sign = m[7];
  if (sign == null || sign == 'Z') return '${date}Z';
  return "$date$sign${m[8] ?? '00'}:${m[9] ?? '00'}";
}
