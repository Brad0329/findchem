/// A-010 생성 전체 — 원문 저장본(`assets/form6/raw/`의 압축 묶음)만 읽어 `form6_constants.json`의 내용을 만든다(REQUIREMENTS_AGENT A-010 D2).
///
/// 네트워크 없이 결정적이다: 시각은 수집 기록(`raw/collected.json`)에서만 온다.
/// 원문이 하나라도 없으면 만들지 않고 [Form6BuildError]로 빠진 파일을 알린다(빈 값으로 조용히 채우지 않는다).
///
/// **Flutter를 import하지 않는다.**
library;

import 'dart:convert';
import 'dart:io';

import '../lookup/chem_parse.dart';
import '../msds/msds_client.dart';
import '../parser/models.dart';
import 'form6_builder.dart';
import 'exposure_tables.dart';
import 'raw_store.dart';
import 'targets.dart';

class Form6BuildError implements Exception {
  const Form6BuildError(this.message, [this.details = const []]);

  final String message;
  final List<String> details;

  @override
  String toString() => details.isEmpty ? message : '$message\n  ${details.join('\n  ')}';
}

/// 사람 보정 한 건(D7).
class Form6Override {
  const Form6Override({required this.cas, required this.field, required this.value, required this.reason, required this.source});

  final String cas, field, reason, source;
  final Object? value;
}

/// 보정 파일 읽기 + 자동 검증(D7). 하나라도 틀리면 전부 사유와 함께 실패한다.
List<Form6Override> parseOverrides(String text, Set<String> targetCas) {
  final root = jsonDecode(text);
  if (root is! List) throw const Form6BuildError('보정 파일은 배열이어야 한다');
  final errors = <String>[];
  final out = <Form6Override>[];
  final seen = <String>{};
  for (var i = 0; i < root.length; i++) {
    final o = root[i];
    if (o is! Map) {
      errors.add('[$i] 객체가 아님');
      continue;
    }
    String s(String k) => (o[k] ?? '').toString().trim();
    final cas = s('cas'), field = s('field'), reason = s('reason'), source = s('source');
    if (!targetCas.contains(cas)) errors.add('[$i] 대상 밖 CAS "$cas"');
    if (!form6FieldNames.contains(field)) errors.add('[$i] 없는 칸 이름 "$field" (${form6FieldNames.join(', ')})');
    if (reason.isEmpty) errors.add('[$i] 근거(reason) 빈칸');
    if (source.isEmpty) errors.add('[$i] 출처(source) 빈칸');
    if (!o.containsKey('value')) errors.add('[$i] 값(value) 없음');
    if (!seen.add('$cas/$field')) errors.add('[$i] 같은 칸 보정이 두 번 "$cas/$field"');
    out.add(Form6Override(cas: cas, field: field, value: o['value'], reason: reason, source: source));
  }
  if (errors.isNotEmpty) throw Form6BuildError('보정 파일 검증 실패 ${errors.length}건', errors);
  return out;
}

Future<Map<String, Object?>> buildForm6({
  required Dataset dataset,
  required String rawDir,
  required List<Form6Override> overrides,
  ExposureTables? exposure,
  void Function(String)? log,
}) async {
  final targets = form6TargetsOf(dataset);
  final collectedFile = File('$rawDir/collected.json');
  final collected = collectedFile.existsSync()
      ? (jsonDecode(collectedFile.readAsStringSync()) as Map).cast<String, Object?>()
      : const <String, Object?>{};

  final store = RawStore.load(rawDir);
  final replay = ReplayClient(store);
  final msds = MsdsClient(httpClient: replay, key: 'replay', log: log, clock: () => DateTime.utc(2000));
  final substances = <Map<String, Object?>>[];
  for (final cas in targets.cas) {
    final at = collected[cas] as String?;
    final kosha = await msds.lookup(cas);
    final ghsText = store.get(rawNameOf(Uri.parse('$ghsEndpoint?${casJsonQuery(cas)}'))!);
    ServiceResult? ghs;
    var ghsRaw = '';
    if (ghsText != null) {
      ghsRaw = ghsText;
      try {
        ghs = parseGhsResponse(ghsRaw);
      } on FormatException catch (e) {
        log?.call('A-010 GHS 원문 해석 실패 $cas: $e');
        ghs = ServiceFailed('응답 형식: $e');
      }
    } else {
      replay.missing.add(rawNameOf(Uri.parse('$ghsEndpoint?${casJsonQuery(cas)}'))!);
    }
    substances.add(buildSubstance(cas: cas, kosha: kosha, ghs: ghs, ghsRaw: ghsRaw, exposure: exposure, collectedAt: at, log: log));
  }
  if (replay.missing.isNotEmpty) {
    throw Form6BuildError('원문이 없는 요청 ${replay.missing.length}건 — collect_form6.dart로 받는다', replay.missing);
  }

  for (final o in overrides) {
    final s = substances.firstWhere((s) => s['cas'] == o.cas);
    final fields = s['fields'] as Map<String, Object?>;
    fields[o.field] = {
      'value': o.value,
      'raw': '',
      'unit': null,
      'condition': null,
      'source': {'kind': '사람 보정', 'id': o.source, 'version': null, 'section': null, 'collectedAt': null},
      'status': Form6Status.confirmed.label,
      'note': o.reason,
      'overriddenFrom': fields[o.field],
    };
  }

  final dates = collected.values.whereType<String>().toList()..sort();
  return {
    'version': 1,
    'notice': '「화학사고예방관리계획서 작성 등에 관한 규정」 제2026-19호 별지 제6호서식 — 물질 상수 9칸',
    'collectedThrough': dates.isEmpty ? null : dates.last,
    'targets': {
      'basis': '번들 별표 3(사고대비물질) 살아 있는 항목 — ${dataset.byeolpyo3.file}, 추출 ${dataset.extractedAt}',
      'entryCount': targets.entryCount,
      'casCount': targets.cas.length,
      'noCasEntries': [for (final e in targets.noCasEntries) {'no': e.no, 'name': e.name}],
    },
    'sources': [
      {'kind': 'KOSHA MSDS', 'provider': 'data.go.kr 15157612', 'endpoint': msdsEndpoint, 'fields': ['state', 'specificGravity', 'lel', 'uel', 'twa', 'vaporPressure']},
      {'kind': '한국환경공단 유독물 GHS', 'provider': 'data.go.kr 15149423', 'endpoint': ghsEndpoint, 'fields': ['ghs', 'corrosive']},
      {
        'kind': '위험노출수준 표 — 별지 주⑨ 순서(ERPG → AEGL → PAC)',
        'tables': exposure?.sources ?? '싣지 않음',
        'fields': ['exposure'],
      },
    ],
    if (exposure != null) 'aihaNotice': exposure.aihaNotice,
    'statusCounts': _counts(substances),
    'overrideCount': overrides.length,
    'substances': substances,
  };
}

/// 칸별 상태 개수 — 머리에서 확인필요가 얼마나 남았는지 한눈에.
Map<String, Object?> _counts(List<Map<String, Object?>> subs) => {
  for (final n in form6FieldNames)
    n: {
      for (final st in Form6Status.values)
        st.label: subs.where((s) => ((s['fields'] as Map)[n] as Map)['status'] == st.label).length,
    },
};
