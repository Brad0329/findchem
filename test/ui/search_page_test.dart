/// F-001 화면 수용 기준 — 실제 번들 데이터로 검색 화면을 띄워 카드 내용·순서·안내·2열을 확인한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/parser/models.dart';
import 'package:findchem/ui/entry_card.dart';
import 'package:findchem/ui/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Dataset ds;

  setUpAll(() {
    final text = File('assets/data/findchem_data.json').readAsStringSync();
    ds = Dataset.fromJson((jsonDecode(text) as Map).cast<String, Object?>());
  });

  Future<void> pumpPage(WidgetTester tester, {Size size = const Size(400, 800), double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale)),
        child: MaterialApp(home: SearchPage(dataset: ds)),
      ),
    );
  }

  Future<void> type(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField), q);
    await tester.pump();
  }

  Finder cardOf(String ko) => find.ancestor(of: find.text(ko), matching: find.byType(EntryCard));

  testWidgets("'50-00-0' → 머리 건수, 사고대비물질 카드가 위에 '우선 적용', 별표2 510이 아래에 참고 문구", (tester) async {
    await pumpPage(tester);
    await type(tester, '50-00-0');

    expect(find.text('전체 2건 · 사고대비물질 1건 · 인체·생태 유해성 1건'), findsOneWidget);
    expect(find.text(CardText.priority), findsOneWidget);
    expect(find.text(CardText.referenceNote), findsOneWidget);

    final top = cardOf('포르말린 또는 포름알데히드(폼알데하이드)');
    final below = cardOf('포르말린; 포름알데히드');
    expect(tester.getTopLeft(top).dy, lessThan(tester.getTopLeft(below).dy));
    expect(find.descendant(of: top, matching: find.text(CardText.priority)), findsOneWidget);
    expect(find.descendant(of: below, matching: find.text(CardText.referenceNote)), findsOneWidget);
    expect(find.text('사고대비물질 · 번호 1'), findsOneWidget);
    expect(find.text('인체·생태 유해성 · 연번 510 · 고유번호 97-1-345'), findsOneWidget);
  });

  testWidgets("'13516-27-3' 카드: 국문명·영문명·표·연번·고유번호·CAS 전부·구분별 수량 원문 그대로", (tester) async {
    await pumpPage(tester);
    await type(tester, '13516-27-3');

    expect(find.text('구아자틴'), findsOneWidget);
    expect(find.text('Guazatine'), findsOneWidget);
    expect(find.text('인체·생태 유해성 · 연번 5 · 고유번호 97-1-4'), findsOneWidget);
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

  testWidgets('시스템 글자 크기 2배에서도 카드가 넘치지 않는다(오버플로 예외 없음)', (tester) async {
    await pumpPage(tester, size: const Size(360, 800), textScale: 2);
    await type(tester, '50-00-0');
    expect(tester.takeException(), isNull);
    await type(tester, '납과 그 화합물');
    expect(tester.takeException(), isNull);
    expect(find.byType(EntryCard), findsWidgets);
  });
}
