/// KOSHA MSDS 항목 값 해석 — 원문 보존, 숫자·단위·조건 분리, H코드·그림문자(A-003, REQUIREMENTS_AGENT A-003 1차).
///
/// KOSHA 값은 자유 문자열이다(plan.md 'KOSHA MSDS 조회 서비스 실측'): `1.15`, `0.8623 (g/cu cm at 20℃)`, `0.79 (물=1, 20℃)`,
/// `자료없음`, 끝에 `|   ※출처 : ECHA`. **추측하지 않는다** — 원문이 숫자로 시작하지 않으면 해석하지 않고(`unparsed`),
/// 단위가 원문에 없으면 무차원으로 단정하지 않는다(`unit: null`, `unitKind: unknown`). 단위 환산은 하지 않는다(Q4 — A-004·A-005 몫).
///
/// **Flutter를 import하지 않는다**(Q1) — 원격 MCP 서버(순수 Dart)가 같이 쓴다. 로그는 [MsdsLog] 콜백으로 받는다.
library;

/// 로그 콜백. 해석 실패처럼 결과에도 남는 일을 원인과 함께 한 줄 적는다.
typedef MsdsLog = void Function(String message);

enum ValueStatus {
  /// 숫자를 뽑았다.
  value,

  /// 원문이 정확히 `자료없음`.
  noData,

  /// 원문은 있는데 숫자를 못 뽑았다(`해당없음` 포함) — 원문과 사유를 남긴다.
  unparsed,

  /// 응답에 그 항목 코드가 없다(2차 — 상세 응답 조립에서 쓴다).
  itemMissing,

  /// 그 절 호출이 실패했다(2차).
  fetchFailed,
}

/// 단위의 종류(Q4). 환산은 하지 않고 같은 종류인지만 판정할 수 있게 한다.
enum UnitKind { density, relativeDensity, pressure, percent, unknown }

/// 해석한 숫자. [number]는 원문에 있던 문자열 그대로(지어낸 숫자 0건을 검사할 수 있게).
class ParsedNumber {
  const ParsedNumber({
    required this.number,
    required this.value,
    required this.unit,
    required this.unitKind,
    required this.basis,
    required this.condition,
  });

  final String number;
  final double value;

  /// 원문 표기 그대로(`g/cu cm`). 원문에 없으면 null.
  final String? unit;
  final UnitKind unitKind;

  /// 상대값의 기준(`물=1`). 없으면 null.
  final String? basis;

  /// 측정 조건(`20℃`). 없으면 null.
  final String? condition;

  Map<String, Object?> toJson() => {
    'number': number,
    'value': value,
    'unit': unit,
    'unitKind': unitKind.name,
    'basis': basis,
    'condition': condition,
  };
}

/// 항목 값 하나. [raw]는 응답 원문 그대로(출처 꼬리 포함).
class MsdsValue {
  const MsdsValue({
    required this.raw,
    required this.text,
    required this.origin,
    required this.status,
    this.parsed,
    this.parseError,
  });

  final String raw;

  /// 출처 꼬리를 뺀 본문.
  final String text;

  /// 출처 꼬리의 출처 이름(`ECHA`). 없으면 null.
  final String? origin;
  final ValueStatus status;
  final ParsedNumber? parsed;
  final String? parseError;

  Map<String, Object?> toJson() => {
    'raw': raw,
    'text': text,
    'origin': origin,
    'status': status.name,
    'parsed': parsed?.toJson(),
    'parseError': parseError,
  };
}

const noDataText = '자료없음';

final _originTail = RegExp(r'\|\s*※\s*출처\s*:\s*(.*?)\s*$');

/// 원문 → (본문, 출처). 꼬리가 없으면 출처 null.
(String, String?) splitOrigin(String raw) {
  final m = _originTail.firstMatch(raw);
  if (m == null) return (raw.trim(), null);
  final origin = m.group(1)!.trim();
  return (raw.substring(0, m.start).trim(), origin.isEmpty ? null : origin);
}

// 앞머리 숫자: 천 단위 쉼표(`6,780`)와 소수를 받는다. 부호는 받는다(온도 등).
final _leadingNumber = RegExp(r'^-?(?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?');
final _paren = RegExp(r'\((.*)\)');
final _basis = RegExp(r'^\s*(물|공기)\s*=\s*1\s*$');
final _temperature = RegExp(r'(℃|°C|°F|\bK\b)');

/// 숫자 하나짜리 값(비중·증기압 등)을 해석한다. 숫자로 시작하지 않으면 해석하지 않는다.
MsdsValue parseNumberValue(String raw, {MsdsLog? log}) {
  final (text, origin) = splitOrigin(raw);
  if (text == noDataText) {
    return MsdsValue(raw: raw, text: text, origin: origin, status: ValueStatus.noData);
  }
  final m = _leadingNumber.firstMatch(text);
  if (m == null) {
    const reason = '숫자로 시작하지 않음';
    log?.call('MSDS 값 해석 실패($reason): "$raw"');
    return MsdsValue(raw: raw, text: text, origin: origin, status: ValueStatus.unparsed, parseError: reason);
  }
  final number = m.group(0)!;
  final rest = text.substring(m.end).trim();

  String? unit;
  String? basis;
  String? condition;
  final p = _paren.firstMatch(rest);
  final outside = (p == null ? rest : rest.substring(0, p.start)).trim();
  if (outside.isNotEmpty) unit = outside;
  if (p != null) {
    final inside = p.group(1)!.trim();
    final at = inside.indexOf(' at ');
    if (at >= 0) {
      // `g/cu cm at 20℃`
      unit ??= inside.substring(0, at).trim();
      condition = inside.substring(at + 4).trim();
    } else {
      // `물=1, 20℃`
      for (final part in inside.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty)) {
        if (_basis.hasMatch(part)) {
          basis = part.replaceAll(' ', '');
        } else if (_temperature.hasMatch(part)) {
          condition = part;
        } else if (unit == null) {
          unit = part;
        } else {
          condition = condition == null ? part : '$condition, $part';
        }
      }
    }
  }

  return MsdsValue(
    raw: raw,
    text: text,
    origin: origin,
    status: ValueStatus.value,
    parsed: ParsedNumber(
      number: number,
      value: double.parse(number.replaceAll(',', '')),
      unit: unit,
      unitKind: classifyUnit(unit, basis),
      basis: basis,
      condition: condition,
    ),
  );
}

/// 단위 표기 → 종류. 기준이 `물=1`이면 상대밀도. 모르는 표기·단위 없음은 unknown(단정하지 않는다).
UnitKind classifyUnit(String? unit, String? basis) {
  if (basis != null) return UnitKind.relativeDensity;
  if (unit == null) return UnitKind.unknown;
  final u = unit.toLowerCase().replaceAll(' ', '').replaceAll('³', '3');
  const density = {'g/cucm', 'g/cm3', 'g/cc', 'g/ml', 'kg/m3', 'g/l', 'kg/l'};
  const pressure = {'mmhg', 'hpa', 'kpa', 'pa', 'mpa', 'atm', 'bar', 'mbar', 'torr', 'psi'};
  if (density.contains(u)) return UnitKind.density;
  if (pressure.contains(u)) return UnitKind.pressure;
  if (u == '%' || u == 'vol%' || u == '%vol' || u == 'v/v%') return UnitKind.percent;
  return UnitKind.unknown;
}

/// H코드 한 줄. 형식이 어긋난 조각은 [code]·[phrase]가 null이고 [raw]만 남는다.
class HazardStatement {
  const HazardStatement({required this.raw, required this.code, required this.phrase});

  final String raw;
  final String? code, phrase;

  Map<String, Object?> toJson() => {'raw': raw, 'code': code, 'phrase': phrase};
}

final _hLine = RegExp(r'^(H\d{3}[A-Za-z]*(?:\s*\+\s*H\d{3}[A-Za-z]*)*)\s*:\s*(.*)$');

/// 2절 B0406 `H220 : 극인화성 가스|H280 : …` → 코드마다 한 줄. `자료없음`이면 빈 목록.
List<HazardStatement> parseHazardStatements(String raw, {MsdsLog? log}) {
  final (text, _) = splitOrigin(raw);
  if (text.isEmpty || text == noDataText) return const [];
  return [
    for (final piece in text.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty))
      _hazard(piece, log),
  ];
}

HazardStatement _hazard(String piece, MsdsLog? log) {
  final m = _hLine.firstMatch(piece);
  if (m == null) {
    log?.call('MSDS H코드 형식 아님(원문 그대로 둠): "$piece"');
    return HazardStatement(raw: piece, code: null, phrase: null);
  }
  return HazardStatement(raw: piece, code: m.group(1)!.replaceAll(' ', ''), phrase: m.group(2)!.trim());
}

/// 그림문자 하나. [standard]는 GHS 표준 번호(`GHS04`), 모르는 형식이면 null.
class Pictogram {
  const Pictogram({required this.koshaRaw, required this.standard});

  final String koshaRaw;
  final String? standard;

  Map<String, Object?> toJson() => {'koshaRaw': koshaRaw, 'standard': standard};
}

final _koshaPictogram = RegExp(r'^GHS(\d{2})\.gif$', caseSensitive: false);

/// 2절 그림문자 `GHS02.gif|GHS03.gif` → 표준 번호로.
///
/// **KOSHA 번호 03·04는 GHS 표준과 뒤바뀌어 있다**(2026-10-01 실측 8물질 — plan.md 'KOSHA MSDS 조회 서비스 실측'):
/// KOSHA `GHS03.gif` = 가스실린더(표준 GHS04 고압가스), `GHS04.gif` = 원 위의 불꽃(표준 GHS03 산화성).
/// 질소(고압가스만) → KOSHA 03, 과산화수소(산화성만) → KOSHA 04, 산소·염소(둘 다) → 03+04. 01·02·05~09는 같았다.
List<Pictogram> parsePictograms(String raw, {MsdsLog? log}) {
  final (text, _) = splitOrigin(raw);
  if (text.isEmpty || text == noDataText) return const [];
  return [
    for (final piece in text.split('|').map((s) => s.trim()).where((s) => s.isNotEmpty))
      Pictogram(koshaRaw: piece, standard: _standardOf(piece, log)),
  ];
}

String? _standardOf(String piece, MsdsLog? log) {
  final m = _koshaPictogram.firstMatch(piece);
  if (m == null) {
    log?.call('MSDS 그림문자 형식 아님(표준 번호 없음): "$piece"');
    return null;
  }
  final n = m.group(1)!;
  final fixed = switch (n) { '03' => '04', '04' => '03', _ => n };
  return 'GHS$fixed';
}
