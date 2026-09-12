/// F-004 행 복사 — 한 물질을 Excel에 붙일 수 있는 TSV로 만든다(REQUIREMENTS F-004 수용 기준이 곧 형식).
///
/// 탭으로 나눠야 Excel에서 열이 갈린다. 마우스로 긁어 복사하는 것으로는 안 된다 —
/// Flutter의 SelectionArea는 여러 위젯에 걸친 선택을 구분자 없이 이어 붙인다(실측:
/// `test/ui/selection_copy_probe_test.dart`). 그래서 복사 버튼이 이 문자열을 직접 클립보드에 넣는다.
library;

import '../parser/models.dart';

/// TSV 열 이름(첫 줄). 화면 표와 달리 영문명이 따로 한 열이다 — Excel에서 쓰기 위해서.
const tsvHeaders = [
  '표',
  '연번',
  '화학물질명',
  '영문명',
  'CAS번호',
  '고유번호',
  '구분',
  '함량기준(% 이상)',
  '최하위규정수량(톤)',
  '하위규정수량(톤)',
  '상위규정수량(톤)',
];

/// [entry] 한 건의 TSV: 머리글 1줄 + 수량 행 수만큼. 앞 6칸(표~고유번호)은 매 줄 반복한다
/// (2026-09-12 사용자 결정 — Excel에서 정렬·필터가 바로 되게).
String tsvText(Entry entry) {
  final head = [
    entry.src.label,
    '${entry.no}',
    entry.ko,
    entry.en,
    entry.cas.join(', '),
    entry.uid ?? '',
  ];
  return [
    tsvHeaders.join('\t'),
    for (final r in entry.rows) [...head, r.kind, r.content, r.min, r.low, r.high].join('\t'),
  ].join('\n');
}
