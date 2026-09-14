/// F-002 저장본 자리 — 올린 PDF로 만든 원천자료(번들 JSON과 같은 형식)를 기기에 따로 둔다(SCHEMA.md '저장 형식').
///
/// Android는 앱 저장소의 파일, 웹은 브라우저 localStorage. 번들 JSON은 건드리지 않는다 — 되돌리기는 [delete].
library;

import 'update_store_io.dart' if (dart.library.js_interop) 'update_store_web.dart' as platform;

/// 저장본 하나를 통째로 읽고 쓰고 지운다. 부분 갱신은 없다.
abstract interface class UpdateStore {
  /// 저장본 JSON. 없으면 null.
  Future<String?> read();

  /// 저장본을 [json]으로 통째로 바꾼다. 실패하면 예외 — 기존 저장본은 그대로 남아야 한다.
  Future<void> write(String json);

  /// 저장본을 지운다. 없으면 아무 일도 하지 않는다.
  Future<void> delete();
}

/// 이 플랫폼의 저장본 자리(Android·데스크톱 = 파일, 웹 = localStorage).
UpdateStore platformUpdateStore() => platform.createUpdateStore();

/// F-005 자주보는 Chem 목록 자리 — F-002 저장본과 **다른 파일**이다(되돌리기가 지우지 않는다, SCHEMA.md).
/// 같은 "JSON 하나를 통째로" 인터페이스를 쓴다. 웹은 F-005가 앱 전용이라 저장소를 두지 않는다(늘 빈 목록, 쓰기 거부).
UpdateStore platformFavoritesStore() => platform.createFavoritesStore();

/// F-007 data.go.kr 키·연동 선택 자리 — F-002 저장본·F-005 목록과 **다른 파일**이다(SCHEMA.md 'API 키·연동 선택').
UpdateStore platformApiSettingsStore() => platform.createApiSettingsStore();
