/// F-008 2단계 — Anthropic Messages API 호출(스트리밍 SSE).
///
/// - **길이 둘이다**(F-010, 2026-10-12): 키가 있으면 `api.anthropic.com`을 **직접** 부르고, 중계 주소를 받으면
///   **중계 서버**(Cloud Run)로 모델ㆍ대화만 보낸다 — 키ㆍ프롬프트ㆍ도구 정의는 서버가 붙인다. 어느 길인지는
///   부르는 쪽(`ApiSettingsController`)이 정한다. 응답(SSE)은 두 길이 같아 해석 코드는 하나다.
/// - **직접 호출은 웹에서 `anthropic-dangerous-direct-browser-access` 헤더가 없으면 CORS로 막힌다** — 2026-09-16 실측:
///   헤더 없이 부르면 응답 자체가 오지 않아(`TypeError: Failed to fetch`) '접속 실패'로 **오인**되고,
///   헤더가 있으면 401이 도달했다. 그래서 이 헤더는 테스트로 건다(`test/assist/llm_client_test.dart`).
/// - 스트리밍은 `http`의 `Client.send`로 받는다. 새 의존성이 필요 없다 — `http` 1.6.0의 `BrowserClient`가
///   XHR이 아니라 `fetch` + `ReadableStream`을 쓰고(`browser_client.dart`), 앱은 `IOClient`가 원래 스트리밍이다.
/// - **키는 헤더에만 쓴다.** 로그ㆍ화면ㆍ예외 문구에 키를 넣지 않는다(F-007 규칙과 같다).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'llm_request.dart';

// 모델 목록ㆍ요청 조립은 Flutter 없는 `llm_request.dart`에 있다(중계 서버와 같이 쓴다) — 종전 import가 그대로 돌게 다시 내보낸다.
export 'llm_request.dart' show AssistModel;

/// 화면 문구(테스트가 같은 상수를 본다). REQUIREMENTS F-008 2단계 '오프라인ㆍ실패'.
abstract final class AssistText {
  static const offline = '오프라인이거나 접속하지 못했습니다. 검색은 계속 쓸 수 있습니다';
  static const badKey = 'AI 키가 올바르지 않습니다';
  static const overLimit = '요청 한도를 넘었습니다';
  static String failed(int code) => '답을 받지 못했습니다 (코드 $code)';

  static const noKey = '이 빌드에는 AI 키가 없습니다';
  static const thinking = '답 작성 중…';
  static const cutOff = '답이 길어 중간에서 잘렸습니다 — 질문을 나눠 다시 물어보세요';
  static const noToolCall = '도구를 부르지 않은 답 — 값을 검색으로 확인하세요';
  static const tooManyRounds = '답을 받지 못했습니다 (도구 호출이 너무 많습니다)';
}

/// 판정 기능(헤더 메뉴 항목, 화면)을 켤지. **앱ㆍ웹 둘 다**(2026-09-16 사용자 지시 "app도 인터넷 되도록").
/// 릴리스 `AndroidManifest.xml`에 INTERNET 권한을 같은 날 넣었다 — 종전에는 debugㆍprofile에만 있어
/// 릴리스 APK에서 호출이 막혔다. 켜고 끄는 분기는 이 값 한 곳이고, 테스트만 직접 넣는다.
/// (F-007 CAS 조회는 별개다 — 그쪽은 `apiLookupEnabledByDefault`로 여전히 웹만이다.)
const bool assistEnabledByDefault = true;

/// 배포 빌드에 들어간 기본 키(`--dart-define=ANTHROPIC_DEFAULT_KEY`). 없으면 빈 문자열 = 키 없음.
/// **배포된 JS에서 공개된다** — 사용자가 감수한 결정(2026-09-16). 배포 전에 콘솔에서 지출 한도를 건다.
const String bundledAnthropicKey = String.fromEnvironment('ANTHROPIC_DEFAULT_KEY');

/// 배포 빌드에 들어간 중계 서버 주소(`--dart-define=ASSIST_PROXY_URL`, F-010). 없으면 빈 문자열 = 중계 없음.
/// 비밀이 아니다. **웹 빌드에만 넣는다** — 서버가 `Origin`으로 출처를 보는데 앱은 `Origin`을 보내지 않아 403이 된다.
const String bundledAssistProxyUrl = String.fromEnvironment('ASSIST_PROXY_URL');

const _endpoint = anthropicMessagesEndpoint;
const _apiVersion = anthropicApiVersion;

/// 웹에서 브라우저 직접 호출을 여는 헤더. 없으면 CORS가 막는다(위 실측).
const browserAccessHeader = 'anthropic-dangerous-direct-browser-access';

/// 한 왕복의 결과. `content`는 그대로 대화에 다시 넣는다(도구 결과를 붙여 다음 왕복으로 간다).
class LlmTurn {
  const LlmTurn({required this.content, required this.stopReason});

  /// assistant 메시지의 content 블록들(text / tool_use).
  final List<Map<String, Object?>> content;
  final String? stopReason;

  /// 이번 턴에서 부른 도구들.
  List<Map<String, Object?>> get toolUses =>
      [for (final b in content) if (b['type'] == 'tool_use') b];
}

/// 화면에 그대로 보일 실패. [message]만 화면에 쓰고 원문은 로그에만 남긴다.
class AssistFailure implements Exception {
  const AssistFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

class AssistLlmClient {
  AssistLlmClient({http.Client? client, this.idleTimeout = const Duration(seconds: 60)})
    : _client = client ?? http.Client();

  final http.Client _client;

  /// **조각이 하나도 오지 않는 시간**의 상한이다 — 글자가 흐르는 중이면 끊지 않는다(REQUIREMENTS F-008 AI 기본값).
  final Duration idleTimeout;

  /// 요청 본문. 테스트가 이것을 직접 본다(모델 ID 교체ㆍ캐싱 블록 확인).
  static Map<String, Object?> requestBody({
    required AssistModel model,
    required List<Map<String, Object?>> messages,
  }) => assistRequestBody(model: model, messages: messages);

  /// 중계 요청의 헤더 — `content-type` 하나다. 키ㆍ판ㆍ브라우저 헤더는 서버가 붙인다(보내면 서버의 CORS 허용 목록에 걸린다).
  static const proxyHeaders = {'content-type': 'application/json'};

  static Map<String, String> headersFor(String key) => {
    'content-type': 'application/json',
    'x-api-key': key,
    'anthropic-version': _apiVersion,
    // 웹 전용 요구지만 앱에서 보내도 무해하다 — 한 벌로 둔다(분기가 하나 줄어든다).
    browserAccessHeader: 'true',
  };

  /// 한 왕복을 보낸다. 답 글자는 [onText]로 오는 대로 흘리고, 왕복이 끝나면 [LlmTurn]을 돌려준다.
  ///
  /// 실패는 [AssistFailure]로 던진다 — 화면 문구만 담고 원인은 로그에 남긴다.
  ///
  /// [proxyUrl]이 있으면 **중계로 보낸다**(F-010) — [apiKey]는 쓰지 않고, 본문은 모델ㆍ대화뿐이다.
  Future<LlmTurn> send({
    required String apiKey,
    String? proxyUrl,
    required AssistModel model,
    required List<Map<String, Object?>> messages,
    required void Function(String) onText,
  }) async {
    final viaProxy = proxyUrl != null;
    final request = http.Request('POST', Uri.parse(viaProxy ? proxyUrl : _endpoint))
      ..headers.addAll(viaProxy ? proxyHeaders : headersFor(apiKey))
      ..body = jsonEncode(
        viaProxy
            ? assistProxyBody(model: model, messages: messages)
            : requestBody(model: model, messages: messages),
      );

    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(idleTimeout);
    } on TimeoutException catch (e) {
      debugPrint('F-008 LLM 응답 시간 초과: $e');
      throw const AssistFailure(AssistText.offline);
    } catch (e, st) {
      // 접속 실패ㆍCORS 차단이 여기로 온다. 키가 섞이지 않도록 종류만 남긴다.
      debugPrint('F-008 LLM 접속 실패: ${e.runtimeType}\n$st');
      throw const AssistFailure(AssistText.offline);
    }

    if (response.statusCode != 200) {
      final body = await _drain(response);
      // 상태만 화면에 쓰고 원문은 로그에만(보안 3층 ①). 키는 본문에 없다.
      debugPrint('F-008 LLM 오류 ${response.statusCode}: $body');
      throw AssistFailure(switch (response.statusCode) {
        // 중계의 401ㆍ403은 서버 쪽 사정이다(서버 키ㆍ출처 거부) — 사용자가 고칠 키가 없으므로 코드로 보인다.
        401 || 403 when !viaProxy => AssistText.badKey,
        429 => AssistText.overLimit,
        final code => AssistText.failed(code),
      });
    }

    return _readStream(response, onText);
  }

  Future<String> _drain(http.StreamedResponse r) async {
    try {
      return await r.stream.bytesToString();
    } catch (e) {
      // 본문을 못 읽어도 상태 코드로 화면 문구는 정해진다 — 이유만 남기고 넘어간다.
      debugPrint('F-008 오류 응답 본문을 읽지 못함: ${e.runtimeType}');
      return '<본문 없음>';
    }
  }

  Future<LlmTurn> _readStream(http.StreamedResponse response, void Function(String) onText) async {
    final assembler = _TurnAssembler(onText);
    final lines = response.stream
        .timeout(idleTimeout) // 조각 사이 간격을 잰다(전체 시간이 아니다)
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    try {
      await for (final line in lines) {
        if (!line.startsWith('data:')) continue; // event: 줄과 빈 줄은 건너뛴다(형식대로다)
        final payload = line.substring(5).trim();
        if (payload.isEmpty) continue;
        try {
          final event = jsonDecode(payload);
          if (event is Map<String, Object?>) assembler.add(event);
        } on FormatException catch (e) {
          // 조각난 JSON은 프로토콜 위반이다 — 조용히 넘기지 않고 남긴다(본문에 키는 없다).
          debugPrint('F-008 SSE 조각을 해석하지 못함: $e');
        }
      }
    } on TimeoutException catch (e) {
      debugPrint('F-008 LLM 스트림이 멈춤: $e');
      throw const AssistFailure(AssistText.offline);
    } catch (e, st) {
      debugPrint('F-008 LLM 스트림 실패: ${e.runtimeType}\n$st');
      throw const AssistFailure(AssistText.offline);
    }
    return assembler.finish();
  }

  /// [키 확인] — 인증만 본다. **`max_tokens: 1`로 최소 호출**해 돈을 거의 쓰지 않는다
  /// (`hanmunstudy`의 `checkKey`에서 베낀 방식, 2026-09-16). 스트리밍하지 않는다.
  Future<KeyCheck> checkKey({required String apiKey, required AssistModel model}) async {
    if (apiKey.trim().isEmpty) return KeyCheck.badKey;
    try {
      final response = await _client
          .post(
            Uri.parse(_endpoint),
            headers: headersFor(apiKey),
            body: jsonEncode({
              'model': model.id,
              'max_tokens': 1,
              'messages': [
                {'role': 'user', 'content': 'hi'},
              ],
            }),
          )
          .timeout(idleTimeout);
      if (response.statusCode == 200) return KeyCheck.ok;
      // 상태만 돌려주고 원문은 로그에만. 본문에 키는 없다.
      debugPrint('F-008 키 확인 실패 ${response.statusCode}: ${response.body}');
      return switch (response.statusCode) {
        401 || 403 => KeyCheck.badKey,
        _ => KeyCheck.failed,
      };
    } on TimeoutException catch (e) {
      debugPrint('F-008 키 확인 시간 초과: $e');
      return KeyCheck.offline;
    } catch (e, st) {
      debugPrint('F-008 키 확인 접속 실패: ${e.runtimeType}\n$st');
      return KeyCheck.offline;
    }
  }

  void close() => _client.close();
}

/// [키 확인] 결과. **인증 실패와 접속 실패를 가른다** — 같은 문구를 주면 사용자가 멀쩡한 키를 지운다.
enum KeyCheck {
  ok('키가 확인됐습니다'),
  badKey('키가 거부됐습니다. 키를 다시 확인하세요'),
  offline('접속하지 못했습니다. 키 문제가 아닐 수 있습니다'),
  failed('확인하지 못했습니다');

  const KeyCheck(this.message);

  final String message;
}

/// SSE 이벤트를 모아 한 턴의 content 블록을 만든다.
///
/// 블록은 셋이다 — `text`(화면에 흐른다) / `tool_use`(`input_json_delta`를 이어 붙여 JSON으로 판다) /
/// `thinking`(화면에 그리지 않지만 **본문과 signature를 그대로 모아** 다음 왕복에 실어 보낸다).
/// 모르는 종류(예: `redacted_thinking`)는 온 그대로 두어 다시 돌려보낸다 — 손대면 서명이 깨진다.
class _TurnAssembler {
  _TurnAssembler(this.onText);

  final void Function(String) onText;
  final _blocks = <int, Map<String, Object?>>{};
  final _partialJson = <int, StringBuffer>{};
  String? _stopReason;

  void add(Map<String, Object?> event) {
    switch (event['type']) {
      case 'content_block_start':
        final index = event['index'];
        final block = event['content_block'];
        if (index is int && block is Map) {
          _blocks[index] = Map<String, Object?>.from(block);
          if (block['type'] == 'tool_use') _partialJson[index] = StringBuffer();
        }
      case 'content_block_delta':
        final index = event['index'];
        final delta = event['delta'];
        if (index is! int || delta is! Map) return;
        switch (delta['type']) {
          case 'text_delta':
            final text = delta['text'];
            if (text is String && text.isNotEmpty) {
              final block = _blocks[index];
              if (block != null) block['text'] = '${block['text'] ?? ''}$text';
              onText(text);
            }
          case 'input_json_delta':
            final part = delta['partial_json'];
            if (part is String) _partialJson[index]?.write(part);
          // thinking 블록은 화면에 그리지 않지만 **다음 왕복에 그대로 실어 보내야 한다** — 조각을 모은다.
          case 'thinking_delta':
            final part = delta['thinking'];
            final block = _blocks[index];
            if (part is String && block != null) block['thinking'] = '${block['thinking'] ?? ''}$part';
          case 'signature_delta':
            final signature = delta['signature'];
            if (signature is String) _blocks[index]?['signature'] = signature;
        }
      case 'message_delta':
        final delta = event['delta'];
        if (delta is Map && delta['stop_reason'] is String) _stopReason = delta['stop_reason'] as String;
      case 'error':
        // 스트림 도중의 오류는 API가 이 이벤트로 준다 — 삼키지 않는다.
        debugPrint('F-008 SSE error 이벤트: ${event['error']}');
    }
  }

  LlmTurn finish() {
    final indexes = _blocks.keys.toList()..sort();
    final content = <Map<String, Object?>>[];
    for (final i in indexes) {
      final block = _blocks[i]!;
      // **본문이 빈 thinking 블록은 버린다.** 되돌려 보내면 API가 400을 준다
      // (`each thinking block must contain thinking`). 요약을 켜 두어도 모델이 아주 짧게 생각하면
      // 요약이 비어 올 수 있다 — 빈 블록에는 보존할 내용도 없으므로 싣지 않는다.
      if (block['type'] == 'thinking' && (block['thinking'] as String? ?? '').isEmpty) {
        debugPrint('F-008 본문이 빈 thinking 블록을 대화에서 뺐습니다');
        continue;
      }
      if (block['type'] == 'tool_use') {
        final raw = _partialJson[i]?.toString() ?? '';
        Object? input;
        try {
          input = raw.trim().isEmpty ? <String, Object?>{} : jsonDecode(raw);
        } on FormatException catch (e) {
          // 잘린 도구 입력. 빈 입력으로 두면 도구가 "query가 비었다"를 돌려주고 모델이 다시 부른다.
          debugPrint('F-008 도구 입력 JSON을 해석하지 못함: $e');
          input = <String, Object?>{};
        }
        block['input'] = input is Map ? Map<String, Object?>.from(input) : <String, Object?>{};
      }
      content.add(block);
    }
    return LlmTurn(content: content, stopReason: _stopReason);
  }
}
