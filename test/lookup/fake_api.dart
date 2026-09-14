/// 테스트 공용: 공공데이터 API 자리. 2026-09-14 CAS 50-00-0 실호출 원문(`test/fixtures/api/`)을 돌려주고 호출을 기록한다.
/// 실호출은 자동 테스트에 넣지 않는다(CLAUDE.md 테스트 규칙).
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/lookup/api_settings.dart';
import 'package:findchem/lookup/chem_api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final Map<ChemService, String> fixtures = {
  ChemService.chem: File('test/fixtures/api/chem_50-00-0.json').readAsStringSync(),
  ChemService.ghs: File('test/fixtures/api/ghs_50-00-0.json').readAsStringSync(),
  ChemService.safety: File('test/fixtures/api/safety_50-00-0.xml').readAsStringSync(),
};

ChemService serviceOfUrl(Uri u) => ChemService.values.firstWhere((s) => Uri.parse(endpointOf(s)).path == u.path);

http.Response utf8Response(String body, int status) => http.Response.bytes(utf8.encode(body), status);

/// 포털 공통 오류 본문(키 미등록 30, 한도 초과 22 등) — HTTP 200으로도 온다.
String portalError(String code) =>
    '<OpenAPI_ServiceResponse><cmmMsgHeader><errMsg>SERVICE ERROR</errMsg>'
    '<returnAuthMsg>ERR</returnAuthMsg><returnReasonCode>$code</returnReasonCode></cmmMsgHeader></OpenAPI_ServiceResponse>';

class FakeApi {
  final List<Uri> calls = [];

  /// 서비스별로 fixture 대신 돌려줄 응답.
  final Map<ChemService, Future<http.Response> Function()> overrides = {};

  late final http.Client httpClient = MockClient((req) async {
    calls.add(req.url);
    final s = serviceOfUrl(req.url);
    final o = overrides[s];
    if (o != null) return o();
    return utf8Response(fixtures[s]!, 200);
  });

  ChemApiClient client({Duration timeout = const Duration(seconds: 20)}) =>
      ChemApiClient(httpClient: httpClient, timeout: timeout);

  int callsTo(ChemService s) => calls.where((u) => serviceOfUrl(u) == s).length;
}

/// F-007 설정 파일 JSON.
String apiSettingsJson({String? key = 'TESTKEY', Map<String, bool>? services}) => jsonEncode({
  'version': 1,
  'serviceKey': ?key,
  'services': services ?? {'chem': true, 'ghs': true, 'safety': true},
});
