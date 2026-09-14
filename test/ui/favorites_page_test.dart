/// F-005 화면 수용 기준 — 검색 카드의 저장 아이콘, 저장 목록 화면(접힘·펼침·공유·삭제·[update]·알림 줄),
/// 설정의 적용 직후 질문·되돌리기와의 분리, 웹(표 화면)에서의 제외. 실제 번들 데이터, 저장 자리만 메모리.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/data/dataset_loader.dart';
import 'package:findchem/data/favorites.dart';
import 'package:findchem/data/source_update.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/search/search.dart';
import 'package:findchem/share/share_action.dart';
import 'package:findchem/ui/app.dart';
import 'package:findchem/ui/app_header.dart';
import 'package:findchem/ui/entry_card.dart';
import 'package:findchem/ui/favorites_page.dart';
import 'package:findchem/ui/search_page.dart';
import 'package:findchem/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fakes.dart';
import '../parser/fixtures.dart';

void main() {
  late Dataset bundled;
  late SearchIndex index;

  setUpAll(() {
    bundled = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
    index = SearchIndex(bundled);
  });

  PdfInfo pdfOf(Source src) => src == Source.byeolpyo3 ? bundled.byeolpyo3 : bundled.byeolpyo2;
  Entry entryOf(Source src, int no) => bundled.entries.singleWhere((e) => e.src == src && e.no == no);

  void setView(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// 저장 자리 [store]를 읽은 컨트롤러에 별표2 연번 [nos]를 저장해 둔다.
  Future<FavoritesController> favoritesWith(MemoryUpdateStore store, [List<int> nos = const []]) async {
    final c = FavoritesController(store: store);
    await c.load();
    for (final no in nos) {
      await c.toggle(index.hitOf(entryOf(Source.byeolpyo2, no)), pdfOf(Source.byeolpyo2), bundled.entries);
    }
    return c;
  }

  Future<DataController> bundledData() async {
    final d = DataController(store: MemoryUpdateStore(), loadBundled: () async => bundled);
    await d.load();
    return d;
  }

  Future<void> type(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField), q);
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
  }

  Finder cardOf(String ko) => find.ancestor(of: find.text(ko), matching: find.byType(EntryCard));

  const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
  List<String> mockShare(WidgetTester tester) {
    final shared = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      shared.add((call.arguments as Map)['text'] as String);
      return 'dev.fluttercommunity.plus/share/success';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));
    return shared;
  }

  group('검색 카드의 저장 아이콘', () {
    Future<void> pumpSearch(WidgetTester tester, FavoritesController fav, {bool useTable = false}) async {
      setView(tester, const Size(400, 800));
      await tester.pumpWidget(const SizedBox()); // 한 테스트에서 다시 띄울 때 앞 화면 상태(열린 메뉴 등)를 남기지 않는다
      await tester.pumpWidget(MaterialApp(home: SearchPage(dataset: bundled, favorites: fav, useTable: useTable)));
    }

    testWidgets("'구아자틴' 2건 → 카드마다 저장 아이콘 1개, 공유 아이콘 왼쪽", (tester) async {
      await pumpSearch(tester, await favoritesWith(MemoryUpdateStore()));
      await type(tester, '구아자틴');
      expect(find.byIcon(Icons.star_border), findsNWidgets(2));
      for (final ko in ['구아자틴', '구아자틴 염류']) {
        final star = find.descendant(of: cardOf(ko), matching: find.byIcon(Icons.star_border));
        final share = find.descendant(of: cardOf(ko), matching: find.byTooltip(ShareText.tooltip));
        expect(star, findsOneWidget);
        expect(tester.getCenter(star).dx, lessThan(tester.getCenter(share).dx), reason: ko);
      }
    });

    testWidgets('연번 5 저장 → "저장했습니다", 채워진 별, 목록에 구아자틴 1건. 다시 누르면 "목록에서 뺐습니다"', (tester) async {
      final fav = await favoritesWith(MemoryUpdateStore());
      await pumpSearch(tester, fav);
      await type(tester, '구아자틴');

      await tester.tap(find.descendant(of: cardOf('구아자틴'), matching: find.byIcon(Icons.star_border)));
      await settle(tester);
      expect(find.text(FavoritesText.saved), findsOneWidget);
      expect([for (final i in fav.items) i.entry.ko], ['구아자틴']);
      expect(find.descendant(of: cardOf('구아자틴'), matching: find.byIcon(Icons.star)), findsOneWidget);
      expect(find.descendant(of: cardOf('구아자틴 염류'), matching: find.byIcon(Icons.star_border)), findsOneWidget);

      await tester.tap(find.descendant(of: cardOf('구아자틴'), matching: find.byIcon(Icons.star)));
      await settle(tester);
      expect(find.text(FavoritesText.removed), findsOneWidget);
      expect(find.text(FavoritesText.saved), findsNothing);
      expect(fav.items, isEmpty);
      expect(find.byIcon(Icons.star_border), findsNWidgets(2));
    });

    testWidgets('쓰기가 실패하면 "저장하지 못했습니다", 기존 목록 그대로', (tester) async {
      final store = MemoryUpdateStore();
      final fav = await favoritesWith(store, [88]);
      final before = store.value;
      store.writeError = const FileSystemException('용량 부족');
      await pumpSearch(tester, fav);
      await type(tester, '구아자틴');
      await tester.tap(find.descendant(of: cardOf('구아자틴'), matching: find.byIcon(Icons.star_border)));
      await settle(tester);
      expect(find.text(FavoritesText.saveFailed), findsOneWidget);
      expect(find.textContaining('용량 부족'), findsNothing, reason: '원인은 로그에만');
      expect([for (final i in fav.items) i.entry.ko], ['리누론']);
      expect(store.value, before);
      expect(find.byIcon(Icons.star), findsNothing);
    });

    testWidgets("웹(표 화면): 저장 아이콘이 없고 '⋮' 메뉴에 '자주보는 Chem 목록'도 없다. 앱은 첫 항목으로 있다", (tester) async {
      final fav = await favoritesWith(MemoryUpdateStore());
      await pumpSearch(tester, fav, useTable: true);
      await type(tester, '구아자틴');
      expect(find.byIcon(Icons.star_border), findsNothing);
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text(HeaderText.favorites), findsNothing);
      expect(find.text(HeaderText.settings), findsOneWidget);

      await pumpSearch(tester, fav);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      expect(find.text(HeaderText.favorites), findsOneWidget);
      expect(
        tester.getTopLeft(find.text(HeaderText.favorites)).dy,
        lessThan(tester.getTopLeft(find.text(HeaderText.settings)).dy),
      );
    });
  });

  group('저장 목록 화면', () {
    Future<void> pumpList(WidgetTester tester, FavoritesController fav, DataController data) async {
      setView(tester, const Size(500, 1400));
      await tester.pumpWidget(const SizedBox()); // 한 테스트에서 다시 띄울 때 앞 화면의 펼침 상태를 남기지 않는다
      await tester.pumpWidget(MaterialApp(home: FavoritesPage(favorites: fav, data: data)));
    }

    testWidgets('접힌 행은 국문명만, 펼치면 F-001 카드와 같은 내용(EntryCard 재사용)', (tester) async {
      final fav = await favoritesWith(MemoryUpdateStore(), [510, 5]);
      await pumpList(tester, fav, await bundledData());
      expect(find.text('포르말린; 포름알데히드'), findsOneWidget);
      expect(find.text('구아자틴'), findsOneWidget);
      expect(find.byType(EntryCard), findsNothing);
      expect(find.text('Formalin; Formaldehyde'), findsNothing);

      await tester.tap(find.text('포르말린; 포름알데히드'));
      await tester.pumpAndSettle();
      final card = find.byType(EntryCard);
      expect(card, findsOneWidget);
      expect(find.text('구아자틴'), findsOneWidget, reason: '다른 행은 접힌 채');
      for (final t in [
        'Formalin; Formaldehyde',
        '인체·생태 유해성',
        '연번 510 · 고유번호 97-1-345',
        'CAS 50-00-0',
        CardText.referenceNote,
        '구분',
        '400',
      ]) {
        expect(find.descendant(of: card, matching: find.text(t)), findsWidgets, reason: t);
      }
      final shown = tester.widget<EntryCard>(card).hit;
      final searched = index.hitOf(entryOf(Source.byeolpyo2, 510));
      expect(jsonEncode(shown.entry.toJson()), jsonEncode(searched.entry.toJson()));
      expect((shown.priority, shown.referenceNote), (searched.priority, searched.referenceNote));

      // CAS가 여러 개인 항목은 전부 나온다
      await tester.tap(find.text('구아자틴'));
      await tester.pumpAndSettle();
      expect(find.text('CAS 13516-27-3, 108173-90-6'), findsOneWidget);
    });

    testWidgets('공유 텍스트 마지막 줄의 기준일은 저장본에 담긴 값이다(현재 원천자료의 날짜가 아니다)', (tester) async {
      final shared = mockShare(tester);
      final store = MemoryUpdateStore(encodeFavorites([
        FavoriteItem(
          entry: entryOf(Source.byeolpyo2, 510),
          priority: false,
          referenceNote: true,
          pdfCreated: '2030-01-01T00:00:00+09:00',
        ),
      ]));
      await pumpList(tester, await favoritesWith(store), await bundledData());
      await tester.tap(find.text('포르말린; 포름알데히드'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(ShareText.tooltip));
      await settle(tester);
      expect(shared.single.split('\n').last, 'FindChem · 「유해화학물질의 규정수량에 관한 규정」 (PDF 2030-01-01 기준)');
    });

    testWidgets('펼친 안의 공유 → F-003 수용 기준 예시와 한 글자도 다르지 않다(연번 510)', (tester) async {
      final shared = mockShare(tester);
      final fav = await favoritesWith(MemoryUpdateStore(), [510]);
      await pumpList(tester, fav, await bundledData());
      await tester.tap(find.text('포르말린; 포름알데히드'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(ShareText.tooltip));
      await settle(tester);
      expect(shared, [
        '[인체·생태 유해성] 포르말린; 포름알데히드\n'
            'Formalin; Formaldehyde\n'
            '연번 510 · 고유번호 97-1-345\n'
            'CAS 50-00-0\n'
            '\n'
            '규정수량(톤) 최하위 / 하위 / 상위\n'
            '· 급성, 함량기준 1%: 0.05 / 2 / 400\n'
            '· 만성, 함량기준 0.1%: 0.125 / 5 / 400\n'
            '\n'
            '※ 사고대비물질은 사고대비물질 규정수량을 적용합니다(별표2 일반기준 가)\n'
            '\n'
            'FindChem · 「유해화학물질의 규정수량에 관한 규정」 (PDF 2026-07-20 기준)',
      ]);
    });

    testWidgets('펼친 안의 삭제 → 확인 창 없이 빠지고 "삭제했습니다", 다른 항목은 남고 다시 켜도 빠진 채', (tester) async {
      final store = MemoryUpdateStore();
      final fav = await favoritesWith(store, [88, 90]);
      await pumpList(tester, fav, await bundledData());
      await tester.tap(find.text('리누론'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(FavoritesText.deleteTooltip));
      await settle(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text(FavoritesText.deleted), findsOneWidget);
      expect(find.text('리누론'), findsNothing);
      expect(find.text('말라티온'), findsOneWidget);
      expect(find.text(FavoritesText.count(1)), findsOneWidget);

      final again = await favoritesWith(store);
      expect([for (final i in again.items) i.entry.ko], ['말라티온']);
    });

    testWidgets('머리에 전체 건수. 0건이면 "저장한 물질이 없습니다"(update 버튼은 꺼짐)', (tester) async {
      await pumpList(tester, await favoritesWith(MemoryUpdateStore()), await bundledData());
      expect(find.text(FavoritesText.count(0)), findsOneWidget);
      expect(find.text(FavoritesText.empty), findsOneWidget);
      final button = find.ancestor(of: find.text(FavoritesText.update), matching: find.bySubtype<OutlinedButton>());
      expect(tester.widget<OutlinedButton>(button).onPressed, isNull);

      await pumpList(tester, await favoritesWith(MemoryUpdateStore(), [88, 90, 16]), await bundledData());
      expect(find.text(FavoritesText.count(3)), findsOneWidget);
      expect(find.text(FavoritesText.empty), findsNothing);
      // 화면에 그리는 순서도 정렬 순서
      final ys = [for (final ko in ['리누론', '말라티온', '2-에틸헥산산 납']) tester.getTopLeft(find.text(ko)).dy];
      expect(ys, orderedEquals([...ys]..sort()));

      // 상한 없음: 120건을 넣어도 전체 건수 그대로, '더 있음' 없이 마지막 행까지 그려진다
      final many = [
        for (final e in bundled.entries.take(120)) FavoriteItem.fromHit(index.hitOf(e), pdfOf(e.src)),
      ];
      final manyFav = await favoritesWith(MemoryUpdateStore(encodeFavorites(many)));
      await pumpList(tester, manyFav, await bundledData());
      expect(manyFav.items, hasLength(120));
      expect(find.text(FavoritesText.count(120)), findsOneWidget);
      expect(find.textContaining('더 있음'), findsNothing);
      final lastKo = manyFav.items.last.entry.ko;
      expect(manyFav.items.where((i) => i.entry.ko == lastKo), hasLength(1), reason: '스크롤 대상이 하나여야 한다');
      await tester.scrollUntilVisible(find.text(lastKo), 600);
      expect(find.text(lastKo), findsOneWidget);
    });

    testWidgets('저장 파일이 깨졌으면 빈 목록 안내 대신 사유와 복구 버튼. 정상이면 버튼이 없다', (tester) async {
      final store = MemoryUpdateStore('{"version": 1, "items": [');
      await pumpList(tester, await favoritesWith(store), await bundledData());
      expect(find.text(FavoritesText.loadFailed), findsOneWidget);
      expect(find.text(FavoritesText.discard), findsOneWidget);
      expect(find.text(FavoritesText.empty), findsNothing);
      expect(store.value, '{"version": 1, "items": [');

      await pumpList(tester, await favoritesWith(MemoryUpdateStore(), [88]), await bundledData());
      expect(find.text(FavoritesText.discard), findsNothing);
      await pumpList(tester, await favoritesWith(MemoryUpdateStore()), await bundledData());
      expect(find.text(FavoritesText.discard), findsNothing);
    });

    Future<void> tapDiscard(WidgetTester tester, {required bool confirm}) async {
      await tester.tap(find.text(FavoritesText.discard));
      await tester.pumpAndSettle();
      expect(find.text(FavoritesText.discardConfirm), findsOneWidget);
      await tester.tap(
        confirm
            ? find.descendant(of: find.byType(AlertDialog), matching: find.text(FavoritesText.discard)).last
            : find.text(FavoritesText.cancel),
      );
      await tester.pumpAndSettle();
    }

    testWidgets("복구 버튼: 취소하면 그대로, 확인하면 파일을 지우고 '지웠습니다'·빈 목록 안내, 이후 저장이 된다", (tester) async {
      const broken = '{"version": 1, "items": [';
      final store = MemoryUpdateStore(broken);
      final fav = await favoritesWith(store);
      await pumpList(tester, fav, await bundledData());

      await tapDiscard(tester, confirm: false);
      expect(store.value, broken);
      expect(find.text(FavoritesText.loadFailed), findsOneWidget);

      await tapDiscard(tester, confirm: true);
      expect(store.value, isNull);
      expect(find.text(FavoritesText.discarded), findsOneWidget);
      expect(find.text(FavoritesText.empty), findsOneWidget);
      expect(find.text(FavoritesText.loadFailed), findsNothing);
      expect(find.text(FavoritesText.discard), findsNothing);

      expect(await fav.toggle(index.hitOf(entryOf(Source.byeolpyo2, 5)), bundled.byeolpyo2, bundled.entries), isTrue);
      await tester.pump();
      expect(find.text('구아자틴'), findsOneWidget);
      expect(store.value, isNotNull);
    });

    testWidgets('복구 버튼: 지우기가 실패하면 "지우지 못했습니다", 파일·사유 그대로', (tester) async {
      const broken = '{"version": 1, "items": [';
      final store = MemoryUpdateStore(broken)..deleteError = const FileSystemException('권한 없음');
      await pumpList(tester, await favoritesWith(store), await bundledData());
      await tapDiscard(tester, confirm: true);
      expect(find.text(FavoritesText.discardFailed), findsOneWidget);
      expect(find.textContaining('권한 없음'), findsNothing, reason: '원인은 로그에만');
      expect(store.value, broken);
      expect(find.text(FavoritesText.loadFailed), findsOneWidget);
    });

    testWidgets('목록은 데이터셋 없이 그려진다: 원천자료를 바꿔도·못 읽어도 저장할 때 본 내용 그대로', (tester) async {
      final fav = await favoritesWith(MemoryUpdateStore(), [510]);
      final data = await bundledData();
      await data.apply(tinyDataset());
      await pumpList(tester, fav, data);
      await tester.tap(find.text('포르말린; 포름알데히드'));
      await tester.pumpAndSettle();
      for (final t in ['CAS 50-00-0', '인체·생태 유해성', CardText.referenceNote, '0.05', '0.125']) {
        expect(find.text(t), findsWidgets, reason: t);
      }

      // 원천자료를 아직 못 읽은(없는) 상태
      await pumpList(tester, fav, DataController(store: MemoryUpdateStore(), loadBundled: () async => bundled));
      await tester.tap(find.text('포르말린; 포름알데히드'));
      await tester.pumpAndSettle();
      expect(find.text('CAS 50-00-0'), findsOneWidget);
      expect(find.text(CardText.referenceNote), findsOneWidget);
    });

    testWidgets('CAS 없는 연번 4·삭제 항목 연번 91도 저장되고, 펼치면 카드와 같은 표시', (tester) async {
      final fav = await favoritesWith(MemoryUpdateStore(), [4, 91]);
      await pumpList(tester, fav, await bundledData());
      await tester.tap(find.text('구아자틴 염류'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('말레산히드라지드'));
      await tester.pumpAndSettle();
      expect(find.descendant(of: cardOf('구아자틴 염류'), matching: find.text(CardText.noCas)), findsOneWidget);
      expect(find.descendant(of: cardOf('말레산히드라지드'), matching: find.text(CardText.deleted)), findsOneWidget);
    });

    testWidgets('같은 국문명이 2건 저장돼 있을 때만 접힌 행에 표 이름을 붙인다', (tester) async {
      final fav = await favoritesWith(MemoryUpdateStore(), [88]);
      final hcl3 = entryOf(Source.byeolpyo3, 42);
      final hcl2 = Entry(
        src: Source.byeolpyo2, no: 9999, uid: '00-0-0', name: hcl3.name, ko: hcl3.ko, en: hcl3.en,
        cas: hcl3.cas, deleted: false, rows: hcl3.rows,
      );
      await fav.toggle(index.hitOf(hcl3), bundled.byeolpyo3, bundled.entries);
      await fav.toggle(Hit(hcl2, priority: false, referenceNote: false), bundled.byeolpyo2, bundled.entries);
      await pumpList(tester, fav, await bundledData());
      expect(find.text('리누론'), findsOneWidget);
      expect(find.text('염화수소 · 사고대비물질'), findsOneWidget);
      expect(find.text('염화수소 · 인체·생태 유해성'), findsOneWidget);
      expect(find.text('염화수소'), findsNothing);
    });

    testWidgets('[update] ①: 상위 규정수량만 바꾼 원천자료 → 새 값, "1건 갱신, 0건은 찾지 못했습니다"', (tester) async {
      final fav = await favoritesWith(MemoryUpdateStore(), [510]);
      final data = await bundledData();
      await data.apply(Dataset(
        byeolpyo2: bundled.byeolpyo2,
        byeolpyo3: bundled.byeolpyo3,
        extractedAt: bundled.extractedAt,
        entries: [
          for (final e in bundled.entries)
            if (e.src == Source.byeolpyo2 && e.no == 510)
              Entry(
                src: e.src, no: e.no, uid: e.uid, name: e.name, ko: e.ko, en: e.en, cas: e.cas, deleted: e.deleted,
                rows: [for (final r in e.rows) QuantityRow(kind: r.kind, content: r.content, min: r.min, low: r.low, high: '999')],
              )
            else
              e,
        ],
      ));
      await pumpList(tester, fav, data);
      expect(find.text(FavoritesText.stale), findsNothing, reason: '기준일이 같다');
      await tester.tap(find.text(FavoritesText.update));
      await settle(tester);
      expect(find.text('1건 갱신, 0건은 찾지 못했습니다'), findsOneWidget);
      await tester.tap(find.text('포르말린; 포름알데히드'));
      await tester.pumpAndSettle();
      expect(find.text('999'), findsNWidgets(2));
      expect(find.text('400'), findsNothing);
    });

    testWidgets('[update] ④: 연번이 밀린 원천자료로 갱신하면 펼친 카드에 새 연번이 보인다', (tester) async {
      final fav = await favoritesWith(MemoryUpdateStore(), [510]);
      final data = await bundledData();
      await data.apply(Dataset(
        byeolpyo2: bundled.byeolpyo2,
        byeolpyo3: bundled.byeolpyo3,
        extractedAt: bundled.extractedAt,
        entries: [
          for (final e in bundled.entries)
            if (e.src == Source.byeolpyo2 && e.no == 510)
              Entry(
                src: e.src, no: 515, uid: e.uid, name: e.name, ko: e.ko, en: e.en, cas: e.cas, deleted: e.deleted,
                rows: e.rows,
              )
            else
              e,
        ],
      ));
      await pumpList(tester, fav, data);
      await tester.tap(find.text(FavoritesText.update));
      await settle(tester);
      expect(find.text('1건 갱신, 0건은 찾지 못했습니다'), findsOneWidget);
      await tester.tap(find.text('포르말린; 포름알데히드'));
      await tester.pumpAndSettle();
      expect(find.text('연번 515 · 고유번호 97-1-345'), findsOneWidget);
      expect(find.text('연번 510 · 고유번호 97-1-345'), findsNothing);
    });

    testWidgets('갱신 알림 줄: 기준일이 다르면 보이고, [update] ②로 못 찾은 항목은 덮지 않고 표시가 붙는다', (tester) async {
      final fav = await favoritesWith(MemoryUpdateStore(), [510]);
      final data = await bundledData();
      await pumpList(tester, fav, data);
      expect(find.text(FavoritesText.stale), findsNothing);

      await data.apply(tinyDataset()); // 별표2 PDF 2027-01-01, 510 없음
      await tester.pump();
      expect(find.text(FavoritesText.stale), findsOneWidget);
      await tester.tap(find.text(FavoritesText.update));
      await settle(tester);
      expect(find.text('0건 갱신, 1건은 찾지 못했습니다'), findsOneWidget);
      expect(find.text(FavoritesText.notFound), findsOneWidget);
      expect(find.text(FavoritesText.stale), findsNothing);
      await tester.tap(find.text('포르말린; 포름알데히드'));
      await tester.pumpAndSettle();
      expect(find.text('CAS 50-00-0'), findsOneWidget, reason: '옛 내용 그대로');
    });
  });

  group('앱: 설정과의 관계', () {
    late PickedPdf pdf2;
    late PickedPdf pdf3;

    setUpAll(() {
      PickedPdf picked(Source src) {
        final f = assetPdf(src);
        return PickedPdf(name: f.uri.pathSegments.last, bytes: f.readAsBytesSync());
      }

      pdf2 = picked(Source.byeolpyo2);
      pdf3 = picked(Source.byeolpyo3);
    });

    /// 옛 기준일(2020-01-01)로 저장해 둔 연번 510 한 건 — 적용한 원천자료와 기준일이 달라 알림 줄이 뜬다.
    String oldSnapshot() => encodeFavorites([
      FavoriteItem(
        entry: entryOf(Source.byeolpyo2, 510),
        priority: false,
        referenceNote: true,
        pdfCreated: '2020-01-01T00:00:00+09:00',
      ),
    ]);

    Future<(MemoryUpdateStore, FavoritesController)> pumpApp(
      WidgetTester tester, {
      String? favoritesJson,
      String? updateJson,
      List<PickedPdf> picks = const [],
    }) async {
      setView(tester, const Size(500, 1400));
      final favStore = MemoryUpdateStore(favoritesJson);
      final fav = FavoritesController(store: favStore);
      await fav.load();
      final queue = [...picks];
      await tester.pumpWidget(FindChemApp(
        controller: DataController(store: MemoryUpdateStore(updateJson), loadBundled: () async => bundled),
        favorites: fav,
        pickPdf: () async => queue.removeAt(0),
      ));
      for (var i = 0; i < 5 && find.byType(SearchPage).evaluate().isEmpty; i++) {
        await tester.pump();
      }
      return (favStore, fav);
    }

    Future<void> openMenu(WidgetTester tester, String item) async {
      await tester.tap(find.byIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item));
      await tester.pumpAndSettle();
      if (item == HeaderText.settings) {
        // F-007: F-002 내용은 '사고대비물질·인체·생태 유해성 정보' 카드 안에 있다(처음엔 접혀 있음)
        await tester.tap(find.text(SettingsText.sourceCard));
        await tester.pumpAndSettle();
      }
    }

    Future<void> applyPdfs(WidgetTester tester) async {
      for (final src in Source.values) {
        await tester.tap(find.descendant(of: find.byKey(ValueKey('pick-${src.id}')), matching: find.text(SettingsText.pick)));
        await tester.pump();
      }
      await tester.tap(find.text(SettingsText.apply));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pumpAndSettle();
    }

    testWidgets("원천자료 적용 직후 '저장 목록도 갱신할까요?' → 예: update와 같은 요약, 기준일이 새것으로", (tester) async {
      final (_, fav) = await pumpApp(tester, favoritesJson: oldSnapshot(), picks: [pdf2, pdf3]);
      await openMenu(tester, HeaderText.settings);
      await applyPdfs(tester);
      expect(find.text(FavoritesText.askUpdate), findsOneWidget);
      await tester.tap(find.text(FavoritesText.yes));
      await tester.pumpAndSettle();
      expect(find.text('1건 갱신, 0건은 찾지 못했습니다'), findsOneWidget);
      expect(fav.items.single.pdfCreated, bundled.byeolpyo2.created);
    });

    testWidgets("적용 직후 질문에 '아니오' → 아무것도 바뀌지 않고 목록에 알림 줄이 남는다", (tester) async {
      final (favStore, _) = await pumpApp(tester, favoritesJson: oldSnapshot(), picks: [pdf2, pdf3]);
      final before = favStore.value;
      await openMenu(tester, HeaderText.settings);
      await applyPdfs(tester);
      await tester.tap(find.text(FavoritesText.no));
      await tester.pumpAndSettle();
      expect(favStore.value, before);
      expect(find.textContaining('건 갱신'), findsNothing);

      await tester.pageBack();
      await tester.pumpAndSettle();
      await openMenu(tester, HeaderText.favorites);
      expect(find.byType(FavoritesPage), findsOneWidget);
      expect(find.text(FavoritesText.stale), findsOneWidget);
    });

    testWidgets('저장 목록이 0건이면 적용 직후 묻지 않는다', (tester) async {
      await pumpApp(tester, picks: [pdf2, pdf3]);
      await openMenu(tester, HeaderText.settings);
      await applyPdfs(tester);
      expect(find.textContaining('적용했습니다'), findsOneWidget);
      expect(find.text(FavoritesText.askUpdate), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets("'처음 데이터로 되돌리기'는 저장 목록을 지우지 않는다. 되돌린 뒤 [update]는 번들 기준으로 맞춘다", (tester) async {
      final (favStore, fav) = await pumpApp(
        tester,
        favoritesJson: oldSnapshot(),
        updateJson: jsonEncode(tinyDataset().toJson()),
      );
      final before = favStore.value;
      await openMenu(tester, HeaderText.settings);
      await tester.tap(find.text(SettingsText.reset));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(SettingsText.reset)).last);
      await tester.pumpAndSettle();
      expect(find.text(SettingsText.resetDone), findsOneWidget);
      expect(favStore.value, before);
      expect(fav.items, hasLength(1));

      await tester.pageBack();
      await tester.pumpAndSettle();
      await openMenu(tester, HeaderText.favorites);
      await tester.tap(find.text(FavoritesText.update));
      await tester.pumpAndSettle();
      expect(find.text('1건 갱신, 0건은 찾지 못했습니다'), findsOneWidget);
      expect(fav.items.single.pdfCreated, bundled.byeolpyo2.created);
    });
  });
}
