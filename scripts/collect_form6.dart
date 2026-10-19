// A-010 수집 — 6호서식 상수의 원천 API 응답 원문을 assets/form6/raw/에 저장한다(REQUIREMENTS_AGENT A-010 D2).
//
//   dart run scripts/collect_form6.dart               → 대상 CAS 전부(번들 별표 3)
//   dart run scripts/collect_form6.dart 108-88-3 ...  → 지정한 CAS만
//
// - 키: 환경 변수 DATA_GO_KR_KEY, 없으면 저장소 루트 .env의 같은 이름(개발 PC 조사용 — probe_chem_api.py와 같다). 키는 출력하지 않는다.
// - 원천: KOSHA MSDS(목록 → 완전 일치마다 상세 02·08·09, lib/msds/msds_client.dart 그대로) + 환경공단 유독물 GHS(ghsList).
// - 실패 응답·키가 든 응답은 저장하지 않는다 — 끝에 목록을 출력하고 종료 코드 1.
// - 호출 수: CAS당 KOSHA 목록 1 + 완전 일치 수 × 3 + GHS 1. 사고대비물질 전부 ≈ 500회(개발 계정 서비스별 하루 한도 안).
// - Flutter에 의존하지 않는다 — `dart run`으로 돈다.
import 'dart:convert';
import 'dart:io';

import 'package:findchem/form6/raw_store.dart';
import 'package:findchem/form6/targets.dart';
import 'package:findchem/lookup/chem_parse.dart';
import 'package:findchem/msds/msds_client.dart';
import 'package:findchem/parser/models.dart';
import 'package:http/http.dart' as http;

const rawDir = 'assets/form6/raw';
const dataPath = 'assets/data/findchem_data.json';

String readKey() {
  final env = Platform.environment['DATA_GO_KR_KEY'] ?? '';
  if (env.trim().isNotEmpty) return env.trim();
  final f = File('.env');
  if (!f.existsSync()) return '';
  for (final line in f.readAsLinesSync()) {
    final t = line.trim();
    if (t.startsWith('DATA_GO_KR_KEY=')) return t.substring('DATA_GO_KR_KEY='.length).trim().replaceAll('"', '');
  }
  return '';
}

/// 수집 날짜를 `raw/collected.json`(CAS → 날짜)에 덧쓴다 — 생성물의 출처 '수집 시각'이 파일 시각(체크아웃마다 바뀐다)이 아니라 이것을 쓴다.
void stampCollected(List<String> cases) {
  final f = File('$rawDir/collected.json');
  final m = f.existsSync() ? (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>() : <String, Object?>{};
  final today = DateTime.now().toIso8601String().substring(0, 10);
  for (final c in cases) {
    m[c] = today;
  }
  final sorted = Map.fromEntries(m.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  f.writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(sorted)}\n');
}

Future<void> main(List<String> args) async {
  // --stamp-only: 부르지 않고 수집 날짜만 적는다(이 기록이 생기기 전에 받은 원문용, 2026-10-19 1회)
  if (args.isNotEmpty && args.first == '--stamp-only') {
    final ds = Dataset.fromJson((jsonDecode(File(dataPath).readAsStringSync()) as Map).cast<String, Object?>());
    stampCollected(args.length > 1 ? args.sublist(1) : form6TargetsOf(ds).cas);
    return;
  }
  final key = readKey();
  if (key.isEmpty) {
    stderr.writeln('collect_form6: DATA_GO_KR_KEY가 없다(환경 변수·.env) — 호출하지 않고 끝낸다');
    exitCode = 2;
    return;
  }
  final List<String> cases;
  if (args.isNotEmpty) {
    cases = args;
  } else {
    final ds = Dataset.fromJson((jsonDecode(File(dataPath).readAsStringSync()) as Map).cast<String, Object?>());
    final t = form6TargetsOf(ds);
    cases = t.cas;
    stdout.writeln('대상: 별표 3 항목 ${t.entryCount}개 → CAS ${t.cas.length}개, CAS 없는 항목 ${t.noCasEntries.length}개');
  }

  final rec = RecordingClient(http.Client(), dir: rawDir, key: key, log: stderr.writeln);
  final msds = MsdsClient(httpClient: rec, key: key, log: (m) => stderr.writeln('  $m'), timeout: const Duration(seconds: 30));
  var i = 0;
  for (final cas in cases) {
    i++;
    final r = await msds.lookup(cas);
    final ghsUri = Uri.parse('$ghsEndpoint?serviceKey=${portalKeyParam(key)}&${casJsonQuery(cas)}');
    String ghsNote;
    try {
      final res = await rec.get(ghsUri);
      ghsNote = 'GHS HTTP ${res.statusCode}';
    } catch (e) {
      ghsNote = 'GHS 접속 실패';
    }
    stdout.writeln('[$i/${cases.length}] $cas  KOSHA ${r.status.name}'
        '${r.status == MsdsStatus.ambiguous ? '(${r.candidates.length}건)' : ''}  $ghsNote');
  }
  rec.close();
  stampCollected(cases);
  stdout.writeln('저장 ${rec.saved}개');
  if (rec.failures.isNotEmpty) {
    stdout.writeln('저장 못 함 ${rec.failures.length}건:');
    for (final f in rec.failures) {
      stdout.writeln('  $f');
    }
    exitCode = 1;
  }
}
