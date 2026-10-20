/// A-010 원문 저장소 — API 응답 원문을 `assets/form6/raw/`의 **원천별 압축 묶음**에 둔다(REQUIREMENTS_AGENT A-010 D2, SCHEMA.md 2026-10-20).
///
/// - `kosha.json.gz`·`ghs.json.gz` = 요청 이름([rawNameOf]) → 응답 원문 글자(UTF-8), 키 정렬. 묶음 이름은 요청 이름의 앞마디(`kosha/…`)다.
/// - 수집(`scripts/collect_form6.dart`)은 [RecordingClient]로 실호출하며 응답을 [RawStore]에 넣고,
///   생성(`scripts/build_form6.dart`)은 [ReplayClient]로 같은 요청에 저장본을 돌려준다 — 두 쪽이 **같은 이름 규칙**을 쓴다.
///   그래서 생성은 실호출과 같은 해석 코드(`MsdsClient`·`parseGhsResponse`)를 네트워크 없이 탄다.
/// - 압축 파일은 git의 줄바꿈 변환(autocrlf)을 타지 않는다 — 파일 하나씩 둘 때 필요했던 CRLF 되돌리기가 없어졌다.
///
/// **Flutter를 import하지 않는다** — `dart run`으로 돈다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../lookup/portal.dart';

/// 묶음 이름(요청 이름의 앞마디).
const rawArchives = ['kosha', 'ghs'];

/// 요청 주소 → 원문 이름. 모르는 요청이면 null(저장·재생하지 않는다).
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

/// 원천별 압축 묶음 — 메모리에 올려 읽고 쓴다.
class RawStore {
  RawStore._(this.dir, this._byArchive);

  /// [dir]의 묶음을 읽는다. 없는 묶음은 빈 것으로(처음 수집).
  factory RawStore.load(String dir) => RawStore._(dir, {
        for (final a in rawArchives)
          a: () {
            final f = File('$dir/$a.json.gz');
            if (!f.existsSync()) return <String, String>{};
            return (jsonDecode(utf8.decode(gzip.decode(f.readAsBytesSync()))) as Map).cast<String, String>();
          }(),
      });

  final String dir;
  final Map<String, Map<String, String>> _byArchive;

  static (String, String)? _split(String name) {
    final i = name.indexOf('/');
    if (i < 0) return null;
    final a = name.substring(0, i);
    return rawArchives.contains(a) ? (a, name) : null;
  }

  String? get(String name) {
    final s = _split(name);
    return s == null ? null : _byArchive[s.$1]![s.$2];
  }

  /// 넣는다. 모르는 묶음 이름이면 false.
  bool put(String name, String text) {
    final s = _split(name);
    if (s == null) return false;
    _byArchive[s.$1]![s.$2] = text;
    return true;
  }

  int count(String archive) => _byArchive[archive]?.length ?? 0;

  /// 묶음마다 키 정렬 JSON → gzip. 같은 내용이면 같은 내용의 압축을 쓴다(키 정렬 — 수집 순서와 무관).
  void save() {
    Directory(dir).createSync(recursive: true);
    for (final a in rawArchives) {
      final m = _byArchive[a]!;
      final sorted = {for (final k in m.keys.toList()..sort()) k: m[k]};
      final tmp = File('$dir/$a.json.gz.tmp');
      tmp.writeAsBytesSync(gzip.encode(utf8.encode(jsonEncode(sorted))));
      tmp.renameSync('$dir/$a.json.gz'); // 다 쓴 뒤 이름을 바꿔 반쯤 쓰인 묶음이 남지 않게
    }
  }
}

/// 실호출하며 응답 원문을 [store]에 넣는다. 키 문자열이 응답에 들어 있으면 넣지 않는다(키가 커밋되지 않게 — A-003과 같다).
/// 접속 실패는 3번까지 다시 부른다(공공데이터 포털이 간헐적으로 끊는다 — record_msds.dart 실측).
class RecordingClient extends http.BaseClient {
  RecordingClient(this._inner, {required this.store, required this.key, required this.log});

  final http.Client _inner;
  final RawStore store;
  final String key;
  final void Function(String) log;

  /// 넣지 못한 요청(사유) — 수집 끝에 보고한다.
  final failures = <String>[];

  /// 넣은 응답 수.
  int saved = 0;

  /// 포털이 '한도 초과'(코드 22)를 돌려준 적이 있다 — 수집기는 이걸 보고 멈춘다(남은 호출을 버리지 않게).
  bool quotaExceeded = false;

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
    final portal = portalReasonCode(body);
    if (portal == '22') quotaExceeded = true;
    if (name == null) {
      failures.add('${request.url.path}: 이름 규칙에 없는 요청 — 저장 안 함');
    } else if (maskKey(body, key) != body) {
      failures.add('$name: 키 문자열이 응답에 있다 — 저장 안 함');
    } else if (res.statusCode != 200 || portal != null) {
      // 실패 응답은 넣지 않는다 — 넣으면 생성이 '자료 없음'으로 오해한다. 다시 수집해야 한다
      failures.add('$name: HTTP ${res.statusCode}, 포털 코드 $portal — 저장 안 함');
    } else {
      store.put(name, body);
      saved++;
    }
    return http.StreamedResponse(Stream.value(res.bodyBytes), res.statusCode, headers: res.headers, request: request);
  }

  static http.Request _copy(http.BaseRequest r) => http.Request(r.method, r.url)..headers.addAll(r.headers);

  @override
  void close() => _inner.close();
}

/// 저장본으로 답한다. 없는 원문은 [missing]에 적고 404 — 생성은 이 목록이 비어 있지 않으면 실패한다(빈 값으로 조용히 채우지 않는다).
class ReplayClient extends http.BaseClient {
  ReplayClient(this.store);

  final RawStore store;
  final missing = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final name = rawNameOf(request.url);
    final text = name == null ? null : store.get(name);
    if (text == null) {
      missing.add(name ?? request.url.toString());
      return http.StreamedResponse(Stream.value(utf8.encode('원문 없음 $name')), 404, request: request);
    }
    final bytes = utf8.encode(text);
    return http.StreamedResponse(Stream.value(bytes), 200, request: request, contentLength: bytes.length);
  }
}
