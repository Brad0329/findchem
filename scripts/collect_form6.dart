// A-010 수집 — 6호서식 상수의 원천 API 응답 원문을 assets/form6/raw/의 압축 묶음(kosha.json.gz·ghs.json.gz)에 넣는다(REQUIREMENTS_AGENT A-010 D2).
//
//   dart run scripts/collect_form6.dart               → 대상 CAS 전부(번들 별표 3), 이미 받은 CAS는 건너뛴다
//   dart run scripts/collect_form6.dart --all         → 별표 3 + 별표 2(범위 확장 — 개발 계정이면 며칠에 나눠 같은 명령을 다시)
//   dart run scripts/collect_form6.dart 108-88-3 ...  → 지정한 CAS만(이미 받았어도 다시 받는다)
//   dart run scripts/collect_form6.dart --import-files <폴더>   → 옛 형식(응답마다 파일 하나) 원문을 묶음으로 옮긴다(2026-10-20 1회)
//
// - 키: 환경 변수 DATA_GO_KR_KEY, 없으면 저장소 루트 .env의 같은 이름(개발 PC 조사용 — probe_chem_api.py와 같다). 키는 출력하지 않는다.
// - 원천: KOSHA MSDS(목록 → 완전 일치마다 상세 02·08·09, lib/msds/msds_client.dart 그대로) + 환경공단 유독물 GHS(ghsList).
// - 이어받기: raw/collected.json(CAS → 수집일)에 있는 CAS는 건너뛴다. 기록은 **그 CAS의 응답을 실패 없이 다 넣었을 때만** 남긴다.
// - 한도: 포털이 '한도 초과'(코드 22)를 돌려주면 그 CAS는 기록하지 않고 바로 멈춘다 — 남은 개수를 출력하고 종료 코드 3.
//   한도(2026-10-20 포털 확인): KOSHA 개발계정 2,000 · GHS 10,000. CAS당 KOSHA 최대 4회 + GHS 1회.
// - 실패 응답·키가 든 응답은 넣지 않는다 — 끝에 목록을 출력하고 종료 코드 1.
// - 50 CAS마다 묶음을 저장한다(중간에 끊겨도 받은 만큼은 남는다).
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

Map<String, Object?> readCollected() {
  final f = File('$rawDir/collected.json');
  return f.existsSync() ? (jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>() : <String, Object?>{};
}

/// 수집 날짜를 `raw/collected.json`(CAS → 날짜)에 덧쓴다 — 생성물의 출처 '수집 시각'과 이어받기가 이것을 쓴다.
void stampCollected(List<String> cases) {
  if (cases.isEmpty) return;
  final m = readCollected();
  final today = DateTime.now().toIso8601String().substring(0, 10);
  for (final c in cases) {
    m[c] = today;
  }
  final sorted = Map.fromEntries(m.entries.toList()..sort((a, b) => a.key.compareTo(b.key)));
  File('$rawDir/collected.json').writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(sorted)}\n');
}

/// 옛 형식 폴더(`kosha/*.xml`·`ghs/*.json`)의 파일을 묶음으로. 받은 원문에는 CR이 없었으므로(2026-10-19 515개 전수)
/// Windows 체크아웃이 넣은 CRLF는 LF로 되돌린다.
void importFiles(String dir) {
  final store = RawStore.load(rawDir);
  var n = 0;
  for (final a in rawArchives) {
    final d = Directory('$dir/$a');
    if (!d.existsSync()) continue;
    for (final f in d.listSync().whereType<File>()) {
      final name = '$a/${f.uri.pathSegments.last}';
      if (!store.put(name, f.readAsStringSync().replaceAll('\r\n', '\n'))) {
        stderr.writeln('옮기지 못함(이름 규칙 밖): $name');
        exitCode = 1;
        continue;
      }
      n++;
    }
  }
  store.save();
  stdout.writeln('옮김 $n개 → kosha ${store.count('kosha')}개, ghs ${store.count('ghs')}개');
}

Future<void> main(List<String> args) async {
  if (args.length == 2 && args.first == '--import-files') {
    importFiles(args[1]);
    return;
  }
  final key = readKey();
  if (key.isEmpty) {
    stderr.writeln('collect_form6: DATA_GO_KR_KEY가 없다(환경 변수·.env) — 호출하지 않고 끝낸다');
    exitCode = 2;
    return;
  }
  final List<String> cases;
  final explicit = args.isNotEmpty && !args.first.startsWith('--');
  if (explicit) {
    cases = args;
  } else {
    final all = args.contains('--all');
    final ds = Dataset.fromJson((jsonDecode(File(dataPath).readAsStringSync()) as Map).cast<String, Object?>());
    final t = form6TargetsOf(ds, includeByeolpyo2: all);
    final done = readCollected().keys.toSet();
    cases = [for (final c in t.cas) if (!done.contains(c)) c];
    stdout.writeln('대상: ${all ? '별표 3 + 별표 2' : '별표 3'} 항목 ${t.entryCount}개 → CAS ${t.cas.length}개 '
        '(CAS 없는 항목 ${t.noCasEntries.length}개), 이미 받음 ${t.cas.length - cases.length}개, 이번에 받을 것 ${cases.length}개');
  }

  final store = RawStore.load(rawDir);
  final rec = RecordingClient(http.Client(), store: store, key: key, log: stderr.writeln);
  final msds = MsdsClient(httpClient: rec, key: key, log: (m) => stderr.writeln('  $m'), timeout: const Duration(seconds: 30));
  final ok = <String>[];
  var i = 0;
  for (final cas in cases) {
    i++;
    final failuresBefore = rec.failures.length;
    final r = await msds.lookup(cas);
    final ghsUri = Uri.parse('$ghsEndpoint?serviceKey=${portalKeyParam(key)}&${casJsonQuery(cas)}');
    String ghsNote;
    try {
      final res = await rec.get(ghsUri);
      ghsNote = 'GHS HTTP ${res.statusCode}';
    } catch (e) {
      ghsNote = 'GHS 접속 실패';
    }
    final clean = rec.failures.length == failuresBefore && r.status != MsdsStatus.failed;
    if (clean) ok.add(cas);
    stdout.writeln('[$i/${cases.length}] $cas  KOSHA ${r.status.name}'
        '${r.status == MsdsStatus.ambiguous ? '(${r.candidates.length}건)' : ''}  $ghsNote${clean ? '' : '  ← 기록 안 함(다음에 다시)'}');
    if (rec.quotaExceeded) {
      stdout.writeln('한도 초과(포털 코드 22) — 멈춘다. 남은 CAS ${cases.length - i + 1}개(이 CAS 포함)는 다음 실행에서 이어받는다');
      exitCode = 3;
      break;
    }
    if (i % 50 == 0) {
      store.save();
      stampCollected(ok);
      ok.clear();
    }
  }
  rec.close();
  store.save();
  stampCollected(ok);
  stdout.writeln('넣음 ${rec.saved}개 → kosha ${store.count('kosha')}개, ghs ${store.count('ghs')}개');
  if (rec.failures.isNotEmpty) {
    stdout.writeln('넣지 못함 ${rec.failures.length}건:');
    for (final f in rec.failures.take(30)) {
      stdout.writeln('  $f');
    }
    if (rec.failures.length > 30) stdout.writeln('  … 외 ${rec.failures.length - 30}건(전체 ${rec.failures.length}건)');
    if (exitCode == 0) exitCode = 1;
  }
}
