/// A-010 원문 저장소 — API 응답 원문을 `assets/form6/raw/`에 두는 규칙(REQUIREMENTS_AGENT A-010 D2).
///
/// 수집(`scripts/collect_form6.dart`)은 [RecordingClient]로 실호출하며 응답을 그대로 저장하고,
/// 생성(`scripts/build_form6.dart`)은 [ReplayClient]로 같은 요청에 저장본을 돌려준다 — 두 쪽이 **같은 파일 이름 규칙**([rawNameOf])을 쓴다.
/// 그래서 생성은 실호출과 같은 해석 코드(`MsdsClient`·`parseGhsResponse`)를 네트워크 없이 탄다.
///
/// **Flutter를 import하지 않는다** — `dart run`으로 돈다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../lookup/portal.dart';

/// 요청 주소 → 원문 파일의 상대 경로. 모르는 요청이면 null(저장·재생하지 않는다).
///
/// - KOSHA 목록 `getChemList001?searchWrd=<cas>&pageNo=<n>` → `kosha/list_<cas>_p<n>.xml`
/// - KOSHA 상세 `getChemDetail<절>1?chemId=<id>` → `kosha/detail<절>_<id>.xml`
/// - 환경공단 GHS `ghsList?searchNm=<cas>` → `ghs/<cas>.json`
String? rawNameOf(Uri uri) {
  final service = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
  final q = uri.queryParameters;
  if (service == 'getChemList001') {
    final cas = q['searchWrd'], page = q['pageNo'] ?? '1';
    return cas == null ? null : 'kosha/list_${cas}_p$page.xml';
  }
  final detail = RegExp(r'^getChemDetail(\d{2})1$').firstMatch(service);
  if (detail != null) {
    final id = q['chemId'];
    return id == null ? null : 'kosha/detail${detail.group(1)}_$id.xml';
  }
  if (service == 'ghsList') {
    final cas = q['searchNm'];
    return cas == null ? null : 'ghs/$cas.json';
  }
  return null;
}

/// 실호출하며 응답 원문을 [dir]에 저장한다. 키 문자열이 응답에 들어 있으면 저장하지 않는다(키가 커밋되지 않게 — A-003과 같다).
/// 접속 실패는 3번까지 다시 부른다(공공데이터 포털이 간헐적으로 끊는다 — record_msds.dart 실측).
class RecordingClient extends http.BaseClient {
  RecordingClient(this._inner, {required this.dir, required this.key, required this.log});

  final http.Client _inner;
  final String dir;
  final String key;
  final void Function(String) log;

  /// 저장하지 못한 요청(사유) — 수집 끝에 보고한다.
  final failures = <String>[];

  /// 저장한 파일 수.
  int saved = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final name = rawNameOf(request.url);
    http.Response? res;
    for (var attempt = 1; res == null; attempt++) {
      try {
        res = await http.Response.fromStream(await _inner.send(_copy(request)));
      } catch (e) {
        log('접속 실패 ${name ?? request.url.path} (시도 $attempt/3): ${maskKey('$e', key)}');
        if (attempt >= 3) {
          failures.add('${name ?? request.url.path}: 접속 실패');
          rethrow;
        }
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
    }
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (name == null) {
      failures.add('${request.url.path}: 이름 규칙에 없는 요청 — 저장 안 함');
    } else if (maskKey(body, key) != body) {
      failures.add('$name: 키 문자열이 응답에 있다 — 저장 안 함');
    } else if (res.statusCode != 200 || portalReasonCode(body) != null) {
      // 실패 응답은 저장하지 않는다 — 저장하면 생성이 '자료 없음'으로 오해한다. 다시 수집해야 한다
      failures.add('$name: HTTP ${res.statusCode}, 포털 코드 ${portalReasonCode(body)} — 저장 안 함');
    } else {
      final f = File('$dir/$name');
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(res.bodyBytes); // 원문 바이트 그대로
      saved++;
    }
    return http.StreamedResponse(Stream.value(res.bodyBytes), res.statusCode, headers: res.headers, request: request);
  }

  static http.Request _copy(http.BaseRequest r) => http.Request(r.method, r.url)..headers.addAll(r.headers);

  @override
  void close() => _inner.close();
}

/// 원문 파일 읽기 — CRLF를 LF로 되돌린다. 받은 원문에는 CR이 없는데(2026-10-19 515개 전수) Windows git(`core.autocrlf=true`)이
/// 체크아웃 때 CRLF로 바꿔 놓아, 그대로 읽으면 같은 원문에서 다른 생성물이 나온다.
String readRawText(File f) => f.readAsStringSync().replaceAll('\r\n', '\n');

/// 저장본으로 답한다. 없는 파일은 [missing]에 적고 404 — 생성은 이 목록이 비어 있지 않으면 실패한다(빈 값으로 조용히 채우지 않는다).
class ReplayClient extends http.BaseClient {
  ReplayClient({required this.dir});

  final String dir;
  final missing = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final name = rawNameOf(request.url);
    final f = name == null ? null : File('$dir/$name');
    if (f == null || !f.existsSync()) {
      missing.add(name ?? request.url.toString());
      return http.StreamedResponse(Stream.value(utf8.encode('원문 없음 $name')), 404, request: request);
    }
    final bytes = utf8.encode(readRawText(f));
    return http.StreamedResponse(Stream.value(bytes), 200, request: request, contentLength: bytes.length);
  }
}
