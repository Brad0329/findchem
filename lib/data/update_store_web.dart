/// 저장본 — 웹: 브라우저 localStorage 키 하나(약 0.6MB, 브라우저 한도 5MB 안). 사이트 데이터를 지우면 함께 지워진다.
library;

import 'package:web/web.dart' as web;

import 'update_store.dart';

UpdateStore createUpdateStore() => LocalStorageUpdateStore();

UpdateStore createFavoritesStore() => const NoFavoritesStore();

/// F-005는 앱 전용이다(2026-09-12 사용자 결정) — 웹에는 저장 목록이 없다. 화면이 저장 아이콘을 그리지 않으므로
/// 쓰기가 들어오면 결함이라 조용히 삼키지 않고 예외를 던진다.
class NoFavoritesStore implements UpdateStore {
  const NoFavoritesStore();

  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String json) async => throw UnsupportedError('웹에는 자주보는 Chem 목록을 저장하지 않습니다');

  @override
  Future<void> delete() async {}
}

class LocalStorageUpdateStore implements UpdateStore {
  static const key = 'findchem_update';

  @override
  Future<String?> read() async => web.window.localStorage.getItem(key);

  /// 한도를 넘으면 setItem이 예외(QuotaExceededError)를 던지고 기존 값은 그대로 남는다.
  @override
  Future<void> write(String json) async => web.window.localStorage.setItem(key, json);

  @override
  Future<void> delete() async => web.window.localStorage.removeItem(key);
}
