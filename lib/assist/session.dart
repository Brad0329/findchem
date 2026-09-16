/// F-008 2단계 — **도구 사용 루프**. 질문 하나에 대해 답이 끝날 때까지 도구를 부르고 대화를 잇는다.
///
/// 대화는 한 화면에서 이어진다(A1→A2→A3처럼 맥락을 받는 질문이 있다). 화면을 나가면 사라지고 저장하지 않는다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../parser/models.dart';
import 'llm_client.dart';
import 'tools.dart';

/// 도구 호출 왕복 상한. 넘으면 지금까지의 근거와 함께 실패로 끝낸다(무한 루프ㆍ비용 폭주 방지).
const assistMaxRounds = 10;

/// 화면에 보이는 말 한 마디.
class AssistMessage {
  AssistMessage.question(this.text) : isUser = true, evidence = Evidence.empty, error = null;
  AssistMessage.answer({required this.text, required this.evidence, this.error}) : isUser = false;

  final bool isUser;

  /// 답 텍스트(스트리밍 중에는 오는 대로 늘어난다). 마크다운 렌더링은 하지 않는다.
  String text;

  /// 이 답을 만들며 호출된 도구 결과. 모델 문장이 아니라 **도구가 돌려준 값**이다.
  Evidence evidence;

  /// 실패 문구(화면에 그대로 보인다). 원인은 로그에만.
  String? error;
}

/// 한 화면의 대화. 화면은 이것만 보고 그린다.
class AssistSession extends ChangeNotifier {
  AssistSession({
    required Dataset dataset,
    required this.client,
    required this.apiKey,
    required this.modelOf,
  }) : tools = AssistTools(dataset);

  final AssistTools tools;
  final AssistLlmClient client;

  /// 이 빌드ㆍ이 기기에서 쓸 키. 비어 있으면 질문을 보내지 않는다(호출 0회).
  final String apiKey;

  /// 보낼 때마다 설정에서 다시 읽는다 — 설정에서 모델을 바꾸면 다음 질문부터 바뀐다.
  final AssistModel Function() modelOf;

  final List<AssistMessage> messages = [];

  /// API에 보내는 대화(도구 결과까지 들어 있다). 화면에는 보이지 않는다.
  final List<Map<String, Object?>> _api = [];

  bool _busy = false;
  bool get busy => _busy;

  bool get hasKey => apiKey.trim().isNotEmpty;

  /// 질문 하나를 보내고 답이 끝날 때까지 도구 루프를 돈다.
  Future<void> ask(String question) async {
    final q = question.trim();
    if (q.isEmpty || _busy) return;
    if (!hasKey) {
      // 키가 없으면 **호출하지 않는다**(REQUIREMENTS F-008 2단계).
      messages
        ..add(AssistMessage.question(q))
        ..add(AssistMessage.answer(text: '', evidence: Evidence.empty, error: AssistText.noKey));
      notifyListeners();
      return;
    }

    final answer = AssistMessage.answer(text: '', evidence: Evidence.empty);
    messages
      ..add(AssistMessage.question(q))
      ..add(answer);
    _api.add({
      'role': 'user',
      'content': [
        {'type': 'text', 'text': q},
      ],
    });
    _busy = true;
    notifyListeners();

    final outcomes = <ToolOutcome>[];
    try {
      for (var round = 0; round < assistMaxRounds; round++) {
        // 도구 호출 앞뒤로 모델이 문장을 나눠 쓴다 — 그대로 이으면 "…확인하겠습니다.## 결론"처럼 붙는다.
        var firstChunk = true;
        final turn = await client.send(
          apiKey: apiKey,
          model: modelOf(),
          messages: _api,
          onText: (chunk) {
            if (firstChunk) {
              firstChunk = false;
              if (answer.text.isNotEmpty && !answer.text.endsWith('\n')) answer.text += '\n\n';
            }
            answer.text += chunk;
            notifyListeners();
          },
        );
        _api.add({'role': 'assistant', 'content': turn.content});

        // 상한에 걸려 답이 잘렸으면 **잘렸다는 사실을 알린다**(조용한 절단 금지 — CLAUDE.md 불변 규칙).
        if (turn.stopReason == 'max_tokens') {
          answer.error = AssistText.cutOff;
          debugPrint('F-008 답이 max_tokens에서 잘렸습니다');
          return;
        }

        final calls = turn.toolUses;
        if (calls.isEmpty) {
          answer.evidence = evidenceOf(outcomes);
          return; // finally가 busy를 내린다
        }

        // 한 턴의 도구 결과는 **한 user 메시지에 모아** 돌려준다(나눠 보내면 병렬 호출이 줄어든다).
        final results = <Map<String, Object?>>[];
        for (final call in calls) {
          final name = call['name'] is String ? call['name'] as String : '';
          final input = call['input'] is Map
              ? Map<String, Object?>.from(call['input'] as Map)
              : <String, Object?>{};
          final outcome = tools.run(name, input);
          outcomes.add(outcome);
          results.add({
            'type': 'tool_result',
            'tool_use_id': call['id'],
            if (outcome.isError) 'is_error': true,
            'content': outcome.isError ? outcome.error! : _encode(outcome.response),
          });
        }
        _api.add({'role': 'user', 'content': results});
        answer.evidence = evidenceOf(outcomes);
        notifyListeners();
      }
      // 상한까지 갔다 — 지금까지의 근거는 남긴다(조용히 비우지 않는다).
      answer.error = AssistText.tooManyRounds;
      debugPrint('F-008 도구 호출 왕복 상한($assistMaxRounds)에 걸렸습니다');
    } on AssistFailure catch (e) {
      answer.error = e.message;
    } catch (e, st) {
      debugPrint('F-008 판정 루프 실패: ${e.runtimeType}\n$st');
      answer.error = AssistText.failed(0);
    } finally {
      answer.evidence = evidenceOf(outcomes);
      _busy = false;
      notifyListeners();
    }
  }

  /// 도구 응답을 모델에 보낼 문자열로. 들여쓰기 없이 보낸다 — 프리픽스 캐시가 흔들리지 않게 같은 내용은 같은 문자열이다.
  static String _encode(Map<String, Object?> response) => jsonEncode(response);
}
