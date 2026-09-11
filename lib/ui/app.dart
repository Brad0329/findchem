/// 앱 뼈대: 테마(REQUIREMENTS '화면 방향' 3·4) + 데이터 로딩 → 검색 화면. 설정 화면은 헤더 메뉴에서 push.
library;

import 'package:flutter/material.dart';

import '../data/dataset_loader.dart';
import '../data/update_store.dart';
import 'app_header.dart';
import 'search_page.dart';
import 'settings_page.dart';

/// 룩앤필: Material 3, 아이콘 파랑을 시드로, 시스템 따라 라이트/다크.
const seedColor = Color(0xFF2E7FE0);

class FindChemApp extends StatefulWidget {
  const FindChemApp({super.key, this.controller, this.pickPdf = pickPdfWithFilePicker});

  /// 테스트에서 저장소·번들을 바꿔 넣을 때. null이면 이 플랫폼의 저장본 자리 + 실제 번들.
  final DataController? controller;
  final PdfPicker pickPdf;

  @override
  State<FindChemApp> createState() => _FindChemAppState();
}

class _FindChemAppState extends State<FindChemApp> {
  late final DataController _controller = widget.controller ?? DataController(store: platformUpdateStore());
  late final Future<LoadedData> _loading = _controller.load();

  void _onMenu(BuildContext context, HeaderMenu item) {
    switch (item) {
      case HeaderMenu.settings:
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SettingsPage(controller: _controller, pickPdf: widget.pickPdf),
          ),
        );
    }
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
              onMenu: (item) => _onMenu(context, item),
            ),
          );
        },
      ),
    );
  }
}
