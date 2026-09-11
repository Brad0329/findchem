/// F-002 원천자료 update의 판정 — 고른 PDF 두 개를 같은 Dart 파서(lib/parser)로 읽어 [Dataset] 하나로 만든다.
///
/// 저장·화면과 무관한 순수 함수라 실제 PDF로 테스트한다. 어느 하나라도 실패하면 [UpdateFailure]를 던지고
/// 아무것도 만들지 않는다 — 부분 적용은 없다(REQUIREMENTS F-002: 두 PDF를 함께).
library;

import 'package:flutter/foundation.dart';

import '../parser/cell_grid.dart' show ParseException;
import '../parser/entry_builder.dart';
import '../parser/models.dart';
import '../parser/pdf_extractor.dart';

/// 사용자가 고른 PDF 한 개.
class PickedPdf {
  const PickedPdf({required this.name, required this.bytes});

  /// 파일명(저장본 `source.*.file`에 들어간다).
  final String name;
  final Uint8List bytes;
}

/// 적용하지 않은 이유. [message]는 화면에 그대로 보여준다.
class UpdateFailure implements Exception {
  const UpdateFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

/// 파싱 결과 + 사람이 봐야 할 경고(형식이 어긋난 CAS 등 — 실패는 아니다).
class ParsedUpdate {
  const ParsedUpdate({required this.dataset, required this.warnings});
  final Dataset dataset;
  final List<String> warnings;
}

/// [pdfs]의 두 자리(인체·생태 유해성, 사고대비물질)를 모두 채워야 한다. [now]는 적용 시각(저장본 `extractedAt`).
ParsedUpdate parseSourcePdfs(Map<Source, PickedPdf?> pdfs, {DateTime? now}) {
  final missing = [for (final src in Source.values) if (pdfs[src] == null) src.label];
  if (missing.isNotEmpty) {
    throw UpdateFailure('${missing.join('·')} PDF를 고르지 않았습니다. 두 PDF를 함께 골라야 적용됩니다');
  }

  // 화면 사유에는 상태와 표 검증 사유만 — 원본 예외(라이브러리 내부 문구 등)는 로그에만 둔다(보안 3층 ①).
  // 둘 다 틀렸으면 두 사유를 함께 보여준다(하나 고치고 다시 올렸다가 또 실패하지 않게).
  final infos = <Source, PdfInfo>{};
  final entries = <Entry>[];
  final warnings = <String>[];
  final failures = <String>[];
  for (final src in Source.values) {
    final pdf = pdfs[src]!;
    final where = '${src.label} 자리의 "${pdf.name}"';
    final ExtractedPdf extracted;
    try {
      extracted = PdfTableExtractor.extract(pdf.bytes);
    } catch (e, st) {
      // PDF 라이브러리가 던지는 예외 종류는 정해져 있지 않다(깨진 파일·PDF 아닌 파일) — 전부 실패 사유로 올린다.
      debugPrint('F-002 ${src.label} PDF 읽기 실패 (${pdf.name}): $e\n$st');
      failures.add('$where을 PDF로 읽지 못했습니다');
      continue;
    }
    try {
      final built = buildEntries(src, extracted.pages);
      infos[src] = PdfInfo(file: pdf.name, created: extracted.created, pages: extracted.pageCount);
      entries.addAll(built.entries);
      warnings.addAll(built.warnings);
    } on ParseException catch (e) {
      debugPrint('F-002 ${src.label} 표 검증 실패 (${pdf.name}): $e');
      failures.add('$where: ${e.reason}');
    } catch (e, st) {
      // 파서 결함(예상하지 못한 예외) — 저장 실패로 오인되지 않게 여기서 사유를 붙인다.
      debugPrint('F-002 ${src.label} 표 읽기 중 예상하지 못한 오류 (${pdf.name}): $e\n$st');
      failures.add('$where의 표를 읽다 예상하지 못한 오류가 났습니다(로그 참조)');
    }
  }
  if (failures.isNotEmpty) throw UpdateFailure(failures.join(' / '));
  for (final w in warnings) {
    debugPrint('F-002 경고: $w');
  }

  return ParsedUpdate(
    dataset: Dataset(
      byeolpyo2: infos[Source.byeolpyo2]!,
      byeolpyo3: infos[Source.byeolpyo3]!,
      extractedAt: (now ?? DateTime.now()).toUtc().toIso8601String(),
      entries: entries,
    ),
    warnings: warnings,
  );
}
