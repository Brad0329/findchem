/// F-007 GHS H·P 코드 → `(코드)문구` 한 줄(2026-09-15 사용자 결정 — 규칙은 REQUIREMENTS F-007 'H·P 문구').
library;

import 'package:flutter/foundation.dart';

import 'ghs_phrase_data.dart';

abstract final class GhsPhraseText {
  static const missing = '문구없음';
  static const notInTable = '(문구표 없음)';
}

/// [code]를 [table]에서 찾아 `(코드)문구`. 없으면 합성 코드는 낱개 문구를 이어 붙이고 `(문구표 없음)`,
/// 낱개도 하나 없으면 `(코드)문구없음`. 없는 코드는 화면에 그렇게 드러내고 로그에도 남긴다.
String ghsPhraseLine(String code, Map<String, String> table) {
  final c = code.trim();
  final exact = table[c];
  if (exact != null) return '($c)$exact';

  final parts = [for (final p in c.split('+')) if (p.trim().isNotEmpty) p.trim()];
  final found = [for (final p in parts) table[p]];
  if (parts.length > 1 && found.any((f) => f != null)) {
    debugPrint('F-007 GHS 문구: $c 합성 코드가 문구표에 없음 — 낱개 문구를 이어 표시(없는 낱개: '
        '${[for (var i = 0; i < parts.length; i++) if (found[i] == null) parts[i]]})');
    return '($c)${[for (final f in found) f ?? GhsPhraseText.missing].join(' ')}${GhsPhraseText.notInTable}';
  }
  debugPrint('F-007 GHS 문구: $c 문구표에 없음 — 문구없음으로 표시');
  return '($c)${GhsPhraseText.missing}';
}

String hPhraseLine(String code) => ghsPhraseLine(code, ghsHPhrases);

String pPhraseLine(String code) => ghsPhraseLine(code, ghsPPhrases);
