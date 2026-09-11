/// 테스트 공용: pdfplumber 정답지(`test/fixtures/*_cells.json`)를 [PageGrid]로 읽는다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/parser/cell_grid.dart';
import 'package:findchem/parser/models.dart';

String fixturePath(Source src) => 'test/fixtures/${src.name}_cells.json';

/// 별표 PDF 파일 경로(assets/). 파일명이 한글이라 접두사로 찾는다.
File assetPdf(Source src) {
  final prefix = src == Source.byeolpyo2 ? '[별표 2]' : '[별표 3]';
  final hits = Directory('assets')
      .listSync()
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.startsWith(prefix) && f.path.endsWith('.pdf'))
      .toList();
  if (hits.length != 1) throw StateError('$prefix PDF가 정확히 1개여야 한다: $hits');
  return hits.single;
}

Map<String, Object?> loadFixtureJson(Source src) =>
    (jsonDecode(File(fixturePath(src)).readAsStringSync()) as Map).cast<String, Object?>();

List<PageGrid> loadFixtureGrid(Source src) {
  final j = loadFixtureJson(src);
  return (j['tables'] as List).map((t) {
    final table = (t as Map).cast<String, Object?>();
    return PageGrid(
      page: table['page'] as int,
      rows: (table['rows'] as List).map((r) => (r as List).cast<String>()).toList(),
    );
  }).toList();
}
