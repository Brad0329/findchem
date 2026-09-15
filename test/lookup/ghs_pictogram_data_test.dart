/// F-007 GHS 그림문자 대응표(생성물 lib/lookup/ghs_pictogram_data.dart) ↔ 그림 파일(assets/data/ghs/) 대조.
/// 표에만 있고 그림이 없거나(화면에 '그림 없음'), 그림만 남는 어긋남을 잡는다. 번들 등록(pubspec)까지 확인한다.
library;

import 'dart:io';

import 'package:findchem/lookup/ghs_pictogram_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('대응표는 GHS01~GHS09 9종이고 분류가 비지 않았다', () {
    expect(ghsPictogramLabels.keys, [for (var i = 1; i <= 9; i++) 'GHS0$i']);
    for (final e in ghsPictogramLabels.entries) {
      expect(e.value, isNotEmpty, reason: e.key);
      expect(e.value.every((s) => s.trim().isNotEmpty && s == s.trim()), isTrue, reason: e.key);
    }
    expect(ghsPictogramLabels['GHS04'], ['고압가스']);
  });

  test('assets/data/ghs/의 그림 파일은 대응표의 코드와 정확히 같다', () {
    final files = Directory('assets/data/ghs').listSync().whereType<File>().map((f) => f.uri.pathSegments.last).toList()
      ..sort();
    expect(files, [for (final c in ghsPictogramLabels.keys) '$c.png']);
  });

  // rootBundle.load로는 확인하지 않는다 — 테스트용 번들(build/unit_test_assets)이 옛 파일을 들고 있어
  // 그림을 지워도 통과했다(2026-09-15 변이 확인). pubspec 등록은 글자로, 파일은 디스크에서 직접 본다.
  test('pubspec이 assets/data/ghs/를 번들에 등록한다(폴더 등록은 하위 폴더를 포함하지 않는다)', () {
    final lines = File('pubspec.yaml').readAsLinesSync().map((l) => l.trim());
    expect(lines, contains('- assets/data/ghs/'));
  });

  test('코드마다 그림 파일이 PNG다', () {
    const pngSignature = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
    for (final code in ghsPictogramLabels.keys) {
      final bytes = File(ghsPictogramAsset(code)).readAsBytesSync();
      expect(bytes.take(8), pngSignature, reason: code);
    }
  });
}
