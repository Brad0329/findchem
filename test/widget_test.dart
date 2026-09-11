import 'dart:async';

import 'package:findchem/data/dataset_loader.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/ui/app.dart';
import 'package:findchem/ui/app_header.dart';
import 'package:findchem/ui/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('번들 JSON을 실제 asset 경로로 읽는다(경로·형식이 틀리면 여기서 잡힌다)', (tester) async {
    // asset 읽기는 실제 I/O라 fake-async 밖에서 돌린다
    final ds = await tester.runAsync(loadDataset);
    expect(ds, isNotNull);
    expect(ds!.entries.length, 1657);
  });

  testWidgets('앱: 읽는 동안 진행 표시 → 검색 화면(헤더 FindChem, 검색창)', (tester) async {
    final completer = Completer<Dataset>();
    await tester.pumpWidget(FindChemApp(dataset: completer.future));
    expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).title, 'FindChem');
    expect(find.text('FindChem'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete(const Dataset(
      byeolpyo2: PdfInfo(file: 'a.pdf', created: null, pages: 1),
      byeolpyo3: PdfInfo(file: 'b.pdf', created: null, pages: 1),
      extractedAt: '2026-09-11T00:00:00Z',
      entries: [],
    ));
    await tester.pump();
    expect(find.byType(SearchPage), findsOneWidget);
    expect(find.text(SearchText.hint), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('데이터 로딩이 실패하면 오류를 화면에 보여준다(조용히 넘어가지 않는다)', (tester) async {
    // 화면이 구독한 뒤에 실패해야 한다 — 미리 실패한 Future는 '미처리 오류'로 테스트가 먼저 잡는다
    final completer = Completer<Dataset>();
    await tester.pumpWidget(FindChemApp(dataset: completer.future));
    completer.completeError(StateError('테스트용 실패'));
    await tester.pump();
    expect(find.textContaining('데이터를 읽지 못했습니다'), findsOneWidget);
    expect(find.textContaining('테스트용 실패'), findsOneWidget);
    expect(find.byType(SearchPage), findsNothing);
  });

  testWidgets('테마: Material 3, 아이콘 파랑 시드, 시스템 따라 라이트/다크(화면 방향 3·4)', (tester) async {
    await tester.pumpWidget(FindChemApp(dataset: Completer<Dataset>().future));
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.system);
    expect(app.theme!.useMaterial3, isTrue);
    expect(app.theme!.colorScheme.brightness, Brightness.light);
    expect(app.darkTheme!.colorScheme.brightness, Brightness.dark);
    expect(app.theme!.colorScheme, ColorScheme.fromSeed(seedColor: seedColor));
  });

  testWidgets("헤더의 '⋮'를 누르면 톱니바퀴 '설정' 메뉴가 열린다", (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(appBar: AppHeader())));
    expect(find.text('설정'), findsNothing);
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    expect(find.text('설정'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
