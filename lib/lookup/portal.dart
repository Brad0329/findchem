/// data.go.kr 포털 공통 — 키 가리기, 포털 사유 코드, 실패 문구(F-007 REQUIREMENTS '실패 문구').
///
/// **Flutter를 import하지 않는다**(A-003 Q1, 2026-10-02): F-007 앱·웹과 원격 MCP 서버(순수 Dart)가 같이 쓴다.
/// `chem_api.dart`에 있던 것을 동작 그대로 옮겼고 `chem_api.dart`가 다시 내보낸다.
library;

import 'dart:developer' as developer;

/// 화면 문구(테스트가 같은 상수를 본다).
abstract final class LookupText {
  static const badKey = '키가 올바르지 않습니다';
  static const notApproved = '이 서비스의 활용신청이 승인되지 않았습니다';
  static const overLimit = '오늘 호출 한도를 넘었습니다';
  static const offline = '접속하지 못했습니다';
  static String failed(String code) => '조회하지 못했습니다 (코드 $code)';

  static const noKey = '설정 → data.go.kr API 키에서 키를 넣으세요';
  static const noService = '설정 → 연동 데이터에서 조회할 정보를 고르세요';
  static const settingsUnreadable = '설정을 읽지 못했습니다';

  static const loading = '조회 중…';
  static const noResult = '조회 결과 없음';
  static const noPictogram = '그림 없음';
  static String title(String cas) => 'CAS $cas 공공데이터 조회';
  static String truncated(int total, int shown) => '$total건 중 $shown건 표시 · 더 있음';
}

/// [text]에서 키(넣은 형태와 인코딩/디코딩한 형태 둘 다)를 `<KEY>`로 바꾼다.
/// 다른 표기를 만들지 못하면 [onWarn]에 사유를 남긴다(키 자체는 쓰지 않는다).
String maskKey(String text, String key, {void Function(String)? onWarn}) {
  if (key.isEmpty) return text;
  var out = text.replaceAll(key, '<KEY>');
  String? other;
  try {
    other = key.contains('%') ? Uri.decodeQueryComponent(key) : Uri.encodeQueryComponent(key);
  } on ArgumentError catch (e) {
    // 잘못된 % 표기라 다른 형태가 없다 — 넣은 형태만 가린다(키 자체는 로그에 쓰지 않는다)
    final msg = '키의 다른 표기를 만들지 못해 원형만 가림: ${e.runtimeType}';
    onWarn != null ? onWarn(msg) : developer.log(msg, name: 'portal');
  }
  if (other != null && other.isNotEmpty && other != key) out = out.replaceAll(other, '<KEY>');
  // Uri는 %xx를 대문자로 바꿔 적는다 — 소문자로 넣은 인코딩 키가 요청 주소(접속 오류 문구)에서 새지 않게
  final upper = key.replaceAllMapped(RegExp('%[0-9a-fA-F]{2}'), (m) => m[0]!.toUpperCase());
  if (upper != key) out = out.replaceAll(upper, '<KEY>');
  return out;
}

/// 포털 공통 오류(키 미등록·한도 초과 등)의 사유 코드. HTTP 200으로도 온다. 없으면 null.
String? portalReasonCode(String body) =>
    RegExp(r'returnReasonCode\W+(\d+)').firstMatch(body)?.group(1);

/// 실패 판정(REQUIREMENTS F-007 '실패 문구').
String failureMessage(int status, String? portalCode) {
  if (status == 401) return LookupText.badKey;
  if (status == 403 || portalCode == '30') return LookupText.notApproved;
  if (portalCode == '22') return LookupText.overLimit;
  return LookupText.failed(portalCode ?? '$status');
}
