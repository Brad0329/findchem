/// 앱 뼈대: 테마(REQUIREMENTS '화면 방향' 3·4) + 데이터 로딩 → 검색 화면.
library;

import 'package:flutter/material.dart';

import '../data/dataset_loader.dart';
import '../parser/models.dart';
import 'app_header.dart';
import 'search_page.dart';

/// 룩앤필: Material 3, 아이콘 파랑을 시드로, 시스템 따라 라이트/다크.
const seedColor = Color(0xFF2E7FE0);

class FindChemApp extends StatefulWidget {
  const FindChemApp({super.key, this.dataset});

  /// 테스트에서 데이터를 직접 넣을 때. null이면 [loadDataset]으로 읽는다.
  final Future<Dataset>? dataset;

  @override
  State<FindChemApp> createState() => _FindChemAppState();
}

class _FindChemAppState extends State<FindChemApp> {
  late final Future<Dataset> _dataset = widget.dataset ?? loadDataset();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FindChem',
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seedColor)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seedColor, brightness: Brightness.dark),
      ),
      themeMode: ThemeMode.system,
      home: FutureBuilder<Dataset>(
        future: _dataset,
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
          final ds = snap.data;
          if (ds == null) {
            return const Scaffold(appBar: AppHeader(), body: Center(child: CircularProgressIndicator()));
          }
          return SearchPage(dataset: ds);
        },
      ),
    );
  }
}
