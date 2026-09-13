/// F-005 자주보는 Chem 목록 — 카드 스냅샷 저장, 정렬, [update]. 규칙의 원본은 REQUIREMENTS F-005,
/// 저장 형식의 결정은 SCHEMA.md '자주보는 Chem 목록'.
///
/// 목록은 **데이터셋 없이 저장본만으로** 그린다. 데이터셋은 [FavoritesController.updateFrom]과 갱신 알림 줄
/// ([FavoritesController.isStale])에서만 본다.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../parser/models.dart';
import '../search/search.dart';
import 'update_store.dart';

/// 저장 파일 형식 버전(SCHEMA.md — 누적되는 사용자 저장소라 처음부터 둔다).
const favoritesFormatVersion = 1;

/// 저장 항목 하나 = 카드 한 장을 그리는 데 필요한 전부(스냅샷).
class FavoriteItem {
  const FavoriteItem({
    required this.entry,
    required this.priority,
    required this.referenceNote,
    required this.pdfCreated,
  });

  /// 검색 결과 카드 [hit](그 표의 PDF [pdf])를 그대로 담는다.
  factory FavoriteItem.fromHit(Hit hit, PdfInfo pdf) => FavoriteItem(
    entry: hit.entry,
    priority: hit.priority,
    referenceNote: hit.referenceNote,
    pdfCreated: pdf.created,
  );

  /// 번들 JSON의 항목과 같은 형식.
  final Entry entry;

  /// 저장할 때의 '우선 적용'·참고 문구 여부 — 전체 데이터셋에서 계산되는 값이라 항목만으로 다시 구할 수 없다.
  final bool priority;
  final bool referenceNote;

  /// 그 항목이 속한 표 PDF의 생성일(ISO 8601). 없으면 null.
  final String? pdfCreated;

  Hit get hit => Hit(entry, priority: priority, referenceNote: referenceNote);

  /// 카드·공유 텍스트에 넘길 PDF 정보. 공유 텍스트는 생성일만 쓰고, 스냅샷에도 생성일만 담는다(SCHEMA.md).
  PdfInfo get pdf => PdfInfo(file: '', created: pdfCreated, pages: 0);

  /// 검색 카드의 [e]가 이 저장 항목과 같은 물질인가(저장 아이콘 채움·토글). 연번은 보지 않는다 — 개정되면 밀린다.
  /// `src+uid+cas+ko`는 번들 1,657건에서 유일하다(`scripts/oracle_key_candidates.py`, 2026-09-13).
  bool sameSubstance(Entry e) =>
      e.src == entry.src &&
      SearchIndex.normalize(e.ko) == SearchIndex.normalize(entry.ko) &&
      e.uid == entry.uid &&
      setEquals(e.cas.toSet(), entry.cas.toSet());

  Map<String, Object?> toJson() => {
    'priority': priority,
    'referenceNote': referenceNote,
    'pdfCreated': pdfCreated,
    'entry': entry.toJson(),
  };

  factory FavoriteItem.fromJson(Map<String, Object?> j) => FavoriteItem(
    entry: Entry.fromJson((j['entry'] as Map).cast<String, Object?>()),
    priority: j['priority'] as bool,
    referenceNote: j['referenceNote'] as bool,
    pdfCreated: j['pdfCreated'] as String?,
  );
}

String encodeFavorites(List<FavoriteItem> items) => jsonEncode({
  'version': favoritesFormatVersion,
  'items': [for (final i in items) i.toJson()],
});

List<FavoriteItem> decodeFavorites(String text) {
  final j = (jsonDecode(text) as Map).cast<String, Object?>();
  final version = j['version'];
  if (version != favoritesFormatVersion) throw FormatException('알 수 없는 저장 목록 형식 버전: $version');
  return [
    for (final i in j['items'] as List) FavoriteItem.fromJson((i as Map).cast<String, Object?>()),
  ];
}

final _hangulSyllable = RegExp('[가-힣]');

/// 정렬 키: 국문명의 앞머리(숫자·기호·로마자 접두)를 건너뛴 **첫 한글 음절부터**(REQUIREMENTS F-005 정렬).
/// 한글이 하나도 없으면 null(현재 데이터 0건 — 방어용). 건너뛴 앞머리가 정말 숫자·기호·로마자뿐인지는
/// 번들 전수 테스트가 건다(`test/data/favorites_store_test.dart`).
String? koreanSortKey(String ko) {
  final i = ko.indexOf(_hangulSyllable);
  return i < 0 ? null : ko.substring(i);
}

/// 목록 순서: 정렬 키 가나다(한글 없는 국문명은 뒤, 전체를 키로) → 사고대비물질 먼저 → 연번.
/// 한글끼리의 `compareTo`가 가나다 순인 것은 `test/data/korean_order_probe_test.dart`가 못박았다.
int compareFavorites(FavoriteItem a, FavoriteItem b) {
  final ka = koreanSortKey(a.entry.ko);
  final kb = koreanSortKey(b.entry.ko);
  if ((ka == null) != (kb == null)) return ka == null ? 1 : -1;
  final byName = (ka ?? a.entry.ko).compareTo(kb ?? b.entry.ko);
  if (byName != 0) return byName;
  if (a.entry.src != b.entry.src) return a.entry.src == Source.byeolpyo3 ? -1 : 1;
  return a.entry.no.compareTo(b.entry.no);
}

/// [update] 찾는 규칙: 같은 표 안에서 정규화한 국문명이 같은 항목. 둘 이상이면 `uid` → `cas`로 좁히고,
/// 그래도 하나가 아니면(0건 포함) null = '못 찾음' — 조용히 아무거나 고르지 않는다.
Entry? findSameSubstance(FavoriteItem item, List<Entry> entries) {
  final saved = item.entry;
  final name = SearchIndex.normalize(saved.ko);
  var found = [
    for (final e in entries)
      if (e.src == saved.src && SearchIndex.normalize(e.ko) == name) e,
  ];
  if (found.length > 1) found = [for (final e in found) if (e.uid == saved.uid) e];
  if (found.length > 1) {
    found = [for (final e in found) if (setEquals(e.cas.toSet(), saved.cas.toSet())) e];
  }
  return found.length == 1 ? found.single : null;
}

PdfInfo _pdfOf(Dataset ds, Source src) => src == Source.byeolpyo3 ? ds.byeolpyo3 : ds.byeolpyo2;

/// [update] 결과 요약.
class FavoritesUpdateSummary {
  const FavoritesUpdateSummary({required this.updated, required this.notFound});

  final int updated;
  final int notFound;
}

/// 저장 목록 파일을 읽지 못한 상태에서 쓰기를 거부할 때. 덮으면 깨진 파일 속 저장이 사라진다.
class FavoritesUnreadable implements Exception {
  const FavoritesUnreadable();

  @override
  String toString() => 'FavoritesUnreadable: 저장 목록 파일을 읽지 못해 쓰기를 거부합니다';
}

/// 앱의 저장 목록. 쓰기는 모두 "새 목록 계산 → 파일 쓰기 성공 → 화면 반영" 순서다 — 쓰기가 실패하면 예외이고
/// 기존 목록은 그대로다.
class FavoritesController extends ChangeNotifier {
  FavoritesController({required this.store});

  final UpdateStore store;

  List<FavoriteItem> _items = const [];
  bool _loadFailed = false;
  Future<void>? _loading;

  /// 마지막 [updateFrom]에서 못 찾은 항목(객체 동일성). 저장하지 않는다 — 앱을 다시 켜면 사라진다.
  final Set<FavoriteItem> _notFound = Set.identity();

  /// 정렬된 저장 항목.
  List<FavoriteItem> get items => _items;

  /// 저장 파일이 있는데 읽지 못했다(사유는 로그). 이때는 쓰기를 모두 거부한다.
  bool get loadFailed => _loadFailed;

  bool isNotFound(FavoriteItem item) => _notFound.contains(item);

  /// 저장 파일을 읽는다. 여러 번 불러도 한 번만 읽는다. 실패해도 예외를 던지지 않고 [loadFailed]로 남긴다.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final text = await store.read();
      _items = text == null ? const [] : _sorted(decodeFavorites(text));
    } catch (e, st) {
      // 빈 목록으로 조용히 대체하지 않는다 — 화면에 사유를 보이고(loadFailed), 파일은 지우지 않는다(F-002 선례).
      debugPrint('F-005 저장 목록 읽기 실패: $e\n$st');
      _loadFailed = true;
    }
    notifyListeners();
  }

  /// 현재 데이터셋 [entries]의 카드 [e]와 같은 물질로 저장된 항목(저장 아이콘 채움·토글 판정). 없으면 null.
  /// 표·정규화한 국문명·uid·CAS가 모두 같으면 바로 그 항목이다. 이름만 같고 uid·CAS가 달라진 항목(개정 뒤 아직
  /// update 안 함)은 [update]와 같은 찾기 규칙([findSameSubstance])이 [e]를 가리킬 때 같은 물질로 본다 —
  /// 그래야 같은 물질이 2건 저장되지 않는다. 이름이 다르면 [entries]를 훑지 않는다(카드마다 부르므로).
  FavoriteItem? savedOf(Entry e, List<Entry> entries) {
    final name = SearchIndex.normalize(e.ko);
    FavoriteItem? byRule;
    for (final i in _items) {
      if (i.entry.src != e.src || SearchIndex.normalize(i.entry.ko) != name) continue;
      if (i.sameSubstance(e)) return i;
      if (byRule == null && identical(findSameSubstance(i, entries), e)) byRule = i;
    }
    return byRule;
  }

  /// 저장 아이콘: 없으면 넣고 true, 있으면 빼고 false. [entries]는 카드가 속한 현재 데이터셋. 쓰기 실패는 예외.
  Future<bool> toggle(Hit hit, PdfInfo pdf, List<Entry> entries) async {
    await load();
    final saved = savedOf(hit.entry, entries);
    await _write(
      saved == null
          ? [..._items, FavoriteItem.fromHit(hit, pdf)]
          : [for (final i in _items) if (!identical(i, saved)) i],
    );
    return saved == null;
  }

  /// 목록의 삭제 버튼.
  Future<void> remove(FavoriteItem item) async {
    await load();
    await _write([for (final i in _items) if (!identical(i, item)) i]);
  }

  /// 원천자료 [ds]가 저장본의 기준일과 다른가 — 날짜 문자열만 비교한다(항목 대조 없음).
  /// 마지막 [updateFrom]에서 못 찾은 항목은 빼고 본다(이미 update를 눌렀는데 알림이 남지 않게).
  bool isStale(Dataset ds) =>
      _items.any((i) => !_notFound.contains(i) && i.pdfCreated != _pdfOf(ds, i.entry.src).created);

  /// [update]: 항목마다 [ds]에서 같은 물질을 찾아 스냅샷을 통째로 새로 쓴다. 못 찾은 항목은 덮지 않는다.
  Future<FavoritesUpdateSummary> updateFrom(Dataset ds) async {
    await load();
    final index = SearchIndex(ds);
    final notFound = <FavoriteItem>[];
    final next = <FavoriteItem>[];
    for (final item in _items) {
      final e = findSameSubstance(item, ds.entries);
      if (e == null) {
        notFound.add(item); // 옛 스냅샷 그대로 둔다
        next.add(item);
      } else {
        next.add(FavoriteItem.fromHit(index.hitOf(e), _pdfOf(ds, e.src)));
      }
    }
    await _write(next);
    _notFound
      ..clear()
      ..addAll(notFound);
    notifyListeners();
    return FavoritesUpdateSummary(updated: next.length - notFound.length, notFound: notFound.length);
  }

  Future<void> _write(List<FavoriteItem> next) async {
    if (_loadFailed) throw const FavoritesUnreadable();
    final sorted = _sorted(next);
    await store.write(encodeFavorites(sorted));
    _items = sorted;
    notifyListeners();
  }

  static List<FavoriteItem> _sorted(List<FavoriteItem> items) =>
      List<FavoriteItem>.unmodifiable(<FavoriteItem>[...items]..sort(compareFavorites));
}
