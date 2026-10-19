/// A-010 생성 — 원천 응답(이미 해석된 [MsdsResult]·[GhsRecord])에서 별지 6호서식 물질 상수 9칸을 만든다(REQUIREMENTS_AGENT A-010).
///
/// 칸 하나 = `{value, raw, unit, condition, source, status, note}`. 상태는 [Form6Status] 셋뿐이고, 출처 없는 값은 없다(D3).
/// **고르지 않는다**: 독성구분 대표 1개(결정 ③)·위험노출수준 종류(D6)는 6호를 채울 때 정한다. 단위 환산은 증기압 mmHg만(D4).
///
/// **Flutter를 import하지 않는다** — 생성 스크립트(`dart run`)와 테스트가 같이 쓴다.
library;

import '../lookup/chem_parse.dart';
import '../msds/msds_client.dart';
import '../msds/msds_value.dart';
import 'exposure_tables.dart';

enum Form6Status {
  confirmed('확정'),
  needsReview('확인필요'),
  noData('자료없음');

  const Form6Status(this.label);
  final String label;
}

/// 별지 6호서식 9칸의 JSON 키(D7 보정 파일의 칸 이름도 이것).
const form6FieldNames = [
  'state',
  'specificGravity',
  'lel',
  'uel',
  'ghs',
  'exposure',
  'twa',
  'vaporPressure',
  'corrosive',
];

/// 증기압 단위 → mmHg 계수(D4). 키는 [normalizeUnit] 표기.
const mmHgFactors = {
  'mmhg': 1.0,
  'torr': 1.0,
  'kpa': 7.50062,
  'hpa': 0.750062,
  'mbar': 0.750062,
  'pa': 0.00750062,
  'bar': 750.062,
  'mpa': 7500.62,
  'atm': 760.0,
  'psi': 51.7149,
};

/// 유효숫자 4자리로 — 환산값이 원문보다 정밀한 척하지 않게. 같은 입력 → 같은 출력.
double sig4(double v) => v == 0 ? 0 : double.parse(v.toStringAsPrecision(4));

Map<String, Object?> _field({
  required Object? value,
  required String raw,
  String? unit,
  String? condition,
  required Map<String, Object?> source,
  required Form6Status status,
  String? note,
  Map<String, Object?> extra = const {},
}) => {
  'value': value,
  'raw': raw,
  'unit': unit,
  'condition': condition,
  'source': source,
  'status': status.label,
  'note': note,
  ...extra,
};

/// KOSHA 원천의 출처.
Map<String, Object?> koshaSource(MsdsResult r, String section, String? collectedAt) => {
  'kind': 'KOSHA MSDS',
  'id': r.source?['chemId'],
  'version': r.source?['lastDate'],
  'section': section,
  'collectedAt': collectedAt,
};

Map<String, Object?> ghsSource(String? collectedAt) => {
  'kind': '한국환경공단 유독물 GHS',
  'id': null,
  'version': null,
  'section': 'ghsList',
  'collectedAt': collectedAt,
};

/// 원천이 응답하지 않을 때(KOSHA 없음·실패) 9칸 중 그 원천 몫을 채운다.
Map<String, Object?> _missingKosha(MsdsResult r, String? collectedAt) => _field(
  value: null,
  raw: '',
  source: {'kind': 'KOSHA MSDS', 'id': null, 'version': null, 'section': null, 'collectedAt': collectedAt},
  status: r.status == MsdsStatus.notFound ? Form6Status.noData : Form6Status.needsReview,
  note: switch (r.status) {
    MsdsStatus.notFound => 'KOSHA MSDS에 이 CAS가 없음',
    MsdsStatus.ambiguous =>
      'KOSHA에 이 CAS의 MSDS가 ${r.candidates.length}건 — 고르지 않음(D8): ${r.candidates.map((c) => '${c.chemId} ${c.nameKor}').join(', ')}',
    _ => 'KOSHA 조회 실패: ${r.message}',
  },
);

// ───── 칸별 ─────

final _gas = RegExp(r'기체|가스');
final _liquid = RegExp(r'액체|액상');
final _solid = RegExp(r'고체|분말|결정|가루|플레이크|덩어리|펠릿');

/// 물질상태 — 9절 성상 글에서 기체·액체·고체 낱말을 찾는다. 하나만 걸리면 확정, 둘 이상·없음·'액화'는 확인필요
/// (액화가스는 성상이 '액체'여도 상온·상압에서는 기체다 — 별지 주④).
Map<String, Object?> stateField(MsdsResult r, String? at) {
  final v = r.appearance();
  final src = koshaSource(r, '09 성상(I0202)', at);
  if (v.status != ValueStatus.value) {
    return _field(value: null, raw: v.raw, source: src, status: Form6Status.noData, note: v.parseError ?? '성상 자료없음');
  }
  final hits = [
    if (_gas.hasMatch(v.text)) '기체',
    if (_liquid.hasMatch(v.text)) '액체',
    if (_solid.hasMatch(v.text)) '고체',
  ];
  if (v.text.contains('액화')) {
    return _field(value: null, raw: v.raw, source: src, status: Form6Status.needsReview, note: "성상에 '액화' — 상온·상압 상태를 사람이 정한다");
  }
  if (hits.length != 1) {
    return _field(
      value: null,
      raw: v.raw,
      source: src,
      status: Form6Status.needsReview,
      note: hits.isEmpty ? '성상 글에 기체·액체·고체 낱말이 없음' : '성상 글에 여러 상태가 있음: ${hits.join('·')}',
    );
  }
  return _field(value: hits.single, raw: v.raw, source: src, status: Form6Status.confirmed);
}

const _sgDensityUnits = {'g/cucm', 'g/cm3', 'g/cc', 'g/ml'};

/// 비중 — 상대밀도(물=1)·단위 없음(항목 이름이 '비중')·g/㎤류(수치가 비중과 같다)는 확정. 그 밖 단위(g/L·kg/㎥ 등)·해석 실패는 확인필요.
Map<String, Object?> specificGravityField(MsdsResult r, String? at, {MsdsLog? log}) {
  final v = r.specificGravity(log: log);
  final src = koshaSource(r, '09 비중(I28)', at);
  final p = v.parsed;
  if (v.status == ValueStatus.noData || v.status == ValueStatus.itemMissing) {
    return _field(value: null, raw: v.raw, source: src, status: Form6Status.noData, note: v.parseError);
  }
  if (p == null) {
    return _field(value: null, raw: v.raw, source: src, status: Form6Status.needsReview, note: '숫자로 해석 못 함: ${v.parseError}');
  }
  final unit = p.unit == null ? null : normalizeUnit(p.unit!);
  // `1.1 (20℃, 상대 밀도)` — 기준 표기 대신 '상대 밀도'라고 쓴 원문(2026-10-19 수집)
  final relative = unit == '상대밀도';
  final ok = p.unitKind == UnitKind.relativeDensity || relative || p.unit == null || _sgDensityUnits.contains(unit);
  return _field(
    value: p.value,
    raw: v.raw,
    unit: p.unit ?? p.basis,
    condition: p.condition,
    source: src,
    status: ok ? Form6Status.confirmed : Form6Status.needsReview,
    note: ok
        ? (p.unit == null && p.basis == null ? '단위 없음 — 항목 이름이 비중' : null)
        : '단위 ${p.unit} — 비중(물=1)으로 바로 쓸 수 없음',
    extra: {'number': p.number},
  );
}

/// GHS 분류에 인화성(가스·액체·고체·에어로졸)·자연발화성 항목이 있는가. 분류를 모르면 null.
bool? flammableByGhs(List<GhsHazard>? hazards) => hazards?.any((h) => h.item.contains('인화성') || h.item.contains('자연발화'));

/// 폭발한계 하한·상한. %(또는 단위 없음) 숫자는 확정, 해석 실패는 확인필요.
/// 단 원문이 `-`(또는 불연성)이고 **GHS 분류에 인화성 항목이 없으면** '해당없음'(확정) — 두 원천이 같은 말을 할 때만이다.
/// 인화성 분류가 있는데 `-`면 자료가 빠진 것이라 확인필요.
(Map<String, Object?>, Map<String, Object?>) explosionFields(MsdsResult r, String? at, {List<GhsHazard>? ghsHazards, MsdsLog? log}) {
  final lim = r.explosionLimits(log: log);
  final src = koshaSource(r, '09 폭발범위(I20)', at);
  final flammable = flammableByGhs(ghsHazards);
  Map<String, Object?> one(MsdsValue v) {
    final p = v.parsed;
    if (v.status == ValueStatus.noData || v.status == ValueStatus.itemMissing) {
      return _field(value: null, raw: v.raw, source: src, status: Form6Status.noData, note: v.parseError);
    }
    if (p == null) {
      final dash = v.text.split('/').every((s) => RegExp(r'^\s*-?\s*(\(불연성\))?\s*$').hasMatch(s));
      final na = (dash || v.text.contains('불연')) && flammable == false;
      return _field(
        value: na ? '해당없음' : null,
        raw: v.raw,
        source: src,
        status: na ? Form6Status.confirmed : Form6Status.needsReview,
        note: na
            ? "원문 '${v.text}' + GHS 분류에 인화성 항목 없음"
            : (dash && flammable == true)
            ? "원문 '-'인데 GHS 분류에 인화성 항목이 있음 — 자료 빠짐"
            : '숫자로 해석 못 함: ${v.parseError}',
      );
    }
    final ok = p.unit == null || p.unitKind == UnitKind.percent;
    return _field(
      value: p.value,
      raw: v.raw,
      unit: p.unit,
      condition: p.condition,
      source: src,
      status: ok ? Form6Status.confirmed : Form6Status.needsReview,
      note: ok ? null : '단위 ${p.unit} — %가 아님',
      extra: {'number': p.number},
    );
  }

  return (one(lim.lower), one(lim.upper));
}

final _tempMark = RegExp(r'℃|°\s*[CF]|deg\s*[CF]|\d\s*K\b', caseSensitive: false);
final _temp20 = RegExp(r'(^|[^\d.])20\s*(℃|°\s*C|deg\s*C)', caseSensitive: false);

/// 증기압 — 원문 숫자·단위·온도를 두고 mmHg 환산값을 함께(D4). 20℃가 아니면 온도를 붙여 두되 확인필요가 아니다(별지 주⑪).
/// 온도 표기가 없으면 확인필요. 모르는 단위는 환산하지 않고 확인필요.
Map<String, Object?> vaporPressureField(MsdsResult r, String? at, {MsdsLog? log}) {
  final v = r.vaporPressure(log: log);
  final src = koshaSource(r, '09 증기압(I22)', at);
  final p = v.parsed;
  if (v.status == ValueStatus.noData || v.status == ValueStatus.itemMissing) {
    return _field(value: null, raw: v.raw, source: src, status: Form6Status.noData, note: v.parseError);
  }
  if (p == null) {
    return _field(value: null, raw: v.raw, source: src, status: Form6Status.needsReview, note: '숫자로 해석 못 함: ${v.parseError}');
  }
  final factor = p.unit == null ? null : mmHgFactors[normalizeUnit(p.unit!)];
  if (factor == null) {
    return _field(
      value: null,
      raw: v.raw,
      unit: p.unit,
      condition: p.condition,
      source: src,
      status: Form6Status.needsReview,
      note: p.unit == null ? '단위 없음 — 환산 못 함' : '모르는 압력 단위 ${p.unit} — 환산 못 함',
      extra: {'number': p.number},
    );
  }
  final mmHg = sig4(p.value * factor);
  final cond = p.condition;
  // 온도 개수는 해석된 조건이 아니라 원문 본문에서 센다 — 해석기는 온도가 둘이면 마지막 것만 남긴다
  // (`63397 ㎩((21.1 ℃)77,973 Pa(26.6 ℃))` → condition 26.6℃, 2026-10-19 수집)
  final temps = cond == null ? 0 : _tempMark.allMatches(v.text).length;
  final at20 = cond != null && temps == 1 && _temp20.hasMatch(cond);
  return _field(
    value: mmHg,
    raw: v.raw,
    unit: 'mmHg',
    condition: cond,
    source: src,
    status: temps == 1 ? Form6Status.confirmed : Form6Status.needsReview,
    note: temps == 0
        ? '온도 표기 없음'
        : temps > 1
        ? '조건에 온도가 여럿 — 어느 값인지 사람이 본다'
        : (at20 ? null : '20℃가 아닌 값 — 온도를 함께 적는다(별지 주⑪)'),
    extra: {'number': p.number, 'rawUnit': p.unit, 'mmHgFactor': factor},
  );
}

final _twa = RegExp(r'TWA\s*:?\s*(\d+(?:\.\d+)?)\s*(ppm|mg/㎥|㎎/㎥|mg/m3|mg/m³|f/cc|개/㎤)?', caseSensitive: false);

/// 허용농도(TWA) — 8절 '국내규정'(H0202)에서 TWA 숫자를 찾는다(국내 고용노동부 노출기준 우선 — 작성 매뉴얼).
/// ACGIH 등 다른 기준은 고르지 않고 메모에 원문으로 남긴다.
Map<String, Object?> twaField(MsdsResult r, String? at) {
  final src = koshaSource(r, '08 국내규정(H0202)', at);
  final items = r.exposureLimits();
  final domestic = items.where((i) => i.code == 'H0202').firstOrNull;
  final others = [
    for (final i in items)
      if (i.code != 'H0202' && (i.detail ?? '').trim().isNotEmpty && i.detail!.trim() != noDataText) '${i.nameKor}: ${i.detail!.trim()}',
  ];
  final otherNote = others.isEmpty ? null : '다른 기준(고르지 않음) — ${others.join(' / ')}';
  if (domestic == null) {
    return _field(value: null, raw: '', source: src, status: Form6Status.noData, note: ['국내규정 항목 없음', if (otherNote != null) otherNote].join('; '));
  }
  final raw = domestic.detail ?? '';
  // KOSHA 8절 값은 `|`로 줄을 나눈다 — `|자료없음`처럼 앞에 붙어 온다(2026-10-19 수집)
  final text = splitOrigin(raw).$1.replaceAll(RegExp(r'^[\s|]+|[\s|]+$'), '');
  if (text.isEmpty || text == noDataText) {
    return _field(value: null, raw: raw, source: src, status: Form6Status.noData, note: ['국내규정 자료없음', if (otherNote != null) otherNote].join('; '));
  }
  final m = _twa.firstMatch(text);
  if (m == null) {
    final ceilingOnly = RegExp(r'STEL\s*:?\s*C', caseSensitive: false).hasMatch(text);
    return _field(
      value: null,
      raw: raw,
      source: src,
      status: Form6Status.needsReview,
      note: [ceilingOnly ? '국내규정에 TWA 없음(최고노출기준 C만)' : '국내규정에 TWA 숫자 없음', if (otherNote != null) otherNote].join('; '),
    );
  }
  return _field(
    value: double.parse(m.group(1)!),
    raw: raw,
    unit: m.group(2),
    source: src,
    status: m.group(2) == null ? Form6Status.needsReview : Form6Status.confirmed,
    note: m.group(2) == null ? 'TWA 단위 없음' : null,
    extra: {'number': m.group(1)},
  );
}

/// 이 CAS의 GHS 분류 — 완전 일치 1건이고 잘리지 않았을 때만. 아니면 null(모른다).
List<GhsHazard>? exactGhsHazards(String cas, ServiceResult? ghs) {
  if (ghs is! ServiceOk || ghs.truncated) return null;
  final exact = [for (final rec in ghs.records.cast<GhsRecord>()) if (rec.casNo == cas) rec];
  return exact.length == 1 && exact.single.hazards.isNotEmpty ? exact.single.hazards : null;
}

/// 독성구분 — 환경공단 유독물 GHS 분류 **전체**를 원문 순서 그대로(결정 ③ — 대표 1개는 채울 때 고른다).
/// 부식성 — 같은 분류 목록에 금속부식성이 있으면 유, 목록이 있는데 없으면 무(D5).
(Map<String, Object?>, Map<String, Object?>) ghsFields(String cas, ServiceResult? ghs, String rawText, String? at) {
  final src = ghsSource(at);
  if (ghs == null || ghs is ServiceFailed) {
    final why = ghs is ServiceFailed ? 'GHS 응답 실패: ${ghs.message}' : 'GHS 원문 없음';
    final f = _field(value: null, raw: '', source: src, status: Form6Status.needsReview, note: why);
    return (f, f);
  }
  final ok = ghs as ServiceOk;
  final exact = [for (final rec in ok.records.cast<GhsRecord>()) if (rec.casNo == cas) rec];
  final truncated = ok.truncated ? '응답 ${ok.total}건 중 ${ok.records.length}건만 받음 — ' : '';
  if (exact.isEmpty) {
    final f = _field(
      value: null,
      raw: '',
      source: src,
      status: ok.truncated ? Form6Status.needsReview : Form6Status.noData,
      note: '$truncated환경공단 GHS에 이 CAS 완전 일치가 없음(받은 ${ok.records.length}건)',
    );
    return (f, f);
  }
  if (exact.length > 1 || ok.truncated) {
    final f = _field(
      value: null,
      raw: '',
      source: src,
      status: Form6Status.needsReview,
      note: '$truncated완전 일치 ${exact.length}건 — 고르지 않음',
    );
    return (f, f);
  }
  final rec = exact.single;
  final list = [for (final h in rec.hazards) {'item': h.item, 'grade': h.grade, 'hCode': h.hCode}];
  final rawLines = [for (final h in rec.hazards) '${h.item}|${h.grade}|${h.hCode}'].join('\n');
  final ghsField = _field(
    value: list,
    raw: rawLines,
    source: src,
    status: list.isEmpty ? Form6Status.noData : Form6Status.confirmed,
    note: list.isEmpty ? '분류 목록이 비었음' : null,
    extra: {'classNumbers': rec.classNumbers},
  );
  final metal = rec.hazards.where((h) => h.item.contains('금속부식')).toList();
  final corrosive = list.isEmpty
      ? _field(value: null, raw: '', source: src, status: Form6Status.noData, note: '분류 목록이 비었음')
      : metal.isNotEmpty
      ? _field(
          value: '유',
          raw: metal.map((h) => '${h.item}|${h.grade}|${h.hCode}').join('\n'),
          source: src,
          status: Form6Status.confirmed,
        )
      : _field(value: '무', raw: '', source: src, status: Form6Status.confirmed, note: '분류 목록에 금속부식성 없음');
  return (ghsField, corrosive);
}

/// 위험노출수준 — 있는 값 전부(D6). 고르기는 채울 때 별지 주⑨ 순서(ERPG → AEGL → PAC → IDLH)로.
Map<String, Object?> exposureField(String cas, ExposureTables? exposure) {
  if (exposure == null) {
    return _field(
      value: null,
      raw: '',
      source: {'kind': '위험노출수준 표', 'id': null, 'version': null, 'section': null, 'collectedAt': null},
      status: Form6Status.needsReview,
      note: '위험노출수준 원천 표를 싣지 않고 만들었음',
    );
  }
  return exposure.fieldOf(cas);
}

/// 한 CAS의 9칸.
Map<String, Object?> buildSubstance({
  required String cas,
  required MsdsResult kosha,
  required ServiceResult? ghs,
  required String ghsRaw,
  required ExposureTables? exposure,
  required String? collectedAt,
  MsdsLog? log,
}) {
  final Map<String, Object?> fields;
  if (kosha.status != MsdsStatus.found) {
    final m = _missingKosha(kosha, collectedAt);
    final (g, c) = ghsFields(cas, ghs, ghsRaw, collectedAt);
    fields = {
      'state': m,
      'specificGravity': m,
      'lel': m,
      'uel': m,
      'ghs': g,
      'exposure': exposureField(cas, exposure),
      'twa': m,
      'vaporPressure': m,
      'corrosive': c,
    };
  } else {
    final (lel, uel) = explosionFields(kosha, collectedAt, ghsHazards: exactGhsHazards(cas, ghs), log: log);
    final (g, c) = ghsFields(cas, ghs, ghsRaw, collectedAt);
    fields = {
      'state': stateField(kosha, collectedAt),
      'specificGravity': specificGravityField(kosha, collectedAt, log: log),
      'lel': lel,
      'uel': uel,
      'ghs': g,
      'exposure': exposureField(cas, exposure),
      'twa': twaField(kosha, collectedAt),
      'vaporPressure': vaporPressureField(kosha, collectedAt, log: log),
      'corrosive': c,
    };
  }
  return {
    'cas': cas,
    'koshaName': kosha.source?['nameKor'],
    'fields': {for (final n in form6FieldNames) n: fields[n]},
  };
}
