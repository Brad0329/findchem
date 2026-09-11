/// CAS 번호 셀 파싱. `-`는 없음, 여러 개는 `,`로 구분(최대 7개, Phase 001 실측).
///
/// 셀 안 줄바꿈(`\n`)은 두 가지다 — 긴 CAS가 `-` 뒤에서 끊긴 것(`1233844-88-⏎6`, 별표2 16건)과
/// 쉼표 없이 줄바꿈만으로 나뉜 두 CAS(`95-47-6⏎106-42-3`, 별표3 98번). 줄 단위로 읽어, 그 줄만으로 CAS가
/// 되면 하나로 세고 아니면 다음 줄과 이어 붙인다. 이어 붙여도 CAS가 안 되면 경고를 남기고 원문 그대로 둔다.
library;

/// CAS 형식 `NN…N-NN-N`(앞 부분 2~7자리). 체크디지트는 검사하지 않는다 — 원문에 틀린 것이 2건 있다.
final casPattern = RegExp(r'^\d{2,7}-\d{2}-\d$');

/// 셀 문자열 → CAS 목록. 형식이 어긋난 조각은 [warnings]에 남기고 원문 그대로 넣는다(조용히 버리지 않는다).
List<String> parseCasCell(String cell, {required List<String> warnings, required String where}) {
  final text = cell.trim();
  if (text.isEmpty || text == '-') return const [];

  final result = <String>[];
  for (final piece in text.split(',')) {
    var buffer = '';
    for (final line in piece.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
      buffer = buffer + line;
      if (casPattern.hasMatch(buffer)) {
        result.add(buffer);
        buffer = '';
      }
    }
    if (buffer.isNotEmpty) {
      warnings.add('$where: CAS 형식 아님 "$buffer" (원문 그대로 둠)');
      result.add(buffer);
    }
  }
  return result;
}
