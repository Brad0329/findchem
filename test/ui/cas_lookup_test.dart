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
import 'package:flutter/rendering.dart' show RenderParagraph;
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
  /// [phraseBubbles] 기본 true — 조회 결과 영역이 실제로 쓰이는 웹과 같게 H·P 말풍선을 켠다(복사 테스트도 켠 채로 돈다).
  Future<FakeApi> pumpPage(
    WidgetTester tester, {
    String? stored,
    bool useTable = true,
    FakeApi? api,
    bool phraseBubbles = true,
  }) async {
    const size = Size(1400, 5000);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final fake = api ?? FakeApi();
    final lookup = CasLookup(
      settings: ApiSettingsController(store: MemoryUpdateStore(stored ?? apiSettingsJson())),
      client: fake.client(),
      phraseBubbles: phraseBubbles,
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
    // H·P 칸은 코드 그대로(2026-09-17 사용자들 요청으로 문구 표시를 뺐다)
    expect(t('H311'), findsOneWidget);
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

  group('선택 복사(2026-09-14 사용자 요청)', () {
    /// [services]만 켜고 50-00-0 결과를 연 뒤, [from]의 왼쪽 위 → [to]의 오른쪽 아래로 마우스로 끌어 선택하고
    /// Ctrl+C로 복사한 클립보드 문자열을 돌려준다.
    Future<String?> dragCopy(
      WidgetTester tester, {
      required Map<String, bool> services,
      required Finder Function() from,
      required Finder Function() to,
    }) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard = (call.arguments as Map)['text'] as String?;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpPage(tester, stored: apiSettingsJson(services: services));
      await type(tester, '50-00-0');
      await tester.tap(cas(Source.byeolpyo3, 1, '50-00-0'));
      await tester.pumpAndSettle();

      final gesture = await tester.startGesture(tester.getTopLeft(from()) + const Offset(1, 4), kind: PointerDeviceKind.mouse);
      await tester.pump();
      await gesture.moveTo(tester.getBottomRight(to()) - const Offset(1, 4));
      await tester.pump();
      await gesture.up();
      await tester.pump();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.control);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.control);
      await tester.pumpAndSettle();
      return clipboard;
    }

    Finder inPanelText(String text) => find.descendant(of: panel(Source.byeolpyo3, 1), matching: find.text(text));
    const chemOnly = {'chem': true, 'ghs': false, 'safety': false};

    testWidgets('한 항목 안의 여러 줄 → 줄바꿈이 산다', (tester) async {
      Finder inhale() =>
          find.descendant(of: panel(Source.byeolpyo3, 1), matching: find.textContaining('·인후통, 기침'));
      final clipboard = await dragCopy(
        tester,
        services: {'chem': false, 'ghs': false, 'safety': true},
        from: inhale,
        to: inhale,
      );
      expect(clipboard, isNotNull, reason: '선택·복사가 되지 않았다');
      expect(clipboard, contains('·인후통, 기침, 숨참을 유발할 수 있음\n·호흡기의 과민성과 자극을 유발함'));
    });

    testWidgets('분류 표 머리글~2행 → 3줄, 칸은 탭, 빈 칸도 자리를 지킨다(Excel 열 분리)', (tester) async {
      final clipboard = await dragCopy(
        tester,
        services: chemOnly,
        from: () => inPanelText('분류'),
        to: () => inPanelText('화학물질안전원고시 제2025-19호'),
      );
      expect(clipboard, isNotNull);
      final lines = clipboard!.split('\n');
      expect(lines, [
        '분류\t고유번호\t함량정보\t예외정보\t고시일자\t고시정보',
        '기존화학물질\tKE-17074\t\t\t20141230\t환경부고시 제2014-237호',
        '인체등유해성물질\t97-1-345\t인체급성유해성 : 1%, 인체만성유해성 : 0.1%\t\t20250807\t화학물질안전원고시 제2025-19호',
      ]);
    });

    testWidgets('이름–값 목록 두 줄 → 줄마다 이름⇥값', (tester) async {
      final clipboard = await dragCopy(
        tester,
        services: chemOnly,
        from: () => inPanelText('국문명'),
        to: () => inPanelText('Formaldehyde').first,
      );
      expect(clipboard, '국문명\t포르말린\n영문명\tFormaldehyde');
    });

    testWidgets('그림문자 표 코드 줄~분류 줄 → 2줄, 칸은 탭·분류 여러 줄은 `, `(그림 줄은 글자가 없어 빠진다)', (tester) async {
      final clipboard = await dragCopy(
        tester,
        services: {'chem': false, 'ghs': true, 'safety': false},
        from: () => inPanelText('GHS02'),
        to: () => inPanelText('호흡기,피부과민성\n발암성\n생식독성\n표적장기독성'),
      );
      expect(
        clipboard,
        'GHS02\tGHS04\tGHS05\tGHS06\tGHS08\n'
        '인화성, 물반응성, 자연발화성\t고압가스\t금속부식성, 피부부식성, 심한눈손상성\t급성독성\t호흡기,피부과민성, 발암성, 생식독성, 표적장기독성',
      );
    });

    // 그림문자 표를 가로 스크롤 영역에 넣었을 때 이 선택에 그림문자 표까지 딸려 온 적이 있다(2026-09-15) — 그 재발을 막는다
    testWidgets('유해성 분류 표 머리글~1행 → 2줄, 그림문자 표는 섞이지 않는다', (tester) async {
      final clipboard = await dragCopy(
        tester,
        services: {'chem': false, 'ghs': true, 'safety': false},
        from: () => inPanelText('분류항목'),
        to: () => inPanelText('P280, P302+P352, P312, P321, P361+P364, P405, P501'),
      );
      expect(clipboard, isNotNull);
      expect(clipboard!.split('\n'), [
        '분류항목\t구분\tH코드\tP코드',
        '급성독성-경피\t3\tH311\tP280, P302+P352, P312, P321, P361+P364, P405, P501',
      ]);
    });

    testWidgets('한 칸 안에서만 선택하면 그 글자만(행 전체가 아니다)', (tester) async {
      final clipboard = await dragCopy(
        tester,
        services: chemOnly,
        from: () => inPanelText('환경부고시 제2014-237호'),
        to: () => inPanelText('환경부고시 제2014-237호'),
      );
      expect(clipboard, '환경부고시 제2014-237호');
    });
  });

  group('그림문자 표(안 A — 2026-09-15 사용자 선택)', () {
    /// 유독물 GHS 정보만 켜고 50-00-0 결과를 연다. [pictograms]가 있으면 응답의 그림문자 코드를 바꾼다.
    Future<void> openGhs(WidgetTester tester, {String? pictograms}) async {
      final api = FakeApi();
      if (pictograms != null) {
        final body = (jsonDecode(fixtures[ChemService.ghs]!) as Map)..['body']['items'][0]['pctgrmCd'] = pictograms;
        api.overrides[ChemService.ghs] = () async => utf8Response(jsonEncode(body), 200);
      }
      await pumpPage(tester, api: api, stored: apiSettingsJson(services: {'chem': false, 'ghs': true, 'safety': false}));
      await type(tester, '50-00-0');
      await tester.tap(cas(Source.byeolpyo3, 1, '50-00-0'));
      await tester.pumpAndSettle();
    }

    Finder t(String text) => find.descendant(of: panel(Source.byeolpyo3, 1), matching: find.text(text));
    // 분류 이름은 아래 유해성 분류 표에도 나온다(`고압가스`) — 그림문자 표 안에서만 찾는다
    Finder inTable(String text) =>
        find.descendant(of: find.byKey(const ValueKey('ghs-pictogram-table')), matching: find.text(text));

    testWidgets('응답 코드마다 한 칸: 코드 → 그림 → 유해성 분류가 같은 열에, 응답 순서대로', (tester) async {
      await openGhs(tester);
      const codes = ['GHS02', 'GHS04', 'GHS05', 'GHS06', 'GHS08'];
      const labels = ['인화성\n물반응성\n자연발화성', '고압가스', '금속부식성\n피부부식성\n심한눈손상성', '급성독성', '호흡기,피부과민성\n발암성\n생식독성\n표적장기독성'];

      final images = tester.widgetList<Image>(find.descendant(of: panel(Source.byeolpyo3, 1), matching: find.byType(Image)));
      expect([for (final i in images) (i.image as AssetImage).assetName], [for (final c in codes) 'assets/data/ghs/$c.png']);

      double centerX(Finder f) => tester.getCenter(f).dx;
      double? prevX;
      for (var i = 0; i < codes.length; i++) {
        final code = inTable(codes[i]), image = find.byKey(ValueKey('ghs-pictogram-${codes[i]}'));
        final label = inTable(labels[i]);
        expect(code, findsOneWidget, reason: codes[i]);
        expect(label, findsOneWidget, reason: codes[i]);
        expect(centerX(image), moreOrLessEquals(centerX(code), epsilon: 1), reason: codes[i]);
        expect(centerX(label), moreOrLessEquals(centerX(code), epsilon: 1), reason: codes[i]);
        expect(tester.getTopLeft(code).dy, lessThan(tester.getTopLeft(image).dy));
        expect(tester.getBottomLeft(image).dy, lessThanOrEqualTo(tester.getTopLeft(label).dy));
        if (prevX != null) expect(centerX(code), greaterThan(prevX), reason: '응답 순서대로 왼쪽부터');
        prevX = centerX(code);
      }
      // 표는 '그림문자' 줄 아래, 'UN번호' 줄 위
      expect(tester.getTopLeft(inTable(codes.first)).dy, greaterThan(tester.getTopLeft(t(codes.join(', '))).dy));
      expect(tester.getBottomLeft(inTable(labels.last)).dy, lessThan(tester.getTopLeft(t('UN번호')).dy));
      expect(t(LookupText.noPictogram), findsNothing);
    });

    testWidgets('대응표에 없는 코드는 그 칸에 그림 없음, 나머지 칸은 그대로', (tester) async {
      await openGhs(tester, pictograms: 'GHS07^GHS99');
      expect(find.byKey(const ValueKey('ghs-pictogram-GHS07')), findsOneWidget);
      expect(inTable('특정표적 장기독성 1회노출'), findsOneWidget);
      expect(inTable('GHS99'), findsOneWidget);
      expect(inTable(LookupText.noPictogram), findsOneWidget);
      expect(
        tester.getCenter(inTable(LookupText.noPictogram)).dx,
        moreOrLessEquals(tester.getCenter(inTable('GHS99')).dx, epsilon: 1),
      );
    });

    testWidgets('그림문자가 없으면 표가 없다', (tester) async {
      await openGhs(tester, pictograms: '');
      expect(find.descendant(of: panel(Source.byeolpyo3, 1), matching: find.byType(Image)), findsNothing);
      expect(t('UN번호'), findsOneWidget);
    });
  });

  group('H·P 말풍선(2026-09-18 — 웹만)', () {
    final bubble = find.byKey(const ValueKey('phrase-bubble'));
    const pText = 'P280, P302+P352, P312, P321, P361+P364, P405, P501';
    Finder inPanelText(String text) => find.descendant(of: panel(Source.byeolpyo3, 1), matching: find.text(text));

    /// 유독물 GHS 정보만 켜고 50-00-0 결과를 연다. [hCode]가 있으면 첫 행의 H코드를 바꾼다.
    Future<void> openGhs(WidgetTester tester, {bool phraseBubbles = true, String? hCode}) async {
      final api = FakeApi();
      if (hCode != null) {
        final body = (jsonDecode(fixtures[ChemService.ghs]!) as Map);
        ((body['body']['items'][0]['hrmflnList'] as List)[0] as Map)['hrmDngrCd'] = hCode;
        api.overrides[ChemService.ghs] = () async => utf8Response(jsonEncode(body), 200);
      }
      await pumpPage(
        tester,
        api: api,
        phraseBubbles: phraseBubbles,
        stored: apiSettingsJson(services: {'chem': false, 'ghs': true, 'safety': false}),
      );
      await type(tester, '50-00-0');
      await tester.tap(cas(Source.byeolpyo3, 1, '50-00-0'));
      await tester.pumpAndSettle();
    }

    /// [text] 칸 안에서 [code]의 **첫 글자 가운데**(전역 좌표). 코드 전체의 가운데는 글자 경계에 떨어질 수 있고,
    /// 경계 위의 점은 어느 글자에도 적중하지 않는다(2026-09-18 실측: 'H311' 가운데 x=25.0 = '3'·'1' 경계).
    Offset codeCenter(WidgetTester tester, String text, String code) {
      final para = tester.renderObject<RenderParagraph>(
        find.descendant(of: inPanelText(text), matching: find.byType(RichText)),
      );
      final start = para.text.toPlainText().indexOf(code);
      expect(start, isNot(-1), reason: '$text 안에 $code가 없다');
      final box = para.getBoxesForSelection(TextSelection(baseOffset: start, extentOffset: start + 1)).first;
      return para.localToGlobal(box.toRect().center);
    }

    Future<TestGesture> hover(WidgetTester tester, Offset at) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      addTearDown(mouse.removePointer);
      await mouse.moveTo(at);
      await tester.pumpAndSettle();
      return mouse;
    }

    testWidgets('문구표에 있는 코드에 올리면 그 자리 위에 말풍선(코드·문구), 치우면 사라진다', (tester) async {
      await openGhs(tester);
      // 마우스 장치는 하나를 계속 옮겨 쓴다 — 같은 테스트에서 장치를 또 더하면 Flutter 검사(MouseTracker)에 걸린다
      final mouse = await hover(tester, const Offset(1, 1));
      for (final (text, code, phrase) in [
        ('H311', 'H311', '피부와 접촉하면 유독함'),
        (pText, 'P302+P352', '피부에 묻으면 다량의 물/···(으)로 씻으시오.'),
      ]) {
        final at = codeCenter(tester, text, code);
        await mouse.moveTo(at);
        await tester.pumpAndSettle();
        expect(bubble, findsOneWidget, reason: code);
        expect(find.descendant(of: bubble, matching: find.text(code)), findsOneWidget, reason: code);
        expect(find.descendant(of: bubble, matching: find.text(phrase)), findsOneWidget, reason: code);
        final rect = tester.getRect(bubble);
        expect(rect.bottom, lessThan(at.dy), reason: '$code 말풍선은 올린 자리보다 위');
        expect(rect.left, lessThanOrEqualTo(at.dx), reason: code);
        expect(rect.right, greaterThanOrEqualTo(at.dx), reason: '$code 말풍선이 가로로 올린 자리를 덮는다');

        await mouse.moveTo(const Offset(1, 1));
        await tester.pumpAndSettle();
        expect(bubble, findsNothing, reason: '$code 마우스를 치우면 사라진다');
      }
    });

    testWidgets('문구표에 없는 코드(H99)는 밑줄도 말풍선도 없다 — 문구표에 있는 P코드는 밑줄', (tester) async {
      await openGhs(tester, hCode: 'H99');
      await hover(tester, codeCenter(tester, 'H99', 'H99'));
      expect(bubble, findsNothing);

      TextSpan spanOf(String text, int index) =>
          (tester.widget<Text>(inPanelText(text)).textSpan! as TextSpan).children![index] as TextSpan;
      expect(spanOf('H99', 0).style?.decoration, isNull);
      expect(spanOf(pText, 0).style?.decoration, TextDecoration.underline, reason: 'P280은 문구표에 있다');
    });

    testWidgets('앱(말풍선 꺼짐): 칸은 글자 그대로이고 올려도 말풍선이 없다', (tester) async {
      await openGhs(tester, phraseBubbles: false);
      expect(tester.widget<Text>(inPanelText('H311')).data, 'H311', reason: '밑줄 없는 평범한 글자');
      await hover(tester, tester.getCenter(inPanelText('H311')));
      expect(bubble, findsNothing);
    });
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
