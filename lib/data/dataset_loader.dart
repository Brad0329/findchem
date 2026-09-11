/// 데이터 로딩 경로 — CLAUDE.md 기본 구조 ②: "저장본 우선, 없으면 번들".
///
/// 분기는 이 파일 한 곳에만 둔다. [DataController]가 앱이 쓰는 현재 데이터를 들고, F-002의 적용·되돌리기가
/// 여기로 들어온다(저장본 쓰기/지우기 → 화면에 알림).
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../parser/models.dart';
import 'update_store.dart';

/// pubspec의 `assets/data/`에 등록된 번들 JSON.
const bundledDataAsset = 'assets/data/findchem_data.json';

Future<Dataset> loadBundledDataset({AssetBundle? bundle}) async {
  final text = await (bundle ?? rootBundle).loadString(bundledDataAsset);
  return Dataset.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
}

/// 지금 쓰는 데이터가 어디서 왔나.
enum DataOrigin { bundled, updated }

class LoadedData {
  const LoadedData(this.dataset, this.origin, {this.storedError});

  final Dataset dataset;
  final DataOrigin origin;

  /// 저장본이 있었지만 읽지 못해 번들로 떨어진 경우 그 사유(설정 화면에 보여준다). 정상이면 null.
  final String? storedError;

  /// 기기에 저장본이 있다(쓰는 중이거나, 깨져서 못 쓰는 중) — 되돌리기로 지울 대상이 있다.
  bool get hasStored => origin == DataOrigin.updated || storedError != null;
}

/// 저장본이 있으면 그것, 없거나 못 읽으면 번들.
Future<LoadedData> loadDataset({
  required UpdateStore store,
  Future<Dataset> Function()? loadBundled,
}) async {
  String? storedError;
  try {
    final text = await store.read();
    if (text != null) {
      final ds = Dataset.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
      return LoadedData(ds, DataOrigin.updated);
    }
  } catch (e, st) {
    // 저장본이 깨졌어도 검색은 돼야 한다 — 번들로 떨어지되 사유를 로그와 설정 화면에 남긴다(지우지는 않는다).
    debugPrint('저장본 읽기 실패, 번들을 씁니다: $e\n$st');
    storedError = '저장된 update 원천자료를 읽지 못해 앱에 들어 있는 데이터를 씁니다. 되돌리기로 지울 수 있습니다';
  }
  final bundled = await (loadBundled ?? loadBundledDataset)();
  return LoadedData(bundled, DataOrigin.bundled, storedError: storedError);
}

/// 앱이 검색에 쓰는 현재 데이터. 적용·되돌리기가 끝나면 듣는 화면(검색·설정)이 다시 그린다.
class DataController extends ChangeNotifier {
  DataController({required this.store, Future<Dataset> Function()? loadBundled})
    : _loadBundled = loadBundled ?? loadBundledDataset;

  final UpdateStore store;
  final Future<Dataset> Function() _loadBundled;

  LoadedData? _data;

  /// [load]가 끝나기 전에는 null.
  LoadedData? get data => _data;

  Future<LoadedData> load() async {
    final loaded = await loadDataset(store: store, loadBundled: _loadBundled);
    _data = loaded;
    notifyListeners();
    return loaded;
  }

  /// 저장본을 [ds]로 통째로 바꾸고 바로 쓴다. 저장이 실패하면 예외 — 현재 데이터는 그대로다.
  Future<void> apply(Dataset ds) async {
    await store.write(jsonEncode(ds.toJson()));
    _data = LoadedData(ds, DataOrigin.updated);
    notifyListeners();
  }

  /// 저장본을 지우고 번들로 돌아간다.
  Future<void> reset() async {
    // 번들을 먼저 읽는다 — 읽다 실패하면 저장본을 지우지 않은 채로 끝나야 한다(쓸 데이터가 없어진다).
    final bundled = await _loadBundled();
    await store.delete();
    _data = LoadedData(bundled, DataOrigin.bundled);
    notifyListeners();
  }
}
