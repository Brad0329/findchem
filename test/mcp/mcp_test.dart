/// A-001 수용 기준 — 원격 MCP 프로토콜(JSON-RPC)과 HTTP 층. 실제 번들 데이터에 직접 질의한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/assist/assist_response.dart';
import 'package:findchem/assist/prompt.dart';
import 'package:findchem/mcp/mcp_handler.dart';
import 'package:findchem/mcp/mcp_http.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/search/search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Dataset ds;
  late McpHandler mcp;
  final logs = <String>[];

  setUpAll(() {
    ds = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
    mcp = McpHandler(ds, version: 'test', log: logs.add);
  });
  setUp(logs.clear);

  Map<String, Object?> call(String method, [Map<String, Object?>? params, Object? id = 1]) =>
      mcp.handleMessage({'jsonrpc': '2.0', 'id': id, 'method': method, 'params': ?params})!;

  Map<String, Object?> result(Map<String, Object?> r) => (r['result']! as Map).cast<String, Object?>();

  group('프로토콜', () {
    test('initialize — 아는 판은 그대로, 모르는 판은 최신. instructions = 시스템 프롬프트', () {
      final r = result(call('initialize', {'protocolVersion': '2025-06-18'}));
      expect(r['protocolVersion'], '2025-06-18');
      expect((r['capabilities']! as Map).containsKey('tools'), true);
      expect((r['serverInfo']! as Map)['name'], 'findchem');
      expect(r['instructions'], assistSystemPrompt);

      expect(result(call('initialize', {'protocolVersion': '1999-01-01'}))['protocolVersion'], mcpProtocolVersions.first);
    });

    test('tools/list — 앞 두 도구는 assistToolDefinitions와 같고, A-004 계산 도구 2개가 뒤에 붙는다', () {
      final tools = (result(call('tools/list'))['tools']! as List).cast<Map>();
      final defs = assistToolDefinitions();
      expect(tools.map((t) => t['name']),
          ['search_chemical', 'get_rule', 'calc_writing_level', 'screen_preliminary_scenarios']);
      for (var i = 0; i < defs.length; i++) {
        expect(tools[i]['description'], defs[i]['description']);
        expect(jsonEncode(tools[i]['inputSchema']), jsonEncode(defs[i]['input_schema']));
      }
    });

    test('tools/call search_chemical 50-00-0 — 앱과 같은 응답 JSON', () {
      final r = result(call('tools/call', {
        'name': 'search_chemical',
        'arguments': {'query': '50-00-0'},
      }));
      expect(r['isError'], false);
      final text = ((r['content']! as List).single as Map)['text'] as String;
      final expected = searchResponse(SearchIndex(ds, cap: assistSearchCap).search('50-00-0'), ds);
      expect(jsonDecode(text), jsonDecode(jsonEncode(expected)));
      expect((jsonDecode(text) as Map)['coverage']['status'], 'exact');
    });

    test('get_rule 없는 주제·알 수 없는 도구 — isError + 사유, 로그에 남는다', () {
      final r = result(call('tools/call', {
        'name': 'get_rule',
        'arguments': {'topic': '없는토픽'},
      }));
      expect(r['isError'], true);
      expect(((r['content']! as List).single as Map)['text'], contains('없는토픽'));

      final u = result(call('tools/call', {'name': 'nope', 'arguments': <String, Object?>{}}));
      expect(u['isError'], true);
      expect(logs.length, 2);
    });

    test('알림은 응답 없음, 모르는 메서드 -32601, JSON 아님 -32700, ping 빈 결과', () {
      expect(mcp.handleMessage({'jsonrpc': '2.0', 'method': 'notifications/initialized'}), isNull);
      expect((call('resources/list')['error']! as Map)['code'], RpcError.methodNotFound);
      expect(((mcp.handleBody('{oops')! as Map)['error']! as Map)['code'], RpcError.parse);
      expect(result(call('ping')), isEmpty);
    });
  });

  group('HTTP', () {
    late HttpServer server;
    late Uri base;
    final client = HttpClient();

    setUpAll(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) => handleMcpHttp(req, mcp, logs.add));
      base = Uri.parse('http://127.0.0.1:${server.port}');
    });
    tearDownAll(() async {
      client.close(force: true);
      await server.close(force: true);
    });

    Future<(int, String, ContentType?)> send(String method, String path, [String? body]) async {
      final req = await client.openUrl(method, base.resolve(path));
      if (body != null) {
        req.headers.contentType = ContentType.json;
        req.add(utf8.encode(body));
      }
      final res = await req.close();
      return (res.statusCode, await utf8.decodeStream(res), res.headers.contentType);
    }

    test('POST /mcp 200 JSON, 알림 202 빈 본문, GET 405, 다른 경로 404', () async {
      final (s, b, ct) = await send('POST', '/mcp', jsonEncode({'jsonrpc': '2.0', 'id': 7, 'method': 'tools/list'}));
      expect(s, 200);
      expect(ct?.mimeType, 'application/json');
      expect(((jsonDecode(b) as Map)['result'] as Map)['tools'], hasLength(4));

      final (s2, b2, _) = await send('POST', '/mcp', jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));
      expect(s2, 202);
      expect(b2, isEmpty);

      expect((await send('GET', '/mcp')).$1, 405);
      expect((await send('POST', '/other', '{}')).$1, 404);
    });

    test('처리 중 예외 — 500 + 사유 없는 오류, 원인은 로그에', () async {
      final broken = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      broken.listen((req) => handleMcpHttp(req, _Throwing(ds), logs.add));
      final req = await client.postUrl(Uri.parse('http://127.0.0.1:${broken.port}/mcp'));
      req.add(utf8.encode('{}'));
      final res = await req.close();
      final body = await utf8.decodeStream(res);
      await broken.close(force: true);
      expect(res.statusCode, 500);
      expect(((jsonDecode(body) as Map)['error'] as Map)['message'], 'Internal error');
      expect(body, isNot(contains('boom')));
      expect(logs.any((l) => l.contains('boom')), true);
    });
  });
}

class _Throwing extends McpHandler {
  _Throwing(super.dataset) : super(version: 'test', log: (_) {});

  @override
  Object? handleBody(String body) => throw StateError('boom');
}
