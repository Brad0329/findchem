/// 검색 결과 항목 카드 — REQUIREMENTS F-001 "항목 카드에는 다음이 모두 나온다".
library;

import 'package:flutter/material.dart';

import '../parser/models.dart';
import '../search/search.dart';

/// 화면 문구(테스트가 같은 상수를 본다).
abstract final class CardText {
  static const priority = '사고대비물질 · 우선 적용';
  static const referenceNote = '사고대비물질은 사고대비물질 규정수량을 적용합니다(별표2 일반기준 가)';
  static const noCas = '묶음 항목 · CAS 없음';
  static const deleted = '삭제된 항목 · 규정수량 없음';
}

class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.hit});

  final Hit hit;

  @override
  Widget build(BuildContext context) {
    final e = hit.entry;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final sourceLine = [
      '${e.src.label} · ${e.src == Source.byeolpyo3 ? '번호' : '연번'} ${e.no}',
      if (e.uid != null) '고유번호 ${e.uid}',
    ].join(' · ');

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (hit.priority) _Badge(CardText.priority, color: cs.primary, onColor: cs.onPrimary),
            if (e.deleted) _Badge(CardText.deleted, color: cs.surfaceContainerHighest, onColor: cs.onSurfaceVariant),
            Text(e.ko, style: theme.textTheme.titleMedium),
            if (e.en.isNotEmpty) Text(e.en, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Text(sourceLine, style: theme.textTheme.bodySmall),
            Text(
              e.cas.isEmpty ? CardText.noCas : 'CAS ${e.cas.join(', ')}',
              style: theme.textTheme.bodySmall,
            ),
            if (!e.deleted) ...[
              const SizedBox(height: 8),
              _QuantityTable(rows: e.rows),
            ],
            if (hit.referenceNote) ...[
              const SizedBox(height: 8),
              Text(
                CardText.referenceNote,
                style: theme.textTheme.bodySmall?.copyWith(color: cs.tertiary),
              ),
            ],
          ],
        ),
      ),
    );
    return e.deleted ? Opacity(opacity: 0.55, child: card) : card;
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, {required this.color, required this.onColor});

  final String text;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: onColor)),
    );
  }
}

/// 구분별 함량기준·최하위·하위·상위 규정수량(톤). 값은 원문 그대로.
class _QuantityTable extends StatelessWidget {
  const _QuantityTable({required this.rows});

  final List<QuantityRow> rows;

  static const headers = ['구분', '함량기준(%)', '최하위(톤)', '하위(톤)', '상위(톤)'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headStyle = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final cellStyle = theme.textTheme.bodyMedium;
    Widget cell(String s, TextStyle? style) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Text(s, style: style, softWrap: true),
    );
    return Table(
      columnWidths: const {0: FlexColumnWidth(1.6)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(horizontalInside: BorderSide(color: theme.dividerColor)),
      children: [
        TableRow(children: [for (final h in headers) cell(h, headStyle)]),
        for (final r in rows)
          TableRow(
            children: [
              cell(r.kind, cellStyle),
              cell(r.content, cellStyle),
              cell(r.min, cellStyle),
              cell(r.low, cellStyle),
              cell(r.high, cellStyle),
            ],
          ),
      ],
    );
  }
}
