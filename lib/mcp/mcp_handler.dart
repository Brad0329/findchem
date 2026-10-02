/// A-001 원격 MCP — JSON-RPC 메시지 하나를 받아 응답 하나를 돌려주는 층(HTTP와 무관).
///
/// - 도구 실행은 앱ㆍ웹 판정 도우미와 **같은 [AssistTools.run]**, 도구 설명ㆍ시스템 프롬프트는
///   `lib/assist/prompt.dart` 하나다 — 두 번째 구현 금지(REQUIREMENTS_AGENT A-001).
/// - 상태가 없다: 세션 ID를 쓰지 않고, `initialize` 없이 온 `tools/call`도 처리한다
///   (Cloud Run이 인스턴스를 바꿔도 깨지지 않게).
/// - Flutter를 import하지 않는다 — `dart compile exe`로 돈다.
library;

import 'dart:convert';

import '../assist/prompt.dart';
import '../assist/tools.dart';
import '../parser/models.dart';
import 'sample_pdf.dart';

/// 지원하는 MCP 프로토콜 판(최신이 앞). 클라이언트가 보낸 판이 여기 있으면 그대로 돌려준다.
const mcpProtocolVersions = ['2025-11-25', '2025-06-18', '2025-03-26', '2024-11-05'];

/// JSON-RPC 오류 코드.
abstract final class RpcError {
  static const parse = -32700;
  static const invalidRequest = -32600;
  static const methodNotFound = -32601;
  static const invalidParams = -32602;
  static const internal = -32603;
}

class McpHandler {
  McpHandler(Dataset dataset, {required this.version, required this.log})
      : _tools = AssistTools(dataset, log: log);

  /// `serverInfo.version`(배포 판 구분용).
  final String version;
  final void Function(String message) log;
  final AssistTools _tools;

  /// 요청 본문(JSON 문자열) 하나를 처리한다. 돌려줄 응답이 없으면(알림뿐) null.
  /// 배치(배열)도 받는다 — 2025-03-26 판 클라이언트가 보낼 수 있다.
  /// [baseUrl]은 이 서버의 공개 주소(`sample_pdf`의 받는 주소를 만든다). 없으면 그 길은 빠진다.
  Object? handleBody(String body, {Uri? baseUrl}) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException catch (e) {
      log('A-001 MCP: JSON 아님 — $e');
      return _error(null, RpcError.parse, 'Parse error');
    }
    if (decoded is List) {
      if (decoded.isEmpty) return _error(null, RpcError.invalidRequest, 'Empty batch');
      final out = [for (final m in decoded) handleMessage(m, baseUrl: baseUrl)].whereType<Map<String, Object?>>().toList();
      return out.isEmpty ? null : out;
    }
    return handleMessage(decoded, baseUrl: baseUrl);
  }

  /// 메시지 하나. 알림(`id` 없음)이나 응답이면 null.
  Map<String, Object?>? handleMessage(Object? msg, {Uri? baseUrl}) {
    if (msg is! Map) return _error(null, RpcError.invalidRequest, 'Invalid Request');
    final id = msg['id'];
    final method = msg['method'];
    final isNotification = !msg.containsKey('id');
    if (method is! String) {
      // 클라이언트가 보낸 응답(서버가 요청한 적 없음) — 무시하되 남긴다.
      if (msg.containsKey('result') || msg.containsKey('error')) {
        log('A-001 MCP: 요청하지 않은 응답을 받아 무시함(id=$id)');
        return null;
      }
      return _error(id, RpcError.invalidRequest, 'Invalid Request');
    }
    final params = msg['params'] is Map ? (msg['params'] as Map).cast<String, Object?>() : const <String, Object?>{};

    if (isNotification) {
      // notifications/initialized·cancelled 등 — 상태 없는 서버라 할 일이 없다.
      if (!method.startsWith('notifications/')) log('A-001 MCP: 모르는 알림 무시 — $method');
      return null;
    }

    switch (method) {
      case 'initialize':
        return _result(id, _initialize(params));
      case 'ping':
        return _result(id, const <String, Object?>{});
      case 'tools/list':
        return _result(id, {'tools': [...mcpToolDefinitions(), sampleToolDefinition]});
      case 'tools/call':
        return _toolsCall(id, params, baseUrl);
      default:
        return _error(id, RpcError.methodNotFound, 'Method not found: $method');
    }
  }

  Map<String, Object?> _initialize(Map<String, Object?> params) {
    final asked = params['protocolVersion'];
    return {
      'protocolVersion': asked is String && mcpProtocolVersions.contains(asked) ? asked : mcpProtocolVersions.first,
      'capabilities': {
        'tools': {'listChanged': false},
      },
      'serverInfo': {'name': 'findchem', 'version': version},
      'instructions': assistSystemPrompt,
    };
  }

  Map<String, Object?> _toolsCall(Object? id, Map<String, Object?> params, Uri? baseUrl) {
    final name = params['name'];
    if (name is! String) return _error(id, RpcError.invalidParams, 'name은 문자열이어야 합니다');
    if (name == sampleToolName) return _result(id, _samplePdfResult(baseUrl));
    final args = params['arguments'];
    if (args != null && args is! Map) return _error(id, RpcError.invalidParams, 'arguments는 객체여야 합니다');
    final outcome = _tools.run(name, args == null ? const {} : (args as Map).cast<String, Object?>());
    if (outcome.isError) {
      // 도구 실패는 프로토콜 오류가 아니라 결과다 — 모델이 사유를 읽고 다시 부르게 한다.
      log('A-001 MCP: 도구 실패($name) — ${outcome.error}');
      return _result(id, {
        'content': [
          {'type': 'text', 'text': outcome.error},
        ],
        'isError': true,
      });
    }
    return _result(id, {
      'content': [
        {'type': 'text', 'text': jsonEncode(outcome.response)},
      ],
      'isError': false,
    });
  }

  /// 시험 PDF 바이트(서버 판이 찍힌다). HTTP 층의 `GET /files/...`도 이것을 준다.
  List<int> samplePdfBytes() => buildSamplePdf([
        'FindChem A-001 file delivery test',
        'server $version',
        'If you can read this, the file arrived intact.',
      ]);

  /// 같은 PDF를 세 길로 돌려준다 — 어느 길이 채팅·Cowork에서 받아지는지 재는 것이 목적이다.
  Map<String, Object?> _samplePdfResult(Uri? baseUrl) {
    final bytes = samplePdfBytes();
    final link = baseUrl?.resolve(samplePdfPath).toString();
    if (link == null) log('A-001 MCP: 공개 주소를 몰라 sample_pdf의 resource_link를 뺌');
    return {
      'content': [
        {
          'type': 'text',
          'text': '시험 PDF(${bytes.length}바이트)를 세 가지로 돌려준다: '
              '① resource_link ② 내장 resource(base64) ③ 받는 주소 ${link ?? '(없음)'}',
        },
        if (link != null)
          {'type': 'resource_link', 'uri': link, 'name': samplePdfName, 'mimeType': 'application/pdf'},
        {
          'type': 'resource',
          'resource': {
            'uri': 'findchem://files/$samplePdfName',
            'mimeType': 'application/pdf',
            'blob': base64Encode(bytes),
          },
        },
      ],
      'isError': false,
    };
  }

  static Map<String, Object?> _result(Object? id, Map<String, Object?> result) =>
      {'jsonrpc': '2.0', 'id': id, 'result': result};

  static Map<String, Object?> _error(Object? id, int code, String message) => {
        'jsonrpc': '2.0',
        'id': id,
        'error': {'code': code, 'message': message},
      };

  /// HTTP 층이 처리 중 예외를 만났을 때 돌려줄 오류(사유 없음 — 원인은 로그에만).
  static Map<String, Object?> internalError() => _error(null, RpcError.internal, 'Internal error');
}

/// MCP `tools/list`의 도구 배열 — [assistToolDefinitions]를 MCP 이름(`inputSchema`)으로 옮긴 것.
/// 설명ㆍ스키마는 손대지 않는다(원본은 prompt.dart 하나).
List<Map<String, Object?>> mcpToolDefinitions() => [
      for (final t in assistToolDefinitions())
        {
          'name': t['name'],
          'description': t['description'],
          'inputSchema': t['input_schema'],
          'annotations': {'readOnlyHint': true, 'openWorldHint': false},
        },
    ];

/// A-001 2차 실험 도구 — 실측이 끝나면 지운다. 앱ㆍ웹 판정 도우미에는 없다.
const sampleToolName = 'sample_pdf';

const sampleToolDefinition = <String, Object?>{
  'name': sampleToolName,
  'description': '[실험] 서버가 만든 파일을 받을 수 있는지 시험하는 도구다. 사용자가 이 도구나 "시험 PDF"를 명시적으로 '
      '요청할 때만 부른다. 같은 한 쪽짜리 PDF를 resource_link(받는 주소)ㆍ내장 resource(base64)ㆍ본문 주소 세 가지로 돌려준다.',
  'inputSchema': {'type': 'object', 'properties': <String, Object?>{}},
  'annotations': {'readOnlyHint': true, 'openWorldHint': false},
};
