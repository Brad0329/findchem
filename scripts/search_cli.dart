// F-008 개발 하네스 — 도구 응답 JSON 하나를 stdout에 낸다.
//
//   dart run scripts/search_cli.dart "<물질명 또는 CAS>"   → 검색 응답
//   dart run scripts/search_cli.dart --rule <주제>          → 규칙 원문(주제: all | byeolpyo2 | byeolpyo3 | byeolpyo4 | byeolpyo1)
//   dart run scripts/search_cli.dart --tools                → 시스템 프롬프트 + 도구 정의(앱ㆍ웹이 쓰는 그 원본)
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
import 'package:findchem/assist/prompt.dart';
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
  if (args.length == 1 && args.single == '--tools') {
    // 시스템 프롬프트ㆍ도구 설명의 **원본은 `lib/assist/prompt.dart` 하나다**(REQUIREMENTS F-008 2단계).
    // MCP 서버(개발 하네스)가 이것을 읽어 쓴다 — 베껴 두면 앱과 하네스가 어긋난다.
    emit({'systemPrompt': assistSystemPrompt, 'tools': assistToolDefinitions()});
    return;
  }
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

  // 상한은 **앱ㆍ웹 판정 도구와 같은 값**([assistSearchCap])이다 — 개발 하네스가 앱과 다른 건수를 주면
  // 여기서 통과한 질문이 앱에서 다르게 답한다(2026-09-16 상한 100→20 결정이 이 파일에만 안 닿아 있었다).
  emit(searchResponse(SearchIndex(ds, cap: assistSearchCap).search(args.single), ds));
}
