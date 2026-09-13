/// 검색 결과 항목 카드 — REQUIREMENTS F-001 "항목 카드에는 다음이 모두 나온다".
library;

import 'package:flutter/material.dart';

import '../parser/models.dart';
import '../search/search.dart';
import '../share/share_action.dart';
import '../share/share_text.dart';

/// 표 이름 뱃지 색 — 인체·생태 유해성(REQUIREMENTS '화면 방향' 3, 2026-09-12 사용자 결정).
/// Material 3 시드(파랑)에서 붉은색이 나오지 않아 고정값을 쓴다. 라이트·다크 공용이고 글자는 흰색이다
/// (흰 글자 대비 5.6:1). 사고대비물질 뱃지는 테마 강조색(`colorScheme.primary`)을 쓴다.
const byeolpyo2BadgeColor = Color(0xFFC62828);

/// 화면 문구(테스트가 같은 상수를 본다).
abstract final class CardText {
  /// 카드에는 쓰지 않는다(2026-09-12 사용자 결정으로 뱃지 삭제) — 공유 텍스트 첫 줄 라벨 전용(F-003 수용 기준).
  static const priority = '사고대비물질 · 우선 적용';
  static const referenceNote = '사고대비물질은 사고대비물질 규정수량을 적용합니다(별표2 일반기준 가)';
  static const noCas = '묶음 항목 · CAS 없음';
  static const deleted = '삭제된 항목 · 규정수량 없음';
}

class EntryCard extends StatelessWidget {
  const EntryCard({super.key, required this.hit, required this.pdf, this.action});

  final Hit hit;

  /// 이 항목이 속한 표의 원본 PDF — 공유 텍스트 마지막 줄의 기준일(F-003).
  final PdfInfo pdf;

  /// 공유 버튼 왼쪽에 놓을 버튼(F-005: 검색 카드는 저장, 저장 목록은 삭제). 없으면 공유 버튼만.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final e = hit.entry;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // 표 이름은 뱃지로, 번호·고유번호는 그 옆 한 줄로(2026-09-12 사용자 결정).
    final isByeolpyo3 = e.src == Source.byeolpyo3;
    final sourceDetail = [
      '${isByeolpyo3 ? '번호' : '연번'} ${e.no}',
      if (e.uid != null) '고유번호 ${e.uid}',
    ].join(' · ');

    final card = Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 오른쪽 위 공유 버튼은 이름 줄까지만 옆에 둔다 — 수량 표는 카드 폭을 다 쓴다.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (e.deleted)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _Badge(
                            CardText.deleted,
                            color: cs.surfaceContainerHighest,
                            onColor: cs.onSurfaceVariant,
                          ),
                        ),
                      Text(e.ko, style: theme.textTheme.titleMedium),
                      if (e.en.isNotEmpty)
                        Text(e.en, style: theme.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
                    ],
                  ),
                ),
                if (action != null) action!,
                IconButton(
                  icon: const Icon(Icons.share_outlined),
                  tooltip: ShareText.tooltip,
                  visualDensity: VisualDensity.compact,
                  onPressed: () => shareOrCopy(context, shareText(hit, pdf)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // 좁은 폭(360dp)에서 뱃지+번호가 한 줄에 안 들어가면 줄을 넘긴다.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 4,
              children: [
                _Badge(
                  e.src.label,
                  color: isByeolpyo3 ? cs.primary : byeolpyo2BadgeColor,
                  onColor: isByeolpyo3 ? cs.onPrimary : Colors.white,
                ),
                Text(sourceDetail, style: theme.textTheme.bodySmall),
              ],
            ),
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
    // 수량 열은 오른쪽 정렬(자릿수를 세로로 맞춘다), 구분 열만 중앙 정렬 — 2026-09-12 사용자 요청.
    Widget cell(String s, TextStyle? style, {TextAlign align = TextAlign.right}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Text(s, style: style, softWrap: true, textAlign: align),
    );
    Widget kindCell(String s, TextStyle? style) => cell(s, style, align: TextAlign.center);
    return Table(
      columnWidths: const {0: FlexColumnWidth(1.6)},
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(horizontalInside: BorderSide(color: theme.dividerColor)),
      children: [
        TableRow(
          children: [
            kindCell(headers.first, headStyle),
            for (final h in headers.skip(1)) cell(h, headStyle),
          ],
        ),
        for (final r in rows)
          TableRow(
            children: [
              kindCell(r.kind, cellStyle),
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
