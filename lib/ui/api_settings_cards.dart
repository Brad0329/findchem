/// F-007 설정 카드 1(data.go.kr API 키)·카드 2(연동 데이터)의 본문. 카드 틀은 `settings_page.dart`가 그린다.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../lookup/api_settings.dart';
import '../lookup/chem_api.dart';
import 'cas_lookup_panel.dart';

/// 화면 문구(테스트가 같은 상수를 본다).
abstract final class ApiSettingsText {
  static const keyCard = 'data.go.kr API 키';
  static const keyHelp = '공공데이터포털 마이페이지의 일반 인증키를 붙여 넣으세요.';
  static const verify = '키 인증';
  static const save = '저장';
  static const delete = '삭제';
  static const enterKey = '키를 입력하세요';
  static const saved = '저장했습니다';
  static const deleted = '삭제했습니다';
  static const saveFailed = '저장하지 못했습니다';
  static const deleteFailed = '삭제하지 못했습니다';
  static const verifying = '확인 중…';
  static const verified = '확인됨';
  static String verifyLine(ChemService s, String result) => '${s.label} — $result';

  static const linkCard = '연동 데이터';
  static const linkHelp = 'CAS 번호를 누르면 체크한 정보만 조회합니다.';
}

void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(text)));

class ApiKeyCardBody extends StatefulWidget {
  const ApiKeyCardBody({super.key, required this.lookup});

  final CasLookup lookup;

  @override
  State<ApiKeyCardBody> createState() => _ApiKeyCardBodyState();
}

class _ApiKeyCardBodyState extends State<ApiKeyCardBody> {
  ApiSettingsController get _settings => widget.lookup.settings;
  late final _key = TextEditingController(text: _settings.serviceKey ?? '');
  bool _edited = false;

  /// 입력창 아래 안내("키를 입력하세요").
  String? _hint;

  /// [키 인증] 결과 — 서비스마다 한 줄. null이면 아직 누르지 않았다.
  Map<ChemService, String>? _verify;

  @override
  void initState() {
    super.initState();
    // 설정을 아직 읽는 중이었으면 다 읽은 뒤 입력창을 채운다(그 사이 사용자가 친 글자는 덮지 않는다)
    unawaited(
      _settings.load().then((_) {
        if (mounted && !_edited) setState(() => _key.text = _settings.serviceKey ?? '');
      }),
    );
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  String? _typedKey() {
    final k = _key.text.trim();
    if (k.isEmpty) {
      setState(() => _hint = ApiSettingsText.enterKey);
      return null;
    }
    setState(() => _hint = null);
    return k;
  }

  Future<void> _verifyKey() async {
    final key = _typedKey();
    if (key == null) {
      setState(() => _verify = null);
      return;
    }
    setState(() => _verify = {for (final s in ChemService.values) s: ApiSettingsText.verifying});
    await Future.wait([
      for (final s in ChemService.values)
        widget.lookup.client.fetch(s, key, verifyCas).then((r) {
          if (!mounted) return; // 결과가 오기 전에 카드를 접었다 — 보여줄 곳이 없다(실패 원인은 fetch가 이미 로그에 남겼다)
          setState(() => _verify![s] = switch (r) {
            ServiceOk() => ApiSettingsText.verified,
            ServiceFailed(:final message) => message,
          });
        }),
    ]);
  }

  Future<void> _save() async {
    final key = _typedKey();
    if (key == null) return;
    try {
      await _settings.saveKey(key);
      if (mounted) _snack(context, ApiSettingsText.saved);
    } catch (e, st) {
      debugPrint('F-007 키 저장 실패: ${e.runtimeType}: ${maskKey('$e', key)}\n$st');
      if (mounted) _snack(context, ApiSettingsText.saveFailed);
    }
  }

  Future<void> _delete() async {
    try {
      await _settings.delete();
      if (!mounted) return;
      setState(() {
        _key.clear();
        _verify = null;
        _hint = null;
      });
      _snack(context, ApiSettingsText.deleted);
    } catch (e, st) {
      debugPrint('F-007 키 삭제 실패: ${e.runtimeType}: $e\n$st');
      if (mounted) _snack(context, ApiSettingsText.deleteFailed);
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
          Text(ApiSettingsText.keyHelp, style: theme.textTheme.bodySmall),
          if (_settings.loadError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(_settings.loadError!, style: TextStyle(color: theme.colorScheme.error)),
            ),
          const SizedBox(height: 8),
          TextField(
            key: const ValueKey('api-key-field'),
            controller: _key,
            onChanged: (_) => _edited = true,
            decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
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
              OutlinedButton(onPressed: _verifyKey, child: const Text(ApiSettingsText.verify)),
              FilledButton(onPressed: _save, child: const Text(ApiSettingsText.save)),
              OutlinedButton(onPressed: _delete, child: const Text(ApiSettingsText.delete)),
            ],
          ),
          if (_verify != null) ...[
            const SizedBox(height: 8),
            for (final s in ChemService.values)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  ApiSettingsText.verifyLine(s, _verify![s]!),
                  style: TextStyle(
                    color: switch (_verify![s]) {
                      ApiSettingsText.verified => theme.colorScheme.primary,
                      ApiSettingsText.verifying => null,
                      _ => theme.colorScheme.error,
                    },
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class LinkedDataCardBody extends StatelessWidget {
  const LinkedDataCardBody({super.key, required this.settings});

  final ApiSettingsController settings;

  Future<void> _set(BuildContext context, ChemService s, bool v) async {
    try {
      await settings.setService(s, v);
    } catch (e, st) {
      debugPrint('F-007 연동 데이터 저장 실패: ${e.runtimeType}: $e\n$st');
      if (context.mounted) _snack(context, ApiSettingsText.saveFailed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(ApiSettingsText.linkHelp, style: theme.textTheme.bodySmall),
          for (final s in ChemService.values)
            CheckboxListTile(
              key: ValueKey('service-${s.name}'),
              value: settings.enabled(s),
              onChanged: (v) => _set(context, s, v ?? false),
              title: Text(s.label),
              subtitle: Text(s.hint),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
        ],
      ),
    );
  }
}
