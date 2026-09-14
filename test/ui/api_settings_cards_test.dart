/// F-007 설정 화면 카드 구성·카드 1(API 키)·카드 2(연동 데이터) 수용 기준. 저장 자리는 메모리, HTTP는 fixture.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/data/dataset_loader.dart';
import 'package:findchem/data/favorites.dart';
import 'package:findchem/lookup/api_settings.dart';
import 'package:findchem/ui/api_settings_cards.dart';
import 'package:findchem/ui/cas_lookup_panel.dart';
import 'package:findchem/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fakes.dart';
import '../lookup/fake_api.dart';

void main() {
  /// 설정 화면만 띄운다. [apiStore]가 null이면 조회가 꺼진 화면(앱).
  Future<(FakeApi, DataController)> pumpSettings(
    WidgetTester tester, {
    MemoryUpdateStore? apiStore,
    bool web = true,
    FakeApi? api,
    MemoryUpdateStore? updateStore,
  }) async {
    tester.view.physicalSize = const Size(600, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = api ?? FakeApi();
    final controller = DataController(store: updateStore ?? MemoryUpdateStore(), loadBundled: () async => tinyDataset());
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsPage(
          controller: controller,
          favorites: FavoritesController(store: MemoryUpdateStore()),
          web: web,
          lookup: apiStore == null
              ? null
              : CasLookup(settings: ApiSettingsController(store: apiStore), client: fake.client()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return (fake, controller);
  }

  Future<void> expand(WidgetTester tester, String title) async {
    await tester.ensureVisible(find.text(title));
    await tester.tap(find.text(title));
    await tester.pumpAndSettle();
  }

  Future<void> tapButton(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  const titles = [ApiSettingsText.keyCard, ApiSettingsText.linkCard, SettingsText.sourceCard, SettingsText.infoCard];

  testWidgets('카드 4개가 이 순서로 있고 모두 접혀 있다', (tester) async {
    await pumpSettings(tester, apiStore: MemoryUpdateStore());
    final ys = [for (final t in titles) tester.getTopLeft(find.text(t)).dy];
    for (var i = 1; i < ys.length; i++) {
      expect(ys[i - 1], lessThan(ys[i]), reason: '${titles[i - 1]} 다음이 ${titles[i]}');
    }
    expect(find.text(ApiSettingsText.keyHelp), findsNothing);
    expect(find.text(ApiSettingsText.linkHelp), findsNothing);
    expect(find.text(SettingsText.sourceSection), findsNothing);
    expect(find.text(SettingsText.webVersion), findsNothing);
  });

  testWidgets('조회가 꺼진 화면(앱)은 카드 1·2가 없고, 카드 4는 앱 버전. 웹은 웹 버전', (tester) async {
    await pumpSettings(tester, web: false);
    expect(find.text(ApiSettingsText.keyCard), findsNothing);
    expect(find.text(ApiSettingsText.linkCard), findsNothing);
    await expand(tester, SettingsText.infoCard);
    expect(find.text('앱 버전 1.1.0 (빌드 2)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox()); // 앞 화면의 펼침 상태가 남지 않게 트리를 비운다
    await pumpSettings(tester, apiStore: MemoryUpdateStore());
    await expand(tester, SettingsText.infoCard);
    expect(find.text('웹 버전 1.1.0 (빌드 2)'), findsOneWidget);
    expect(SettingsText.webVersion, '웹 버전 1.1.0 (빌드 2)');
  });

  testWidgets('카드 1: [저장] → 저장했습니다, 다시 읽으면 입력창에 같은 키. [삭제] → 입력창이 비고 삭제했습니다', (tester) async {
    final store = MemoryUpdateStore();
    await pumpSettings(tester, apiStore: store);
    await expand(tester, ApiSettingsText.keyCard);
    await tester.enterText(find.byKey(const ValueKey('api-key-field')), ' KEY123 ');
    await tapButton(tester, ApiSettingsText.save);
    expect(find.text(ApiSettingsText.saved), findsOneWidget);
    expect((jsonDecode(store.value!) as Map)['serviceKey'], 'KEY123');

    // 앱 재실행: 같은 저장 자리를 새 컨트롤러로 읽는다
    await tester.pumpWidget(const SizedBox());
    await pumpSettings(tester, apiStore: store);
    await expand(tester, ApiSettingsText.keyCard);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('api-key-field'))).controller!.text, 'KEY123');

    await tapButton(tester, ApiSettingsText.delete);
    expect(find.text(ApiSettingsText.deleted), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const ValueKey('api-key-field'))).controller!.text, isEmpty);
    expect(store.value, isNull);
  });

  testWidgets('카드 1: 빈 입력으로 [저장]·[키 인증] → 키를 입력하세요, 쓰기·호출 없음', (tester) async {
    final store = MemoryUpdateStore();
    final (api, _) = await pumpSettings(tester, apiStore: store);
    await expand(tester, ApiSettingsText.keyCard);
    await tapButton(tester, ApiSettingsText.save);
    expect(find.text(ApiSettingsText.enterKey), findsOneWidget);
    await tapButton(tester, ApiSettingsText.verify);
    expect(find.text(ApiSettingsText.enterKey), findsOneWidget);
    expect(store.value, isNull);
    expect(api.calls, isEmpty);
  });

  testWidgets('카드 1: 쓰기·지우기 실패 → 저장하지 못했습니다 / 삭제하지 못했습니다, 기존 저장은 그대로', (tester) async {
    final before = apiSettingsJson(key: 'OLD');
    final store = MemoryUpdateStore(before)
      ..writeError = const FileSystemException('용량 부족')
      ..deleteError = const FileSystemException('권한 없음');
    await pumpSettings(tester, apiStore: store);
    await expand(tester, ApiSettingsText.keyCard);
    await tester.enterText(find.byKey(const ValueKey('api-key-field')), 'NEW');
    await tapButton(tester, ApiSettingsText.save);
    expect(find.text(ApiSettingsText.saveFailed), findsOneWidget);
    await tapButton(tester, ApiSettingsText.delete);
    expect(find.text(ApiSettingsText.deleteFailed), findsOneWidget);
    expect(store.value, before);
  });

  testWidgets('카드 1: [키 인증] → 입력창의 키로 세 서비스를 50-00-0으로 부르고 서비스마다 한 줄. 저장하지 않는다', (tester) async {
    final api = FakeApi()..overrides[ChemService.ghs] = () async => utf8Response(portalError('30'), 403);
    final store = MemoryUpdateStore();
    await pumpSettings(tester, apiStore: store, api: api);
    await expand(tester, ApiSettingsText.keyCard);
    await tester.enterText(find.byKey(const ValueKey('api-key-field')), 'TYPED');
    await tapButton(tester, ApiSettingsText.verify);

    expect(find.text('화학물질 정보 — 확인됨'), findsOneWidget);
    expect(find.text('유독물 GHS 정보 — 이 서비스의 활용신청이 승인되지 않았습니다'), findsOneWidget);
    expect(find.text('안전관리정보(응급 증상) — 확인됨'), findsOneWidget);
    expect(api.calls, hasLength(3));
    for (final u in api.calls) {
      expect(u.queryParameters['serviceKey'], 'TYPED');
      expect(u.queryParameters['searchNm'] ?? u.queryParameters['casNo'], '50-00-0');
    }
    expect(store.value, isNull);
  });

  testWidgets('카드 2: 처음엔 3개 모두 체크, 바꾸면 바로 저장되고 다시 읽어도 유지', (tester) async {
    final store = MemoryUpdateStore();
    await pumpSettings(tester, apiStore: store);
    await expand(tester, ApiSettingsText.linkCard);
    for (final s in ChemService.values) {
      expect(tester.widget<CheckboxListTile>(find.byKey(ValueKey('service-${s.name}'))).value, isTrue, reason: s.name);
    }
    await tester.tap(find.byKey(const ValueKey('service-ghs')));
    await tester.pumpAndSettle();
    expect(tester.widget<CheckboxListTile>(find.byKey(const ValueKey('service-ghs'))).value, isFalse);
    final again = ApiSettingsController(store: store);
    await again.load();
    expect(again.enabled(ChemService.ghs), isFalse);
    expect(again.enabled(ChemService.chem), isTrue);
  });

  testWidgets("'처음 데이터로 되돌리기'는 키·연동 선택을 지우지 않는다", (tester) async {
    final apiBefore = apiSettingsJson(key: 'K', services: {'chem': true, 'ghs': false, 'safety': true});
    final apiStore = MemoryUpdateStore(apiBefore);
    final updateStore = MemoryUpdateStore(jsonEncode(tinyDataset().toJson()));
    await pumpSettings(tester, apiStore: apiStore, updateStore: updateStore);
    await expand(tester, SettingsText.sourceCard);
    await tapButton(tester, SettingsText.reset);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(SettingsText.reset)).last);
    await tester.pumpAndSettle();
    expect(updateStore.value, isNull);
    expect(apiStore.value, apiBefore);
  });
}
