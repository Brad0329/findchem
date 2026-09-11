/// 저장본 — 웹: 브라우저 localStorage 키 하나(약 0.6MB, 브라우저 한도 5MB 안). 사이트 데이터를 지우면 함께 지워진다.
library;

import 'package:web/web.dart' as web;

import 'update_store.dart';

UpdateStore createUpdateStore() => LocalStorageUpdateStore();

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
