// 번들 JSON 빌드: assets/의 별표 PDF 2개 → assets/data/findchem_data.json
//
//   dart run scripts/build_data.dart
//
// 앱의 F-002(원천자료 update)와 같은 Dart 파서(lib/parser)를 쓴다 — 파서는 하나뿐이다(plan.md).
// entries·source가 기존 파일과 같으면 파일을 건드리지 않는다(extractedAt만 바뀌는 무의미한 diff 방지).
import 'dart:convert';
import 'dart:io';

import 'package:findchem/parser/entry_builder.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/parser/pdf_extractor.dart';

const outputPath = 'assets/data/findchem_data.json';

File findPdf(Source src) {
  final prefix = src == Source.byeolpyo2 ? '[별표 2]' : '[별표 3]';
  final hits = Directory('assets')
      .listSync()
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.startsWith(prefix) && f.path.endsWith('.pdf'))
      .toList();
  if (hits.length != 1) {
    stderr.writeln('$prefix PDF가 assets/에 정확히 1개여야 합니다: ${hits.map((f) => f.path).toList()}');
    exit(2);
  }
  return hits.single;
}

/// 한 항목 = 한 줄로 직렬화(diff 가독성).
String encodeDataset(Dataset ds) {
  final j = ds.toJson();
  final source = jsonEncode(j['source']);
  final entries = (j['entries'] as List).map(jsonEncode).join(',\n');
  return '{"source":$source,\n"entries":[\n$entries\n]}\n';
}

void main() {
  final sw = Stopwatch()..start();
  final infos = <Source, PdfInfo>{};
  final entries = <Entry>[];
  for (final src in Source.values) {
    final file = findPdf(src);
    final extracted = PdfTableExtractor.extract(file.readAsBytesSync());
    final built = buildEntries(src, extracted.pages);
    for (final w in built.warnings) {
      stderr.writeln('경고: $w');
    }
    infos[src] = PdfInfo(
      file: file.uri.pathSegments.last,
      created: extracted.created,
      pages: extracted.pageCount,
    );
    entries.addAll(built.entries);
    stdout.writeln('${src.label}: ${extracted.pageCount}쪽, ${built.entries.length}건, 경고 ${built.warnings.length}건');
  }

  final out = File(outputPath);
  String? previousExtractedAt;
  if (out.existsSync()) {
    final old = Dataset.fromJson((jsonDecode(out.readAsStringSync()) as Map).cast<String, Object?>());
    final oldBody = encodeDataset(Dataset(
      byeolpyo2: old.byeolpyo2, byeolpyo3: old.byeolpyo3, extractedAt: '', entries: old.entries));
    final newBody = encodeDataset(Dataset(
      byeolpyo2: infos[Source.byeolpyo2]!, byeolpyo3: infos[Source.byeolpyo3]!, extractedAt: '', entries: entries));
    if (oldBody == newBody) {
      stdout.writeln('변경 없음: $outputPath 그대로 둡니다 (${sw.elapsedMilliseconds}ms)');
      return;
    }
    previousExtractedAt = old.extractedAt;
  }

  final ds = Dataset(
    byeolpyo2: infos[Source.byeolpyo2]!,
    byeolpyo3: infos[Source.byeolpyo3]!,
    extractedAt: DateTime.now().toUtc().toIso8601String(),
    entries: entries,
  );
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(encodeDataset(ds));
  stdout.writeln('${previousExtractedAt == null ? '생성' : '갱신(이전 $previousExtractedAt)'}: $outputPath '
      '${out.lengthSync()} bytes, ${entries.length}건 (${sw.elapsedMilliseconds}ms)');
}
