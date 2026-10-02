// A-003 1차 — 녹화 스크립트는 키가 없으면 호출 0회로 끝나고 이유를 낸다(REQUIREMENTS_AGENT A-003 '1차 — 구조').
// 실호출은 하지 않는다 — 키를 비운 환경으로만 돌린다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DATA_GO_KR_KEY가 비면 호출하지 않고 이유를 출력하며 파일을 쓰지 않는다', () async {
    final dir = Directory('test/fixtures/msds');
    final before = dir.existsSync() ? dir.listSync().length : 0;

    final r = await Process.run(
      'dart',
      ['run', 'scripts/record_msds.dart', '50-00-0'],
      environment: {'DATA_GO_KR_KEY': ''},
    );

    expect(r.exitCode, 2, reason: '${r.stdout}\n${r.stderr}');
    expect('${r.stderr}', contains('DATA_GO_KR_KEY'));
    expect('${r.stdout}', isNot(contains('저장')));
    expect(dir.existsSync() ? dir.listSync().length : 0, before);
  }, timeout: const Timeout(Duration(minutes: 3)));
}
