/// A-001 원격 MCP — Streamable HTTP 층(상태 없음, 요청마다 JSON 응답 하나, SSE 안 씀).
///
/// `POST /mcp`만 받는다. `GET /mcp`(서버가 먼저 보내는 스트림)는 지원하지 않는다 — 명세상 405로 알린다.
/// 새 의존성 없이 `dart:io`만 쓴다.
library;

import 'dart:convert';
import 'dart:io';

import 'mcp_handler.dart';

const mcpPath = '/mcp';

/// 요청 본문 상한(바이트). 도구 입력은 짧은 문자열뿐이라 넉넉하다 — 넘으면 413.
const maxBodyBytes = 1 << 20;

Future<void> handleMcpHttp(HttpRequest req, McpHandler handler, void Function(String) log) async {
  final res = req.response;
  try {
    if (req.uri.path != mcpPath) {
      res.statusCode = HttpStatus.notFound;
      return;
    }
    if (req.method != 'POST') {
      res.statusCode = HttpStatus.methodNotAllowed;
      res.headers.set(HttpHeaders.allowHeader, 'POST');
      return;
    }
    final bytes = <int>[];
    await for (final chunk in req) {
      bytes.addAll(chunk);
      if (bytes.length > maxBodyBytes) {
        log('A-001 MCP: 본문이 ${bytes.length}바이트를 넘어 거부(상한 $maxBodyBytes)');
        res.statusCode = HttpStatus.requestEntityTooLarge;
        return;
      }
    }
    final String body;
    try {
      body = utf8.decode(bytes);
    } on FormatException catch (e) {
      log('A-001 MCP: UTF-8 아님 — $e');
      _json(res, HttpStatus.badRequest, {
        'jsonrpc': '2.0',
        'id': null,
        'error': {'code': RpcError.parse, 'message': 'Parse error'},
      });
      return;
    }
    final out = handler.handleBody(body);
    if (out == null) {
      // 알림만 왔다 — 명세대로 202, 본문 없음.
      res.statusCode = HttpStatus.accepted;
      return;
    }
    _json(res, HttpStatus.ok, out);
  } catch (e, st) {
    log('A-001 MCP: 처리 중 예외 — $e\n$st');
    try {
      _json(res, HttpStatus.internalServerError, McpHandler.internalError());
    } catch (e2) {
      // 헤더를 이미 보냈으면 상태를 못 바꾼다 — 그 사실만 남긴다.
      log('A-001 MCP: 오류 응답도 쓰지 못함 — $e2');
    }
  } finally {
    await res.close();
  }
}

void _json(HttpResponse res, int status, Object body) {
  res.statusCode = status;
  res.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
  res.add(utf8.encode(jsonEncode(body)));
}
