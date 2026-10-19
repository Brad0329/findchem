// A-010 생성 — assets/form6/raw/(원문) + exposure_tables.json(위험노출수준 추출 표) + overrides.json(사람 보정)
//   → assets/form6/form6_constants.json.
//
//   python scripts/extract_exposure.py   (위험노출수준 원천이 바뀌었을 때만)
//   dart run scripts/build_form6.dart
//
// 네트워크를 쓰지 않는다. 원문이 빠졌거나 보정 파일이 틀리면 쓰지 않고 종료 코드 1(사유 출력).
// 추출 표가 없으면 위험노출수준은 '싣지 않고 만들었음'(확인필요)으로 남고 그 사실을 출력한다.
// Flutter에 의존하지 않는다 — `dart run`으로 돈다.
import 'dart:convert';
import 'dart:io';

import 'package:findchem/form6/exposure_tables.dart';
import 'package:findchem/form6/form6_build.dart';
import 'package:findchem/form6/targets.dart';
import 'package:findchem/parser/models.dart';

const dir = 'assets/form6';
const dataPath = 'assets/data/findchem_data.json';

Future<void> main() async {
  final ds = Dataset.fromJson((jsonDecode(File(dataPath).readAsStringSync()) as Map).cast<String, Object?>());
  final targetCas = form6TargetsOf(ds).cas.toSet();
  final logs = <String>[];
  try {
    final ovFile = File('$dir/overrides.json');
    final overrides = ovFile.existsSync() ? parseOverrides(ovFile.readAsStringSync(), targetCas) : const <Form6Override>[];
    final exposure = loadExposureTables('$dir/exposure_tables.json');
    if (exposure == null) stdout.writeln('경고: $dir/exposure_tables.json 없음 — 위험노출수준 없이 만든다');
    final out = await buildForm6(dataset: ds, rawDir: '$dir/raw', overrides: overrides, exposure: exposure, log: logs.add);
    File('$dir/form6_constants.json').writeAsStringSync('${const JsonEncoder.withIndent(' ').convert(out)}\n');
    stdout.writeln('form6_constants.json: CAS ${(out['substances'] as List).length}개, 보정 ${out['overrideCount']}건');
    final counts = out['statusCounts'] as Map;
    for (final e in counts.entries) {
      stdout.writeln('  ${e.key.toString().padRight(16)} ${e.value}');
    }
    if (logs.isNotEmpty) stdout.writeln('해석 로그 ${logs.length}줄(원문 그대로 둔 값) — 첫 줄: ${logs.first}');
  } on Form6BuildError catch (e) {
    stderr.writeln('build_form6: $e');
    exitCode = 1;
  }
}
