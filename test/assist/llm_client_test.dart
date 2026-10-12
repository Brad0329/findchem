/// F-008 2단계 수용 기준 — 요청(CORS 헤더·모델 ID·캐싱)과 스트리밍·실패 문구.
/// LLM 응답은 고정 응답(fixture)으로만 돈다 — 실호출은 자동 테스트에 넣지 않는다.
library;

import 'package:findchem/assist/llm_client.dart';
import 'package:findchem/assist/prompt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fake_llm.dart';

void main() {
  const messages = [
    {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': '암모니아 0.3톤이면 규정수량 넘나요?'},
      ],
    },
  ];

  const proxy = 'https://proxy.test/assist/messages';

  Future<LlmTurn> send(
    FakeAnthropic fake, {
    AssistModel model = AssistModel.opus5,
    void Function(String)? onText,
    String? proxyUrl,
  }) =>
      AssistLlmClient(client: fake.client).send(
        apiKey: proxyUrl == null ? 'test-key' : '',
        proxyUrl: proxyUrl,
        model: model,
        messages: messages,
        onText: onText ?? (_) {},
      );

  group('요청', () {
    test('웹 CORS 헤더가 요청에 있다 — 없으면 브라우저에서 응답 자체가 오지 않는다(2026-09-16 실측)', () async {
      final fake = FakeAnthropic(turns: const [FakeTurn(text: ['답'])]);
      await send(fake);
      expect(fake.headers.single[browserAccessHeader], 'true');
      expect(fake.headers.single['x-api-key'], 'test-key');
      expect(fake.headers.single['anthropic-version'], '2023-06-01');
    });

    test('기본 모델 ID는 Opus 5이고, Sonnet 5를 고르면 요청 본문의 모델 ID가 바뀐다', () async {
      expect(AssistModel.fallback.id, 'claude-opus-5');

      final fake = FakeAnthropic(turns: const [FakeTurn(text: ['답']), FakeTurn(text: ['답'])]);
      await send(fake);
      expect(fake.bodies[0]['model'], 'claude-opus-5');

      await send(fake, model: AssistModel.sonnet5);
      expect(fake.bodies[1]['model'], 'claude-sonnet-5');
    });

    test('프롬프트 캐싱 블록과 도구 둘, 시스템 프롬프트의 설계 조건이 본문에 있다', () async {
      final fake = FakeAnthropic(turns: const [FakeTurn(text: ['답'])]);
      await send(fake);
      final body = fake.bodies.single;

      expect(body['cache_control'], {'type': 'ephemeral'});
      expect(body['stream'], true);

      final tools = (body['tools']! as List).cast<Map<String, Object?>>();
      expect([for (final t in tools) t['name']], [ToolName.search, ToolName.rule]);

      final system = body['system']! as String;
      // spike의 설계 조건 네 가지(수용 기준)
      expect(system, contains('도구가 준 것 이상을 말하지 않는다'));
      expect(system, contains('수량 행이 둘 이상이면'));
      expect(system, contains('함량기준을 답에 넣는다'));
      expect(system, contains('어느 순간의 최대 체류량'));
    });
  });

  group('요청 본문 전체 — 조립 함수를 옮겨도(F-010) 값이 바뀌지 않는다', () {
    test('직접 호출의 본문이 고정 기대값과 같다', () {
      expect(AssistLlmClient.requestBody(model: AssistModel.sonnet5, messages: messages), {
        'model': 'claude-sonnet-5',
        'max_tokens': 16000,
        'stream': true,
        'thinking': {'type': 'adaptive', 'display': 'summarized'},
        'system': assistSystemPrompt,
        'tools': assistToolDefinitions(),
        'messages': messages,
        'cache_control': {'type': 'ephemeral'},
      });
    });
  });

  group('중계 경로 (F-010)', () {
    test('중계 주소가 있으면 그 주소로 가고, 키·판·브라우저 헤더가 없고, 본문은 모델과 대화뿐이다', () async {
      final fake = FakeAnthropic(turns: const [FakeTurn(text: ['답'])]);
      final turn = await send(fake, proxyUrl: proxy, model: AssistModel.sonnet5);

      expect(fake.urls.single, Uri.parse(proxy));
      final headers = fake.headers.single;
      expect(headers.keys, isNot(contains('x-api-key')));
      expect(headers.keys, isNot(contains('anthropic-version')));
      expect(headers.keys, isNot(contains(browserAccessHeader)));
      expect(fake.bodies.single, {'model': 'claude-sonnet-5', 'messages': messages});
      expect(turn.content.single['text'], '답', reason: '응답(SSE) 해석은 직접 호출과 같은 코드다');
    });

    test('중계 주소가 없으면 종전대로 api.anthropic.com으로 간다', () async {
      final fake = FakeAnthropic(turns: const [FakeTurn(text: ['답'])]);
      await send(fake);
      expect(fake.urls.single, Uri.parse('https://api.anthropic.com/v1/messages'));
    });

    test('실패 문구 — 429는 한도, 401·403을 포함한 그 밖은 코드(사용자가 고칠 키가 없다)', () async {
      Future<String> failureOf(int status) async {
        try {
          await send(FakeAnthropic(statusCode: status), proxyUrl: proxy);
          fail('$status에서 실패하지 않았습니다');
        } on AssistFailure catch (e) {
          return e.message;
        }
      }

      expect(await failureOf(429), AssistText.overLimit);
      for (final code in [400, 401, 403, 413, 503]) {
        expect(await failureOf(code), AssistText.failed(code));
      }
    });

    test('접속 실패는 오프라인 안내로 간다', () async {
      final client = AssistLlmClient(client: _ThrowingClient());
      await expectLater(
        client.send(apiKey: '', proxyUrl: proxy, model: AssistModel.opus5, messages: messages, onText: (_) {}),
        throwsA(isA<AssistFailure>().having((e) => e.message, 'message', AssistText.offline)),
      );
    });
  });

  group('스트리밍', () {
    test('조각이 오는 대로 텍스트가 늘어난다(한 번에 오지 않는다)', () async {
      final fake = FakeAnthropic()..manualNext();
      final seen = <String>[];
      final done = send(fake, onText: seen.add);

      // 이벤트를 손으로 하나씩 흘려보내며 그때그때 쌓였는지 본다.
      await Future<void>.delayed(Duration.zero);
      fake.emit(_startText);
      await _tick();
      expect(seen, isEmpty, reason: '블록만 열렸을 뿐 아직 글자는 없다');

      fake.emit(_delta('성상에 따라 '));
      await _tick();
      expect(seen, ['성상에 따라 ']);

      fake.emit(_delta('갈립니다.'));
      await _tick();
      expect(seen, ['성상에 따라 ', '갈립니다.']);

      fake.emit(_stop('end_turn'));
      await fake.endManual();

      final turn = await done;
      expect(turn.stopReason, 'end_turn');
      expect(turn.content.single['text'], '성상에 따라 갈립니다.');
    });

    test('도구 호출은 조각난 input_json_delta를 이어 붙여 판다', () async {
      final fake = FakeAnthropic(
        turns: const [
          FakeTurn(toolUses: [FakeToolUse('toolu_1', ToolName.search, {'query': '암모니아'})]),
        ],
      );
      final turn = await send(fake);
      expect(turn.stopReason, 'tool_use');
      expect(turn.toolUses.single['name'], ToolName.search);
      expect(turn.toolUses.single['input'], {'query': '암모니아'});
    });
  });

  group('실패 문구 — 화면에는 상태만', () {
    Future<String> failureOf(int status) async {
      final fake = FakeAnthropic(statusCode: status);
      try {
        await send(fake);
        fail('$status에서 실패하지 않았습니다');
      } on AssistFailure catch (e) {
        return e.message;
      }
    }

    test('401은 키, 429는 한도, 그 밖은 코드', () async {
      expect(await failureOf(401), AssistText.badKey);
      expect(await failureOf(429), AssistText.overLimit);
      expect(await failureOf(500), AssistText.failed(500));
    });

    test('접속 실패는 오프라인 안내로 간다(CORS 차단도 여기로 온다)', () async {
      final client = AssistLlmClient(client: _ThrowingClient());
      await expectLater(
        client.send(apiKey: 'k', model: AssistModel.opus5, messages: messages, onText: (_) {}),
        throwsA(isA<AssistFailure>().having((e) => e.message, 'message', AssistText.offline)),
      );
    });

    test('조각이 끊기고 오지 않으면(멈춤) 오프라인 안내로 간다', () async {
      final fake = FakeAnthropic()..manualNext();
      final client = AssistLlmClient(client: fake.client, idleTimeout: const Duration(milliseconds: 60));
      final done = client.send(apiKey: 'k', model: AssistModel.opus5, messages: messages, onText: (_) {});
      await Future<void>.delayed(Duration.zero);
      fake.emit(_startText); // 열어만 두고 더 보내지 않는다
      await expectLater(
        done,
        throwsA(isA<AssistFailure>().having((e) => e.message, 'message', AssistText.offline)),
      );
    });
  });

  group('모델 저장값 해석', () {
    test('모르는 값·null이면 기본값으로 떨어진다(조용히 넘어가지 않고 로그에 남긴다)', () {
      final logs = <String>[];
      expect(AssistModel.fromId(null, log: logs.add), AssistModel.opus5);
      expect(AssistModel.fromId('claude-sonnet-5', log: logs.add), AssistModel.sonnet5);
      expect(logs, isEmpty);
      expect(AssistModel.fromId('claude-opus-4-8', log: logs.add), AssistModel.opus5);
      expect(AssistModel.fromId('', log: logs.add), AssistModel.opus5);
      expect(logs, hasLength(2), reason: '모르는 값 둘이 각각 로그에 남는다');
    });
  });
}

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 10));

const _startText =
    'event: content_block_start\ndata: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}\n\n';

String _delta(String text) =>
    'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,'
    '"delta":{"type":"text_delta","text":"$text"}}\n\n';

String _stop(String reason) =>
    'event: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"$reason"}}\n\n';

/// 접속 자체가 안 되는 클라이언트(오프라인·CORS 차단).
class _ThrowingClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Future.error(http.ClientException('Failed to fetch', request.url));
}
