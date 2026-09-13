/// F-005 저장 목록 — 스냅샷 저장·토글·쓰기 실패·깨진 파일·정렬(전수 포함)·[update]·갱신 알림·F-002 저장본과의 분리.
/// 실제 번들 데이터에 질의한다. 저장 자리만 메모리로 바꾼다(파일 분리 확인만 임시 디렉토리의 실제 파일).
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/data/favorites.dart';
import 'package:findchem/data/update_store_io.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/search/search.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late Dataset bundled;
  late SearchIndex index;

  setUpAll(() {
    bundled = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
    index = SearchIndex(bundled);
  });

  Entry entryOf(Source src, int no, [Dataset? ds]) =>
      (ds ?? bundled).entries.singleWhere((e) => e.src == src && e.no == no);
  Hit hit2(int no) => index.hitOf(entryOf(Source.byeolpyo2, no));

  Future<FavoritesController> loaded(MemoryUpdateStore store) async {
    final c = FavoritesController(store: store);
    await c.load();
    return c;
  }

  Future<void> save(FavoritesController c, List<int> nos) async {
    for (final no in nos) {
      expect(await c.toggle(hit2(no), bundled.byeolpyo2, bundled.entries), isTrue, reason: '연번 $no 저장');
    }
  }

  List<String> kos(FavoritesController c) => [for (final i in c.items) i.entry.ko];

  /// [base]에서 [change]로 항목 하나를 바꾼 데이터셋(나머지는 그대로).
  Dataset withEntries(Dataset base, List<Entry> Function(List<Entry>) change) => Dataset(
    byeolpyo2: base.byeolpyo2,
    byeolpyo3: base.byeolpyo3,
    extractedAt: base.extractedAt,
    entries: change([...base.entries]),
  );

  Entry copyEntry(Entry e, {int? no, String? uid, List<QuantityRow>? rows}) => Entry(
    src: e.src,
    no: no ?? e.no,
    uid: uid ?? e.uid,
    name: e.name,
    ko: e.ko,
    en: e.en,
    cas: e.cas,
    deleted: e.deleted,
    rows: rows ?? e.rows,
  );

  group('저장·토글', () {
    test('연번 5(구아자틴) 저장 → 목록에 구아자틴 1건. 다시 누르면 빠진다. 같은 항목이 2건 생기지 않는다', () async {
      final store = MemoryUpdateStore();
      final c = await loaded(store);
      expect(await c.toggle(hit2(5), bundled.byeolpyo2, bundled.entries), isTrue);
      expect(kos(c), ['구아자틴']);
      expect(c.savedOf(entryOf(Source.byeolpyo2, 5), bundled.entries), isNotNull);
      expect(c.savedOf(entryOf(Source.byeolpyo2, 4), bundled.entries), isNull, reason: '구아자틴 염류는 다른 물질');

      expect(await c.toggle(hit2(5), bundled.byeolpyo2, bundled.entries), isFalse);
      expect(c.items, isEmpty);
      await save(c, [5]);
      await save(c, [4]);
      expect(await c.toggle(hit2(5), bundled.byeolpyo2, bundled.entries), isFalse);
      expect(kos(c), ['구아자틴 염류']);
    });

    test('개정으로 uid·CAS가 바뀐 뒤(아직 update 안 함)에도 이름으로 같은 물질이면 저장된 것으로 본다 — 2건 생기지 않는다', () async {
      // 옛 판에서 저장한 구아자틴: 연번·고유번호·CAS가 지금 번들과 다르다고 친다
      final e5 = entryOf(Source.byeolpyo2, 5);
      final old = FavoriteItem(
        entry: Entry(
          src: e5.src, no: 6, uid: '97-1-999', name: e5.name, ko: e5.ko, en: e5.en,
          cas: const ['13516-27-3'], deleted: false, rows: e5.rows,
        ),
        priority: false,
        referenceNote: false,
        pdfCreated: '2020-01-01T00:00:00+09:00',
      );
      final c = await loaded(MemoryUpdateStore(encodeFavorites([old])));
      expect(c.savedOf(e5, bundled.entries), same(c.items.single));
      expect(c.savedOf(entryOf(Source.byeolpyo2, 4), bundled.entries), isNull);
      expect(await c.toggle(hit2(5), bundled.byeolpyo2, bundled.entries), isFalse, reason: '누르면 빼기 — 두 번째 저장이 아니다');
      expect(c.items, isEmpty);
    });

    test('저장 파일 = SCHEMA 형식: version 1, 항목은 번들 항목 그대로 + 우선 적용·참고 문구 + PDF 생성일', () async {
      final store = MemoryUpdateStore();
      final c = await loaded(store);
      await c.toggle(hit2(510), bundled.byeolpyo2, bundled.entries);
      final j = jsonDecode(store.value!) as Map;
      expect(j['version'], 1);
      final item = (j['items'] as List).single as Map;
      expect(item.keys.toSet(), {'priority', 'referenceNote', 'pdfCreated', 'entry'});
      expect(item['entry'], jsonDecode(jsonEncode(entryOf(Source.byeolpyo2, 510).toJson())));
      expect(item['referenceNote'], isTrue);
      expect(item['priority'], isFalse);
      expect(item['pdfCreated'], bundled.byeolpyo2.created);
    });

    test('사고대비물질 번호 1은 우선 적용이 스냅샷에 담긴다', () async {
      final c = await loaded(MemoryUpdateStore());
      await c.toggle(index.hitOf(entryOf(Source.byeolpyo3, 1)), bundled.byeolpyo3, bundled.entries);
      expect(c.items.single.priority, isTrue);
      expect(c.items.single.referenceNote, isFalse);
    });

    test('쓰기가 실패하면 예외, 기존 목록과 저장 파일은 그대로', () async {
      final store = MemoryUpdateStore();
      final c = await loaded(store);
      await save(c, [88]);
      final before = store.value;
      store.writeError = const FileSystemException('용량 부족');
      await expectLater(c.toggle(hit2(90), bundled.byeolpyo2, bundled.entries), throwsA(isA<FileSystemException>()));
      expect(kos(c), ['리누론']);
      expect(store.value, before);
      await expectLater(c.remove(c.items.single), throwsA(isA<FileSystemException>()));
      expect(kos(c), ['리누론']);
    });

    test('다시 켜도(새 컨트롤러로 읽어도) 목록이 유지되고, 삭제한 항목은 빠진 채다', () async {
      final store = MemoryUpdateStore();
      final c = await loaded(store);
      await save(c, [88, 90, 16]);
      await c.remove(c.items.firstWhere((i) => i.entry.no == 90));
      final again = await loaded(store);
      expect(kos(again), ['리누론', '2-에틸헥산산 납']);
    });

    test('깨진 파일: 빈 목록으로 대체하지 않고 loadFailed, 파일은 지우지 않고 쓰기도 거부한다', () async {
      final store = MemoryUpdateStore('{"version": 1, "items": [');
      final c = await loaded(store);
      expect(c.loadFailed, isTrue);
      await expectLater(c.toggle(hit2(5), bundled.byeolpyo2, bundled.entries), throwsA(isA<FavoritesUnreadable>()));
      expect(store.value, '{"version": 1, "items": [');

      final unknownVersion = await loaded(MemoryUpdateStore('{"version": 2, "items": []}'));
      expect(unknownVersion.loadFailed, isTrue, reason: '모르는 형식 버전을 추측해 읽지 않는다');
    });
  });

  group('정렬', () {
    test('연번 88·16·90 순으로 저장 → 리누론 → 말라티온 → 2-에틸헥산산 납', () async {
      final c = await loaded(MemoryUpdateStore());
      await save(c, [88, 16, 90]);
      expect(kos(c), ['리누론', '말라티온', '2-에틸헥산산 납']);
    });

    test('연번 16·325·407 → 2-에틸헥산산 납 → (S)-왈파린 → 2,5-자이레놀(에 → 왈 → 자)', () async {
      final c = await loaded(MemoryUpdateStore());
      await save(c, [407, 325, 16]);
      expect(kos(c), ['2-에틸헥산산 납', '(S)-왈파린', '2,5-자이레놀']);
    });

    test('한글로 시작하는 항목끼리 가나다: 88·89·90 → 리누론 → 말라티온 → 헥사클로로시클로헥산', () async {
      final c = await loaded(MemoryUpdateStore());
      await save(c, [88, 89, 90]);
      expect(kos(c), ['리누론', '말라티온', '헥사클로로시클로헥산']);
    });

    test('같은 정렬 키면 사고대비물질 먼저 → 연번, 한글이 없는 국문명은 맨 뒤', () {
      FavoriteItem item(Source src, int no, String ko) => FavoriteItem(
        entry: Entry(src: src, no: no, uid: null, name: ko, ko: ko, en: '', cas: const [], deleted: false, rows: const []),
        priority: false,
        referenceNote: false,
        pdfCreated: null,
      );
      final items = [
        item(Source.byeolpyo2, 9, 'ABC'),
        item(Source.byeolpyo2, 7, '1-납'),
        item(Source.byeolpyo2, 3, '납'),
        item(Source.byeolpyo3, 5, '납'),
        item(Source.byeolpyo2, 1, '가'),
      ]..sort(compareFavorites);
      expect([for (final i in items) '${i.entry.src.id}/${i.entry.no}'], ['별표2/1', '별표3/5', '별표2/3', '별표2/7', '별표2/9']);
    });

    // ★ 손으로 만든 규칙(접두 건너뛰기)의 전수 검증 — 번들 1,657건 전부.
    test('전수: 국문명 1,657건 모두 한글이 있고, 건너뛰는 앞머리는 숫자·기호·로마자뿐이다(551건: 숫자 379·영문 99·기호 73)', () {
      expect(bundled.entries, hasLength(1657));
      final noHangul = [for (final e in bundled.entries) if (koreanSortKey(e.ko) == null) e.ko];
      expect(noHangul, isEmpty, reason: 'REQUIREMENTS: 한글이 하나도 없는 국문명은 현재 0건');

      // 앞머리에 들어가도 되는 글자: ASCII 인쇄 문자(숫자·로마자·기호·공백), 라틴-1 기호, 그리스 문자, 일반 구두점·기호, 전각 기호.
      // 한글 자모·한자 등 **뜻이 있는 글자가 앞머리로 잘려 나가면** 여기서 걸린다.
      final allowed = RegExp(r'^[\x20-\x7E -Ͽ -⯿＀-￯]*$');
      // 국문명은 두 표에 겹치기도 해서(같은 이름 2건) Map이 아니라 목록으로 센다.
      final prefixes = <(String, String)>[];
      final byFirst = {'숫자': 0, '영문': 0, '기호': 0};
      for (final e in bundled.entries) {
        final key = koreanSortKey(e.ko)!;
        expect(key.codeUnitAt(0), inInclusiveRange(0xAC00, 0xD7A3), reason: '${e.ko}: 키는 한글 음절로 시작');
        expect(e.ko.endsWith(key), isTrue, reason: '${e.ko}: 키는 국문명의 뒷부분 그대로');
        final prefix = e.ko.substring(0, e.ko.length - key.length);
        if (prefix.isEmpty) continue;
        prefixes.add((e.ko, prefix));
        final first = prefix[0];
        byFirst.update(
          RegExp('[0-9]').hasMatch(first) ? '숫자' : (RegExp('[A-Za-z]').hasMatch(first) ? '영문' : '기호'),
          (n) => n + 1,
        );
      }
      final bad = [
        for (final (ko, prefix) in prefixes)
          if (!allowed.hasMatch(prefix)) '$ko ← "$prefix"',
      ];
      expect(bad, isEmpty, reason: '앞머리에 숫자·기호·로마자가 아닌 글자가 있다');
      expect(prefixes, hasLength(551));
      expect(byFirst, {'숫자': 379, '영문': 99, '기호': 73});
    });
  });

  group('[update]', () {
    test('① 연번 510의 상위 규정수량만 바꾼 데이터셋 → 새 값으로 바뀌고 1건 갱신·0건 못 찾음', () async {
      final c = await loaded(MemoryUpdateStore());
      await save(c, [510]);
      final newDs = withEntries(bundled, (list) {
        final i = list.indexWhere((e) => e.src == Source.byeolpyo2 && e.no == 510);
        list[i] = copyEntry(list[i], rows: [
          for (final r in list[i].rows) QuantityRow(kind: r.kind, content: r.content, min: r.min, low: r.low, high: '999'),
        ]);
        return list;
      });
      final s = await c.updateFrom(newDs);
      expect((s.updated, s.notFound), (1, 0));
      expect([for (final r in c.items.single.entry.rows) r.high], ['999', '999']);
      expect(c.items.single.referenceNote, isTrue, reason: '우선 적용·참고 문구도 새 데이터셋에서 다시 계산');
      expect(c.isNotFound(c.items.single), isFalse);
    });

    test('② 새 데이터셋에 없으면 덮지 않는다 — 옛 내용 그대로, 못 찾음 표시, 요약에 세어진다', () async {
      final c = await loaded(MemoryUpdateStore());
      await save(c, [88, 90]);
      final oldLinuron = c.items.first;
      final newDs = withEntries(bundled, (list) => list..removeWhere((e) => e.src == Source.byeolpyo2 && e.no == 88));
      final s = await c.updateFrom(newDs);
      expect((s.updated, s.notFound), (1, 1));
      expect(identical(c.items.first, oldLinuron), isTrue);
      expect(c.isNotFound(c.items.first), isTrue);
      expect(c.isNotFound(c.items.last), isFalse);
    });

    test('③ 이름이 같은 후보가 둘 이상이고 uid·cas로도 안 좁혀지면 못 찾음(아무거나 고르지 않는다)', () async {
      final c = await loaded(MemoryUpdateStore());
      await save(c, [88]);
      final linuron = entryOf(Source.byeolpyo2, 88);
      final twin = withEntries(bundled, (list) => list..add(copyEntry(linuron, no: 9999)));
      expect((await c.updateFrom(twin)).notFound, 1);
      expect(c.items.single.entry.no, 88);

      // uid가 다른 쌍둥이는 uid로 좁혀진다
      final other = withEntries(bundled, (list) => list..add(copyEntry(linuron, no: 9999, uid: '00-0-0')));
      expect((await c.updateFrom(other)).updated, 1);
      expect(c.items.single.entry.no, 88);
    });

    test('③ 이름·uid가 같고 CAS만 다른 후보는 CAS로 좁혀진다(실제 반례: 97-1-9 납 계열)', () {
      final saved = FavoriteItem.fromHit(hit2(88), bundled.byeolpyo2);
      final linuron = entryOf(Source.byeolpyo2, 88);
      final otherCas = Entry(
        src: linuron.src, no: 9999, uid: linuron.uid, name: linuron.name, ko: linuron.ko, en: linuron.en,
        cas: const ['1-11-1'], deleted: false, rows: linuron.rows,
      );
      expect(findSameSubstance(saved, [...bundled.entries, otherCas])?.no, 88);
    });

    test('④ 연번이 밀려도 이름으로 찾아 갱신되고, 갱신 뒤 연번은 새 연번이다', () async {
      final c = await loaded(MemoryUpdateStore());
      await save(c, [510]);
      final shifted = withEntries(bundled, (list) {
        final i = list.indexWhere((e) => e.src == Source.byeolpyo2 && e.no == 510);
        list[i] = copyEntry(list[i], no: 512);
        return list;
      });
      expect((await c.updateFrom(shifted)).updated, 1);
      expect(c.items.single.entry.no, 512);
    });

    test('이름 대조는 SearchIndex.normalize — 띄어쓰기·전각 공백·대소문자 차이는 같은 물질', () {
      final saved = FavoriteItem.fromHit(hit2(325), bundled.byeolpyo2); // (S)-왈파린
      final e = entryOf(Source.byeolpyo2, 325);
      final spaced = Entry(
        src: e.src, no: 1, uid: e.uid, name: e.name, ko: '(s)- 왈　파린', en: e.en, cas: e.cas, deleted: false, rows: e.rows,
      );
      expect(findSameSubstance(saved, [spaced])?.no, 1);
    });
  });

  group('갱신 알림 줄(기준일 비교)', () {
    test('저장본의 PDF 기준일과 현재 데이터셋의 기준일이 같으면 false, 다르면 true', () async {
      final c = await loaded(MemoryUpdateStore());
      await save(c, [5]);
      expect(c.isStale(bundled), isFalse);
      expect(c.isStale(tinyDataset()), isTrue, reason: 'tinyDataset 별표2 PDF 2027-01-01');
      // 사고대비물질 쪽 날짜만 달라지면 별표2 항목만 저장한 목록에는 해당 없음
      final only3 = Dataset(
        byeolpyo2: bundled.byeolpyo2,
        byeolpyo3: const PdfInfo(file: 'x', created: '2030-01-01', pages: 1),
        extractedAt: bundled.extractedAt,
        entries: bundled.entries,
      );
      expect(c.isStale(only3), isFalse);
    });

    test('update 후: 찾은 항목은 새 기준일로 바뀌고, 못 찾은 항목은 알림 판정에서 빠진다', () async {
      final c = await loaded(MemoryUpdateStore());
      await save(c, [5]);
      final t = tinyDataset();
      expect(c.isStale(t), isTrue);
      await c.updateFrom(t); // 구아자틴이 없다 → 못 찾음
      expect(c.isStale(t), isFalse);
    });
  });

  test('저장 파일은 F-002 저장본과 다른 파일 — 저장본을 지워도 저장 목록은 남는다', () async {
    final dir = Directory.systemTemp.createTempSync('findchem_fav_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final update = FileUpdateStore(directory: dir);
    final favorites = FileUpdateStore(directory: dir, name: FileUpdateStore.favoritesFileName);
    expect(FileUpdateStore.favoritesFileName, isNot(FileUpdateStore.fileName));

    await update.write('{"u":1}');
    final c = FavoritesController(store: favorites);
    await c.load();
    await c.toggle(hit2(5), bundled.byeolpyo2, bundled.entries);
    await update.delete(); // '처음 데이터로 되돌리기'
    expect(await update.read(), isNull);
    expect(decodeFavorites((await favorites.read())!).single.entry.ko, '구아자틴');
    expect(dir.listSync().map((e) => e.uri.pathSegments.last), [FileUpdateStore.favoritesFileName]);
  });
}
