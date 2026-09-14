/// F-007 CAS 조회(웹 표) 수용 기준 — 실제 번들 데이터로 표를 띄우고, 응답은 2026-09-14 실호출 원문(fixture).
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/lookup/api_settings.dart';
import 'package:findchem/lookup/chem_api.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/ui/cas_lookup_panel.dart';
import 'package:findchem/ui/entry_card.dart';
import 'package:findchem/ui/search_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fakes.dart';
import '../lookup/fake_api.dart';

void main() {
  late Dataset ds;

  setUpAll(() {
    ds = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
  });

  /// 표 화면 + 조회. [stored]는 F-007 설정 파일.
  Future<FakeApi> pumpPage(WidgetTester tester, {String? stored, bool useTable = true, FakeApi? api}) async {
    const size = Size(1400, 5000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = api ?? FakeApi();
    final lookup = CasLookup(
      settings: ApiSettingsController(store: MemoryUpdateStore(stored ?? apiSettingsJson())),
      client: fake.client(),
    );
    await tester.pumpWidget(
      MaterialApp(home: SearchPage(dataset: ds, useTable: useTable, lookup: lookup)),
    );
    return fake;
  }

  Future<void> type(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField), q);
    await tester.pump();
  }

  Finder cas(Source src, int no, String number) => find.byKey(ValueKey('cas-${src.id}-$no-$number'));
  Finder panel(Source src, int no) => find.byKey(ValueKey('lookup-panel-${src.id}-$no'));
  Finder inPanel(Source src, int no, String text) => find.descendant(of: panel(src, no), matching: find.text(text));
  final anyCasLink = find.byWidgetPredicate(
    (w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('cas-'),
  );

  testWidgets('CAS가 여러 개면 번호마다 따로 눌리고, 같은 행의 결과 영역은 하나다. 묶음 항목·앱 카드는 눌리지 않는다', (tester) async {
    await pumpPage(tester);
    await type(tester, '13516-27-3');
    expect(cas(Source.byeolpyo2, 5, '13516-27-3'), findsOneWidget);
    expect(cas(Source.byeolpyo2, 5, '108173-90-6'), findsOneWidget);

    await tester.tap(cas(Source.byeolpyo2, 5, '108173-90-6'));
    await tester.pumpAndSettle();
    expect(find.text(LookupText.title('108173-90-6')), findsOneWidget);
    await tester.tap(cas(Source.byeolpyo2, 5, '13516-27-3'));
    await tester.pumpAndSettle();
    expect(find.text(LookupText.title('13516-27-3')), findsOneWidget);
    expect(find.text(LookupText.title('108173-90-6')), findsNothing);
    expect(find.byType(CasLookupPanel), findsOneWidget);

    await type(tester, '구아자틴 염류');
    expect(find.text(CardText.noCas), findsOneWidget);
    expect(anyCasLink, findsNothing);

    await tester.pumpWidget(const SizedBox());
    await pumpPage(tester, useTable: false);
    await type(tester, '50-00-0');
    expect(find.byType(EntryCard), findsNWidgets(2));
    expect(anyCasLink, findsNothing, reason: '앱 카드는 앱 단계(REQUIREMENTS F-007 단계)');
  });

  testWidgets("'50-00-0' → 사고대비물질 행 CAS → 그 행 바로 아래에 조회 중 → 세 섹션 순서·값. 다시 누르면 접힌다", (tester) async {
    final api = await pumpPage(tester);
    await type(tester, '50-00-0');
    await tester.tap(cas(Source.byeolpyo3, 1, '50-00-0'));
    await tester.pump();
    expect(find.text(LookupText.loading), findsWidgets);
    await tester.pumpAndSettle();
    expect(find.text(LookupText.loading), findsNothing);

    // 위치: 누른 행(사고대비물질 1)보다 아래, 다음 행(인체·생태 유해성 510)보다 위
    final p = panel(Source.byeolpyo3, 1);
    expect(p, findsOneWidget);
    final panelTop = tester.getTopLeft(p).dy;
    expect(panelTop, greaterThan(tester.getTopLeft(find.text('포르말린 또는 포름알데히드(폼알데하이드)')).dy));
    expect(tester.getBottomLeft(p).dy, lessThanOrEqualTo(tester.getTopLeft(find.text('포르말린; 포름알데히드')).dy));

    // 섹션 순서
    final y = [for (final s in ChemService.values) tester.getTopLeft(inPanel(Source.byeolpyo3, 1, s.label)).dy];
    expect(y[0], lessThan(y[1]));
    expect(y[1], lessThan(y[2]));

    // 화학물질 정보
    Finder t(String text) => inPanel(Source.byeolpyo3, 1, text);
    expect(t('포르말린'), findsOneWidget);
    expect(t('CH2O · 30.03'), findsOneWidget);
    expect(t('KE-17074'), findsWidgets);
    expect(t('분류 6건'), findsOneWidget);
    expect(t('화학물질안전원고시 제2025-19호'), findsOneWidget);
    // 유독물 GHS 정보
    expect(t('위험'), findsOneWidget);
    expect(t('1198, 2209'), findsOneWidget);
    expect(t('GHS02, GHS04, GHS05, GHS06, GHS08'), findsOneWidget);
    expect(t('유해성 분류 9건'), findsOneWidget);
    expect(t('P280, P302+P352, P312, P321, P361+P364, P405, P501'), findsOneWidget);
    // 안전관리정보: 6항목, 중복 문장 2번, 자료없음
    for (final label in ['일반증상', '흡입', '피부', '안구', '경구', '기타']) {
      expect(t(label), findsOneWidget, reason: label);
    }
    // 항목마다 Text 하나에 문장별 줄(선택 복사 때 줄바꿈이 살게) — 피부 16문장, 중복 문장 2번 그대로
    final skin = tester
        .widget<Text>(find.descendant(of: panel(Source.byeolpyo3, 1), matching: find.textContaining('·독성이 있음')))
        .data!;
    expect(skin.split('\n'), hasLength(16));
    expect(skin.split('\n').where((l) => l == '·반복 노출은 홍반, 부어오름, 수포 등의 접촉성 피부염을 유발시킬 수 있음'), hasLength(2));
    expect(t('·자료없음'), findsOneWidget);
    expect(api.calls, hasLength(3));

    await tester.tap(cas(Source.byeolpyo3, 1, '50-00-0'));
    await tester.pumpAndSettle();
    expect(p, findsNothing);
  });

  testWidgets('펼친 결과를 마우스로 끌어 선택하고 Ctrl+C로 복사한다 — 한 항목 안의 줄바꿈이 산다', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await pumpPage(tester, stored: apiSettingsJson(services: {'chem': false, 'ghs': false, 'safety': true}));
    await type(tester, '50-00-0');
    await tester.tap(cas(Source.byeolpyo3, 1, '50-00-0'));
    await tester.pumpAndSettle();

    final inhale = find.descendant(of: panel(Source.byeolpyo3, 1), matching: find.textContaining('·인후통, 기침'));
    final gesture = await tester.startGesture(tester.getTopLeft(inhale) + const Offset(1, 4), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await gesture.moveTo(tester.getBottomRight(inhale) - const Offset(1, 4));
    await tester.pump();
    await gesture.up();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
    await tester.pumpAndSettle();

    expect(clipboard, isNotNull, reason: '선택·복사가 되지 않았다');
    expect(clipboard, contains('·인후통, 기침, 숨참을 유발할 수 있음\n·호흡기의 과민성과 자극을 유발함'));
  });

  testWidgets('빈 값은 그 줄을 뺀다(영문명이 비면 영문명 줄이 없다)', (tester) async {
    final api = FakeApi();
    final body = (jsonDecode(fixtures[ChemService.chem]!) as Map)..['body']['items'][0]['sbstnNmEng'] = '  ';
    api.overrides[ChemService.chem] = () async => utf8Response(jsonEncode(body), 200);
    await pumpPage(tester, api: api, stored: apiSettingsJson(services: {'chem': true, 'ghs': false, 'safety': false}));
    await type(tester, '50-00-0');
    await tester.tap(cas(Source.byeolpyo3, 1, '50-00-0'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: panel(Source.byeolpyo3, 1), matching: find.text('영문명')), findsNothing);
    expect(find.descendant(of: panel(Source.byeolpyo3, 1), matching: find.text('국문명')), findsOneWidget);
  });

  testWidgets('체크 해제한 서비스는 부르지 않고 섹션도 없다', (tester) async {
    final api = await pumpPage(tester, stored: apiSettingsJson(services: {'chem': true, 'ghs': false, 'safety': true}));
    await type(tester, '50-00-0');
    await tester.tap(cas(Source.byeolpyo3, 1, '50-00-0'));
    await tester.pumpAndSettle();
    expect(api.callsTo(ChemService.ghs), 0);
    expect(find.text(ChemService.ghs.label), findsNothing);
    expect(find.text(ChemService.chem.label), findsOneWidget);
    expect(find.text(ChemService.safety.label), findsOneWidget);
  });

  testWidgets('키가 없으면·체크가 0개면 부르지 않고 안내', (tester) async {
    var api = await pumpPage(tester, stored: apiSettingsJson(key: null));
    await type(tester, '50-00-0');
    await tester.tap(cas(Source.byeolpyo3, 1, '50-00-0'));
    await tester.pumpAndSettle();
    expect(find.text(LookupText.noKey), findsOneWidget);
    expect(api.calls, isEmpty);

    await tester.pumpWidget(const SizedBox()); // 앞 화면의 열린 행 상태가 남지 않게 트리를 비운다
    api = await pumpPage(tester, stored: apiSettingsJson(services: {'chem': false, 'ghs': false, 'safety': false}));
    await type(tester, '50-00-0');
    await tester.tap(cas(Source.byeolpyo3, 1, '50-00-0'));
    await tester.pumpAndSettle();
    expect(find.text(LookupText.noService), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('한 서비스가 실패해도 다른 섹션은 나온다. 0건이면 조회 결과 없음, 더 있으면 N건 중 M건', (tester) async {
    final api = FakeApi();
    api.overrides[ChemService.ghs] = () async => utf8Response(portalError('30'), 403);
    final chem = (jsonDecode(fixtures[ChemService.chem]!) as Map)..['body']['totalCount'] = 12;
    api.overrides[ChemService.chem] = () async => utf8Response(jsonEncode(chem), 200);
    final safety = fixtures[ChemService.safety]!
        .replaceFirst(RegExp(r'<items>.*</items>', dotAll: true), '<items></items>')
        .replaceFirst('<totalCount>1</totalCount>', '<totalCount>0</totalCount>');
    api.overrides[ChemService.safety] = () async => utf8Response(safety, 200);

    await pumpPage(tester, api: api);
    await type(tester, '50-00-0');
    await tester.tap(cas(Source.byeolpyo3, 1, '50-00-0'));
    await tester.pumpAndSettle();
    expect(find.text(LookupText.notApproved), findsOneWidget);
    expect(find.text('분류 6건'), findsOneWidget, reason: '실패한 섹션과 무관하게 나온다');
    expect(find.text(LookupText.truncated(12, 1)), findsOneWidget);
    expect(find.text(LookupText.noResult), findsOneWidget);
  });
}
