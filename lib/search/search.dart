/// F-001 물질 검색 — docs/REQUIREMENTS.md F-001 수용 기준이 곧 이 파일의 규칙이다.
///
/// - 이름: 부분 일치, 띄어쓰기 무시, 영문 대소문자 무시. 원문 `name` 전체를 대상으로 한다(ko·en을 모두 덮고,
///   별표3 33번처럼 국문명에 단서가 붙은 형식도 포함 — Phase_003.md).
/// - CAS: 입력이 숫자·하이픈뿐이면 CAS 앞부분 일치도 함께 본다(입력 즉시 검색이라 타이핑 중에도 좁혀진다).
///   비교는 양쪽 다 하이픈을 뺀 숫자로 한다 — `96297`로도 `96-29-7`이 찾힌다(2026-09-11 사용자 결정).
/// - 순서: 사고대비물질(별표3) → 인체·생태 유해성(별표2) 살아있는 항목 → `(삭제)` 항목. 각 묶음 안은 연번 순.
/// - 두 표에 같은 CAS가 있으면 별표3 항목에 '우선 적용', 별표2 항목에 참고 문구(별표2 일반기준 가).
/// - 상한 [SearchIndex.cap]건. 넘으면 잘랐다는 사실과 전체 건수를 함께 돌려준다(조용한 절단 금지).
library;

import '../parser/models.dart';

/// 검색 결과 한 건.
class Hit {
  const Hit(this.entry, {required this.priority, required this.referenceNote});

  final Entry entry;

  /// 별표3 항목인데 같은 CAS가 살아있는 별표2 항목에도 있다 → '사고대비물질 · 우선 적용'.
  final bool priority;

  /// 별표2 항목인데 같은 CAS가 별표3에도 있다 → "사고대비물질은 사고대비물질 규정수량을 적용합니다" 참고 문구.
  final bool referenceNote;
}

class SearchResult {
  const SearchResult({
    required this.query,
    required this.hits,
    required this.total,
    required this.count2,
    required this.count3,
    required this.casQueryNoHit,
  });

  static const empty = SearchResult(
    query: '',
    hits: [],
    total: 0,
    count2: 0,
    count3: 0,
    casQueryNoHit: false,
  );

  final String query;

  /// 순서대로, 상한까지.
  final List<Hit> hits;

  /// 상한 적용 전 전체 건수.
  final int total;

  /// 표별 건수(상한 적용 전).
  final int count2;
  final int count3;

  /// CAS 형식으로 넣었는데 0건 → 묶음 항목 안내를 띄운다(2026-09-11 사용자 결정).
  final bool casQueryNoHit;

  bool get truncated => hits.length < total;
}

/// 검색용 색인. 데이터셋 하나당 한 번 만든다.
class SearchIndex {
  SearchIndex(Dataset ds, {this.cap = 100}) : _entries = List.unmodifiable(ds.entries) {
    final cas3 = <String>{};
    final cas2Live = <String>{};
    for (final e in _entries) {
      if (e.src == Source.byeolpyo3) {
        cas3.addAll(e.cas);
      } else if (!e.deleted) {
        cas2Live.addAll(e.cas);
      }
    }
    _priority = {
      for (final e in _entries)
        if (e.src == Source.byeolpyo3 && e.cas.any(cas2Live.contains)) e,
    };
    _referenceNote = {
      for (final e in _entries)
        if (e.src == Source.byeolpyo2 && !e.deleted && e.cas.any(cas3.contains)) e,
    };
    _normalizedNames = [for (final e in _entries) normalize(e.name)];
    _casDigits = [
      for (final e in _entries) [for (final c in e.cas) casDigits(c)],
    ];
  }

  /// 결과 상한. 넘으면 [SearchResult.truncated].
  final int cap;

  final List<Entry> _entries;
  late final Set<Entry> _priority;
  late final Set<Entry> _referenceNote;
  late final List<String> _normalizedNames;
  late final List<List<String>> _casDigits;

  /// 이름 비교용: 공백(전각 포함) 제거 + 소문자.
  static String normalize(String s) => s.replaceAll(RegExp(r'[\s　]+'), '').toLowerCase();

  /// CAS 비교용: 하이픈 제거.
  static String casDigits(String s) => s.replaceAll('-', '');

  static final _casLike = RegExp(r'^[0-9-]+$');

  /// CAS로 볼 수 있는 입력(하이픈 뺀 숫자 5~10자리 — CAS는 2~7+2+1 자리). 0건 안내의 조건.
  static final _casFull = RegExp(r'^\d{5,10}$');

  /// 이 데이터셋의 항목 [e]를 카드 한 건으로('우선 적용'·참고 문구 계산 포함). F-005 [update]도 이것으로 스냅샷을 만든다.
  Hit hitOf(Entry e) => Hit(e, priority: _priority.contains(e), referenceNote: _referenceNote.contains(e));

  SearchResult search(String rawQuery) {
    final q = normalize(rawQuery);
    if (q.isEmpty) return SearchResult.empty;

    final qDigits = casDigits(q);
    final byCas = _casLike.hasMatch(q) && qDigits.isNotEmpty;
    final b3 = <Entry>[];
    final b2 = <Entry>[];
    final deleted = <Entry>[];
    for (var i = 0; i < _entries.length; i++) {
      final e = _entries[i];
      final matched =
          _normalizedNames[i].contains(q) || (byCas && _casDigits[i].any((c) => c.startsWith(qDigits)));
      if (!matched) continue;
      if (e.src == Source.byeolpyo3) {
        b3.add(e);
      } else if (e.deleted) {
        deleted.add(e);
      } else {
        b2.add(e);
      }
    }
    // 입력 순서(별표2 연번 순 → 별표3 번호 순)를 유지한 채 묶음만 재배열한다.
    final ordered = [...b3, ...b2, ...deleted];
    final hits = [for (final e in ordered.take(cap)) hitOf(e)];
    return SearchResult(
      query: rawQuery,
      hits: hits,
      total: ordered.length,
      count2: b2.length + deleted.length,
      count3: b3.length,
      casQueryNoHit: ordered.isEmpty && byCas && _casFull.hasMatch(qDigits),
    );
  }
}
