// F-008 개발 하네스 — 도구 응답 JSON 하나를 stdout에 낸다.
//
//   dart run scripts/search_cli.dart "<물질명 또는 CAS>"   → 검색 응답
//   dart run scripts/search_cli.dart --rule <주제>          → 규칙 원문(주제: all | byeolpyo2 | byeolpyo3 | byeolpyo4 | byeolpyo1)
//
// - **여기에는 규칙도 문장도 없다.** 응답 조립은 전부 `lib/assist/`(앱ㆍ웹 tool use가 쓸 바로 그 코드)가 하고,
//   검색ㆍ정규화ㆍCAS 처리는 `lib/search/`가 한다. 이 파일은 번들 JSON을 읽어 그 함수를 부르고 찍는 껍데기다
//   (CLAUDE.md '같은 규칙이 두 곳' — 재구현하면 대조 테스트가 또 필요해진다).
// - 번들 JSON 하나만 읽는다. 기기 저장본(F-002)은 보지 않는다 — 하네스 범위.
// - 판정(합산ㆍ초과 비교)은 하지 않는다. 조합은 LLM이 한다(F-008 결정 4).
// - Flutter에 의존하는 것(lib/ui)은 import하지 않는다 — `dart run`으로 돌아야 한다.
import 'dart:convert';
import 'dart:io';

import 'package:findchem/assist/assist_response.dart';
import 'package:findchem/assist/rules.dart';
import 'package:findchem/parser/models.dart';
import 'package:findchem/search/search.dart';

const dataPath = 'assets/data/findchem_data.json';

final usage = '사용법: dart run scripts/search_cli.dart "<물질명 또는 CAS>"\n'
    '        dart run scripts/search_cli.dart --rule <${(['all', ...ruleTopics]).join(' | ')}>';

/// [dataPath]를 현재 디렉토리 기준으로 찾고, 없으면 이 스크립트 위치(scripts/) 기준으로 한 번 더 찾는다.
/// MCP 서버가 다른 작업 디렉토리에서 부를 수 있어서다.
File findData() {
  final fromCwd = File(dataPath);
  if (fromCwd.existsSync()) return fromCwd;
  final fromScript = File.fromUri(Platform.script.resolve('../$dataPath'));
  if (fromScript.existsSync()) return fromScript;
  fail('번들 JSON을 찾지 못했습니다: ${fromCwd.absolute.path} / ${fromScript.path}');
}

Never fail(String message) {
  stderr.add(utf8.encode('$message\n'));
  exit(2);
}

void emit(Map<String, Object?> out) =>
    stdout.add(utf8.encode('${const JsonEncoder.withIndent('  ').convert(out)}\n'));

void main(List<String> args) {
  if (args.isNotEmpty && args.first == '--rule') {
    if (args.length != 2) fail(usage);
    try {
      emit(ruleResponse(args[1]));
    } on UnknownRuleTopic catch (e) {
      // 조용히 전체로 대체하지 않는다(REQUIREMENTS F-008 수용 기준).
      fail('$e');
    }
    return;
  }
  if (args.length != 1 || args.single.trim().isEmpty) fail(usage);

  final file = findData();
  final Dataset ds;
  try {
    ds = Dataset.fromJson((jsonDecode(file.readAsStringSync()) as Map).cast<String, Object?>());
  } on FormatException catch (e) {
    fail('번들 JSON을 읽지 못했습니다(${file.path}): $e');
  }

  emit(searchResponse(SearchIndex(ds).search(args.single), ds));
}
