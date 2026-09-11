/// PDF에서 뽑은 표의 원시 셀 격자. 추출 층(PDF 라이브러리)과 정규화 층(entry_builder)의 경계.
///
/// 셀 값은 원문 그대로다 — 셀 안 줄바꿈은 `\n`으로, 줄 끝 공백도 그대로 둔다(줄바꿈 처리 규칙은 빌더에만 있다).
/// `test/fixtures/*_cells.json`(pdfplumber 정답지)과 같은 형식이라 추출 층을 대조할 수 있다.
library;

/// 한 페이지의 표. 첫 행은 머리글(매 페이지 반복)이다.
class PageGrid {
  const PageGrid({required this.page, required this.rows});

  /// 1부터 시작하는 페이지 번호.
  final int page;

  /// 행 → 셀 문자열. 각 행의 길이는 표의 열 수와 같다.
  final List<List<String>> rows;
}

/// 파싱 실패. [reason]은 화면에 그대로 보여줄 수 있는 문장(F-002 수용 기준).
class ParseException implements Exception {
  const ParseException(this.reason);

  final String reason;

  @override
  String toString() => 'ParseException: $reason';
}
