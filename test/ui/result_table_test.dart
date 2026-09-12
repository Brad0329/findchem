/// F-004 웹 표 화면 수용 기준 — 실제 번들 데이터로 표를 띄워 행 구성·복사·가로 스크롤을 확인한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/parser/models.dart';
import 'package:findchem/share/share_action.dart';
import 'package:findchem/ui/entry_card.dart';
import 'package:findchem/ui/result_table.dart';
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

  Future<void> pumpPage(WidgetTester tester, {bool useTable = true, Size size = const Size(1200, 800)}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(size: size),
        child: MaterialApp(home: SearchPage(dataset: ds, useTable: useTable)),
      ),
    );
  }

  Future<void> type(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField), q);
    await tester.pump();
  }

  testWidgets("웹(표)에서 '50-00-0' → 표 2행, 사고대비물질이 위. 앱(카드)에서는 카드가 나온다", (tester) async {
    await pumpPage(tester);
    await type(tester, '50-00-0');

    expect(find.byType(ResultTable), findsOneWidget);
    expect(find.byType(EntryCard), findsNothing);
    expect(find.text('전체 2건 · 사고대비물질 1건 · 인체·생태 유해성 1건'), findsOneWidget);
    final top = find.text('포르말린 또는 포름알데히드(폼알데하이드)');
    final below = find.text('포르말린; 포름알데히드');
    expect(tester.getTopLeft(top).dy, lessThan(tester.getTopLeft(below).dy));

    await pumpPage(tester, useTable: false);
    await type(tester, '50-00-0');
    expect(find.byType(EntryCard), findsNWidgets(2));
    expect(find.byType(ResultTable), findsNothing);
  });

  testWidgets('수량 행이 2개인 항목: 앞 열(연번·물질명·CAS·고유번호·복사)은 첫 줄에만', (tester) async {
    await pumpPage(tester);
    await type(tester, '13516-27-3');

    expect(find.text('구아자틴'), findsOneWidget);
    expect(find.text('Guazatine'), findsOneWidget);
    expect(find.text('13516-27-3, 108173-90-6'), findsOneWidget);
    expect(find.text('97-1-4'), findsOneWidget);
    expect(find.byTooltip(ShareText.copyTooltip), findsOneWidget); // 복사 버튼도 물질당 하나
    // '표' 열은 없다(2026-09-12 사용자 요청 — 어느 표인지는 '구분' 칸으로 안다).
    expect(find.text('인체·생태 유해성'), findsNothing);
    expect(find.text('표'), findsNothing);
    // 수량 줄은 둘 다 있다
    expect(find.text('급성'), findsOneWidget);
    expect(find.text('생태'), findsOneWidget);

    // 앞 칸은 세로로 병합돼 보여야 한다(2026-09-12 사용자 요청) — 높이를 재서 확인한다.
    double cellHeight(String text) => tester
        .getSize(find.ancestor(of: find.text(text), matching: find.byType(Container)).first)
        .height;
    expect(cellHeight('97-1-4'), greaterThan(cellHeight('급성') * 1.5));
    // 수량 줄들이 병합 칸의 높이를 빈틈없이 나눠 가진다 — 남으면 아래쪽 표 선이 끊긴다(2026-09-12 사용자 지적).
    expect(cellHeight('급성') + cellHeight('생태'), closeTo(cellHeight('97-1-4'), 0.5));
    // 웹 표에는 공유 아이콘이 없다(F-003 — 복사가 대신한다)
    expect(find.byTooltip(ShareText.tooltip), findsNothing);
  });

  testWidgets('복사 버튼 → TSV가 클립보드에, "복사했습니다" 알림', (tester) async {
    String? clipboard;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = ((call.arguments as Map)['text'] as String?);
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpPage(tester);
    await type(tester, '13516-27-3');
    await tester.tap(find.byTooltip(ShareText.copyTooltip));
    await tester.pumpAndSettle();

    expect(clipboard, isNotNull);
    final lines = clipboard!.split('\n');
    expect(lines, hasLength(2)); // 머리글 없이 그 물질의 수량 줄만(2026-09-12 사용자 요청)
    expect(lines[0], startsWith('5\t구아자틴\t'));
    expect(clipboard, isNot(contains('연번\t화학물질명')));
    expect(clipboard, isNot(contains('Guazatine'))); // 영문명 열은 없다(2026-09-12 사용자 요청)
    expect(find.text(ShareText.copied), findsOneWidget);
  });

  testWidgets('클립보드 쓰기가 거부되면 "복사하지 못했습니다" 알림(조용히 끝나지 않는다)', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        throw PlatformException(code: 'denied');
      }
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null),
    );

    await pumpPage(tester);
    await type(tester, '13516-27-3');
    await tester.tap(find.byTooltip(ShareText.copyTooltip));
    await tester.pumpAndSettle();

    expect(find.text(ShareText.copyFailed), findsOneWidget);
    expect(find.text(ShareText.copied), findsNothing);
  });

  testWidgets('CAS 없는 항목은 화면에 묶음 안내, 삭제 항목은 흐리게', (tester) async {
    await pumpPage(tester);
    await type(tester, '구아자틴 염류');
    expect(find.text(CardText.noCas), findsOneWidget);

    await type(tester, '123-33-1');
    expect(find.text('말레산히드라지드'), findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.ancestor(of: find.text('말레산히드라지드'), matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, lessThan(1));
  });

  testWidgets('폭 375에서도 표가 잘리지 않고 가로로 스크롤된다', (tester) async {
    await pumpPage(tester, size: const Size(375, 700));
    await type(tester, '13516-27-3');

    // 표 폭이 화면보다 넓다(잘라서 맞추지 않는다).
    expect(tableWidth, greaterThan(375));
    final scroll = find.descendant(
      of: find.byType(ResultTable),
      matching: find.byType(Scrollable),
    );
    final horizontal = tester
        .widgetList<Scrollable>(scroll)
        .where((s) => s.axisDirection == AxisDirection.right);
    expect(horizontal, isNotEmpty);

    // 실제로 움직이는지 값을 재서 본다 — 존재 확인만으로는 잡히지 않는다.
    final before = tester.getTopLeft(find.text('구아자틴')).dx;
    await tester.drag(find.byType(ResultTable), const Offset(-200, 0));
    await tester.pump();
    final after = tester.getTopLeft(find.text('구아자틴')).dx;
    expect(after, lessThan(before));
  });
}
