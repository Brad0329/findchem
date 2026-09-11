/// 셀 격자([PageGrid]) → [Entry] 목록. PDF 라이브러리와 무관한 정규화 층.
///
/// 행 구조(Phase 001 실측): 연번이 있는 행이 항목 시작, 연번이 빈 행은 같은 항목의 다른 '구분' 행.
/// 머리글은 매 페이지 첫 행에 반복된다. 검증(표 형식·연번 연속)에 실패하면 [ParseException]을 던진다 —
/// F-002는 이 사유를 화면에 보여주고 기존 원천자료를 그대로 둔다.
library;

import 'cas.dart';
import 'cell_grid.dart';
import 'models.dart';
import 'name_split.dart';

/// 별표별 표 형식. 머리글 대조는 공백을 전부 뺀 뒤 한다(셀 줄바꿈 자리에 공백이 남는다).
class TableLayout {
  const TableLayout._({
    required this.src,
    required this.header,
    required this.colNo,
    required this.colUid,
    required this.colName,
    required this.colCas,
    required this.colKind,
    required this.colContent,
    required this.colMin,
    required this.colLow,
    required this.colHigh,
  });

  final Source src;
  final List<String> header;
  final int colNo;
  final int? colUid;
  final int colName;
  final int colCas;

  /// 구분 열. 별표3에는 없다(null) — 둘째 행의 구분은 물질명 열에 온다.
  final int? colKind;
  final int colContent;
  final int colMin;
  final int colLow;
  final int colHigh;

  int get columns => header.length;

  static const byeolpyo2 = TableLayout._(
    src: Source.byeolpyo2,
    header: ['연번', '고유번호', '화학물질명', 'CAS번호', '구분', '함량기준(% 이상)',
      '최하위규정수량(톤)', '하위규정수량(톤)', '상위규정수량(톤)'],
    colNo: 0, colUid: 1, colName: 2, colCas: 3, colKind: 4, colContent: 5,
    colMin: 6, colLow: 7, colHigh: 8,
  );

  static const byeolpyo3 = TableLayout._(
    src: Source.byeolpyo3,
    header: ['번호', '사고대비물질명', 'CAS번호', '함량기준(% 이상)',
      '최하위규정수량(톤)', '하위규정수량(톤)', '상위규정수량(톤)'],
    colNo: 0, colUid: null, colName: 1, colCas: 2, colKind: null, colContent: 3,
    colMin: 4, colLow: 5, colHigh: 6,
  );

  static TableLayout of(Source src) => switch (src) {
    Source.byeolpyo2 => byeolpyo2,
    Source.byeolpyo3 => byeolpyo3,
  };
}

final _whitespace = RegExp(r'\s+');
String _squash(String s) => s.replaceAll(_whitespace, '');

/// 셀 안 줄바꿈 제거(Phase 001 규칙, 2026-09-11 정답지로 재확인): 단어 경계 줄바꿈은 앞 줄 끝에 공백이 남아
/// 있고(`Lead ⏎2,4,6`) 단어 중간 줄바꿈에는 없어서(`Fo⏎rmaldehyde`) `\n`만 지우면 원문이 된다.
/// CAS 열은 예외 — 줄바꿈이 구분자이기도 해서 [parseCasCell]이 줄 단위로 읽는다.
String _joinLines(String cell) => cell.replaceAll('\n', '').trim();

/// 빌드 결과. [warnings]는 실패는 아니지만 사람이 봐야 할 것(형식 어긋난 CAS 등) — 조용히 넘기지 않는다.
class BuildResult {
  const BuildResult({required this.entries, required this.warnings, required this.exceptionsUsed});

  final List<Entry> entries;
  final List<String> warnings;

  /// 이름 분리 예외 목록에서 실제로 쓰인 원문 이름들(손으로 만든 목록의 자동 검증용).
  final Set<String> exceptionsUsed;
}

/// 격자를 항목으로 만든다. 첫 항목 번호는 1이어야 하고 연번은 연속이어야 한다.
BuildResult buildEntries(Source src, List<PageGrid> pages) {
  final layout = TableLayout.of(src);
  final label = src.label;
  final entries = <Entry>[];
  final warnings = <String>[];
  final exceptionsUsed = <String>{};

  if (pages.isEmpty) throw ParseException('$label: 표가 없습니다');

  // 현재 조립 중인 항목
  int? curNo;
  String? curUid;
  String? curName;
  List<String>? curCas;
  List<QuantityRow>? curRows;

  void flush() {
    if (curNo == null) return;
    final name = curName!;
    final split = splitName(name);
    if (split.usedException) exceptionsUsed.add(name.trim());
    final rows = curRows!;
    final deleted = src == Source.byeolpyo2 && rows.any((r) => r.kind == '(삭제)');
    if (deleted && rows.length != 1) {
      warnings.add('$label 연번 $curNo: (삭제) 항목인데 행이 ${rows.length}개');
    }
    entries.add(Entry(
      src: src,
      no: curNo!,
      uid: curUid,
      name: name,
      ko: split.ko,
      en: split.en,
      cas: curCas!,
      deleted: deleted,
      rows: rows,
    ));
    curNo = null;
  }

  for (final page in pages) {
    final where = '$label ${page.page}쪽';
    if (page.rows.isEmpty) throw ParseException('$where: 표 행이 없습니다');
    final header = page.rows.first;
    if (header.length != layout.columns) {
      throw ParseException('$where: 열이 ${layout.columns}개여야 하는데 ${header.length}개입니다');
    }
    for (var c = 0; c < layout.columns; c++) {
      if (_squash(header[c]) != _squash(layout.header[c])) {
        throw ParseException('$where: 첫 행이 $label 머리글이 아닙니다 (${c + 1}열 "${header[c]}")');
      }
    }

    for (var r = 1; r < page.rows.length; r++) {
      final raw = page.rows[r];
      if (raw.length != layout.columns) {
        throw ParseException('$where ${r + 1}행: 열이 ${layout.columns}개여야 하는데 ${raw.length}개입니다');
      }
      final row = [
        for (var c = 0; c < raw.length; c++) c == layout.colCas ? raw[c].trim() : _joinLines(raw[c]),
      ];
      final noText = row[layout.colNo];
      final rowWhere = '$where ${r + 1}행';

      if (noText.isNotEmpty) {
        final no = int.tryParse(noText);
        if (no == null) throw ParseException('$rowWhere: 연번이 숫자가 아닙니다 "$noText"');
        flush();
        final expected = entries.isEmpty ? 1 : entries.last.no + 1;
        if (no != expected) {
          throw ParseException('$rowWhere: 연번이 $expected이어야 하는데 $no입니다');
        }
        curNo = no;
        curUid = layout.colUid == null ? null : row[layout.colUid!];
        final nameCell = row[layout.colName];
        if (nameCell.isEmpty) throw ParseException('$rowWhere: 물질명이 비어 있습니다');
        curName = nameCell;
        curCas = parseCasCell(row[layout.colCas], warnings: warnings, where: '$label 연번 $no');
        curRows = [_quantityRow(layout, row, kind: layout.colKind == null ? '' : row[layout.colKind!])];
      } else {
        if (curNo == null) throw ParseException('$rowWhere: 연번 없는 행이 항목보다 먼저 나왔습니다');
        // 이어지는 행: 고유번호·CAS는 비어 있어야 한다. 물질명은 별표2면 비어야 하고, 별표3은 '용액' 구분이 온다.
        if (layout.colUid != null && row[layout.colUid!].isNotEmpty) {
          throw ParseException('$rowWhere: 연번 없는 행에 고유번호가 있습니다');
        }
        if (row[layout.colCas].isNotEmpty) {
          throw ParseException('$rowWhere: 연번 없는 행에 CAS가 있습니다');
        }
        final String kind;
        if (layout.colKind != null) {
          if (row[layout.colName].isNotEmpty) {
            throw ParseException('$rowWhere: 연번 없는 행에 물질명이 있습니다');
          }
          kind = row[layout.colKind!];
        } else {
          kind = row[layout.colName];
        }
        curRows!.add(_quantityRow(layout, row, kind: kind));
      }
    }
  }
  flush();

  if (entries.isEmpty) throw ParseException('$label: 항목이 하나도 없습니다');
  return BuildResult(entries: entries, warnings: warnings, exceptionsUsed: exceptionsUsed);
}

QuantityRow _quantityRow(TableLayout layout, List<String> row, {required String kind}) =>
    QuantityRow(
      kind: kind,
      content: row[layout.colContent],
      min: row[layout.colMin],
      low: row[layout.colLow],
      high: row[layout.colHigh],
    );
