/// F-004 웹 표 화면 — 검색 결과를 격자 표로 그리고, 물질마다 TSV 복사 버튼을 둔다(REQUIREMENTS F-004).
///
/// 앱(Android)은 카드(`entry_card.dart`)를 쓴다. 어느 쪽을 그릴지는 `search_page.dart` 한 곳에서 정한다.
/// 표는 폭이 좁아도 카드로 바뀌지 않는다 — 가로로 스크롤한다(REQUIREMENTS '화면 방향' 2).
///
/// 한 물질의 수량 행이 여러 개면 **앞 칸(연번·물질명·CAS·고유번호·복사)은 세로로 병합**한다(2026-09-12 사용자 요청:
/// 원본 고시 표와 같은 모양). Flutter의 `Table`에는 rowspan이 없어서, 왼쪽 고정 칸들과 오른쪽 수량 칸 묶음을
/// `IntrinsicHeight` 안의 `Row`로 놓아 높이를 맞춘다.
library;

import 'package:flutter/material.dart';

import '../parser/models.dart';
import '../search/search.dart';
import '../share/share_action.dart';
import '../share/tsv_text.dart';
import 'entry_card.dart' show CardText;

/// 물질마다 한 번씩 나오는(세로 병합되는) 앞 칸.
const entryColumns = <({String label, double width, TextAlign align})>[
  (label: '연번', width: 56, align: TextAlign.right),
  (label: '화학물질명', width: 260, align: TextAlign.left),
  (label: 'CAS번호', width: 150, align: TextAlign.left),
  (label: '고유번호', width: 88, align: TextAlign.left),
];

/// 수량 행마다 나오는 칸.
const rowColumns = <({String label, double width, TextAlign align})>[
  (label: '구분', width: 72, align: TextAlign.center),
  (label: '함량기준\n(% 이상)', width: 88, align: TextAlign.right),
  (label: '최하위\n규정수량(톤)', width: 96, align: TextAlign.right),
  (label: '하위\n규정수량(톤)', width: 96, align: TextAlign.right),
  (label: '상위\n규정수량(톤)', width: 96, align: TextAlign.right),
];

const _copyColumn = (label: '복사', width: 52.0, align: TextAlign.center);

/// 표 전체 폭(맨 왼쪽 테두리 1px 포함). 화면이 이보다 좁으면 가로 스크롤이 생긴다.
double get tableWidth =>
    entryColumns.fold<double>(0, (s, c) => s + c.width) +
    rowColumns.fold<double>(0, (s, c) => s + c.width) +
    _copyColumn.width +
    _outerBorder;

const _outerBorder = 1.0;

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
                itemBuilder: (context, i) => _EntryRow(hit: hits[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 격자 한 칸. 오른쪽·아래 선으로 표를 그린다(맨 왼쪽·맨 위 선은 표 바깥 테두리가 맡는다).
Widget _cell(
  BuildContext context, {
  required double width,
  required Widget child,
  bool bottomBorder = true,
}) {
  final divider = Theme.of(context).dividerColor;
  return Container(
    width: width,
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    decoration: BoxDecoration(
      border: Border(
        right: BorderSide(color: divider),
        bottom: bottomBorder ? BorderSide(color: divider) : BorderSide.none,
      ),
    ),
    child: child,
  );
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget head(({String label, double width, TextAlign align}) c) => _cell(
      context,
      width: c.width,
      child: Align(
        alignment: switch (c.align) {
          TextAlign.right => Alignment.centerRight,
          TextAlign.center => Alignment.center,
          _ => Alignment.centerLeft,
        },
        child: Text(c.label, style: style, textAlign: c.align),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        // 칸들은 오른쪽·아래 선만 그린다 — 표의 맨 위·맨 왼쪽 선은 여기서 그린다(2026-09-12 사용자 지적).
        border: Border(
          left: BorderSide(color: theme.dividerColor, width: _outerBorder),
          top: BorderSide(color: theme.dividerColor, width: _outerBorder),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final c in entryColumns) head(c),
            for (final c in rowColumns) head(c),
            head(_copyColumn),
          ],
        ),
      ),
    );
  }
}

/// 물질 한 건: 왼쪽 앞 칸(세로 병합) + 오른쪽 수량 행들 + 복사 버튼.
class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.hit});

  final Hit hit;

  @override
  Widget build(BuildContext context) {
    final e = hit.entry;
    final theme = Theme.of(context);
    final cellStyle = theme.textTheme.bodySmall;

    Widget entryCell(int i, Widget child) => _cell(
      context,
      width: entryColumns[i].width,
      child: Align(
        alignment: entryColumns[i].align == TextAlign.right
            ? Alignment.topRight
            : Alignment.topLeft,
        child: child,
      ),
    );

    final row = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          entryCell(0, Text('${e.no}', style: cellStyle, textAlign: TextAlign.right)),
          entryCell(1, _NameCell(hit: hit)),
          entryCell(2, Text(e.cas.isEmpty ? CardText.noCas : e.cas.join(', '), style: cellStyle)),
          entryCell(3, Text(e.uid ?? '', style: cellStyle)),
          // 수량 행 묶음: 병합된 앞 칸의 높이를 줄 수만큼 나눠 갖는다.
          // (줄이 제 높이만 쓰면 물질 칸보다 짧아져 아래쪽 선이 끊긴다 — 2026-09-12 사용자 지적)
          Column(
            children: [
              for (var i = 0; i < e.rows.length; i++)
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < rowColumns.length; c++)
                        _cell(
                          context,
                          width: rowColumns[c].width,
                          child: Text(
                            _rowValue(e.rows[i], c),
                            style: cellStyle,
                            textAlign: rowColumns[c].align,
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
          _cell(
            context,
            width: _copyColumn.width,
            child: Align(
              alignment: Alignment.topCenter,
              child: IconButton(
                icon: const Icon(Icons.content_copy_outlined, size: 18),
                tooltip: ShareText.copyTooltip,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () => copyToClipboard(context, tsvText(e)),
              ),
            ),
          ),
        ],
      ),
    );

    final divider = Theme.of(context).dividerColor;
    final bordered = Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: divider, width: _outerBorder)),
      ),
      child: row,
    );
    return e.deleted ? Opacity(opacity: 0.55, child: bordered) : bordered;
  }
}

String _rowValue(QuantityRow r, int column) => switch (column) {
  0 => r.kind,
  1 => r.content,
  2 => r.min,
  3 => r.low,
  _ => r.high,
};

/// 국문명 + 영문명(+ 참고 문구). 화면에는 카드와 같은 내용을 보인다(TSV에는 국문명만 넣는다).
class _NameCell extends StatelessWidget {
  const _NameCell({required this.hit});

  final Hit hit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = hit.entry;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
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
    );
  }
}
