/// F-001 화면 수용 기준 — 실제 번들 데이터로 검색 화면을 띄워 카드 내용·순서·안내·2열을 확인한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/parser/models.dart';
import 'package:findchem/share/share_action.dart';
import 'package:findchem/share/share_text.dart';
import 'package:findchem/ui/entry_card.dart';
import 'package:findchem/ui/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Dataset ds;

  setUpAll(() {
    final text = File('assets/data/findchem_data.json').readAsStringSync();
    ds = Dataset.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    Size size = const Size(400, 800),
    double textScale = 1,
    Dataset? data,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(home: SearchPage(dataset: data ?? ds)),
      ),
    );
  }

  Future<void> type(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField), q);
    await tester.pump();
  }

  Finder cardOf(String ko) => find.ancestor(of: find.text(ko), matching: find.byType(EntryCard));

  testWidgets("'50-00-0' → 머리 건수, 사고대비물질 카드가 위에(뱃지만, '우선 적용' 문구 없음), 별표2 510이 아래에 참고 문구",
      (tester) async {
    await pumpPage(tester);
    await type(tester, '50-00-0');

    expect(find.text('전체 2건 · 사고대비물질 1건 · 인체·생태 유해성 1건'), findsOneWidget);
    // 2026-09-12 사용자 결정: 카드의 '우선 적용' 뱃지는 없앴다(공유 텍스트에는 남아 있다 — F-003).
    expect(find.text(CardText.priority), findsNothing);
    expect(find.text(CardText.referenceNote), findsOneWidget);

    final top = cardOf('포르말린 또는 포름알데히드(폼알데하이드)');
    final below = cardOf('포르말린; 포름알데히드');
    expect(tester.getTopLeft(top).dy, lessThan(tester.getTopLeft(below).dy));
    expect(find.descendant(of: below, matching: find.text(CardText.referenceNote)), findsOneWidget);
    expect(find.descendant(of: top, matching: find.text('사고대비물질')), findsOneWidget);
    expect(find.descendant(of: top, matching: find.text('번호 1')), findsOneWidget);
    expect(find.descendant(of: below, matching: find.text('인체·생태 유해성')), findsOneWidget);
    expect(find.descendant(of: below, matching: find.text('연번 510 · 고유번호 97-1-345')), findsOneWidget);
  });

  testWidgets('표 이름 뱃지 색: 사고대비물질은 테마 강조색, 인체·생태 유해성은 붉은색 + 흰 글자', (tester) async {
    await pumpPage(tester);
    await type(tester, '50-00-0');

    ({Color background, Color? foreground}) badge(String label) {
      final text = find.text(label);
      final box = tester.widget<Container>(find.ancestor(of: text, matching: find.byType(Container)).first);
      return (
        background: (box.decoration! as BoxDecoration).color!,
        foreground: tester.widget<Text>(text).style?.color,
      );
    }

    final cs = Theme.of(tester.element(find.byType(EntryCard).first)).colorScheme;
    final b3 = badge('사고대비물질');
    final b2 = badge('인체·생태 유해성');
    expect(b3.background, cs.primary);
    expect(b3.foreground, cs.onPrimary);
    expect(b2.background, byeolpyo2BadgeColor);
    expect(b2.foreground, Colors.white);
    expect(b2.background, isNot(b3.background));
  });

  testWidgets("'13516-27-3' 카드: 국문명·영문명·표·연번·고유번호·CAS 전부·구분별 수량 원문 그대로", (tester) async {
    await pumpPage(tester);
    await type(tester, '13516-27-3');

    expect(find.text('구아자틴'), findsOneWidget);
    expect(find.text('Guazatine'), findsOneWidget);
    expect(find.text('인체·생태 유해성'), findsOneWidget); // 표 이름 뱃지
    expect(find.text('연번 5 · 고유번호 97-1-4'), findsOneWidget);
    expect(find.text('CAS 13516-27-3, 108173-90-6'), findsOneWidget);
    for (final h in ['구분', '함량기준(%)', '최하위(톤)', '하위(톤)', '상위(톤)']) {
      expect(find.text(h), findsOneWidget, reason: h);
    }
    // 급성 1 / 0.125 / 5 / 200, 생태 25 / 0.125 / 5 / 200
    expect(find.text('급성'), findsOneWidget);
    expect(find.text('생태'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('25'), findsOneWidget);
    expect(find.text('0.125'), findsNWidgets(2));
    expect(find.text('5'), findsNWidgets(2));
    expect(find.text('200'), findsNWidgets(2));
  });

  testWidgets("'구아자틴' → 2건, 연번 4(염류)에 '묶음 항목 · CAS 없음'", (tester) async {
    await pumpPage(tester);
    await type(tester, '구아자틴');
    expect(find.text('전체 2건 · 사고대비물질 0건 · 인체·생태 유해성 2건'), findsOneWidget);
    expect(find.descendant(of: cardOf('구아자틴 염류'), matching: find.text(CardText.noCas)), findsOneWidget);
    expect(find.text(CardText.noCas), findsOneWidget);
  });

  testWidgets("별표3 42번 '염화수소 용액' 행 값 '0.2*'가 원문 그대로 나온다", (tester) async {
    await pumpPage(tester);
    await type(tester, '7647-01-0');
    expect(find.text('염화수소 용액'), findsOneWidget);
    expect(find.text('0.2*'), findsOneWidget);
    expect(find.text('8*'), findsOneWidget);
    expect(find.text('40*'), findsOneWidget);
  });

  testWidgets("CAS 형식 0건 → 묶음 안내. '123-33-1'(삭제 1건) → 안내 없음, 삭제 표시·흐리게", (tester) async {
    await pumpPage(tester);
    await type(tester, '99999-99-9');
    expect(find.text(SearchText.casNoHit), findsOneWidget);
    expect(find.text('전체 0건 · 사고대비물질 0건 · 인체·생태 유해성 0건'), findsOneWidget);

    await type(tester, '123-33-1');
    expect(find.text(SearchText.casNoHit), findsNothing);
    expect(find.text(SearchText.noHit), findsNothing);
    expect(find.text(CardText.deleted), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('말레산히드라지드'), matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, lessThan(1));
    // 삭제 항목에는 수량 표가 없다
    expect(find.text('구분'), findsNothing);

    await type(tester, '없는물질zzz');
    expect(find.text(SearchText.noHit), findsOneWidget);
    expect(find.text(SearchText.casNoHit), findsNothing);
  });

  testWidgets("'톨루엔' → 첫 카드는 사고대비물질, (삭제) 439는 목록 끝(스크롤 뒤)에", (tester) async {
    await pumpPage(tester);
    await type(tester, '톨루엔');
    final first = tester.widget<EntryCard>(find.byType(EntryCard).first);
    expect(first.hit.entry.src, Source.byeolpyo3);

    // 목록은 지연 생성이라 끝까지 스크롤해야 삭제 항목이 만들어진다
    for (var i = 0; i < 60 && find.text(CardText.deleted).evaluate().isEmpty; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pump();
    }
    expect(find.text(CardText.deleted), findsOneWidget);
    final last = tester.widget<EntryCard>(find.byType(EntryCard).last);
    expect((last.hit.entry.src, last.hit.entry.no), (Source.byeolpyo2, 439));
  });

  testWidgets("'산' → 상한을 넘으면 전체 건수와 '더 있음'", (tester) async {
    await pumpPage(tester);
    await type(tester, '산');
    final header = tester.widget<Text>(find.textContaining('전체 ')).data!;
    final total = int.parse(RegExp(r'전체 (\d+)건').firstMatch(header)!.group(1)!);
    expect(total, greaterThan(100));
    expect(find.text('앞 100건만 표시 · 더 있음'), findsOneWidget);
  });

  testWidgets('빈 입력이면 결과 영역이 비어 있다', (tester) async {
    await pumpPage(tester);
    expect(find.byType(EntryCard), findsNothing);
    expect(find.textContaining('전체 '), findsNothing);
    await type(tester, '구아자틴');
    expect(find.byType(EntryCard), findsNWidgets(2));
    await type(tester, '');
    expect(find.byType(EntryCard), findsNothing);
    expect(find.textContaining('전체 '), findsNothing);
  });

  testWidgets('폭 900 이상이면 2열, 400이면 1열', (tester) async {
    await pumpPage(tester, size: const Size(1200, 800));
    await type(tester, '50-00-0');
    final a = tester.getTopLeft(find.byType(EntryCard).at(0));
    final b = tester.getTopLeft(find.byType(EntryCard).at(1));
    expect(a.dy, b.dy, reason: '같은 행');
    expect(a.dx, lessThan(b.dx));
    // 두 카드의 폭이 화면 절반씩
    expect(tester.getSize(find.byType(EntryCard).at(0)).width, closeTo(600, 1));

    await pumpPage(tester, size: const Size(400, 800));
    await type(tester, '50-00-0');
    final c = tester.getTopLeft(find.byType(EntryCard).at(0));
    final d = tester.getTopLeft(find.byType(EntryCard).at(1));
    expect(c.dy, lessThan(d.dy));
    expect(c.dx, d.dx);
  });

  group('F-003 공유 버튼', () {
    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');

    /// 공유 창 채널을 가로챈다. [fail]이면 공유 창을 못 여는 환경처럼 예외를 던진다.
    List<String> mockShare(WidgetTester tester, {bool fail = false}) {
      final shared = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(shareChannel, (call) async {
        if (fail) throw PlatformException(code: 'unavailable');
        shared.add((call.arguments as Map)['text'] as String);
        return 'dev.fluttercommunity.plus/share/success';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));
      return shared;
    }

    Finder shareButtonOf(String ko) =>
        find.descendant(of: cardOf(ko), matching: find.byTooltip(ShareText.tooltip));

    testWidgets("'50-00-0' → 카드마다 공유 버튼, 누르면 그 카드의 공유 텍스트가 공유 창으로(날짜는 그 카드의 표 PDF)", (tester) async {
      // 실제 두 PDF는 생성일이 같다(2026-07-20) — 표를 바꿔 쓰는 결함이 드러나게 사고대비물질 쪽 날짜만 바꾼다.
      final data = Dataset(
        byeolpyo2: ds.byeolpyo2,
        byeolpyo3: PdfInfo(file: ds.byeolpyo3.file, created: '2030-01-01T00:00:00+09:00', pages: ds.byeolpyo3.pages),
        extractedAt: ds.extractedAt,
        entries: ds.entries,
      );
      final shared = mockShare(tester);
      await pumpPage(tester, data: data);
      await type(tester, '50-00-0');
      expect(find.byTooltip(ShareText.tooltip), findsNWidgets(2));

      await tester.tap(shareButtonOf('포르말린; 포름알데히드'));
      await tester.pump();
      await tester.tap(shareButtonOf('포르말린 또는 포름알데히드(폼알데하이드)'));
      await tester.pump();
      final hit = tester.widget<EntryCard>(cardOf('포르말린; 포름알데히드')).hit;
      expect(shared.first, shareText(hit, ds.byeolpyo2));
      expect(shared.first.split('\n').first, '[인체·생태 유해성] 포르말린; 포름알데히드');
      expect(shared.first.split('\n').last, endsWith('(PDF 2026-07-20 기준)'));
      expect(shared.last.split('\n').first, '[사고대비물질 · 우선 적용] 포르말린 또는 포름알데히드(폼알데하이드)');
      expect(shared.last.split('\n').last, endsWith('(PDF 2030-01-01 기준)'));
      expect(find.text(ShareText.copied), findsNothing);
    });

    testWidgets('클립보드 쓰기도 거부되면 "공유하지 못했습니다" 알림(아무 반응 없이 끝나지 않는다)', (tester) async {
      mockShare(tester, fail: true);
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') throw PlatformException(code: 'denied');
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpPage(tester);
      await type(tester, '7647-01-0');
      await tester.tap(shareButtonOf('염화수소'));
      await tester.pump();
      expect(find.text(ShareText.failed), findsOneWidget);
      expect(find.text(ShareText.copied), findsNothing);
    });

    testWidgets('공유 창을 열 수 없으면 같은 텍스트가 클립보드로, "복사했습니다" 알림', (tester) async {
      mockShare(tester, fail: true);
      final clipboard = <String>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') clipboard.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(SystemChannels.platform, null));

      await pumpPage(tester);
      await type(tester, '7647-01-0');
      await tester.tap(shareButtonOf('염화수소'));
      await tester.pump();
      final hit = tester.widget<EntryCard>(cardOf('염화수소')).hit;
      expect(clipboard, [shareText(hit, ds.byeolpyo3)]);
      expect(find.text(ShareText.copied), findsOneWidget);
    });
  });

  testWidgets('시스템 글자 크기 2배에서도 카드가 넘치지 않는다(오버플로 예외 없음)', (tester) async {
    await pumpPage(tester, size: const Size(360, 800), textScale: 2);
    await type(tester, '50-00-0');
    expect(tester.takeException(), isNull);
    await type(tester, '납과 그 화합물');
    expect(tester.takeException(), isNull);
    expect(find.byType(EntryCard), findsWidgets);
  });
}
