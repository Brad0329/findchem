/// F-003 카드 공유 텍스트 — 카드 한 장을 메신저에 붙여 넣을 평문으로 만든다(REQUIREMENTS F-003 수용 기준이 곧 형식).
///
/// 메신저 글꼴은 고정폭이 아니라 표로 맞추면 틀어진다 — 구분별 수량을 한 줄에 하나씩 쓴다. 값은 카드처럼 원문 그대로.
library;

import '../parser/models.dart';
import '../search/search.dart';
import '../ui/entry_card.dart' show CardText;

const _decree = '「유해화학물질의 규정수량에 관한 규정」';
final _isoDate = RegExp(r'^\d{4}-\d{2}-\d{2}');

/// [hit] 카드의 공유 텍스트. [pdf]는 그 카드가 속한 표의 원본 PDF(마지막 줄 기준일).
String shareText(Hit hit, PdfInfo pdf) {
  final e = hit.entry;
  final label = hit.priority ? CardText.priority : e.src.label;
  return [
    '[$label] ${e.ko}',
    if (e.en.isNotEmpty) e.en,
    ['${e.src == Source.byeolpyo3 ? '번호' : '연번'} ${e.no}', if (e.uid != null) '고유번호 ${e.uid}'].join(' · '),
    e.cas.isEmpty ? CardText.noCas : 'CAS ${e.cas.join(', ')}',
    '',
    if (e.deleted)
      CardText.deleted
    else ...[
      '규정수량(톤) 최하위 / 하위 / 상위',
      for (final r in e.rows) '· ${_rowLabel(r)}: ${r.min} / ${r.low} / ${r.high}',
    ],
    if (hit.referenceNote) ...['', '※ ${CardText.referenceNote}'],
    '',
    _footer(pdf),
  ].join('\n');
}

/// `급성, 함량기준 1%` / `함량기준 10%`(별표3은 구분이 없다) / `염화수소 용액`(함량기준 빈칸).
/// 함량기준에 이미 %가 있으면(`70% 초과`) 붙이지 않는다. 구분·함량기준이 둘 다 빈 행은 번들 데이터에 없다(2026-09-11 확인).
String _rowLabel(QuantityRow r) => [
  if (r.kind.isNotEmpty) r.kind,
  if (r.content.isNotEmpty) '함량기준 ${r.content.contains('%') ? r.content : '${r.content}%'}',
].join(', ');

String _footer(PdfInfo pdf) {
  final date = pdf.created == null ? null : _isoDate.firstMatch(pdf.created!)?.group(0);
  return 'FindChem · $_decree${date == null ? '' : ' (PDF $date 기준)'}';
}
