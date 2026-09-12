/// F-004 웹 표 화면 — 검색 결과를 표로 그리고, 행마다 TSV 복사 버튼을 둔다(REQUIREMENTS F-004).
///
/// 앱(Android)은 카드(`entry_card.dart`)를 쓴다. 어느 쪽을 그릴지는 `search_page.dart` 한 곳에서 정한다.
/// 표는 폭이 좁아도 카드로 바뀌지 않는다 — 가로로 스크롤한다(REQUIREMENTS '화면 방향' 2).
library;

import 'package:flutter/material.dart';

import '../parser/models.dart';
import '../search/search.dart';
import '../share/share_action.dart';
import '../share/tsv_text.dart';
import 'entry_card.dart' show CardText, byeolpyo2BadgeColor;

/// 열 순서와 폭(논리 픽셀). 화면 표의 열이다 — TSV 열은 [tsvHeaders]로 따로 있다(영문명이 한 열 더 있다).
const tableColumns = <({String label, double width, TextAlign align})>[
  (label: '표', width: 128, align: TextAlign.left),
  (label: '연번', width: 52, align: TextAlign.right),
  (label: '화학물질명', width: 220, align: TextAlign.left),
  (label: 'CAS번호', width: 160, align: TextAlign.left),
  (label: '고유번호', width: 84, align: TextAlign.left),
  (label: '구분', width: 72, align: TextAlign.center),
  (label: '함량기준(% 이상)', width: 92, align: TextAlign.right),
  (label: '최하위(톤)', width: 76, align: TextAlign.right),
  (label: '하위(톤)', width: 76, align: TextAlign.right),
  (label: '상위(톤)', width: 76, align: TextAlign.right),
  (label: '복사', width: 52, align: TextAlign.center),
];

/// 표 전체 폭. 화면이 이보다 좁으면 가로 스크롤이 생긴다.
double get tableWidth => tableColumns.fold(0, (sum, c) => sum + c.width);

Map<int, TableColumnWidth> get _columnWidths => {
  for (var i = 0; i < tableColumns.length; i++) i: FixedColumnWidth(tableColumns[i].width),
};

class ResultTable extends StatelessWidget {
  const ResultTable({super.key, required this.hits});

  final List<Hit> hits;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: tableWidth,
        child: Column(
          children: [
            const _HeaderRow(),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: hits.length,
                itemBuilder: (context, i) => _EntryRows(hit: hits[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Widget _cell(String text, int column, TextStyle? style, {TextAlign? align}) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
  child: Text(text, style: style, textAlign: align ?? tableColumns[column].align),
);

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Table(
        columnWidths: _columnWidths,
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [for (var i = 0; i < tableColumns.length; i++) _cell(tableColumns[i].label, i, style)],
          ),
        ],
      ),
    );
  }
}

/// 물질 한 건 = 수량 행 수만큼의 표 줄. 앞 열(표·연번·물질명·CAS·고유번호·복사)은 첫 줄에만 쓴다.
class _EntryRows extends StatelessWidget {
  const _EntryRows({required this.hit});

  final Hit hit;

  @override
  Widget build(BuildContext context) {
    final e = hit.entry;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final cellStyle = theme.textTheme.bodySmall;
    final isByeolpyo3 = e.src == Source.byeolpyo3;

    final table = Table(
      columnWidths: _columnWidths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      border: TableBorder(
        horizontalInside: BorderSide(color: theme.dividerColor.withValues(alpha: 0.4)),
        bottom: BorderSide(color: theme.dividerColor),
      ),
      children: [
        for (var i = 0; i < e.rows.length; i++)
          TableRow(
            children: [
              i == 0
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _SourceBadge(
                          label: e.src.label,
                          color: isByeolpyo3 ? cs.primary : byeolpyo2BadgeColor,
                          onColor: isByeolpyo3 ? cs.onPrimary : Colors.white,
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
              i == 0 ? _cell('${e.no}', 1, cellStyle) : const SizedBox.shrink(),
              i == 0 ? _NameCell(hit: hit) : const SizedBox.shrink(),
              i == 0
                  ? _cell(e.cas.isEmpty ? CardText.noCas : e.cas.join(', '), 3, cellStyle)
                  : const SizedBox.shrink(),
              i == 0 ? _cell(e.uid ?? '', 4, cellStyle) : const SizedBox.shrink(),
              _cell(e.rows[i].kind, 5, cellStyle),
              _cell(e.rows[i].content, 6, cellStyle),
              _cell(e.rows[i].min, 7, cellStyle),
              _cell(e.rows[i].low, 8, cellStyle),
              _cell(e.rows[i].high, 9, cellStyle),
              i == 0
                  ? IconButton(
                      icon: const Icon(Icons.content_copy_outlined, size: 18),
                      tooltip: ShareText.copyTooltip,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => copyToClipboard(context, tsvText(e)),
                    )
                  : const SizedBox.shrink(),
            ],
          ),
      ],
    );
    return e.deleted ? Opacity(opacity: 0.55, child: table) : table;
  }
}

/// 국문명 + 영문명(+ 참고 문구). 카드와 같은 내용이다.
class _NameCell extends StatelessWidget {
  const _NameCell({required this.hit});

  final Hit hit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = hit.entry;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(e.ko, style: theme.textTheme.bodySmall),
          if (e.en.isNotEmpty)
            Text(
              e.en,
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          if (hit.referenceNote)
            Text(
              '※ ${CardText.referenceNote}',
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.tertiary),
            ),
        ],
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.label, required this.color, required this.onColor});

  final String label;
  final Color color;
  final Color onColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(6)),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: onColor),
      ),
    );
  }
}
