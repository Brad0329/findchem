/// F-008 설정 카드 — Anthropic 키(사용자 키 우선)와 판정 모델 선택.
///
/// 구성은 F-007 키 카드(`api_settings_cards.dart`)와 같은 뼈대에, `hanjadic` 계열 앱에서 베낀 둘을 더했다
/// (2026-09-16 사용자 지시): **입력칸 마스킹 + 눈 아이콘**, **[키 확인]은 `max_tokens: 1` 최소 호출**.
/// 저장 자리는 기존 설정 파일 하나를 그대로 쓴다(SCHEMA.md '판정 설정 — 모델 선택과 사용자 키').
library;

import 'package:flutter/material.dart';

import '../assist/llm_client.dart';
import '../lookup/api_settings.dart';

/// 화면 문구(테스트가 같은 상수를 본다).
abstract final class AssistSettingsText {
  static const card = '판정(AI) 키·모델';
  static const keyHelp = 'Anthropic 콘솔에서 발급한 키를 붙여 넣으세요. 이 기기에만 저장됩니다.';
  static const hint = '발급받은 키를 붙여넣으세요';
  static const show = '보기';
  static const hide = '가리기';
  static const verify = '키 확인';
  static const save = '저장';
  static const delete = '삭제';
  static const enterKey = '키를 입력하세요';
  static const saved = '저장했습니다';
  static const deleted = '지웠습니다';
  static const saveFailed = '저장하지 못했습니다';
  static const deleteFailed = '지우지 못했습니다';
  static const verifying = '확인 중…';
  static const defaultMask = '****';
  static const usingDefault = '기본 키 사용 중 — 내 키를 넣고 [저장]하면 그 키를 씁니다';
  static const noKeyAtAll = '키가 없습니다 — 넣기 전에는 판정 화면에서 질문을 보내지 않습니다';

  static const modelSection = '판정에 쓸 모델';
  static String modelHint(AssistModel m) => '${m.hint} · ${m.id}';
}

class AssistSettingsCardBody extends StatefulWidget {
  const AssistSettingsCardBody({super.key, required this.settings, required this.client});

  final ApiSettingsController settings;

  /// [키 확인]에 쓴다. 테스트에서 가짜를 넣는다.
  final AssistLlmClient client;

  @override
  State<AssistSettingsCardBody> createState() => _AssistSettingsCardBodyState();
}

class _AssistSettingsCardBodyState extends State<AssistSettingsCardBody> {
  final _key = TextEditingController();
  bool _visible = false;
  String? _hint;
  String? _result;
  bool _resultOk = false;

  ApiSettingsController get _settings => widget.settings;

  @override
  void initState() {
    super.initState();
    _key.text = _settings.anthropicKey ?? '';
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  void _snack(String text) => ScaffoldMessenger.maybeOf(context)
    ?..removeCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _save() async {
    final key = _key.text.trim();
    if (key.isEmpty) {
      setState(() => _hint = AssistSettingsText.enterKey);
      return;
    }
    try {
      await _settings.saveAnthropicKey(key);
      if (!mounted) return;
      setState(() => _hint = null);
      _snack(AssistSettingsText.saved);
    } catch (e, st) {
      // 예외 문구에 키가 섞일 수 있어 종류만 남긴다(F-007과 같은 규칙).
      debugPrint('F-008 키 저장 실패: ${e.runtimeType}\n$st');
      if (mounted) _snack(AssistSettingsText.saveFailed);
    }
  }

  Future<void> _delete() async {
    try {
      await _settings.deleteAnthropicKey();
      if (!mounted) return;
      setState(() {
        _key.clear();
        _hint = null;
        _result = null;
      });
      _snack(AssistSettingsText.deleted);
    } catch (e, st) {
      debugPrint('F-008 키 삭제 실패: ${e.runtimeType}\n$st');
      if (mounted) _snack(AssistSettingsText.deleteFailed);
    }
  }

  /// 입력칸의 키(비었으면 지금 쓰는 키)로 확인한다. **저장하지 않는다**(F-007 [키 인증]과 같다).
  Future<void> _verify() async {
    final key = _key.text.trim().isNotEmpty ? _key.text.trim() : (_settings.effectiveAnthropicKey ?? '');
    if (key.isEmpty) {
      setState(() => _hint = AssistSettingsText.enterKey);
      return;
    }
    setState(() {
      _hint = null;
      _result = AssistSettingsText.verifying;
      _resultOk = false;
    });
    final outcome = await widget.client.checkKey(apiKey: key, model: _settings.assistModel);
    if (!mounted) return;
    setState(() {
      _result = outcome.message;
      _resultOk = outcome == KeyCheck.ok;
    });
  }

  Future<void> _setModel(AssistModel? model) async {
    if (model == null || model == _settings.assistModel) return;
    try {
      await _settings.setAssistModel(model);
    } catch (e, st) {
      debugPrint('F-008 모델 저장 실패: ${e.runtimeType}\n$st');
      if (mounted) _snack(AssistSettingsText.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(AssistSettingsText.keyHelp, style: theme.textTheme.bodySmall),
          if (_settings.loadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_settings.loadError!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('assist-key-field'),
            controller: _key,
            obscureText: !_visible,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              isDense: true,
              hintText: _settings.usingDefaultAnthropicKey ? AssistSettingsText.defaultMask : AssistSettingsText.hint,
              suffixIcon: IconButton(
                icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
                tooltip: _visible ? AssistSettingsText.hide : AssistSettingsText.show,
                onPressed: () => setState(() => _visible = !_visible),
              ),
            ),
          ),
          if (_settings.usingDefaultAnthropicKey)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(AssistSettingsText.usingDefault, style: theme.textTheme.bodySmall),
            )
          else if (_settings.effectiveAnthropicKey == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(AssistSettingsText.noKeyAtAll, style: TextStyle(color: theme.colorScheme.error)),
            ),
          if (_hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_hint!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(onPressed: _verify, child: const Text(AssistSettingsText.verify)),
              FilledButton(onPressed: _save, child: const Text(AssistSettingsText.save)),
              OutlinedButton(onPressed: _delete, child: const Text(AssistSettingsText.delete)),
            ],
          ),
          if (_result != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _result!,
                style: TextStyle(
                  color: _result == AssistSettingsText.verifying
                      ? null
                      : (_resultOk ? theme.colorScheme.primary : theme.colorScheme.error),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(AssistSettingsText.modelSection, style: theme.textTheme.labelLarge),
          // 실제로 불리는 모델 ID를 그대로 보인다 — 요금이 걸린 경로다(hanjadic에서 베낀 원칙).
          RadioGroup<AssistModel>(
            groupValue: _settings.assistModel,
            onChanged: _setModel,
            child: Column(
              children: [
                for (final model in AssistModel.values)
                  RadioListTile<AssistModel>(
                    value: model,
                    title: Text(model.label),
                    subtitle: Text(AssistSettingsText.modelHint(model)),
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
