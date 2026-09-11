import 'package:flutter/material.dart';

void main() {
  runApp(const FindChemApp());
}

/// 앱 뼈대. 검색 화면은 F-001(Phase 004)에서 '화면 방향'을 정한 뒤 만든다 — 지금은 자리표시만 둔다.
class FindChemApp extends StatelessWidget {
  const FindChemApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'FindChem',
      home: Scaffold(body: Center(child: Text('FindChem'))),
    );
  }
}
