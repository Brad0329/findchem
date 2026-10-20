/// A-010 2단계 MCP 도구 `get_form6_constants` — CAS 목록 → CAS마다 별지 6호서식 한 행의 뼈대(REQUIREMENTS_AGENT A-010 '2단계').
///
/// 두 데이터를 서버 안에서 CAS로 합친다: 별표 2ㆍ3 번들(물질명ㆍ물질구분ㆍ고유번호 후보 — 분류는 A-008 [classifyCas] 그대로)
/// + 6호 상수 생성물(`assets/form6/form6_constants.json`의 9칸). 모델이 두 결과를 옮겨 맞추는 자리를 없앤다.
/// 고르지 않는다 — 독성구분 대표 1개ㆍ위험노출수준 종류ㆍ고유번호 표기는 채울 때 정한다(결정 ③ㆍD6ㆍE1).
///
/// 예외를 밖으로 던지지 않는다. Flutter를 import하지 않는다.
library;

import 'dart:convert';
import 'dart:io';

import '../calc/calc.dart' show CalcOutcome;
import '../classify/classify_cas.dart';
import '../parser/models.dart';

const form6ToolName = 'get_form6_constants';

/// 한 번에 받는 CAS 상한(E3) — 항목마다 칸 9개의 원문ㆍ출처가 실려 응답이 크다. 넘으면 조회하지 않는다(조용한 절단 금지).
const form6CasCap = 50;

/// 별지 주② 물질구분 표기.
const _shortClass = {
  ChemClass.accident: '사고대비',
  ChemClass.acute: '급성',
  ChemClass.chronic: '만성',
  ChemClass.eco: '생태',
};

/// 상수 생성물 — CAS → 항목, 머리(범위ㆍ원천ㆍ고지문).
class Form6Data {
  Form6Data._(this.header, this.byCas);

  factory Form6Data.fromJson(Map<String, Object?> j) => Form6Data._(
        {for (final e in j.entries) if (e.key != 'substances') e.key: e.value},
        {for (final s in j['substances'] as List) (s as Map)['cas'] as String: s.cast<String, Object?>()},
      );

  /// 파일을 읽는다. 없거나 깨졌으면 null + 로그(E5 — 이 도구만 실패하고 서버는 뜬다).
  static Form6Data? load(String path, void Function(String) log) {
    try {
      return Form6Data.fromJson((jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>());
    } catch (e) {
      log('A-010 6호 상수 파일을 읽지 못함($path) — get_form6_constants는 실패로 답한다: $e');
      return null;
    }
  }

  final Map<String, Object?> header;
  final Map<String, Map<String, Object?>> byCas;
}

const form6ToolDescription = '''CAS 번호 여러 개로 화학사고예방관리계획서 별지 제6호서식(유해화학물질 목록 및 명세)의 행 뼈대를 한 번에 가져온다.
항목마다: name(유해화학물질명 — 고시 국문명), material_class(물질구분 — 사고대비ㆍ급성ㆍ만성ㆍ생태), unique_number_candidates(고유번호 후보와 출처),
fields(상수 9칸 — state 물질상태, specificGravity 비중, lel/uel 폭발한계 하한ㆍ상한, ghs 독성구분(공식 분류 전체), exposure 위험노출수준(있는 값 전부),
twa 허용농도, vaporPressure 증기압(mmHg, condition에 온도), corrosive 부식성). 칸마다 value(값)ㆍraw(원천 원문)ㆍsource(출처)ㆍstatus(확정/확인필요/자료없음)ㆍnote.
- 값은 그대로 옮긴다. status가 확인필요ㆍ자료없음이면 지어 채우지 말고 사용자에게 확인을 요청한다(note에 사유).
- 고르는 일은 이 도구가 하지 않는다: 독성구분은 ghs 목록에서 대표 1개를, 위험노출수준은 별지 주⑨ 순서(ERPG → AEGL → PAC)로 exposure 목록의 첫 값을 쓴다.
  고유번호 표기도 후보에서 고른다.
- 연번ㆍ함량(%)은 사업장 값이라 여기 없다. 함량기준 미만 성분은 6호 대상이 아니다 — 판정은 이 도구가 하지 않는다.
- status: found(9칸 있음) / not_covered(유해화학물질이지만 아직 상수 범위 밖 — classes 참고, 칸은 MSDS 등에서 따로 채운다) /
  not_listed(별표 2ㆍ3에 없음 — 6호 대상 아님) / invalid(CAS 형식 아님).
- ERPG 값은 AIHA 자료다 — 결과를 내보낼 때 응답 머리의 aiha_notice를 함께 싣고 출처를 표시한다.
한 번에 최대 $form6CasCap개, 응답 items는 입력과 같은 순서ㆍ같은 개수.''';

List<Map<String, Object?>> form6ToolDefinitions() => [
      {
        'name': form6ToolName,
        'description': form6ToolDescription,
        'input_schema': {
          'type': 'object',
          'properties': {
            'cas': {
              'type': 'array',
              'description': 'CAS 번호 목록(예: ["108-88-3", "68-12-2"]). 최대 $form6CasCap개',
              'items': {'type': 'string'},
            },
          },
          'required': ['cas'],
        },
      },
    ];

/// 이름이 [form6ToolName]이 아니면 null(다른 도구).
CalcOutcome? runForm6Tool(Dataset ds, Form6Data? data, String name, Map<String, Object?> args) {
  if (name != form6ToolName) return null;
  if (data == null) {
    return const CalcOutcome({}, error: '이 서버에 6호서식 상수 데이터가 없어 조회하지 못했습니다');
  }
  return form6Constants(ds, data, args);
}

CalcOutcome form6Constants(Dataset ds, Form6Data data, Map<String, Object?> args) {
  final list = args['cas'];
  if (list is! List || list.isEmpty) {
    return const CalcOutcome({}, error: 'cas는 비어 있지 않은 문자열 배열이어야 합니다');
  }
  if (list.length > form6CasCap) {
    return CalcOutcome(const {}, error: 'CAS가 ${list.length}개로 상한 $form6CasCap개를 넘어 조회하지 않았습니다 — 나눠 부르세요');
  }
  final classified = classifyCas(ds, {'cas': list});
  if (classified.error != null) return classified;

  final uids = <String, Set<String>>{};
  for (final e in ds.entries) {
    if (e.deleted || e.uid == null) continue;
    for (final c in e.cas) {
      uids.putIfAbsent(c, () => <String>{}).add(e.uid!);
    }
  }

  final items = <Map<String, Object?>>[
    for (final c in (classified.response['items'] as List).cast<Map<String, Object?>>()) _item(c, data, uids),
  ];
  int count(String s) => items.where((i) => i['status'] == s).length;
  final h = data.header;
  return CalcOutcome({
    'total': items.length,
    'counts': {for (final s in ['found', 'not_covered', 'not_listed', 'invalid']) s: count(s)},
    'items': items,
    'scope': '상수 범위: ${h['targets'] is Map ? (h['targets'] as Map)['basis'] : '?'} — CAS '
        '${h['targets'] is Map ? (h['targets'] as Map)['casCount'] : '?'}개(1단계 사고대비물질). 그 밖의 유해화학물질은 not_covered',
    'form': h['notice'],
    'collected_through': h['collectedThrough'],
    'sources': h['sources'],
    'aiha_notice': h['aihaNotice'],
    'fill_rules': '독성구분 = ghs 목록에서 대표 1개(별지 주⑧). 위험노출수준 = exposure 목록 첫 값(주⑨ 순서로 이미 늘어놓음). '
        '증기압은 20℃가 아니면 온도를 함께(주⑪). 확인필요ㆍ자료없음 칸은 채우지 말고 확인 요청.',
  });
}

Map<String, Object?> _item(Map<String, Object?> c, Form6Data data, Map<String, Set<String>> uids) {
  final status = c['status'] as String;
  if (status == 'invalid') return {'input': c['input'], 'status': 'invalid', 'reason': c['reason']};
  final cas = c['cas'] as String;
  final base = <String, Object?>{'input': c['input'], 'cas': cas};
  if (status == 'not_listed') {
    return {...base, 'status': 'not_listed', 'note': '별표 2ㆍ3에 개별 항목이 없다 — 6호(유해화학물질 목록) 대상이 아니다', if (c['notes'] != null) 'notes': c['notes']};
  }
  final classes = (c['classes'] as List).cast<String>();
  final entries = (c['entries'] as List).cast<Map<String, Object?>>();
  final sub = data.byCas[cas];
  final common = <String, Object?>{
    ...base,
    'name': entries.isEmpty ? null : entries.first['name'],
    'material_class': [for (final k in classes) _shortClass[k] ?? k],
    'classes': classes,
  };
  if (sub == null) {
    return {
      ...common,
      'status': 'not_covered',
      'note': '유해화학물질이지만 6호 상수 범위 밖이다(지금은 사고대비물질만) — 9칸은 MSDS 등에서 따로 채운다',
      'unique_number_candidates': [
        for (final u in (uids[cas] ?? const <String>{}).toList()..sort()) {'value': u, 'source': '별표 2 고유번호'},
      ],
    };
  }
  final fields = (sub['fields'] as Map).cast<String, Object?>();
  final ghs = (fields['ghs'] as Map?)?.cast<String, Object?>();
  return {
    ...common,
    'status': 'found',
    'unique_number_candidates': [
      for (final u in (uids[cas] ?? const <String>{}).toList()..sort()) {'value': u, 'source': '별표 2 고유번호'},
      for (final n in (ghs?['classNumbers'] as List? ?? const [])) {'value': n, 'source': '한국환경공단 유독물 GHS(sbstnTypeUnqno)'},
    ],
    'site_fields': '연번ㆍ함량(%)은 사업장 값 — 비워 둔다',
    'fields': fields,
  };
}
