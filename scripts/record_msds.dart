// A-003 녹화 — KOSHA MSDS 실호출 원문 XML을 test/fixtures/msds/에 저장한다(REQUIREMENTS_AGENT A-003 Q2).
//
//   dart run scripts/record_msds.dart               → 기본 표본 CAS 전부
//   dart run scripts/record_msds.dart 50-00-0 ...   → 지정한 CAS만
//
// - 키는 환경 변수 `DATA_GO_KR_KEY`에서만 읽는다(클라우드 환경 설정 — 저장소·채팅에 두지 않는다). 없으면 호출 0회로 끝낸다.
// - 원문을 **고치지 않고** 저장한다. 단 키 문자열이 응답에 들어 있으면 저장하지 않고 실패로 끝낸다(키가 커밋되지 않게).
// - 목록(getChemList001) → casNo 완전 일치 행의 chemId마다 상세 021·081·091. 상세는 numOfRows를 넣지 않는다 —
//   기본 쪽 크기로 잘리는지(totalCount 대조)를 녹화본으로 확인하려는 것이다(A-003 2차 '상세 쪽 나눔').
// - 틀린 키 응답도 한 건 녹화한다(실패 문구 테스트용).
// - 호출 수: CAS당 목록 1 + 완전 일치 수 × 3. 기본 표본 9개 ≈ 30회(개발 계정 하루 2,000건).
// - Flutter에 의존하지 않는다 — `dart run`으로 돈다.
import 'dart:convert';
import 'dart:io';

import 'package:findchem/lookup/portal.dart';
import 'package:findchem/msds/msds_client.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

const outDir = 'test/fixtures/msds';

/// 기본 표본: 비중 실측 5종(마지막은 비중 '자료없음') + 그림문자 03·04 실측 3종 + 없는 CAS.
const defaultCas = [
  '50-00-0', // 포름알데히드 — 목록에 부분 일치 13150-00-0이 섞여 온다
  '108-88-3', // 톨루엔
  '67-56-1', // 메탄올
  '7664-93-9', // 황산
  '13516-27-3', // 구아자틴 — 비중 자료없음
  '7727-37-9', // 질소 — KOSHA GHS03(표준 GHS04)
  '7722-84-1', // 과산화수소 — KOSHA GHS04(표준 GHS03)
  '7782-44-7', // 산소 — 03+04
  '99999-99-9', // 없는 CAS
];

const detailSections = ['02', '08', '09'];

Future<void> main(List<String> args) async {
  final key = Platform.environment['DATA_GO_KR_KEY'] ?? '';
  if (key.trim().isEmpty) {
    stderr.writeln('record_msds: 환경 변수 DATA_GO_KR_KEY가 비어 있다 — 호출하지 않고 끝낸다(클라우드 환경 설정에 키를 넣고 새 세션에서 돌릴 것).');
    exitCode = 2;
    return;
  }
  final cases = args.isEmpty ? defaultCas : args;
  final client = http.Client();
  Directory(outDir).createSync(recursive: true);
  var failures = 0;

  Future<String?> get(String path, String query, String file) async {
    final uri = msdsRequestUri(key, path, query);
    http.Response? res;
    // 클라우드 프록시가 연결을 간헐적으로 끊는다(2026-10-02 실측 9/30) — 접속 실패만 3회까지 다시 부른다
    for (var attempt = 1; res == null; attempt++) {
      try {
        res = await client.get(uri).timeout(const Duration(seconds: 30));
      } catch (e) {
        stderr.writeln('  접속 실패 $file (시도 $attempt/3): ${maskKey('$e', key)}');
        if (attempt >= 3) {
          failures++;
          return null;
        }
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
      }
    }
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    if (maskKey(body, key) != body) {
      stderr.writeln('  실패 $file: 키 문자열이 응답에 있다 — 저장하지 않는다');
      failures++;
      return null;
    }
    File('$outDir/$file').writeAsBytesSync(res.bodyBytes); // 원문 바이트 그대로
    final portal = portalReasonCode(body);
    stdout.writeln('  저장 $file (HTTP ${res.statusCode}${portal == null ? '' : ', 포털 코드 $portal'}, ${res.bodyBytes.length}바이트)');
    if (res.statusCode != 200 || portal != null) failures++;
    return body;
  }

  for (final cas in cases) {
    stdout.writeln('CAS $cas');
    final listFile = 'list_$cas.xml';
    final raw = await get('getChemList001', 'searchWrd=${Uri.encodeQueryComponent(cas)}&searchCnd=1&numOfRows=100&pageNo=1', listFile);
    if (raw == null) continue;
    final List<String> ids;
    try {
      final doc = XmlDocument.parse(raw);
      ids = [
        for (final item in doc.findAllElements('item'))
          if ((item.getElement('casNo')?.innerText.trim() ?? '') == cas) item.getElement('chemId')?.innerText.trim() ?? '',
      ].where((s) => s.isNotEmpty).toList();
      final total = doc.findAllElements('totalCount').firstOrNull?.innerText.trim();
      final items = doc.findAllElements('item').length;
      stdout.writeln('  목록 totalCount=$total, 받은 행=$items, casNo 완전 일치=${ids.length}');
    } catch (e) {
      stderr.writeln('  목록 해석 실패(원문은 저장됨): ${e.runtimeType}: $e');
      failures++;
      continue;
    }
    for (final id in ids) {
      for (final s in detailSections) {
        await get('getChemDetail${s}1', 'chemId=$id', 'detail${s}_$id.xml');
      }
    }
  }

  stdout.writeln('틀린 키 응답');
  await () async {
    final uri = msdsRequestUri('INVALID_KEY_FOR_FIXTURE', 'getChemList001', 'searchWrd=50-00-0&searchCnd=1');
    try {
      final res = await client.get(uri).timeout(const Duration(seconds: 30));
      File('$outDir/error_badkey.xml').writeAsBytesSync(res.bodyBytes);
      stdout.writeln('  저장 error_badkey.xml (HTTP ${res.statusCode}, 포털 코드 ${portalReasonCode(utf8.decode(res.bodyBytes, allowMalformed: true))})');
    } catch (e) {
      stderr.writeln('  실패 error_badkey.xml: $e');
      failures++;
    }
  }();

  client.close();
  stdout.writeln(failures == 0 ? '끝 — 실패 0' : '끝 — 실패·비정상 응답 $failures건(위 줄 참고)');
  if (failures > 0) exitCode = 1;
}
