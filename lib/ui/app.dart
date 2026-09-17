/// 앱 뼈대: 테마(REQUIREMENTS '화면 방향' 3·4) + 데이터 로딩 → 검색 화면. 저장 목록·설정 화면은 헤더 메뉴에서 push.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../assist/llm_client.dart';
import '../assist/session.dart';
import '../data/dataset_loader.dart';
import '../data/favorites.dart';
import '../data/update_store.dart';
import '../lookup/api_settings.dart';
import '../lookup/chem_api.dart';
import 'app_header.dart';
import 'assist_page.dart';
import 'cas_lookup_panel.dart';
import 'favorites_page.dart';
import 'search_page.dart';
import 'settings_page.dart';

/// 룩앤필: Material 3, 아이콘 파랑을 시드로, 시스템 따라 라이트/다크.
const seedColor = Color(0xFF2E7FE0);

class FindChemApp extends StatefulWidget {
  const FindChemApp({
    super.key,
    this.controller,
    this.favorites,
    this.pickPdf = pickPdfWithFilePicker,
    this.apiSettings,
    this.apiClient,
    this.assistClient,
    this.assistKey,
    bool? lookupEnabled,
    bool? assistEnabled,
  }) : lookupEnabled = lookupEnabled ?? apiLookupEnabledByDefault,
       assistEnabled = assistEnabled ?? assistEnabledByDefault;

  /// 테스트에서 저장소·번들을 바꿔 넣을 때. null이면 이 플랫폼의 저장본 자리 + 실제 번들.
  final DataController? controller;

  /// 테스트에서 저장 목록 자리를 바꿔 넣을 때. null이면 이 플랫폼의 저장 목록 자리(F-005).
  final FavoritesController? favorites;
  final PdfPicker pickPdf;

  /// F-007 CAS 조회를 켤지. 기본값은 웹만(`apiLookupEnabledByDefault`) — 테스트에서만 직접 넣는다.
  final bool lookupEnabled;

  /// 테스트에서 F-007 설정 자리·HTTP를 바꿔 넣을 때. null이면 이 플랫폼의 자리 + 실제 호출.
  final ApiSettingsController? apiSettings;
  final ChemApiClient? apiClient;

  /// F-008 판정을 켤지. 기본값은 앱·웹 둘 다(`assistEnabledByDefault`) — 테스트에서만 직접 넣는다.
  final bool assistEnabled;

  /// 테스트에서 LLM 호출을 바꿔 넣을 때. null이면 실제 호출.
  final AssistLlmClient? assistClient;

  /// 테스트에서 키를 바꿔 넣을 때. null이면 빌드에 들어간 기본 키(`--dart-define`).
  final String? assistKey;

  @override
  State<FindChemApp> createState() => _FindChemAppState();
}

class _FindChemAppState extends State<FindChemApp> {
  late final DataController _controller = widget.controller ?? DataController(store: platformUpdateStore());
  late final FavoritesController _favorites =
      widget.favorites ?? FavoritesController(store: platformFavoritesStore());
  late final Future<LoadedData> _loading = _controller.load();

  /// 설정 저장소는 **언제나** 만든다 — F-007 조회는 웹만이지만 F-008 판정 설정(키·모델)은 앱에도 있다.
  late final ApiSettingsController _apiSettings =
      widget.apiSettings ?? ApiSettingsController(store: platformApiSettingsStore());
  late final CasLookup? _lookup = widget.lookupEnabled
      ? CasLookup(settings: _apiSettings, client: widget.apiClient ?? ChemApiClient())
      : null;
  late final AssistLlmClient _assistClient = widget.assistClient ?? AssistLlmClient();

  @override
  void initState() {
    super.initState();
    // 저장 목록은 검색을 막지 않게 따로 읽는다. load는 실패를 예외 대신 loadFailed로 남긴다(목록 화면에 사유).
    unawaited(_favorites.load());
    // 설정 파일도 따로 읽는다(F-007 키·체크 + F-008 키·모델). 깨진 파일은 loadError로 남는다(설정 카드에 사유).
    unawaited(_apiSettings.load());
  }

  void _onMenu(BuildContext context, HeaderMenu item) {
    final page = switch (item) {
      HeaderMenu.favorites => FavoritesPage(favorites: _favorites, data: _controller),
      // 대화는 화면을 나가면 사라진다(저장하지 않는다) — 열 때마다 새 세션을 만든다.
      HeaderMenu.assist => AssistPage(
        session: AssistSession(
          dataset: _controller.data!.dataset,
          client: _assistClient,
          // 사용자 키가 우선, 없으면 빌드 기본 키. 테스트만 직접 넣는다.
          apiKey: widget.assistKey ?? _apiSettings.effectiveAnthropicKey ?? '',
          // 보낼 때마다 설정에서 다시 읽는다 — 설정에서 바꾸면 다음 질문부터 그 모델이다.
          modelOf: () => _apiSettings.assistModel,
        ),
      ),
      HeaderMenu.settings => SettingsPage(
        controller: _controller,
        favorites: _favorites,
        pickPdf: widget.pickPdf,
        lookup: _lookup,
        assistSettings: widget.assistEnabled ? _apiSettings : null,
        assistClient: _assistClient,
      ),
    };
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FindChem',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seedColor)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark),
      ),
      themeMode: ThemeMode.system,
      home: FutureBuilder<LoadedData>(
        future: _loading,
        builder: (context, snap) {
          if (snap.hasError) {
            // 번들 JSON을 못 읽으면 검색이 불가능하다 — 숨기지 않고 화면에 그대로 보여준다.
            debugPrint('데이터 로딩 실패: ${snap.error}\n${snap.stackTrace}');
            return Scaffold(
              appBar: const AppHeader(),
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('데이터를 읽지 못했습니다.\n${snap.error}'),
              ),
            );
          }
          if (!snap.hasData) {
            return const Scaffold(appBar: AppHeader(), body: Center(child: CircularProgressIndicator()));
          }
          // 적용·되돌리기가 끝나면 컨트롤러가 알린다 → 검색 화면이 새 데이터로 다시 색인한다.
          return ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => SearchPage(
              dataset: _controller.data!.dataset,
              favorites: _favorites,
              lookup: _lookup,
              showAssist: widget.assistEnabled,
              onMenu: (item) => _onMenu(context, item),
            ),
          );
        },
      ),
    );
  }
}
