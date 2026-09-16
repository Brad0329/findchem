/// F-008 2단계 테스트용 가짜 Anthropic 서버 — **고정 응답(fixture)으로만 돈다.**
/// 실호출은 자동 테스트에 넣지 않는다(REQUIREMENTS F-008 2단계).
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// 한 왕복에서 모델이 내놓을 것. 텍스트 조각과 도구 호출을 섞어 담는다.
class FakeTurn {
  const FakeTurn({this.text = const [], this.toolUses = const [], this.stopReason});

  /// 조각 단위로 흘려보낼 답 텍스트(스트리밍 확인용).
  final List<String> text;

  /// 이 턴에서 부를 도구들.
  final List<FakeToolUse> toolUses;

  /// 비우면 도구가 있으면 `tool_use`, 없으면 `end_turn`.
  final String? stopReason;
}

class FakeToolUse {
  const FakeToolUse(this.id, this.name, this.input);

  final String id;
  final String name;
  final Map<String, Object?> input;
}

/// 스크립트대로 SSE를 돌려주는 가짜 서버. 보낸 요청을 모두 기록한다(헤더·본문 확인용).
class FakeAnthropic {
  FakeAnthropic({List<FakeTurn> turns = const [], this.statusCode = 200, this.errorBody = '{"error":"x"}'})
    : _turns = List.of(turns);

  final List<FakeTurn> _turns;

  /// 200이 아니면 그 상태로 응답한다(오류 문구 대조용).
  final int statusCode;
  final String errorBody;

  /// 보낸 요청의 본문(JSON)과 헤더.
  final List<Map<String, Object?>> bodies = [];
  final List<Map<String, String>> headers = [];

  /// 조각을 하나씩 손으로 흘려보내고 싶을 때 쓴다(스트리밍 확인).
  /// [_pending]은 아직 요청이 오지 않은 것, [_active]는 요청이 와서 붙은 것 —
  /// 붙은 뒤에도 [emit]할 수 있어야 하므로 둘을 나눈다.
  StreamController<List<int>>? _pending;
  StreamController<List<int>>? _active;

  /// 요청이 아직 안 왔을 때 [emit]한 조각. 요청이 오면 그대로 흘려보낸다
  /// (테스트가 요청 도착을 기다리지 않아도 되게 — 기다리는 코드는 타이밍에 기댄다).
  final _buffered = <String>[];
  bool _closeRequested = false;

  /// 이 턴은 테스트가 [emit]으로 직접 흘린다.
  void manualNext() => _pending = StreamController<List<int>>();

  void emit(String chunk) {
    final active = _active;
    if (active == null) {
      _buffered.add(chunk);
      return;
    }
    active.add(utf8.encode(chunk));
  }

  Future<void> endManual() async {
    final active = _active;
    if (active == null) {
      _closeRequested = true;
      return;
    }
    await active.close();
  }

  int get callCount => bodies.length;

  http.Client get client => MockClient.streaming((request, bodyStream) async {
    headers.add(Map.of(request.headers));
    final raw = await bodyStream.bytesToString();
    bodies.add(jsonDecode(raw) as Map<String, Object?>);

    if (statusCode != 200) {
      return http.StreamedResponse(Stream.value(utf8.encode(errorBody)), statusCode);
    }
    final manual = _pending;
    if (manual != null) {
      _pending = null;
      _active = manual;
      for (final chunk in _buffered) {
        manual.add(utf8.encode(chunk));
      }
      _buffered.clear();
      if (_closeRequested) {
        _closeRequested = false;
        await manual.close();
      }
      return http.StreamedResponse(manual.stream, 200);
    }
    if (_turns.isEmpty) throw StateError('가짜 서버에 남은 턴이 없습니다 — 스크립트보다 많이 불렀습니다');
    return http.StreamedResponse(Stream.value(utf8.encode(sseFor(_turns.removeAt(0)))), 200);
  });
}

/// 한 턴을 SSE 본문으로. 실제 API가 내는 이벤트 이름·모양 그대로다.
String sseFor(FakeTurn turn) {
  final out = StringBuffer();
  void event(Map<String, Object?> data) => out.write('event: ${data['type']}\ndata: ${jsonEncode(data)}\n\n');

  event({'type': 'message_start', 'message': <String, Object?>{'id': 'msg_fake'}});
  var index = 0;
  if (turn.text.isNotEmpty) {
    event({'type': 'content_block_start', 'index': index, 'content_block': {'type': 'text', 'text': ''}});
    for (final chunk in turn.text) {
      event({
        'type': 'content_block_delta',
        'index': index,
        'delta': {'type': 'text_delta', 'text': chunk},
      });
    }
    event({'type': 'content_block_stop', 'index': index});
    index++;
  }
  for (final tool in turn.toolUses) {
    event({
      'type': 'content_block_start',
      'index': index,
      'content_block': {'type': 'tool_use', 'id': tool.id, 'name': tool.name, 'input': <String, Object?>{}},
    });
    // 실제 API처럼 입력을 조각내 보낸다 — 이어 붙여 JSON이 되어야 한다.
    final json = jsonEncode(tool.input);
    final cut = json.length ~/ 2;
    for (final part in [json.substring(0, cut), json.substring(cut)]) {
      event({
        'type': 'content_block_delta',
        'index': index,
        'delta': {'type': 'input_json_delta', 'partial_json': part},
      });
    }
    event({'type': 'content_block_stop', 'index': index});
    index++;
  }
  event({
    'type': 'message_delta',
    'delta': {'stop_reason': turn.stopReason ?? (turn.toolUses.isEmpty ? 'end_turn' : 'tool_use')},
  });
  event({'type': 'message_stop'});
  return out.toString();
}
