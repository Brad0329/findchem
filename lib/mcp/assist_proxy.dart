/// F-010 — 웹의 판정(AI) 호출을 Anthropic으로 중계한다. **키는 여기(서버)에만 있다.**
///
/// `POST /assist/messages` `{model, messages}` → 서버가 프롬프트ㆍ도구 정의를 붙여(`assistRequestBody`, 웹의 직접 호출과 같은 함수)
/// Anthropic에 보내고, 응답 SSE를 그대로 흘려보낸다. 남용 방지는 둘이다 — 허용 출처(`Origin`)와 시간당 호출 상한.
/// 둘 다 문턱이지 벽이 아니다(REQUIREMENTS F-010 G1ㆍG2): 진짜 상한은 Anthropic 콘솔의 지출 한도다.
///
/// 대화 내용ㆍ키는 로그에 남기지 않는다 — 시각은 Cloud Logging이 붙이고, 여기서는 상태ㆍ모델ㆍ크기만 쓴다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../assist/llm_request.dart';

const assistProxyPath = '/assist/messages';

/// 허용 출처 — 배포된 웹 하나. 다르거나 없으면 403(앱ㆍcurl은 `Origin`을 보내지 않는다).
const assistAllowedOrigin = 'https://brad0329.github.io';

/// 요청 본문 상한(바이트). 대화는 왕복마다 통째로 오고 도구 결과가 실려 커진다 — 넘으면 413.
const assistMaxBodyBytes = 512 * 1024;

/// 인스턴스 하나가 1시간(고정 창)에 Anthropic으로 넘기는 요청 수. **단위는 질문이 아니라 왕복이다.**
const assistHourlyLimit = 200;

class AssistProxy {
  AssistProxy({
    required String apiKey,
    required http.Client upstream,
    required this.log,
    DateTime Function()? now,
  }) : _apiKey = apiKey.trim(),
       _upstream = upstream,
       _now = now ?? DateTime.now;

  final String _apiKey;
  final http.Client _upstream;
  final DateTime Function() _now;
  final void Function(String) log;

  /// 지금 세는 시간 창(epoch 시 단위)과 그 창에서 Anthropic으로 넘긴 요청 수. 메모리에만 있다 — 인스턴스가 꺼지면 0이다.
  int _window = -1;
  int _count = 0;

  bool get hasKey => _apiKey.isNotEmpty;

  Future<void> handle(HttpRequest req) async {
    final res = req.response;
    try {
      // 출처부터 본다. 허용 출처가 아니면 CORS 헤더도 주지 않는다(브라우저가 응답을 읽지 못한다).
      if (req.headers.value('origin') != assistAllowedOrigin) {
        log('F-010 중계: 403 허용 출처 아님');
        res.statusCode = HttpStatus.forbidden;
        return;
      }
      // 여기부터의 모든 응답에 붙인다 — 오류 응답에 빠지면 웹이 상태 코드를 못 읽고 '접속 실패'로 오인한다.
      res.headers
        ..set('access-control-allow-origin', assistAllowedOrigin)
        ..set('vary', 'origin');

      if (req.method == 'OPTIONS') {
        res.headers
          ..set('access-control-allow-methods', 'POST')
          ..set('access-control-allow-headers', 'content-type')
          ..set('access-control-max-age', '3600');
        res.statusCode = HttpStatus.noContent;
        return;
      }
      if (req.method != 'POST') {
        res.statusCode = HttpStatus.methodNotAllowed;
        res.headers.set(HttpHeaders.allowHeader, 'POST, OPTIONS');
        return;
      }
      if (!hasKey) {
        log('F-010 중계: 503 서버에 ANTHROPIC_API_KEY가 없다');
        return _fail(res, HttpStatus.serviceUnavailable);
      }

      final bytes = <int>[];
      var received = 0;
      await for (final chunk in req) {
        // 상한을 넘어도 **끝까지 읽고 버린다** — 보내는 도중에 닫으면 상대는 413이 아니라 연결 끊김을 본다
        // (웹이 '접속 실패'로 오인한다). 담지는 않으므로 메모리는 상한에서 멈춘다. 전체 크기는 Cloud Run이 막는다.
        received += chunk.length;
        if (received <= assistMaxBodyBytes) bytes.addAll(chunk);
      }
      if (received > assistMaxBodyBytes) {
        log('F-010 중계: 413 본문 $received바이트가 상한 $assistMaxBodyBytes바이트를 넘음');
        return _fail(res, HttpStatus.requestEntityTooLarge);
      }
      final parsed = _parse(bytes);
      if (parsed == null) {
        log('F-010 중계: 400 본문 형식(model·messages) 오류, ${bytes.length}바이트');
        return _fail(res, HttpStatus.badRequest);
      }
      final (model, messages) = parsed;

      if (!_admit()) {
        log('F-010 중계: 429 시간당 상한 $assistHourlyLimit회에 닿음');
        return _fail(res, HttpStatus.tooManyRequests);
      }

      // 본문은 서버가 조립한다 — 클라이언트가 보낸 system·tools·max_tokens는 쓰지 않는다.
      final request = http.Request('POST', Uri.parse(anthropicMessagesEndpoint))
        ..headers.addAll({
          'content-type': 'application/json',
          'x-api-key': _apiKey,
          'anthropic-version': anthropicApiVersion,
        })
        ..body = jsonEncode(assistRequestBody(model: model, messages: messages));

      final http.StreamedResponse upstream;
      try {
        upstream = await _upstream.send(request);
      } catch (e) {
        // 예외 문구에 요청이 섞일 수 있어 종류만 남긴다.
        log('F-010 중계: 502 Anthropic 접속 실패 — ${e.runtimeType}');
        return _fail(res, HttpStatus.badGateway);
      }

      if (upstream.statusCode != 200) {
        // 원인은 로그에만, 응답에는 상태만(보안 3층 ①).
        log('F-010 중계: ${upstream.statusCode} Anthropic 오류 — ${await _errorSummary(upstream)}');
        return _fail(res, upstream.statusCode);
      }

      log('F-010 중계: 200 model=${model.id} 요청 ${bytes.length}바이트');
      res.statusCode = HttpStatus.ok;
      res.headers
        ..set(HttpHeaders.contentTypeHeader, 'text/event-stream; charset=utf-8')
        ..set(HttpHeaders.cacheControlHeader, 'no-cache');
      // 조각이 오는 대로 내보낸다 — 모아 두면 웹의 '조각 사이 60초' 제한에 걸린다.
      res.bufferOutput = false;
      await res.addStream(upstream.stream);
    } catch (e) {
      log('F-010 중계: 처리 중 예외 — ${e.runtimeType}');
      try {
        res.statusCode = HttpStatus.internalServerError;
      } catch (e2) {
        // 헤더를 이미 보냈으면(스트리밍 도중) 상태를 못 바꾼다 — 그 사실만 남긴다.
        log('F-010 중계: 오류 상태도 쓰지 못함 — ${e2.runtimeType}');
      }
    } finally {
      await res.close();
    }
  }

  /// `{model, messages}`를 꺼낸다. 형식이 아니면 null. 모델은 **정확히 아는 ID만** 받는다(기본값으로 바꿔 부르지 않는다).
  (AssistModel, List<Map<String, Object?>>)? _parse(List<int> bytes) {
    final Object? root;
    try {
      root = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      return null; // 부르는 쪽이 400과 로그를 남긴다
    }
    if (root is! Map) return null;
    final model = root['model'];
    final messages = root['messages'];
    final known = AssistModel.byId(model is String ? model : null);
    if (known == null || messages is! List || messages.isEmpty) return null;
    final out = <Map<String, Object?>>[];
    for (final m in messages) {
      if (m is! Map) return null;
      out.add(m.cast<String, Object?>());
    }
    return (known, out);
  }

  /// 시간당 상한 안이면 하나를 세고 true.
  bool _admit() {
    final window = _now().millisecondsSinceEpoch ~/ Duration.millisecondsPerHour;
    if (window != _window) {
      _window = window;
      _count = 0;
    }
    if (_count >= assistHourlyLimit) return false;
    _count++;
    return true;
  }

  /// Anthropic 오류 본문에서 종류와 메시지 앞부분만(로그용). 본문에 키는 없다.
  Future<String> _errorSummary(http.StreamedResponse upstream) async {
    try {
      final body = await upstream.stream.bytesToString();
      final decoded = jsonDecode(body);
      final error = decoded is Map ? decoded['error'] : null;
      if (error is Map) {
        final message = '${error['message'] ?? ''}';
        return '${error['type']}: ${message.length > 200 ? message.substring(0, 200) : message}';
      }
      return '형식을 모르는 본문 ${body.length}바이트';
    } catch (e) {
      // 본문을 못 읽어도 상태 코드는 이미 로그에 있다.
      return '본문을 읽지 못함(${e.runtimeType})';
    }
  }

  void _fail(HttpResponse res, int status) {
    res.statusCode = status;
    res.headers.contentType = ContentType('application', 'json', charset: 'utf-8');
    res.add(utf8.encode(jsonEncode({'error': 'assist_proxy', 'status': status})));
  }
}
