/// F-008ㆍF-010 — Anthropic 요청의 **조립**(모델 목록, 요청 본문, 주소ㆍ판).
///
/// **Flutter 없이 컴파일된다** — 웹의 직접 호출(`llm_client.dart`)과 중계 서버(F-010, `lib/mcp/`)가 같은 함수를 쓴다.
/// 두 번째 구현을 만들지 않는다(CLAUDE.md '구조'). 그래서 여기서는 `debugPrint`를 쓰지 않고 로그 수단을 인자로 받는다.
library;

import 'prompt.dart';

const anthropicMessagesEndpoint = 'https://api.anthropic.com/v1/messages';
const anthropicApiVersion = '2023-06-01';

/// 고른 모델. **선택지는 이 둘뿐이다** — 목록을 일반화하지 않는다(YAGNI, REQUIREMENTS F-008).
enum AssistModel {
  opus5('claude-opus-5', 'Opus 5', '더 정확하고 더 비쌈(기본값)'),
  sonnet5('claude-sonnet-5', 'Sonnet 5', '더 싸고 덜 정확함');

  const AssistModel(this.id, this.label, this.hint);

  /// API에 보내는 모델 ID.
  final String id;

  /// 설정 화면 표기(제품명 그대로).
  final String label;
  final String hint;

  /// 기본값. 1단계에서 **같은 자산으로 두 모델의 답이 갈렸고**(B1) Opus 5만 통과했다.
  static const fallback = AssistModel.opus5;

  /// ID가 정확히 맞는 모델, 없으면 null. **중계 서버는 이것만 쓴다** — 모르는 ID를 기본값으로 바꿔 부르지 않는다(F-010).
  static AssistModel? byId(String? id) {
    for (final m in values) {
      if (m.id == id) return m;
    }
    return null;
  }

  /// 저장된 값 → 모델. 모르는 값이면 [fallback]으로 떨어지고 **그 사실을 [log]에 남긴다**(조용히 넘어가지 않는다).
  static AssistModel fromId(String? id, {required void Function(String) log}) {
    if (id == null) return fallback;
    final found = byId(id);
    if (found != null) return found;
    log('F-008 모르는 모델 ID($id) — 기본값 ${fallback.id}으로 대체합니다');
    return fallback;
  }
}

/// Anthropic에 보내는 요청 본문. 테스트가 이것을 직접 본다(모델 ID 교체ㆍ캐싱 블록 확인).
Map<String, Object?> assistRequestBody({
  required AssistModel model,
  required List<Map<String, Object?>> messages,
}) => {
  'model': model.id,
  // 두 모델 모두 thinking이 켜져 있어(adaptive) 생각 토큰도 여기에 든다 — 빠듯하게 잡으면 답이 잘린다.
  // 잘리면 `stop_reason: max_tokens`로 오고, 그때는 화면에 그 사실을 알린다(조용한 절단 금지).
  'max_tokens': 16000,
  'stream': true,
  // **thinking 블록을 되돌려 보낼 수 있어야 한다.** 두 모델 모두 thinking이 기본으로 켜져 있고,
  // 도구 호출 뒤 다음 왕복에는 그 턴의 thinking 블록을 **그대로** 실어 보내야 한다.
  // 기본값 display: omitted는 thinking 본문을 빈 문자열로 주는데, 빈 블록을 되돌리면
  // `each thinking block must contain thinking`(400)이 난다 — 2026-09-16 실호출로 확인했다.
  'thinking': {'type': 'adaptive', 'display': 'summarized'},
  'system': assistSystemPrompt,
  'tools': assistToolDefinitions(),
  'messages': messages,
  // 대화는 왕복마다 통째로 재전송된다 — 프리픽스를 캐시해 누적 재전송 비용을 낮춘다.
  // 본문 최상위에 두면 마지막 캐시 가능 블록에 자동으로 붙는다(왕복마다 프리픽스가 자란다).
  'cache_control': {'type': 'ephemeral'},
};

/// 중계 서버(F-010)에 보내는 본문 — **모델과 대화뿐이다.** 나머지는 서버가 [assistRequestBody]로 붙인다.
Map<String, Object?> assistProxyBody({
  required AssistModel model,
  required List<Map<String, Object?>> messages,
}) => {'model': model.id, 'messages': messages};
