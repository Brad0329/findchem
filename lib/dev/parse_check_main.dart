// 개발용 진입점: 기기(웹·Android)에서 Dart 파서를 돌려 번들 JSON과 같은 결과가 나오는지 확인한다 (Phase 003 게이트).
// 앱 본체가 아니다 — main.dart는 이 파일을 참조하지 않는다.
//
// 쓰는 법 — 원천 PDF는 번들하지 않으므로 확인할 때만 임시로 넣고, 끝나면 pubspec을 되돌린다:
//   1. assets/의 PDF 2개를 build/check_assets/byeolpyo2.pdf, byeolpyo3.pdf 로 복사한다(ASCII 이름 — 원래 한글
//      파일명은 URL 인코딩되면 Windows 경로 길이를 넘겨 웹 빌드가 실패한다, 2026-09-11 실측)
//   2. pubspec.yaml의 assets에 `- build/check_assets/` 한 줄을 임시로 넣는다
//   3. flutter build web -t lib/dev/parse_check_main.dart  → build/web 을 .claude/launch.json의 web-build로 띄운다
//      flutter build apk --split-per-abi -t lib/dev/parse_check_main.dart → adb install
// 화면에 "일치 1657/1657"이 나와야 통과. 다르면 첫 불일치 20건을 보여준다.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../parser/entry_builder.dart';
import '../parser/models.dart';
import '../parser/pdf_extractor.dart';

const _pdfKeys = {
  Source.byeolpyo2: 'build/check_assets/byeolpyo2.pdf',
  Source.byeolpyo3: 'build/check_assets/byeolpyo3.pdf',
};

void main() => runApp(const MaterialApp(home: _ParseCheckPage()));

class _ParseCheckPage extends StatefulWidget {
  const _ParseCheckPage();

  @override
  State<_ParseCheckPage> createState() => _ParseCheckPageState();
}

class _ParseCheckPageState extends State<_ParseCheckPage> {
  String _report = '파싱 중…';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    final lines = <String>[];
    try {
      final bundled = Dataset.fromJson(
        (jsonDecode(await rootBundle.loadString('assets/data/findchem_data.json')) as Map).cast<String, Object?>(),
      );
      final parsed = <Entry>[];
      final sw = Stopwatch()..start();
      for (final src in Source.values) {
        final bytes = (await rootBundle.load(_pdfKeys[src]!)).buffer.asUint8List();
        final t0 = sw.elapsedMilliseconds;
        final extracted = PdfTableExtractor.extract(bytes);
        final built = buildEntries(src, extracted.pages);
        parsed.addAll(built.entries);
        lines.add('${src.label}: ${extracted.pageCount}쪽 → ${built.entries.length}건, '
            '경고 ${built.warnings.length}건, ${sw.elapsedMilliseconds - t0}ms, 생성일 ${extracted.created}');
        lines.addAll(built.warnings.map((w) => '  경고: $w'));
      }
      final mismatches = <String>[];
      if (parsed.length != bundled.entries.length) {
        mismatches.add('건수 ${parsed.length} != 번들 ${bundled.entries.length}');
      }
      for (var i = 0; i < parsed.length && i < bundled.entries.length; i++) {
        final a = jsonEncode(parsed[i].toJson());
        final b = jsonEncode(bundled.entries[i].toJson());
        if (a != b) mismatches.add('${parsed[i].src.id} ${parsed[i].no}: $a\n  != $b');
      }
      lines.add(mismatches.isEmpty
          ? '일치 ${parsed.length}/${bundled.entries.length}'
          : '불일치 ${mismatches.length}건:\n${mismatches.take(20).join('\n')}');
    } catch (e, st) {
      lines.add('실패: $e\n$st');
    }
    setState(() => _report = lines.join('\n'));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('FindChem 파서 확인')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: SelectableText(_report, key: const Key('report')),
        ),
      );
}
