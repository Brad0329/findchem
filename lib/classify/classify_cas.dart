/// A-008 CAS 일괄 분류 도구 — CAS 목록을 받아 CAS마다 별표 2ㆍ3의 **분류와 함량기준만** 돌려준다.
///
/// `search_chemical`을 물질 수만큼 부르는 대신 한 번에 묻는다(MSDS 성분 정리ㆍ계획서 물질 목록ㆍ초안 검증이 같이 쓴다).
/// 결정과 근거: REQUIREMENTS_AGENT A-008.
///
/// - 일치는 CAS 완전 일치만 — 검색의 앞부분 일치ㆍ이름 일치를 쓰면 분류가 다른 물질에 붙는다.
/// - 체크섬이 틀려도 조회한다 — 고시 원문에 체크섬이 안 맞는 CAS가 실려 있다. 틀렸다는 사실만 붙인다.
/// - 규정수량ㆍ적용 조건 문장은 싣지 않는다(`search_chemical`의 몫). 함량 판정도 하지 않는다.
/// - 예외를 밖으로 던지지 않는다 — 항목마다 사유를 돌려준다. Flutter를 import하지 않는다.
library;

import '../assist/assist_response.dart';
import '../assist/conditions.dart';
import '../assist/rules.dart';
import '../calc/calc.dart' show CalcOutcome;
import '../parser/cas.dart';
import '../parser/models.dart';
import '../search/search.dart';

const classifyToolName = 'classify_cas';

/// 한 번에 받는 CAS 상한. 넘으면 조회하지 않고 받은 개수를 돌려준다(조용한 절단 금지).
const classifyCasCap = 200;

/// 분류 이름(고시 용어). 응답 `classes`의 순서이기도 하다.
abstract final class ChemClass {
  static const accident = '사고대비물질';
  static const acute = '인체급성유해성';
  static const chronic = '인체만성유해성';
  static const eco = '생태유해성';

  static const order = [accident, acute, chronic, eco];

  /// 별표2 행의 구분 한 마디 → 분류. 용액ㆍ저확산 등은 분류가 아니다(null).
  static String? ofKind(String kind) => switch (kind) {
        '급성' => acute,
        '만성' => chronic,
        '생태' => eco,
        _ => null,
      };
}

const classifyToolDescription = '''CAS 번호 여러 개의 분류를 한 번에 조회한다 — 「유해화학물질의 규정수량에 관한 규정」 별표 2(인체ㆍ생태 유해성)ㆍ별표 3(사고대비물질).
물질이 여럿이고 분류ㆍ함량기준만 필요하면 search_chemical을 여러 번 부르지 말고 이것을 쓴다(MSDS 구성성분 표, 물질 목록).
규정수량(최하위ㆍ하위ㆍ상위)과 행 적용 조건은 여기 없다 — 필요하면 그 물질만 search_chemical로 다시 본다.
응답 items는 입력과 같은 순서ㆍ같은 개수다. 항목마다:
- status: listed(별표 2ㆍ3에 있음) / not_listed(개별 항목 없음 — 이 고시의 분류에 해당하지 않는다고 답한다. 다른 법령의 규제 여부는 아니다) /
  invalid(CAS 형식이 아님 — reason을 읽고 원문을 다시 확인한다. 분류를 지어내지 않는다)
- classes: 사고대비물질 / 인체급성유해성 / 인체만성유해성 / 생태유해성 중 해당하는 것 전부(값을 그대로 옮긴다)
- entries: 근거 항목(src 표, no 번호, name 국문명)과 rows — 행마다 kind(구분: 급성ㆍ만성ㆍ생태ㆍ저확산ㆍ용액, 별표3은 빈 문자열)와
  content(함량기준 % 이상, 원문 문자열. 빈 문자열이면 그 행에 숫자 기준이 없다). 함량이 함량기준 미만인 혼합물에는 그 행이 적용되지 않는다 —
  이 도구는 함량을 받지 않으므로 미달 여부는 판정하지 않았다.
  priority true = 같은 CAS가 두 표에 있어 이 항목(별표 3)이 우선 적용된다(별표 2 일반기준 가). reference_note true = 이 별표 2 항목은 참고값이다
  (같은 항목의 CAS가 별표 3에도 있다 — 이 CAS 자체가 별표 3에 없을 수 있으니 classes를 본다).
- checksum_ok false = CAS 체크섬이 맞지 않는다. not_listed면 오독ㆍ오타를 의심하고 원문을 다시 본다.
- notes: 그 항목에 대한 안내 문장.
CAS는 하이픈이 있는 형식으로 넣는다(앞자리 0은 지우고 조회한다). 묶음으로 규정된 항목(염류ㆍ"~와 그 화합물")은 CAS로 안 잡힐 수 있다 — 의심되면 물질명으로 search_chemical.''';

List<Map<String, Object?>> classifyToolDefinitions() => [
      {
        'name': classifyToolName,
        'description': classifyToolDescription,
        'input_schema': {
          'type': 'object',
          'properties': {
            'cas': {
              'type': 'array',
              'description': 'CAS 번호 목록(예: ["107-13-1", "65-85-0"]). 최대 $classifyCasCap개',
              'items': {'type': 'string'},
            },
          },
          'required': ['cas'],
        },
      },
    ];

/// CAS 체크섬 — 끝자리를 뺀 숫자에 오른쪽부터 1, 2, 3… 을 곱해 더한 값의 일의 자리가 끝자리다.
/// [cas]는 [casPattern] 형식이어야 한다.
bool casChecksumOk(String cas) {
  final digits = cas.replaceAll('-', '');
  var sum = 0;
  for (var i = digits.length - 2, weight = 1; i >= 0; i--, weight++) {
    sum += (digits.codeUnitAt(i) - 0x30) * weight;
  }
  return sum % 10 == digits.codeUnitAt(digits.length - 1) - 0x30;
}

final _leadingZeros = RegExp(r'^0+(?=\d)');

/// 입력 표기를 조회용 CAS로. 형식이 아니면 null.
String? normalizeCas(String raw) {
  final s = raw.trim().replaceFirst(_leadingZeros, '');
  return casPattern.hasMatch(s) ? s : null;
}

/// 이름이 [classifyToolName]이 아니면 null(다른 도구).
CalcOutcome? runClassifyTool(Dataset ds, String name, Map<String, Object?> args) =>
    name == classifyToolName ? classifyCas(ds, args) : null;

CalcOutcome classifyCas(Dataset ds, Map<String, Object?> args) {
  final list = args['cas'];
  if (list is! List || list.isEmpty) {
    return const CalcOutcome({}, error: 'cas는 비어 있지 않은 문자열 배열이어야 합니다');
  }
  if (list.length > classifyCasCap) {
    return CalcOutcome(const {},
        error: 'CAS가 ${list.length}개로 상한 $classifyCasCap개를 넘어 조회하지 않았습니다 — 나눠 부르세요');
  }

  final index = SearchIndex(ds);
  final byCas = <String, List<Entry>>{};
  for (final e in ds.entries) {
    for (final c in e.cas) {
      byCas.putIfAbsent(c, () => []).add(e);
    }
  }

  final items = [for (final raw in list) _classifyOne(raw, byCas, index)];
  int count(String status) => items.where((i) => i['status'] == status).length;
  return CalcOutcome({
    'total': items.length,
    'counts': {'listed': count('listed'), 'not_listed': count('not_listed'), 'invalid': count('invalid')},
    'items': items,
    'coverage': coverageStatement,
    'source': {'notice': notice},
  });
}

Map<String, Object?> _classifyOne(Object? raw, Map<String, List<Entry>> byCas, SearchIndex index) {
  if (raw is! String) {
    return {'input': raw, 'status': 'invalid', 'reason': 'CAS는 문자열이어야 합니다'};
  }
  final cas = normalizeCas(raw);
  if (cas == null) {
    return {
      'input': raw,
      'status': 'invalid',
      'reason': "CAS 형식(숫자 2~7자리-2자리-1자리, 예: '107-13-1')이 아닙니다",
    };
  }

  final found = byCas[cas] ?? const <Entry>[];
  // 별표3(우선 적용) 먼저, 그 안은 번호 순.
  final live = found.where((e) => !e.deleted).toList()
    ..sort((a, b) => a.src == b.src ? a.no.compareTo(b.no) : (a.src == Source.byeolpyo3 ? -1 : 1));
  final deleted = found.where((e) => e.deleted).toList();

  final classes = <String>{};
  for (final e in live) {
    if (e.src == Source.byeolpyo3) {
      classes.add(ChemClass.accident);
      continue;
    }
    for (final r in e.rows) {
      for (final part in r.kind.split(',')) {
        if (ChemClass.ofKind(part.trim()) case final c?) classes.add(c);
      }
    }
  }

  final checksumOk = casChecksumOk(cas);
  final notes = <String>[
    if (!checksumOk && live.isNotEmpty) '체크섬은 맞지 않으나 고시 원문에 이 표기로 실려 있다.',
    if (!checksumOk && live.isEmpty) '체크섬이 맞지 않는다 — 오독ㆍ오타일 수 있다(원문의 CAS를 다시 확인한다).',
    if (live.any((e) => e.src == Source.byeolpyo3) && live.any((e) => e.src == Source.byeolpyo2))
      '두 표에 모두 있다 — 사고대비물질(별표 3)의 규정수량이 우선 적용된다(별표 2 일반기준 가).',
    if (live.any((e) => e.rows.any(isLowDiffusionRow))) '저확산 행이 있다 — 취급 과정의 성상(액체ㆍ고체)에 따라 적용 행이 달라진다(별표 2 일반기준 다).',
    if (live.any((e) => e.rows.any((r) => isSolutionRow(e, r)))) '용액ㆍ* 행이 있다 — 상온ㆍ상압 성상에 따라 적용 행이 달라진다.',
    for (final e in deleted) '${e.src.id} 제${e.no}호는 (삭제)된 항목이라 분류에 넣지 않았다.',
  ];

  return {
    'input': raw,
    'cas': cas,
    'status': live.isEmpty ? 'not_listed' : 'listed',
    'checksum_ok': checksumOk,
    'classes': [
      for (final c in ChemClass.order)
        if (classes.contains(c)) c,
    ],
    'entries': [
      for (final e in live)
        {
          'src': e.src.id,
          'no': e.no,
          'name': e.ko,
          'rows': [
            for (final r in e.rows) {'kind': r.kind, 'content': r.content},
          ],
          if (index.hitOf(e).priority) 'priority': true,
          if (index.hitOf(e).referenceNote) 'reference_note': true,
        },
    ],
    if (notes.isNotEmpty) 'notes': notes,
  };
}
