/// F-008 2단계 수용 기준 — 메뉴 진입·순서와 판정 화면(답·근거 칸). LLM만 고정 응답(fixture), 검색은 실제 번들 데이터.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/assist/llm_client.dart';
import 'package:findchem/assist/prompt.dart';
import 'package:findchem/assist/session.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/ui/app.dart';
import 'package:findchem/ui/app_header.dart';
import 'package:findchem/ui/assist_page.dart';
import 'package:findchem/ui/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../assist/fake_llm.dart';
import '../data/fakes.dart';
import 'package:findchem/data/dataset_loader.dart';

void main() {
  late Dataset bundled;

  setUpAll(() {
    bundled = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
  });

  void setView(WidgetTester tester) {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeAnthropic fake,
    String key = 'test-key',
    bool useTable = false,
  }) async {
    setView(tester);
    await tester.pumpWidget(
      FindChemApp(
        controller: DataController(store: MemoryUpdateStore(), loadBundled: () async => bundled),
        assistClient: AssistLlmClient(client: fake.client),
        assistKey: key,
      ),
    );
    for (var i = 0; i < 5 && find.byType(SearchPage).evaluate().isEmpty; i++) {
      await tester.pump();
    }
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
  }

  group('메뉴', () {
    testWidgets('순서는 자주보는 Chem 목록 → 판정(AI) → 설정이다', (tester) async {
      await pumpApp(tester, fake: FakeAnthropic());
      await openMenu(tester);

      final favorites = tester.getTopLeft(find.text(HeaderText.favorites)).dy;
      final assist = tester.getTopLeft(find.text(HeaderText.assist)).dy;
      final settings = tester.getTopLeft(find.text(HeaderText.settings)).dy;
      expect(favorites, lessThan(assist));
      expect(assist, lessThan(settings));
    });

    testWidgets('판정을 누르면 질문 입력창이 있는 화면이 열린다', (tester) async {
      await pumpApp(tester, fake: FakeAnthropic());
      await openMenu(tester);
      await tester.tap(find.text(HeaderText.assist));
      await tester.pumpAndSettle();

      expect(find.byType(AssistPage), findsOneWidget);
      expect(find.text(AssistPageText.send), findsOneWidget);
      expect(find.text(AssistPageText.empty), findsOneWidget);
    });
  });

  group('판정 화면', () {
    Future<AssistSession> pumpPage(
      WidgetTester tester,
      FakeAnthropic fake, {
      String key = 'test-key',
    }) async {
      setView(tester);
      final session = AssistSession(
        dataset: bundled,
        client: AssistLlmClient(client: fake.client),
        apiKey: key,
        modelOf: () => AssistModel.opus5,
      );
      await tester.pumpWidget(MaterialApp(home: AssistPage(session: session)));
      return session;
    }

    /// 실제 비동기를 한 번 돌린다. 위젯 테스트의 가짜 시계 안에서는 HTTP 스트림이 끝까지 가지 못해
    /// (`pump`만으로는 도구 왕복이 끝나지 않는다 — 실제로 여기서 한 번 걸렸다) [WidgetTester.runAsync]로 나간다.
    Future<void> tick(WidgetTester tester) =>
        tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));

    /// 답이 끝날 때까지 기다린다.
    /// **`pumpAndSettle`을 쓰면 안 된다** — '답 작성 중'의 진행 표시기가 끝없이 프레임을 예약해서
    /// 답이 오기 전에는 영영 가라앉지 않는다.
    Future<void> settle(WidgetTester tester, AssistSession session) async {
      for (var i = 0; i < 200 && session.busy; i++) {
        await tick(tester);
        await tester.pump();
      }
      await tester.pump();
      expect(session.busy, false, reason: '답이 끝나지 않았습니다');
    }

    Future<void> ask(WidgetTester tester, AssistSession session, String question) async {
      await tester.enterText(find.byType(TextField), question);
      await tester.tap(find.text(AssistPageText.send));
      await settle(tester, session);
    }

    testWidgets('답과 근거 칸이 함께 나온다 — 근거는 도구가 돌려준 값이다', (tester) async {
      final fake = FakeAnthropic(
        turns: const [
          FakeTurn(
            toolUses: [
              FakeToolUse('toolu_1', ToolName.search, {'query': '7664-41-7'}),
              FakeToolUse('toolu_2', ToolName.rule, {'topic': 'byeolpyo3'}),
            ],
          ),
          FakeTurn(text: ['성상에 따라 갈립니다.']),
        ],
      );
      final session = await pumpPage(tester, fake);
      await ask(tester, session, '암모니아 0.3톤이면 규정수량 넘나요?');

      expect(find.text('성상에 따라 갈립니다.'), findsOneWidget);
      expect(find.text(AssistPageText.evidence), findsOneWidget);
      // 표 이름(화면 용어)·연번·물질명, 그리고 수량 문자열이 별표(*)까지 그대로 보인다.
      expect(find.text('사고대비물질 제44호 암모니아'), findsOneWidget);
      expect(find.textContaining('최하위 0.5* / 하위 20* / 상위 400*'), findsOneWidget);
      expect(find.textContaining('함량기준 10'), findsWidgets);
      expect(find.textContaining('${AssistPageText.rulesUsed}: byeolpyo3'), findsOneWidget);
      expect(find.textContaining('규정수량에 관한 규정'), findsOneWidget);
      expect(find.text(AssistText.noToolCall), findsNothing);
    });

    testWidgets('도구 호출 0건이면 근거 칸에 그 사실이 보인다', (tester) async {
      final session = await pumpPage(tester, FakeAnthropic(turns: const [FakeTurn(text: ['0.05톤입니다'])]));
      await ask(tester, session, '톨루엔 규정수량?');

      expect(find.text('0.05톤입니다'), findsOneWidget);
      expect(find.text(AssistText.noToolCall), findsOneWidget);
    });

    testWidgets('키가 없는 빌드는 안내를 보이고 질문을 보내지 않는다', (tester) async {
      final fake = FakeAnthropic(turns: const [FakeTurn(text: ['답'])]);
      final session = await pumpPage(tester, fake, key: '');
      await ask(tester, session, '톨루엔 규정수량?');

      expect(fake.callCount, 0);
      expect(find.text(AssistText.noKey), findsWidgets);
    });

    testWidgets('실패 문구가 화면에 그대로 보인다', (tester) async {
      final session = await pumpPage(tester, FakeAnthropic(statusCode: 401));
      await ask(tester, session, '톨루엔 규정수량?');

      expect(find.text(AssistText.badKey), findsOneWidget);
      // 답이 오지 않았으니 근거 칸도 없다 — 오지도 않은 답에 "도구를 부르지 않았다"를 붙이지 않는다.
      expect(find.text(AssistPageText.evidence), findsNothing);
      expect(find.text(AssistText.noToolCall), findsNothing);
    });

    testWidgets('답을 기다리는 동안 답 작성 중 표시가 있고, 조각이 오는 대로 늘어난다', (tester) async {
      final fake = FakeAnthropic()..manualNext();
      final session = await pumpPage(tester, fake);

      await tester.enterText(find.byType(TextField), '암모니아 0.3톤?');
      await tester.tap(find.text(AssistPageText.send));
      await tester.pump();
      expect(find.text(AssistText.thinking), findsOneWidget);

      fake.emit(
        'event: content_block_start\ndata: {"type":"content_block_start","index":0,'
        '"content_block":{"type":"text","text":""}}\n\n'
        'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,'
        '"delta":{"type":"text_delta","text":"성상에 "}}\n\n',
      );
      await tick(tester);
      await tester.pump();
      expect(find.text('성상에 '), findsOneWidget);

      fake.emit(
        'event: content_block_delta\ndata: {"type":"content_block_delta","index":0,'
        '"delta":{"type":"text_delta","text":"따라 갈립니다."}}\n\n'
        'event: message_delta\ndata: {"type":"message_delta","delta":{"stop_reason":"end_turn"}}\n\n',
      );
      await tick(tester);
      await tester.pump();
      expect(find.text('성상에 따라 갈립니다.'), findsOneWidget);

      await fake.endManual();
      await settle(tester, session);
      expect(find.text(AssistText.thinking), findsNothing);
    });
  });
}
