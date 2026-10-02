/// A-001 수용 기준 — 원격 MCP 프로토콜(JSON-RPC)과 HTTP 층. 실제 번들 데이터에 직접 질의한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/assist/assist_response.dart';
import 'package:findchem/assist/prompt.dart';
import 'package:findchem/mcp/mcp_handler.dart';
import 'package:findchem/mcp/mcp_http.dart';
import 'package:findchem/mcp/sample_pdf.dart';
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

    test('tools/list — 앞 두 도구는 이름·설명·스키마가 assistToolDefinitions와 같고, 셋째가 실험 도구 sample_pdf', () {
      final tools = (result(call('tools/list'))['tools']! as List).cast<Map>();
      final defs = assistToolDefinitions();
      expect(tools.map((t) => t['name']), ['search_chemical', 'get_rule', 'sample_pdf']);
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

  group('시험 PDF (A-001 2차)', () {
    test('%PDF-로 시작해 %%EOF로 끝나고, xref 오프셋마다 그 위치에 N 0 obj가 있다', () {
      final text = latin1.decode(mcp.samplePdfBytes());
      expect(text.startsWith('%PDF-'), true);
      expect(text.trimRight().endsWith('%%EOF'), true);
      final startxref = int.parse(RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!);
      expect(text.substring(startxref).startsWith('xref'), true);
      final offsets = RegExp(r'^(\d{10}) 00000 n $', multiLine: true)
          .allMatches(text)
          .map((m) => int.parse(m.group(1)!))
          .toList();
      expect(offsets, hasLength(5));
      for (var i = 0; i < offsets.length; i++) {
        expect(text.substring(offsets[i]).startsWith('${i + 1} 0 obj'), true, reason: '객체 ${i + 1}');
      }
      expect(() => buildSamplePdf(['한글']), throwsArgumentError);
    });

    test('tools/call sample_pdf — resource_link는 공개 주소 기준, 내장 blob은 같은 바이트. 주소를 모르면 링크를 뺀다', () {
      final r = (mcp.handleMessage({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': 'sample_pdf'},
      }, baseUrl: Uri.parse('https://example.run.app/'))!['result']! as Map);
      final content = (r['content']! as List).cast<Map>();
      expect(content.map((c) => c['type']), ['text', 'resource_link', 'resource']);
      expect(content[1]['uri'], 'https://example.run.app/files/findchem-sample.pdf');
      expect(base64Decode((content[2]['resource'] as Map)['blob'] as String), mcp.samplePdfBytes());

      final noBase = (result(call('tools/call', {'name': 'sample_pdf'}))['content']! as List).cast<Map>();
      expect(noBase.map((c) => c['type']), ['text', 'resource']);
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
      expect(((jsonDecode(b) as Map)['result'] as Map)['tools'], hasLength(3));

      final (s2, b2, _) = await send('POST', '/mcp', jsonEncode({'jsonrpc': '2.0', 'method': 'notifications/initialized'}));
      expect(s2, 202);
      expect(b2, isEmpty);

      expect((await send('GET', '/mcp')).$1, 405);
      expect((await send('POST', '/other', '{}')).$1, 404);
    });

    test('GET /files/findchem-sample.pdf — 200 application/pdf attachment, 바이트가 같다. 다른 이름 404. 링크는 Host·X-Forwarded-Proto 기준', () async {
      final req = await client.getUrl(base.resolve(samplePdfPath));
      final res = await req.close();
      final bytes = await res.fold<List<int>>([], (a, b) => a..addAll(b));
      expect(res.statusCode, 200);
      expect(res.headers.contentType?.mimeType, 'application/pdf');
      expect(res.headers.value('content-disposition'), contains('attachment'));
      expect(bytes, mcp.samplePdfBytes());
      expect((await send('GET', '/files/other.pdf')).$1, 404);
      expect((await send('GET', '/files/../mcp')).$1, isNot(200));

      final call = await client.postUrl(base.resolve('/mcp'));
      call.headers.set('x-forwarded-proto', 'https');
      call.add(utf8.encode(jsonEncode({
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'tools/call',
        'params': {'name': 'sample_pdf'},
      })));
      final body = jsonDecode(await utf8.decodeStream(await call.close())) as Map;
      final link = ((body['result'] as Map)['content'] as List)[1] as Map;
      expect(link['uri'], 'https://127.0.0.1:${server.port}/files/findchem-sample.pdf');
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
  Object? handleBody(String body, {Uri? baseUrl}) => throw StateError('boom');
}
