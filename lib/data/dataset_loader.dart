/// 데이터 로딩 경로 — CLAUDE.md 기본 구조 ②: "저장본 우선, 없으면 번들".
///
/// 지금은 번들만 있다. F-002(Phase 005)가 기기 저장본을 넣으면 [loadDataset]이 먼저 저장본을 찾고 없을 때
/// [loadBundledDataset]으로 떨어진다 — 분기는 이 파일 한 곳에만 둔다.
library;

import 'dart:convert';

import 'package:flutter/services.dart';

import '../parser/models.dart';

/// pubspec의 `assets/data/`에 등록된 번들 JSON.
const bundledDataAsset = 'assets/data/findchem_data.json';

/// 앱이 검색에 쓸 데이터. (저장본 분기는 Phase 005에서 여기에 붙는다.)
Future<Dataset> loadDataset({AssetBundle? bundle}) => loadBundledDataset(bundle: bundle);

Future<Dataset> loadBundledDataset({AssetBundle? bundle}) async {
  final text = await (bundle ?? rootBundle).loadString(bundledDataAsset);
  return Dataset.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
}
