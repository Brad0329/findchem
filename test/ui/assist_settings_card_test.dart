/// F-008 2단계 수용 기준 — 설정의 Anthropic 키(사용자 키 우선)와 모델 선택.
/// 저장 자리는 메모리, LLM은 고정 응답(fixture).
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/assist/llm_client.dart';
import 'package:findchem/data/dataset_loader.dart';
import 'package:findchem/lookup/api_settings.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/ui/app.dart';
import 'package:findchem/ui/app_header.dart';
import 'package:findchem/ui/assist_settings_card.dart';
import 'package:findchem/ui/search_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../assist/fake_llm.dart';
import '../data/fakes.dart';

void main() {
  late Dataset bundled;

  setUpAll(() {
    bundled = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
  });

  group('저장 형식 (SCHEMA.md 판정 설정)', () {
    Future<ApiSettingsController> loaded(String? stored) async {
      final c = ApiSettingsController(store: MemoryUpdateStore(stored), defaultKey: '');
      await c.load();
      return c;
    }

    test('필드가 없는 기존 저장본도 그대로 읽힌다 — 기본값 Opus 5, 사용자 키 없음(마이그레이션 없음)', () async {
      final c = await loaded('{"version":1,"serviceKey":"abc","services":{"chem":false}}');
      expect(c.loadError, isNull);
      expect(c.serviceKey, 'abc');
      expect(c.enabled(ChemService.chem), false);
      expect(c.anthropicKey, isNull);
      expect(c.assistModel, AssistModel.opus5);
    });

    test('모르는 모델 ID는 기본값으로 떨어진다(깨진 파일로 보지 않는다)', () async {
      final c = await loaded('{"version":1,"assistModel":"claude-opus-4-8"}');
      expect(c.loadError, isNull);
      expect(c.assistModel, AssistModel.opus5);
    });

    test('키와 모델을 저장하면 다시 읽어도 남는다. 한쪽을 바꿔도 옆 필드가 지워지지 않는다', () async {
      final store = MemoryUpdateStore();
      final c = ApiSettingsController(store: store, defaultKey: '');
      await c.load();
      await c.saveKey('data-key');
      await c.saveAnthropicKey('sk-ant-user');
      await c.setAssistModel(AssistModel.sonnet5);

      final again = ApiSettingsController(store: store, defaultKey: '');
      await again.load();
      expect(again.serviceKey, 'data-key');
      expect(again.anthropicKey, 'sk-ant-user');
      expect(again.assistModel, AssistModel.sonnet5);
    });

    test('Anthropic 키를 지워도 data.go.kr 키는 남는다(파일을 지우지 않는다)', () async {
      final store = MemoryUpdateStore();
      final c = ApiSettingsController(store: store, defaultKey: '');
      await c.load();
      await c.saveKey('data-key');
      await c.saveAnthropicKey('sk-ant-user');
      await c.deleteAnthropicKey();

      expect(c.anthropicKey, isNull);
      expect(c.serviceKey, 'data-key');
      expect(store.value, isNotNull);
    });

    test('사용자 키가 있으면 우선, 없으면 기본 키, 둘 다 없으면 null', () async {
      final c = ApiSettingsController(store: MemoryUpdateStore(), defaultKey: '');
      await c.load();
      expect(c.effectiveAnthropicKey, isNull);

      await c.saveAnthropicKey('sk-ant-user');
      expect(c.effectiveAnthropicKey, 'sk-ant-user');
      expect(c.usingDefaultAnthropicKey, false);
    });
  });

  group('설정 카드', () {
    Future<ApiSettingsController> pumpCard(
      WidgetTester tester, {
      required FakeAnthropic fake,
      String? stored,
    }) async {
      tester.view.physicalSize = const Size(600, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = ApiSettingsController(store: MemoryUpdateStore(stored), defaultKey: '');
      await settings.load();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AssistSettingsCardBody(
                settings: settings,
                client: AssistLlmClient(client: fake.client),
              ),
            ),
          ),
        ),
      );
      return settings;
    }

    testWidgets('키는 가려져 있고 눈 아이콘으로 보였다 가렸다 한다', (tester) async {
      await pumpCard(tester, fake: FakeAnthropic());
      TextField field() => tester.widget<TextField>(find.byKey(const ValueKey('assist-key-field')));

      expect(field().obscureText, true);
      await tester.tap(find.byTooltip(AssistSettingsText.show));
      await tester.pump();
      expect(field().obscureText, false);

      await tester.tap(find.byTooltip(AssistSettingsText.hide));
      await tester.pump();
      expect(field().obscureText, true);
    });

    testWidgets('[저장] → 저장되고, [삭제] → 지워진다. 빈 칸으로 저장하면 안내만', (tester) async {
      final settings = await pumpCard(tester, fake: FakeAnthropic());

      await tester.tap(find.text(AssistSettingsText.save));
      await tester.pumpAndSettle();
      expect(find.text(AssistSettingsText.enterKey), findsOneWidget);
      expect(settings.anthropicKey, isNull);

      await tester.enterText(find.byKey(const ValueKey('assist-key-field')), 'sk-ant-user');
      await tester.tap(find.text(AssistSettingsText.save));
      await tester.pumpAndSettle();
      expect(settings.anthropicKey, 'sk-ant-user');

      await tester.tap(find.text(AssistSettingsText.delete));
      await tester.pumpAndSettle();
      expect(settings.anthropicKey, isNull);
    });

    testWidgets('[키 확인]은 max_tokens 1로 한 번만 부르고 저장하지 않는다', (tester) async {
      final fake = FakeAnthropic(turns: const [FakeTurn(text: ['x'])]);
      final settings = await pumpCard(tester, fake: fake);

      await tester.enterText(find.byKey(const ValueKey('assist-key-field')), 'sk-ant-user');
      await tester.tap(find.text(AssistSettingsText.verify));
      await tester.pumpAndSettle();

      expect(fake.callCount, 1);
      expect(fake.bodies.single['max_tokens'], 1);
      expect(fake.bodies.single['stream'], isNull);
      expect(fake.headers.single['x-api-key'], 'sk-ant-user');
      expect(find.text(KeyCheck.ok.message), findsOneWidget);
      expect(settings.anthropicKey, isNull, reason: '확인은 저장이 아니다');
    });

    testWidgets('인증 실패와 접속 실패는 문구가 다르다 — 멀쩡한 키를 지우게 하지 않는다', (tester) async {
      await pumpCard(tester, fake: FakeAnthropic(statusCode: 401));
      await tester.enterText(find.byKey(const ValueKey('assist-key-field')), 'bad');
      await tester.tap(find.text(AssistSettingsText.verify));
      await tester.pumpAndSettle();
      expect(find.text(KeyCheck.badKey.message), findsOneWidget);
      expect(KeyCheck.badKey.message, isNot(KeyCheck.offline.message));
    });

    testWidgets('모델 라디오에 실제 모델 ID가 보이고, 고르면 저장된다', (tester) async {
      final settings = await pumpCard(tester, fake: FakeAnthropic());

      expect(find.textContaining('claude-opus-5'), findsOneWidget);
      expect(find.textContaining('claude-sonnet-5'), findsOneWidget);

      await tester.tap(find.text(AssistModel.sonnet5.label));
      await tester.pumpAndSettle();
      expect(settings.assistModel, AssistModel.sonnet5);
    });
  });

  testWidgets('설정에서 Sonnet 5를 고르면 판정 요청 본문의 모델 ID가 바뀐다', (tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final fake = FakeAnthropic(turns: const [FakeTurn(text: ['답'])]);
    final settings = ApiSettingsController(store: MemoryUpdateStore(), defaultKey: '');
    await tester.pumpWidget(
      FindChemApp(
        controller: DataController(store: MemoryUpdateStore(), loadBundled: () async => bundled),
        apiSettings: settings,
        assistClient: AssistLlmClient(client: fake.client),
        assistKey: 'test-key',
      ),
    );
    for (var i = 0; i < 5 && find.byType(SearchPage).evaluate().isEmpty; i++) {
      await tester.pump();
    }

    // 설정 → 판정 카드에서 Sonnet 5를 고른다.
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(HeaderText.settings));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AssistSettingsText.card));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AssistModel.sonnet5.label));
    await tester.pumpAndSettle();
    expect(settings.assistModel, AssistModel.sonnet5);

    // 판정 화면에서 질문하면 그 모델로 부른다.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text(HeaderText.assist));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '톨루엔 규정수량?');
    await tester.tap(find.text('보내기'));
    // 가짜 시계 안에서는 HTTP 스트림이 끝까지 가지 못한다 — 실제 비동기로 나간다(assist_page_test와 같은 이유).
    for (var i = 0; i < 200 && fake.callCount == 0; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }

    expect(fake.bodies.single['model'], 'claude-sonnet-5');
  });
}
