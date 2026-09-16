/// F-008 판정 화면 — 질문을 넣으면 LLM이 검색ㆍ규칙 도구를 불러 답하고, 화면이 **근거 칸을 직접 그린다**.
/// 헤더 '⋮' → '규정수량·최대보유량 판정(AI)'에서 Navigator.push로 연다.
///
/// 근거는 모델 문장이 아니라 도구가 돌려준 값이다(REQUIREMENTS F-008 결정 5) —
/// 도구를 한 번도 안 불렀으면 그 사실이 근거 칸에 보인다.
library;

import 'package:flutter/material.dart';

import '../assist/llm_client.dart';
import '../assist/session.dart';
import '../assist/tools.dart';

/// 화면 문구(테스트가 같은 상수를 본다).
abstract final class AssistPageText {
  static const title = '규정수량·최대보유량 판정(AI)';
  static const hint = '예) 보관시설만 있는 창고에 톨루엔 0.01톤, 황산 0.05톤이면 최하위 규정수량 미만인가요?';
  static const send = '보내기';
  static const evidence = '근거 — 도구가 돌려준 값';
  static const rulesUsed = '쓰인 규칙';
  static const empty = '규정수량·최대보유량을 물어보세요. 답과 함께 근거(도구가 돌려준 값)가 나옵니다.';
  static const online = '이 기능은 온라인에서만 됩니다. 검색·목록은 그대로 쓸 수 있습니다.';

  static String substance(EvidenceSubstance s) => '${s.srcLabel} 제${s.no}호 ${s.name}';
  static String row(EvidenceRow r) {
    final kind = r.kind.isEmpty ? '' : '[${r.kind}] ';
    final content = r.content.isEmpty ? '함량기준 -' : '함량기준 ${r.content}';
    return '$kind최하위 ${r.min} / 하위 ${r.low} / 상위 ${r.high} · $content';
  }
}

class AssistPage extends StatefulWidget {
  const AssistPage({super.key, required this.session});

  final AssistSession session;

  @override
  State<AssistPage> createState() => _AssistPageState();
}

class _AssistPageState extends State<AssistPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    if (text.trim().isEmpty || widget.session.busy) return;
    _controller.clear();
    await widget.session.ask(text);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return Scaffold(
      appBar: AppBar(title: const Text(AssistPageText.title)),
      body: ListenableBuilder(
        listenable: session,
        builder: (context, _) {
          return Column(
            children: [
              if (!session.hasKey)
                const _Banner(text: AssistText.noKey)
              else
                const _Banner(text: AssistPageText.online, subtle: true),
              Expanded(
                child: session.messages.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(AssistPageText.empty, textAlign: TextAlign.center),
                        ),
                      )
                    : ListView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
                        itemCount: session.messages.length,
                        itemBuilder: (context, i) => _Bubble(message: session.messages[i]),
                      ),
              ),
              if (session.busy)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Row(
                    children: [
                      SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                      SizedBox(width: 8),
                      Text(AssistText.thinking),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        decoration: const InputDecoration(
                          hintText: AssistPageText.hint,
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: session.busy ? null : _send,
                      child: const Text(AssistPageText.send),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, this.subtle = false});

  final String text;
  final bool subtle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: subtle ? theme.colorScheme.surfaceContainerHighest : theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(text, style: theme.textTheme.bodySmall),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message});

  final AssistMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (message.isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(message.text),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (message.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            // 마크다운 렌더링은 하지 않는다(의존성 추가 없음) — 온 그대로 보인다.
            child: SelectableText(message.text),
          ),
        if (message.error case final error?)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(error, style: TextStyle(color: theme.colorScheme.error)),
          ),
        // 답이 아예 오지 않았으면(키 없음·접속 실패) 근거 칸을 그리지 않는다 —
        // 그 자리에 "도구를 부르지 않은 답"을 띄우면 오지도 않은 답을 평가하는 꼴이 된다.
        if (message.text.isNotEmpty || !message.evidence.isEmpty)
          _EvidencePanel(evidence: message.evidence),
      ],
    );
  }
}

/// 근거 칸. **앱이 도구 결과에서 직접 그린다** — 모델이 인용을 빠뜨려도 근거는 남는다.
class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({required this.evidence});

  final Evidence evidence;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = evidence;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AssistPageText.evidence, style: theme.textTheme.labelMedium),
          const SizedBox(height: 6),
          if (e.isEmpty)
            Text(AssistText.noToolCall, style: TextStyle(color: theme.colorScheme.error))
          else ...[
            for (final s in e.substances) ...[
              Text(AssistPageText.substance(s), style: theme.textTheme.bodyMedium),
              for (final r in s.rows)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 2),
                  child: Text(AssistPageText.row(r), style: theme.textTheme.bodySmall),
                ),
            ],
            if (e.ruleTopics.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '${AssistPageText.rulesUsed}: ${e.ruleTopics.join(', ')}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            for (final f in e.failures)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(f, style: TextStyle(color: theme.colorScheme.error)),
              ),
            if (e.notice case final notice?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(notice, style: theme.textTheme.bodySmall),
              ),
          ],
        ],
      ),
    );
  }
}
