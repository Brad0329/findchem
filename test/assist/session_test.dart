/// F-008 2단계 수용 기준 — 도구 사용 루프. 검색은 실제 번들 데이터, LLM만 고정 응답(fixture).
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/assist/llm_client.dart';
import 'package:findchem/assist/prompt.dart';
import 'package:findchem/assist/session.dart';
import 'package:findchem/parser/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_llm.dart';

void main() {
  late Dataset ds;

  setUpAll(() {
    ds = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
  });

  AssistSession sessionOf(FakeAnthropic fake, {String key = 'test-key'}) => AssistSession(
    dataset: ds,
    client: AssistLlmClient(client: fake.client),
    apiKey: key,
    modelOf: () => AssistModel.opus5,
  );

  test('도구를 부르면 결과를 돌려주고 대화를 이어 답을 받는다 — 근거는 도구 결과에서 나온다', () async {
    final fake = FakeAnthropic(
      turns: const [
        FakeTurn(
          toolUses: [
            FakeToolUse('toolu_1', ToolName.search, {'query': '7664-41-7'}),
            FakeToolUse('toolu_2', ToolName.rule, {'topic': 'byeolpyo3'}),
          ],
        ),
        FakeTurn(text: ['성상에 따라 갈립니다.']),
      ],
    );
    final session = sessionOf(fake);
    await session.ask('암모니아 0.3톤이면 규정수량 넘나요?');

    expect(fake.callCount, 2, reason: '도구 결과를 붙여 한 번 더 부른다');
    expect(session.busy, false);

    final answer = session.messages.last;
    expect(answer.isUser, false);
    expect(answer.text, '성상에 따라 갈립니다.');
    expect(answer.error, isNull);
    expect(answer.evidence.toolCalls, 2);
    expect(answer.evidence.ruleTopics, ['byeolpyo3']);
    expect(answer.evidence.substances.any((s) => s.no == 44 && s.srcLabel == '사고대비물질'), true);

    // 한 턴의 도구 결과는 한 user 메시지에 모아 보낸다(나눠 보내면 병렬 호출이 줄어든다).
    final second = (fake.bodies[1]['messages']! as List).cast<Map<String, Object?>>();
    expect(second.length, 3); // 질문 / assistant(tool_use) / tool_result 묶음
    final results = (second.last['content']! as List).cast<Map<String, Object?>>();
    expect(results.length, 2);
    expect(results.map((r) => r['tool_use_id']), ['toolu_1', 'toolu_2']);
  });

  test('thinking 블록은 본문·서명 그대로 다음 왕복에 실린다 — 빈 채로 보내면 API가 400을 준다', () async {
    // 실호출에서 실제로 걸렸던 결함이다(2026-09-16):
    // `messages.1.content.0.thinking: each thinking block must contain thinking`.
    final fake = FakeAnthropic(
      turns: const [
        FakeTurn(
          thinking: (text: '별표 3을 먼저 본다', signature: 'sig-abc'),
          toolUses: [FakeToolUse('toolu_1', ToolName.search, {'query': '7664-41-7'})],
        ),
        FakeTurn(text: ['답']),
      ],
    );
    final session = sessionOf(fake);
    await session.ask('암모니아 0.3톤?');

    expect(fake.callCount, 2);
    // 요청에 thinking을 켜 두고(본문이 오도록 summarized), 받은 블록을 그대로 돌려보낸다.
    expect(fake.bodies.first['thinking'], {'type': 'adaptive', 'display': 'summarized'});
    final assistant = (fake.bodies[1]['messages']! as List)[1] as Map;
    final thinking = (assistant['content']! as List).first as Map;
    expect(thinking['type'], 'thinking');
    expect(thinking['thinking'], '별표 3을 먼저 본다');
    expect(thinking['signature'], 'sig-abc');
  });

  test('도구 호출 앞뒤 문장 사이에 빈 줄이 들어간다(그대로 이으면 "…합니다.## 결론"처럼 붙는다)', () async {
    final fake = FakeAnthropic(
      turns: const [
        FakeTurn(
          text: ['암모니아 규정수량을 확인하겠습니다.'],
          toolUses: [FakeToolUse('toolu_1', ToolName.search, {'query': '7664-41-7'})],
        ),
        FakeTurn(text: ['## 결론: 성상에 따라 갈립니다']),
      ],
    );
    final session = sessionOf(fake);
    await session.ask('암모니아 0.3톤?');

    expect(session.messages.last.text, '암모니아 규정수량을 확인하겠습니다.\n\n## 결론: 성상에 따라 갈립니다');
  });

  test('도구를 한 번도 안 부른 답은 근거가 비어 있다', () async {
    final fake = FakeAnthropic(turns: const [FakeTurn(text: ['0.05톤입니다'])]);
    final session = sessionOf(fake);
    await session.ask('톨루엔 규정수량?');

    expect(fake.callCount, 1);
    expect(session.messages.last.evidence.isEmpty, true);
  });

  test('키가 없으면 호출하지 않고 안내만 남긴다(호출 0회)', () async {
    final fake = FakeAnthropic(turns: const [FakeTurn(text: ['답'])]);
    final session = sessionOf(fake, key: '');

    expect(session.hasKey, false);
    await session.ask('톨루엔 규정수량?');

    expect(fake.callCount, 0);
    expect(session.messages.last.error, AssistText.noKey);
  });

  test('도구 호출 왕복이 상한을 넘으면 실패로 끝내되 지금까지의 근거는 남긴다', () async {
    final fake = FakeAnthropic(
      turns: [
        for (var i = 0; i < assistMaxRounds; i++)
          FakeTurn(toolUses: [FakeToolUse('toolu_$i', ToolName.search, const {'query': '108-88-3'})]),
      ],
    );
    final session = sessionOf(fake);
    await session.ask('끝없이 부르면?');

    expect(fake.callCount, assistMaxRounds);
    expect(session.messages.last.error, AssistText.tooManyRounds);
    expect(session.messages.last.evidence.isEmpty, false);
  });

  test('답이 max_tokens에서 잘리면 잘렸다고 알린다(조용한 절단 금지)', () async {
    final fake = FakeAnthropic(
      turns: const [FakeTurn(text: ['성상에 따라'], stopReason: 'max_tokens')],
    );
    final session = sessionOf(fake);
    await session.ask('길게 설명해줘');

    expect(session.messages.last.text, '성상에 따라');
    expect(session.messages.last.error, AssistText.cutOff);
  });

  test('실패하면 화면 문구만 남고 대화는 살아 있다', () async {
    final fake = FakeAnthropic(statusCode: 429);
    final session = sessionOf(fake);
    await session.ask('톨루엔 규정수량?');

    expect(session.messages.last.error, AssistText.overLimit);
    expect(session.busy, false);
  });

  test('도구가 실패해도 루프는 이어지고, 모델에 is_error로 알린다', () async {
    final fake = FakeAnthropic(
      turns: const [
        FakeTurn(toolUses: [FakeToolUse('toolu_1', ToolName.rule, {'topic': '없는주제'})]),
        FakeTurn(text: ['주제를 다시 고르겠습니다']),
      ],
    );
    final session = sessionOf(fake);
    await session.ask('규칙 보여줘');

    final results = ((fake.bodies[1]['messages']! as List).last as Map)['content']! as List;
    expect((results.single as Map)['is_error'], true);
    expect(session.messages.last.evidence.failures.single, contains('알 수 없는 규칙 주제'));
  });

  test('대화는 한 화면에서 이어진다 — 앞 질문과 답이 다음 요청에 들어 있다', () async {
    final fake = FakeAnthropic(turns: const [FakeTurn(text: ['첫 답']), FakeTurn(text: ['둘째 답'])]);
    final session = sessionOf(fake);
    await session.ask('첫 질문');
    await session.ask('그럼 용액이면요?');

    final messages = (fake.bodies[1]['messages']! as List).cast<Map<String, Object?>>();
    expect(messages.length, 3); // 첫 질문 / 첫 답 / 둘째 질문
    expect(session.messages.length, 4);
  });
}
