/// F-007 CAS 조회 결과 영역 — 누른 행(웹 표) 바로 아래에 세 서비스 섹션을 펼친다. 값은 응답 그대로(코드는 코드로).
library;

import 'package:flutter/material.dart';

import '../lookup/api_settings.dart';
import '../lookup/chem_api.dart';

/// 조회에 필요한 것 묶음. null이면 CAS가 눌리지 않는다(앱 — REQUIREMENTS F-007 '단계').
class CasLookup {
  const CasLookup({required this.settings, required this.client});

  final ApiSettingsController settings;
  final ChemApiClient client;
}

class CasLookupPanel extends StatefulWidget {
  const CasLookupPanel({super.key, required this.cas, required this.lookup});

  final String cas;
  final CasLookup lookup;

  @override
  State<CasLookupPanel> createState() => _CasLookupPanelState();
}

class _CasLookupPanelState extends State<CasLookupPanel> {
  // 펼칠 때 한 번 부른다(캐시 없음 — REQUIREMENTS F-007 AI 기본값).
  late final Future<LookupStart> _start = startLookup(widget.lookup.settings, widget.lookup.client, widget.cas);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(LookupText.title(widget.cas), style: theme.textTheme.labelMedium),
        FutureBuilder<LookupStart>(
          future: _start,
          builder: (context, snap) {
            if (snap.hasError) {
              debugPrint('F-007 조회 시작 실패: ${snap.error.runtimeType}\n${snap.stackTrace}');
              return _message(context, LookupText.failed('시작'), error: true);
            }
            return switch (snap.data) {
              null => const _Loading(),
              LookupBlocked(:final message) => _message(context, message, error: true),
              LookupRunning(:final calls) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final s in ChemService.values)
                    if (calls[s] != null) _Section(key: ValueKey('lookup-${s.name}'), service: s, call: calls[s]!),
                ],
              ),
            };
          },
        ),
      ],
    );
  }
}

Widget _message(BuildContext context, String text, {bool error = false}) {
  final theme = Theme.of(context);
  return Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Text(text, style: TextStyle(color: error ? theme.colorScheme.error : null)),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.only(top: 8),
    child: Row(
      children: [
        SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 8),
        Text(LookupText.loading),
      ],
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({super.key, required this.service, required this.call});

  final ChemService service;
  final Future<ServiceResult> call;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: theme.dividerColor))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(service.label, style: theme.textTheme.titleSmall),
          FutureBuilder<ServiceResult>(
            future: call,
            builder: (context, snap) {
              if (snap.hasError) {
                // fetch는 예외를 던지지 않게 짰다 — 여기 오면 결함이라 사유를 숨기지 않는다
                debugPrint('F-007 ${service.name} 섹션 오류: ${snap.error.runtimeType}\n${snap.stackTrace}');
                return _message(context, LookupText.failed('내부'), error: true);
              }
              return switch (snap.data) {
                null => const _Loading(),
                ServiceFailed(:final message) => _message(context, message, error: true),
                ServiceOk(:final records) when records.isEmpty => _message(context, LookupText.noResult),
                final ServiceOk ok => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (ok.truncated)
                      _message(context, LookupText.truncated(ok.total, ok.records.length), error: true),
                    for (final r in ok.records)
                      Padding(padding: const EdgeInsets.only(top: 6), child: _record(r)),
                  ],
                ),
              };
            },
          ),
        ],
      ),
    );
  }

  Widget _record(Object r) => switch (r) {
    ChemRecord() => _ChemView(r),
    GhsRecord() => _GhsView(r),
    SafetyRecord() => _SafetyView(r),
    _ => Text(LookupText.failed('형식')),
  };
}

/// 이름 | 값 두 칸. 값이 비었으면 그 줄을 뺀다.
class _KeyValues extends StatelessWidget {
  const _KeyValues(this.pairs);

  final List<(String, Widget?)> pairs;

  static Widget? text(BuildContext context, String v) =>
      v.isEmpty ? null : Text(v, style: Theme.of(context).textTheme.bodySmall);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Table(
      columnWidths: const {0: FixedColumnWidth(120), 1: FlexColumnWidth()},
      children: [
        for (final (k, v) in pairs)
          if (v != null)
            TableRow(
              children: [
                Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Text(k, style: label)),
                Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: v),
              ],
            ),
      ],
    );
  }
}

/// 격자 표(분류 목록 등). 빈 칸은 비워 둔다.
class _Grid extends StatelessWidget {
  const _Grid({required this.caption, required this.header, required this.flex, required this.rows});

  final String caption;
  final List<String> header;
  final List<double> flex;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.bodySmall;
    Widget cell(String v, {TextStyle? s}) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4), child: Text(v, style: s ?? style));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Text(caption, style: style?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
        Table(
          border: TableBorder.all(color: theme.dividerColor),
          columnWidths: {for (var i = 0; i < flex.length; i++) i: FlexColumnWidth(flex[i])},
          children: [
            TableRow(
              decoration: BoxDecoration(color: theme.colorScheme.surfaceContainerHighest),
              children: [for (final h in header) cell(h, s: theme.textTheme.labelSmall)],
            ),
            for (final r in rows) TableRow(children: [for (final v in r) cell(v)]),
          ],
        ),
      ],
    );
  }
}

class _ChemView extends StatelessWidget {
  const _ChemView(this.r);

  final ChemRecord r;

  @override
  Widget build(BuildContext context) {
    Widget? t(String v) => _KeyValues.text(context, v);
    final formula = [r.formula, r.weight].where((v) => v.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KeyValues([
          ('국문명', t(r.ko)),
          ('영문명', t(r.en)),
          ('다른 이름', t(r.otherKo)),
          ('다른 이름(영문)', t(r.otherEn)),
          ('분자식 · 분자량', t(formula)),
          ('기존화학물질', t(r.existingNo)),
        ]),
        if (r.types.isNotEmpty)
          _Grid(
            caption: '분류 ${r.types.length}건',
            header: const ['분류', '고유번호', '함량정보', '예외정보', '고시일자', '고시정보'],
            flex: const [1.3, 0.9, 2, 2.2, 0.9, 1.6],
            rows: [
              for (final x in r.types) [x.name, x.unqNo, x.content, x.exception, x.date, x.notice],
            ],
          ),
      ],
    );
  }
}

class _GhsView extends StatelessWidget {
  const _GhsView(this.r);

  final GhsRecord r;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget? t(String v) => _KeyValues.text(context, v);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _KeyValues([
          (
            '신호어',
            r.signal.isEmpty
                ? null
                : Text(r.signal, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
          ),
          ('그림문자', t(r.pictograms.join(', '))),
          ('UN번호', t(r.unNumbers.join(', '))),
          ('M계수', t(r.mFactor)),
          ('분류·고유번호', t(r.classNumbers.join(', '))),
        ]),
        if (r.hazards.isNotEmpty)
          _Grid(
            caption: '유해성 분류 ${r.hazards.length}건',
            header: const ['분류항목', '구분', 'H코드', 'P코드'],
            flex: const [1.4, 0.5, 0.6, 4],
            rows: [
              for (final h in r.hazards) [h.item, h.grade, h.hCode, h.pCodes.join(', ')],
            ],
          ),
      ],
    );
  }
}

class _SafetyView extends StatelessWidget {
  const _SafetyView(this.r);

  final SafetyRecord r;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return _KeyValues([
      for (final (label, lines) in r.items)
        (
          label,
          lines.isEmpty
              ? null
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final l in lines) Text(l, style: style)],
                ),
        ),
    ]);
  }
}
