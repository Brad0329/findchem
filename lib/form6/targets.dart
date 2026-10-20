/// A-010 대상 물질 — 번들의 살아 있는 항목에서 CAS를 뽑는다(REQUIREMENTS_AGENT A-010 결정 ①).
///
/// 1단계는 별표 3(사고대비물질)만. [includeByeolpyo2]는 범위 확장(사용자 2026-10-20) — 별표 3 다음에 별표 2를 붙인다.
///
/// **Flutter를 import하지 않는다.**
library;

import '../parser/models.dart';

class Form6Targets {
  const Form6Targets({required this.cas, required this.noCasEntries, required this.entryCount});

  /// 대상 CAS — 별표 3 먼저, 그 안은 번들 순서(연번), 중복 없음.
  final List<String> cas;

  /// CAS가 없는 항목(묶음 등) — 조용히 빠지지 않게 머리에 적는다.
  final List<Entry> noCasEntries;

  /// 대상으로 본 항목 수(삭제 아님).
  final int entryCount;
}

Form6Targets form6TargetsOf(Dataset ds, {bool includeByeolpyo2 = false}) {
  List<Entry> of(Source s) => ds.entries.where((e) => e.src == s && !e.deleted).toList()..sort((a, b) => a.no.compareTo(b.no));
  final entries = [...of(Source.byeolpyo3), if (includeByeolpyo2) ...of(Source.byeolpyo2)];
  final seen = <String>{};
  return Form6Targets(
    cas: [
      for (final e in entries)
        for (final c in e.cas)
          if (seen.add(c)) c,
    ],
    noCasEntries: [for (final e in entries) if (e.cas.isEmpty) e],
    entryCount: entries.length,
  );
}
