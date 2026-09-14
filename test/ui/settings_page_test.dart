/// F-002 화면 수용 기준 — 앱 전체(FindChemApp)를 띄워 헤더 메뉴 → 설정 화면에서 실제 PDF로 적용·실패·되돌리기를 한다.
/// 저장본 자리만 메모리로 바꾸고, 파일 선택 창 대신 고를 PDF를 차례로 넘긴다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/data/dataset_loader.dart';
import 'package:findchem/data/source_update.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/ui/app.dart';
import 'package:findchem/ui/entry_card.dart';
import 'package:findchem/ui/search_page.dart';
import 'package:findchem/ui/settings_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fakes.dart';
import '../parser/fixtures.dart';

void main() {
  late Dataset bundled;
  late PickedPdf pdf2;
  late PickedPdf pdf3;
  late int parseWarnings;

  setUpAll(() {
    bundled = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
    PickedPdf picked(Source src) {
      final f = assetPdf(src);
      return PickedPdf(name: f.uri.pathSegments.last, bytes: f.readAsBytesSync());
    }

    pdf2 = picked(Source.byeolpyo2);
    pdf3 = picked(Source.byeolpyo3);
    parseWarnings = parseSourcePdfs({Source.byeolpyo2: pdf2, Source.byeolpyo3: pdf3}).warnings.length;
  });

  /// 앱을 띄운다. [stored]가 있으면 저장본이 있는 기기. [picks]는 '선택'을 누를 때마다 차례로 돌려줄 PDF.
  Future<(MemoryUpdateStore, DataController)> pumpApp(
    WidgetTester tester, {
    String? stored,
    List<PickedPdf?> picks = const [],
  }) async {
    tester.view.physicalSize = const Size(500, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final store = MemoryUpdateStore(stored);
    final controller = DataController(store: store, loadBundled: () async => bundled);
    final queue = [...picks];
    await tester.pumpWidget(FindChemApp(controller: controller, pickPdf: () async => queue.removeAt(0)));
    for (var i = 0; i < 5 && find.byType(SearchPage).evaluate().isEmpty; i++) {
      await tester.pump();
    }
    expect(find.byType(SearchPage), findsOneWidget);
    return (store, controller);
  }

  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('설정'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsPage), findsOneWidget);
    // F-007: F-002 내용은 '사고대비물질·인체·생태 유해성 정보' 카드 안에 있다(처음엔 접혀 있음)
    await tester.tap(find.text(SettingsText.sourceCard));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, Source src) async {
    await tester.tap(find.descendant(of: find.byKey(ValueKey('pick-${src.id}')), matching: find.text(SettingsText.pick)));
    await tester.pump();
  }

  Future<void> tapApply(WidgetTester tester) async {
    await tester.tap(find.text(SettingsText.apply));
    await tester.pump(); // '읽는 중' 표시 프레임
    await tester.pump(const Duration(milliseconds: 50)); // 한 프레임 넘긴 뒤 파싱·저장
    await tester.pump();
  }

  Future<void> search(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField), q);
    await tester.pump();
  }

  // OutlinedButton.icon은 비공개 하위 타입이라 정확한 타입 비교(widgetWithText)로는 안 잡힌다
  Finder resetButton() =>
      find.ancestor(of: find.text(SettingsText.reset), matching: find.bySubtype<OutlinedButton>());

  testWidgets('설정 화면에 현재 원천자료 정보: 번들, 표별 건수, PDF 생성일, 만든 날짜. 되돌리기는 꺼져 있다', (tester) async {
    await pumpApp(tester);
    await openSettings(tester);
    expect(find.text(SettingsText.bundled), findsOneWidget);
    expect(find.text('인체·생태 유해성 1,557건 · PDF 2026-07-20'), findsOneWidget);
    expect(find.text('사고대비물질 100건 · PDF 2026-07-20'), findsOneWidget);
    expect(find.text(bundled.byeolpyo2.file), findsOneWidget);
    expect(find.text(SettingsText.builtAt(bundled.extractedAt)), findsOneWidget);
    expect(find.textContaining('적용한 날짜'), findsNothing);
    expect(tester.widget<OutlinedButton>(resetButton()).onPressed, isNull);
    // F-006: 앱 버전(값이 pubspec과 같은지는 test/release_test.dart) — F-007부터 '웹·앱 정보' 카드 안
    await tester.ensureVisible(find.text(SettingsText.infoCard));
    await tester.tap(find.text(SettingsText.infoCard));
    await tester.pumpAndSettle();
    expect(find.text('앱 버전 1.1.0 (빌드 2)'), findsOneWidget);
    expect(SettingsText.version, '앱 버전 1.1.0 (빌드 2)');
  });

  testWidgets('두 PDF를 골라 적용 → 읽는 중 표시, update 원천자료로 바뀌고 적용한 날짜가 나온다, 저장본이 생긴다', (tester) async {
    final (store, controller) = await pumpApp(tester, picks: [pdf2, pdf3]);
    await openSettings(tester);
    await pick(tester, Source.byeolpyo2);
    await pick(tester, Source.byeolpyo3);
    expect(find.text(pdf2.name), findsWidgets);

    await tester.tap(find.text(SettingsText.apply));
    await tester.pump();
    expect(find.text(SettingsText.parsing), findsOneWidget, reason: '파싱 전에 표시가 먼저 그려진다');
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump();

    expect(find.text(SettingsText.parsing), findsNothing);
    final saved = Dataset.fromJson((jsonDecode(store.value!) as Map).cast<String, Object?>());
    expect(saved.count(Source.byeolpyo2), 1557);
    expect(saved.count(Source.byeolpyo3), 100);
    expect(find.text(SettingsText.applied(saved, parseWarnings)), findsOneWidget);
    expect(SettingsText.applied(saved, parseWarnings), startsWith('적용했습니다: 인체·생태 유해성 1,557건, 사고대비물질 100건'));
    expect(find.text(SettingsText.updated), findsOneWidget);
    final now = DateTime.now();
    final today = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    expect(find.text('적용한 날짜 $today'), findsOneWidget);
    expect(find.text(SettingsText.notPicked), findsNWidgets(2), reason: '적용되면 고른 파일 칸을 비운다');
    expect(controller.data!.origin, DataOrigin.updated);
    expect(tester.widget<OutlinedButton>(resetButton()).onPressed, isNotNull);
  });

  testWidgets('하나만 고르면 적용되지 않고 무엇이 빠졌는지 화면에 알린다', (tester) async {
    final (store, controller) = await pumpApp(tester, picks: [pdf2]);
    await openSettings(tester);
    await pick(tester, Source.byeolpyo2);
    await tapApply(tester);
    expect(find.textContaining('사고대비물질 PDF를 고르지 않았습니다'), findsOneWidget);
    expect(find.textContaining(SettingsText.keepExisting), findsOneWidget);
    expect(store.value, isNull);
    expect(controller.data!.origin, DataOrigin.bundled);
  });

  testWidgets('바꿔 고르면(표 형식 검증 실패) 기존 원천자료(update본)를 그대로 두고 사유를 보여준다', (tester) async {
    final before = jsonEncode(tinyDataset().toJson());
    final (store, controller) = await pumpApp(tester, stored: before, picks: [pdf3, pdf2]);
    await openSettings(tester);
    await pick(tester, Source.byeolpyo2);
    await pick(tester, Source.byeolpyo3);
    await tapApply(tester);
    expect(find.textContaining('적용하지 않았습니다. 인체·생태 유해성 자리의 "${pdf3.name}"'), findsOneWidget);
    expect(store.value, before);
    expect(controller.data!.dataset.entries.single.ko, '테스트물질');
    expect(find.text(SettingsText.updated), findsOneWidget);
    expect(find.text('인체·생태 유해성 1건 · PDF 2027-01-01'), findsOneWidget);
  });

  testWidgets('저장이 실패하면(용량 한도 등) 적용되지 않았다고 알리고 현재 데이터는 그대로', (tester) async {
    final (store, controller) = await pumpApp(tester, picks: [pdf2, pdf3]);
    store.writeError = const FileSystemException('용량 부족');
    await openSettings(tester);
    await pick(tester, Source.byeolpyo2);
    await pick(tester, Source.byeolpyo3);
    await tapApply(tester);
    expect(find.textContaining('적용하지 않았습니다. 저장하지 못했습니다'), findsOneWidget);
    expect(find.textContaining('용량 부족'), findsNothing, reason: '예외 원문(경로가 섞일 수 있다)은 로그에만');
    expect(controller.data!.origin, DataOrigin.bundled);
    expect(find.text(SettingsText.bundled), findsOneWidget);
  });

  testWidgets("'처음 데이터로 되돌리기' → 저장본을 지우고, 설정 정보와 검색 결과가 번들 기준으로 바뀐다", (tester) async {
    final (store, _) = await pumpApp(tester, stored: jsonEncode(tinyDataset().toJson()));
    // 저장본을 쓰는 중: 번들에 없는 물질이 찾히고 번들 물질은 안 찾힌다
    await search(tester, '테스트물질');
    expect(find.byType(EntryCard), findsOneWidget);

    await openSettings(tester);
    expect(find.text(SettingsText.updated), findsOneWidget);
    await tester.tap(resetButton());
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(SettingsText.reset)).last);
    await tester.pumpAndSettle();

    expect(store.value, isNull);
    expect(find.text(SettingsText.resetDone), findsOneWidget);
    expect(find.text(SettingsText.bundled), findsOneWidget);
    expect(find.text('인체·생태 유해성 1,557건 · PDF 2026-07-20'), findsOneWidget);
    expect(find.text('사고대비물질 100건 · PDF 2026-07-20'), findsOneWidget);
    expect(find.text(SettingsText.builtAt(bundled.extractedAt)), findsOneWidget);
    expect(find.textContaining('적용한 날짜'), findsNothing);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(EntryCard), findsNothing, reason: '입력해 둔 검색어가 번들 기준으로 다시 검색된다');
    expect(find.text(SearchText.noHit), findsOneWidget);
    await search(tester, '구아자틴');
    expect(find.byType(EntryCard), findsNWidgets(2));
  });

  testWidgets('저장본이 깨졌으면 번들로 검색하고 설정 화면에 사유, 되돌리기로 지울 수 있다', (tester) async {
    final (store, _) = await pumpApp(tester, stored: '{"source": 1');
    await search(tester, '구아자틴');
    expect(find.byType(EntryCard), findsNWidgets(2));

    await openSettings(tester);
    expect(find.text(SettingsText.bundled), findsOneWidget);
    expect(find.textContaining('저장된 update 원천자료를 읽지 못해'), findsOneWidget);
    await tester.tap(resetButton());
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text(SettingsText.reset)).last);
    await tester.pumpAndSettle();

    expect(store.value, isNull);
    expect(find.textContaining('저장된 update 원천자료를 읽지 못해'), findsNothing);
    expect(tester.widget<OutlinedButton>(resetButton()).onPressed, isNull);
  });

  testWidgets('되돌리기 확인 창에서 취소하면 아무것도 바뀌지 않는다', (tester) async {
    final before = jsonEncode(tinyDataset().toJson());
    final (store, _) = await pumpApp(tester, stored: before);
    await openSettings(tester);
    await tester.tap(resetButton());
    await tester.pumpAndSettle();
    await tester.tap(find.text(SettingsText.cancel));
    await tester.pumpAndSettle();
    expect(store.value, before);
    expect(find.text(SettingsText.updated), findsOneWidget);
  });

  testWidgets('적용되면 검색 화면이 곧바로 새 원천자료로 검색한다', (tester) async {
    final (_, controller) = await pumpApp(tester);
    await search(tester, '테스트물질');
    expect(find.byType(EntryCard), findsNothing);
    await controller.apply(tinyDataset());
    await tester.pump();
    expect(find.byType(EntryCard), findsOneWidget);
    expect(find.text('Testium'), findsOneWidget);
  });
}
