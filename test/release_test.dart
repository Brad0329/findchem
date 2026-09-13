/// F-006 배포 — 앱 버전 사본이 pubspec과 같은지, 받기 페이지의 링크가 최신 릴리스의 findchem.apk를 가리키는지.
library;

import 'dart:io';

import 'package:findchem/app_version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('lib/app_version.dart = pubspec.yaml version (버전의 원본은 pubspec)', () {
    final m = RegExp(r'^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$', multiLine: true)
        .firstMatch(File('pubspec.yaml').readAsStringSync());
    expect(m, isNotNull, reason: 'pubspec version은 X.Y.Z+N 형식');
    expect(appVersion, m!.group(1));
    expect(appBuildNumber, int.parse(m.group(2)!));
  });

  group('web/download/index.html', () {
    late String html;
    setUpAll(() => html = File('web/download/index.html').readAsStringSync());

    List<String> hrefs() => [for (final m in RegExp(r'href="([^"]*)"').allMatches(html)) m.group(1)!];

    test('받기 링크는 최신 릴리스의 findchem.apk 하나, 최신 릴리스 페이지·웹 앱 링크가 있다', () {
      const apk = 'https://github.com/Brad0329/findchem/releases/latest/download/findchem.apk';
      expect(hrefs().where((h) => h.endsWith('.apk')), [apk]);
      expect(hrefs(), containsAll(['https://github.com/Brad0329/findchem/releases/latest', '../']));
    });

    test('설치 안내: 출처를 알 수 없는 앱, Play 프로텍트, 덮어 설치(목록 유지), 설정의 앱 버전', () {
      for (final phrase in ['출처를 알 수 없는 앱', 'Play 프로텍트', '덮어 설치', '자주보는 Chem 목록', '앱 버전']) {
        expect(html, contains(phrase), reason: phrase);
      }
    });

    test('스크립트·입력 폼이 없는 정적 페이지다(보안 3층 — 새 공개 표면이지만 입력을 받지 않는다)', () {
      expect(html.toLowerCase(), isNot(contains('<script')));
      expect(html.toLowerCase(), isNot(contains('<form')));
      expect(html.toLowerCase(), isNot(contains('<input')));
    });
  });
}
