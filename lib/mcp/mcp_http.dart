/// A-001 원격 MCP — Streamable HTTP 층(상태 없음, 요청마다 JSON 응답 하나, SSE 안 씀).
///
/// `POST /mcp`만 받는다. `GET /mcp`(서버가 먼저 보내는 스트림)는 지원하지 않는다 — 명세상 405로 알린다.
/// 예외: A-001 2차 실험의 `GET /files/findchem-sample.pdf`(고정 이름 하나 — 경로 입력으로 파일을 찾지 않는다).
/// 새 의존성 없이 `dart:io`만 쓴다.
library;

import 'dart:convert';
import 'dart:io';

import 'mcp_handler.dart';
import 'sample_pdf.dart';

const mcpPath = '/mcp';

/// 요청 본문 상한(바이트). 도구 입력은 짧은 문자열뿐이라 넉넉하다 — 넘으면 413.
const maxBodyBytes = 1 << 20;

Future<void> handleMcpHttp(HttpRequest req, McpHandler handler, void Function(String) log) async {
  final res = req.response;
  try {
    if (req.uri.path.startsWith('/files/')) {
      if (req.uri.path != samplePdfPath || req.method != 'GET') {
        res.statusCode = HttpStatus.notFound;
        return;
      }
      final bytes = handler.samplePdfBytes();
      res.statusCode = HttpStatus.ok;
      res.headers.contentType = ContentType('application', 'pdf');
      res.headers.set('content-disposition', 'attachment; filename="$samplePdfName"');
      res.add(bytes);
      return;
    }
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
    final out = handler.handleBody(body, baseUrl: publicBaseUrl(req));
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

/// 이 요청이 들어온 공개 주소. Cloud Run은 TLS를 앞에서 끝내므로 `X-Forwarded-Proto`로 https를 안다.
/// Host가 없으면 null(받는 주소를 만들지 않는다).
Uri? publicBaseUrl(HttpRequest req) {
  final host = req.headers.value(HttpHeaders.hostHeader);
  if (host == null || host.isEmpty) return null;
  final proto = req.headers.value('x-forwarded-proto') == 'https' ? 'https' : 'http';
  return Uri.tryParse('$proto://$host/');
}

void _json(HttpResponse res, int status, Object body) {
  res.statusCode = status;
  res.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
  res.add(utf8.encode(jsonEncode(body)));
}
