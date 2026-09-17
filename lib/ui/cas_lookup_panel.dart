/// F-007 CAS 조회 결과 영역 — 누른 행(웹 표) 바로 아래에 세 서비스 섹션을 펼친다. 값은 응답 그대로(코드는 코드로).
///
/// 결과는 마우스로 선택·복사할 수 있다(2026-09-14 사용자 요청). Flutter `SelectionArea`는 여러 Text에 걸친 선택을
/// **구분자 없이** 이어 붙이므로(selection_copy_probe_test 실측) 결과 영역은 [_CopyJoin]으로 감싸 칸은 탭, 줄은 줄바꿈으로 나눈다.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;

import '../lookup/api_settings.dart';
import '../lookup/chem_api.dart';
import '../lookup/ghs_pictogram_data.dart';

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
    return SelectionArea(
      child: _CopyJoin.lines(
        child: Column(
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
                  LookupRunning(:final calls) => _CopyJoin.lines(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final s in ChemService.values)
                          if (calls[s] != null)
                            _Section(key: ValueKey('lookup-${s.name}'), service: s, call: calls[s]!),
                      ],
                    ),
                  ),
                };
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ───── 선택 복사 구분자 ─────

/// 선택 복사 때 자식들 사이에 구분자를 넣는 선택 컨테이너.
/// - [_CopyJoin.lines]: 선택된 자식들을 줄바꿈으로 잇는다(목록의 줄, 섹션, 표의 행 묶음).
/// - [_CopyJoin.row]: 표·목록의 한 줄. **두 칸 이상** 걸치면 그 줄의 값 전체([cells])를 탭으로 잇는다 — 빈 칸도 자리를 지켜
///   Excel 열이 밀리지 않는다(빈 Text는 선택 내용이 없어 선택된 조각만으로는 칸 수를 알 수 없다). **한 칸 안**이면 그 선택만.
class _CopyJoin extends StatefulWidget {
  const _CopyJoin.lines({required this.child}) : cells = null;

  const _CopyJoin.row({required List<String> this.cells, required this.child});

  final List<String>? cells;
  final Widget child;

  @override
  State<_CopyJoin> createState() => _CopyJoinState();
}

class _CopyJoinState extends State<_CopyJoin> {
  late final _JoinDelegate _delegate = _JoinDelegate(() => widget.cells);

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SelectionContainer(delegate: _delegate, child: widget.child);
}

class _JoinDelegate extends StaticSelectionContainerDelegate {
  _JoinDelegate(this._cells);

  final List<String>? Function() _cells;

  @override
  SelectedContent? getSelectedContent() {
    final parts = <String>[
      for (final s in selectables)
        if (s.getSelectedContent() case final SelectedContent c when c.plainText.isNotEmpty) c.plainText,
    ];
    if (parts.isEmpty) return null;
    final cells = _cells();
    if (cells == null) return SelectedContent(plainText: parts.join('\n'));
    return SelectedContent(plainText: parts.length == 1 ? parts.single : cells.join('\t'));
  }
}

// ───── 조각 ─────

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
      child: _CopyJoin.lines(
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
                  final ServiceOk ok => _CopyJoin.lines(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (ok.truncated)
                          _message(context, LookupText.truncated(ok.total, ok.records.length), error: true),
                        for (final r in ok.records)
                          Padding(padding: const EdgeInsets.only(top: 6), child: _record(r)),
                      ],
                    ),
                  ),
                };
              },
            ),
          ],
        ),
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

/// 이름–값 한 줄. [color]가 있으면 값 글자색(신호어).
typedef _Pair = ({String label, String value, Color? color});

_Pair _pair(String label, String value, {Color? color}) => (label: label, value: value, color: color);

/// 이름 | 값 목록. 값이 빈 줄은 뺀다. 복사하면 줄마다 `이름⇥값`.
class _KeyValues extends StatelessWidget {
  const _KeyValues(this.pairs);

  final List<_Pair> pairs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return _CopyJoin.lines(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final p in pairs)
            if (p.value.isNotEmpty)
              _CopyJoin.row(
                cells: [p.label, p.value],
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 120, child: Text(p.label, style: labelStyle)),
                      Expanded(
                        child: Text(p.value, style: theme.textTheme.bodySmall?.copyWith(color: p.color)),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// 격자 표(분류 목록 등). 빈 칸은 비워 두고, 복사하면 칸은 탭·행은 줄바꿈(빈 칸도 자리 유지).
class _Grid extends StatelessWidget {
  const _Grid({required this.caption, required this.header, required this.flex, required this.rows});

  final String caption;
  final List<String> header;
  final List<int> flex;
  final List<List<String>> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final side = BorderSide(color: theme.dividerColor);

    Widget row(List<String> values, {TextStyle? style, bool isHeader = false}) => _CopyJoin.row(
      cells: values,
      child: Container(
        decoration: BoxDecoration(
          color: isHeader ? theme.colorScheme.surfaceContainerHighest : null,
          border: isHeader ? Border(top: side) : null,
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < values.length; i++)
                Expanded(
                  flex: flex[i],
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border(left: i == 0 ? side : BorderSide.none, right: side, bottom: side),
                    ),
                    child: Text(values[i], style: style ?? theme.textTheme.bodySmall),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return _CopyJoin.lines(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              caption,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          row(header, style: theme.textTheme.labelSmall, isHeader: true),
          for (final r in rows) row(r),
        ],
      ),
    );
  }
}

class _ChemView extends StatelessWidget {
  const _ChemView(this.r);

  final ChemRecord r;

  @override
  Widget build(BuildContext context) {
    final formula = [r.formula, r.weight].where((v) => v.isNotEmpty).join(' · ');
    return _CopyJoin.lines(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyValues([
            _pair('국문명', r.ko),
            _pair('영문명', r.en),
            _pair('다른 이름', r.otherKo),
            _pair('다른 이름(영문)', r.otherEn),
            _pair('분자식 · 분자량', formula),
            _pair('기존화학물질', r.existingNo),
          ]),
          if (r.types.isNotEmpty)
            _Grid(
              caption: '분류 ${r.types.length}건',
              header: const ['분류', '고유번호', '함량정보', '예외정보', '고시일자', '고시정보'],
              flex: const [13, 9, 20, 22, 9, 16],
              rows: [
                for (final x in r.types) [x.name, x.unqNo, x.content, x.exception, x.date, x.notice],
              ],
            ),
        ],
      ),
    );
  }
}

class _GhsView extends StatelessWidget {
  const _GhsView(this.r);

  final GhsRecord r;

  @override
  Widget build(BuildContext context) {
    return _CopyJoin.lines(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _KeyValues([
            _pair('신호어', r.signal, color: Theme.of(context).colorScheme.error),
            _pair('그림문자', r.pictograms.join(', ')),
          ]),
          if (r.pictograms.isNotEmpty) _PictogramTable(r.pictograms),
          _KeyValues([
            _pair('UN번호', r.unNumbers.join(', ')),
            _pair('M계수', r.mFactor),
            _pair('분류·고유번호', r.classNumbers.join(', ')),
          ]),
          if (r.hazards.isNotEmpty)
            _Grid(
              caption: '유해성 분류 ${r.hazards.length}건',
              header: const ['분류항목', '구분', 'H코드', 'P코드'],
              flex: const [14, 5, 6, 40],
              // 코드 그대로 보인다 — 2026-09-15에 넣었던 `(코드)문구` 표시는 2026-09-17 사용자들 요청으로 화면에서 뺐다
              // (문구 대응표 lib/lookup/ghs_phrase_data.dart·ghs_phrases.dart와 만드는 스크립트는 다시 켤 때를 위해 남겨 두었다)
              rows: [
                for (final h in r.hazards) [h.item, h.grade, h.hCode, h.pCodes.join(', ')],
              ],
            ),
        ],
      ),
    );
  }
}

/// 그림문자 표(안 A — 2026-09-15 사용자 선택): 응답의 코드마다 한 칸, 위에서 코드·그림·유해성 분류.
/// 그림·분류는 assets/유해성 분류.xlsx에서 뽑은 [ghsPictogramLabels]. 폭이 모자라면 가로로 민다.
/// 복사하면 코드 줄·분류 줄이 칸마다 탭이고, 분류의 여러 줄은 `, `로 잇는다(칸 안 줄바꿈은 Excel 칸을 깬다). 그림 줄은 글자가 없어 빠진다.
class _PictogramTable extends StatelessWidget {
  const _PictogramTable(this.codes) : super(key: const ValueKey('ghs-pictogram-table'));

  final List<String> codes;

  static const _cellWidth = 110.0, _imageSize = 72.0, _indent = 120.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final side = BorderSide(color: theme.dividerColor);
    final small = theme.textTheme.bodySmall;

    Widget row(List<Widget> children, {Color? color, bool top = false}) => Container(
      decoration: BoxDecoration(border: top ? Border(top: side) : null),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < children.length; i++)
              Container(
                width: _cellWidth,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                alignment: Alignment.topCenter,
                decoration: BoxDecoration(
                  color: color,
                  border: Border(left: i == 0 ? side : BorderSide.none, right: side, bottom: side),
                ),
                child: children[i],
              ),
          ],
        ),
      ),
    );

    Widget missing() => Text(LookupText.noPictogram, style: small?.copyWith(color: theme.colorScheme.error));

    Widget picture(String code) {
      if (!ghsPictogramLabels.containsKey(code)) {
        debugPrint('F-007 그림문자 $code: 대응표에 없음(assets/유해성 분류.xlsx에 없는 코드) — 그림 없음으로 표시');
        return missing();
      }
      return Image.asset(
        ghsPictogramAsset(code),
        key: ValueKey('ghs-pictogram-$code'),
        width: _imageSize,
        height: _imageSize,
        errorBuilder: (context, error, stack) {
          debugPrint('F-007 그림문자 $code 그림을 읽지 못함: $error');
          return missing();
        },
      );
    }

    final labels = [for (final c in codes) ghsPictogramLabels[c] ?? const <String>[]];
    // 폭이 모자라면 줄여서 넣는다. 가로 SingleChildScrollView는 쓰지 않는다 — 스크롤 영역의 선택은 가로 위치만 비교해서
    // 아래 유해성 분류 표를 끌어 선택하면 이 표 전체가 함께 선택됐다(2026-09-15 복사 테스트로 발견)
    return Padding(
      padding: const EdgeInsets.only(left: _indent, top: 4, bottom: 6),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: _CopyJoin.lines(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _CopyJoin.row(
                cells: codes,
                child: row(
                  [for (final c in codes) Text(c, style: theme.textTheme.labelSmall)],
                  color: theme.colorScheme.surfaceContainerHighest,
                  top: true,
                ),
              ),
              row([for (final c in codes) picture(c)]),
              _CopyJoin.row(
                cells: [for (final l in labels) l.join(', ')],
                child: row([
                  for (final l in labels) Text(l.join('\n'), style: small, textAlign: TextAlign.center),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SafetyView extends StatelessWidget {
  const _SafetyView(this.r);

  final SafetyRecord r;

  // 한 항목의 문장들은 Text 하나에 줄바꿈으로 — 그 항목 안에서 여러 줄을 끌어 복사해도 줄이 나뉘어 들어간다
  @override
  Widget build(BuildContext context) => _KeyValues([
    for (final (label, lines) in r.items) _pair(label, lines.join('\n')),
  ]);
}
