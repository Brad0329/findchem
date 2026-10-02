/// A-004 계산 도구 — 작성수준 판정(별지 제1호)과 예비시나리오 대상 산정(제23조ㆍ별표 2)의 **산술과 비교**.
///
/// 에이전트가 암산하지 않게 코드로 한다. 규정수량ㆍ함량기준은 호출자가 주지 않는다 —
/// 물질을 `src`+`no`로 받아 번들 데이터에서 읽는다(지어낸 수량 차단). 결정과 근거: REQUIREMENTS_AGENT A-004.
///
/// - 원문이 기계적으로 정하는 것만 코드가 정한다(유해성 구분 행의 함량기준 비교, 별표3 질산의 함량 구간).
///   원문이 성상 판단에 맡긴 것(용액ㆍ* 행, 저확산 행)은 호출자가 값으로 정하고, 없으면 `selection_required`.
/// - 예외를 밖으로 던지지 않는다 — 설비마다 오류 사유를 돌려주고, 하나라도 있으면 판정 전체가 `incomplete`.
/// - Flutter를 import하지 않는다(원격 MCP 서버가 `dart compile exe`로 돈다).
library;

import '../assist/conditions.dart';
import '../parser/models.dart';

/// 작성 규정 고시(계산 규칙의 원천). 규정수량 고시는 `lib/assist/rules.dart`의 `notice`.
const planNotice = '화학물질안전원고시 「화학사고예방관리계획서 작성 등에 관한 규정」 제2026-19호(2026-10-01 시행)';

/// 한 번에 받는 설비 상한. 넘으면 계산하지 않고 전체 건수를 돌려준다(조용한 절단 금지).
const calcFacilityCap = 500;

/// 비중(물=1) 상한. 이보다 크면 g/L 등 다른 단위로 넣은 값으로 본다(가장 무거운 원소도 약 22.6).
const maxSpecificGravity = 23.0;

abstract final class CalcToolName {
  static const level = 'calc_writing_level';
  static const scenario = 'screen_preliminary_scenarios';
}

/// 계산 결과. [error]가 있으면 요청 전체를 처리하지 못한 것(입력 형식 오류ㆍ상한 초과).
class CalcOutcome {
  const CalcOutcome(this.response, {this.error});

  final Map<String, Object?> response;
  final String? error;

  bool get isError => error != null;
}

// ───── 수량ㆍ함량기준 문자열 해석 ─────

/// 규정수량 원문(`"0.2*"`, `"400"`, `"-"`) → 톤. 숫자가 없으면 null('-' = 그 수량이 없음).
double? quantityOf(String raw) => double.tryParse(raw.replaceAll('*', '').trim());

/// 함량기준. [strict]면 '초과'(질산 `70% 초과`), 아니면 '이상'.
class Threshold {
  const Threshold(this.pct, {this.strict = false, required this.raw, this.inherited = false});

  final double pct;
  final bool strict;
  final String raw;

  /// 빈 칸이라 같은 항목 다른 행의 가장 낮은 숫자 기준을 쓴 것(별표 2 일반기준 나ㆍ다).
  final bool inherited;

  bool met(double content) => strict ? _r(content) > _r(pct) : _r(content) >= _r(pct);

  Map<String, Object?> toJson() => {
        'pct': pct,
        'rule': strict ? '초과' : '이상',
        'raw': raw,
        if (inherited) 'inherited': '빈 칸 — 같은 항목 다른 행의 숫자 함량기준 중 가장 낮은 것(별표 2 일반기준 나ㆍ다 해석)',
      };
}

final _pctRaw = RegExp(r'^([0-9.]+)\s*(?:%\s*초과)?$');

Threshold? _ownThreshold(String raw) {
  final m = _pctRaw.firstMatch(raw.trim());
  if (m == null) return null;
  final v = double.tryParse(m.group(1)!);
  if (v == null) return null;
  return Threshold(v, strict: raw.contains('초과'), raw: raw);
}

/// 행 [r]의 함량기준. 빈 칸이면 같은 항목 다른 행의 숫자 기준 중 가장 낮은 것. 끝내 없으면 null.
Threshold? thresholdOf(Entry e, QuantityRow r) {
  final own = _ownThreshold(r.content);
  if (own != null) return own;
  if (r.content.trim().isNotEmpty) return null; // '-' 등 — 숫자 기준이 없다
  final siblings = [
    for (final s in e.rows)
      if (!identical(s, r)) ?_ownThreshold(s.content),
  ]..sort((a, b) => a.pct.compareTo(b.pct));
  if (siblings.isEmpty) return null;
  return Threshold(siblings.first.pct, strict: siblings.first.strict, raw: siblings.first.raw, inherited: true);
}

/// 항목의 숫자 함량기준 중 가장 낮은 것(예비시나리오 '함량미만' 판정).
Threshold? lowestThresholdOf(Entry e) {
  final all = [for (final r in e.rows) ?_ownThreshold(r.content)]..sort((a, b) => a.pct.compareTo(b.pct));
  return all.firstOrNull;
}

/// 부동소수 비교 오차를 없애려고 6자리에서 반올림한다(표시도 같은 값).
double _r(double v) => (v * 1e6).roundToDouble() / 1e6;

// 행 판별(용액ㆍ* 행, 저확산 행)은 F-008 condition 문장과 같은 함수(`conditions.dart`)를 쓴다.
// 빈 함량기준 해석([thresholdOf])은 여기에만 있다 — condition 문장과의 대조는 test/calc/calc_test.dart.
const _isSolution = isSolutionRow;
const _isLowDiffusion = isLowDiffusionRow;

// ───── 입력 ─────

class _Input {
  _Input(this.index, this.raw);

  final int index;
  final Map<String, Object?> raw;

  String? str(String k) => raw[k] is String ? (raw[k] as String).trim() : null;
  double? num_(String k) => raw[k] is num ? (raw[k] as num).toDouble() : null;
  bool? flag(String k) => raw[k] is bool ? raw[k] as bool : null;
  bool has(String k) => raw.containsKey(k) && raw[k] != null;
}

/// 설비 목록을 꺼낸다. 형식이 틀리면 사유 문자열.
Object _facilities(Map<String, Object?> args) {
  final list = args['facilities'];
  if (list is! List || list.isEmpty) return 'facilities는 비어 있지 않은 배열이어야 합니다';
  if (list.length > calcFacilityCap) {
    return '설비가 ${list.length}개로 상한 $calcFacilityCap개를 넘어 계산하지 않았습니다 — 단위공장 등으로 나눠 부르세요';
  }
  final out = <_Input>[];
  for (var i = 0; i < list.length; i++) {
    final f = list[i];
    if (f is! Map) return 'facilities[$i]는 객체여야 합니다';
    out.add(_Input(i, f.cast<String, Object?>()));
  }
  return out;
}

/// 공통 검증 + 항목 찾기. 실패면 사유.
Object _entryOf(Dataset ds, _Input f) {
  final src = f.str('src');
  final no = f.raw['no'];
  final source = switch (src) {
    '별표2' => Source.byeolpyo2,
    '별표3' => Source.byeolpyo3,
    _ => null,
  };
  if (source == null) return "src는 '별표2' 또는 '별표3'이어야 합니다(search_chemical 결과의 표)";
  if (no is! int) return 'no는 정수여야 합니다(search_chemical 결과의 연번ㆍ번호)';
  final e = ds.entries.where((e) => e.src == source && e.no == no).firstOrNull;
  if (e == null) return '$src 제$no호가 데이터에 없습니다';
  if (e.deleted) return '$src 제$no호는 (삭제)된 항목이라 규정수량이 없습니다';
  return e;
}

String _id(Entry e) => '${e.src.id} 제${e.no}호';

/// 별표 2 일반기준 가 — 별표2 항목인데 같은 CAS가 별표3에 있으면.
/// 함량이 별표3 기준 이상이면 오류 사유, 미만이면 note, 별표3이 없으면 null.
({String? error, String? note}) _ruleGa(Dataset ds, Entry e, double content) {
  if (e.src == Source.byeolpyo3) {
    final low = lowestThresholdOf(e);
    if (low != null && !low.met(content)) {
      final b2 = ds.entries.where((x) => x.src == Source.byeolpyo2 && !x.deleted && x.cas.any(e.cas.contains));
      if (b2.isNotEmpty) {
        return (
          error: null,
          note: '함량이 ${_id(e)}의 함량기준(${low.raw}%) 미만이다 — 같은 CAS가 ${b2.map(_id).join(', ')}에 있으니 '
              '그 항목으로 다시 계산해야 할 수 있다',
        );
      }
    }
    return (error: null, note: null);
  }
  for (final x in ds.entries) {
    if (x.src != Source.byeolpyo3 || !x.cas.any(e.cas.contains)) continue;
    final low = lowestThresholdOf(x);
    if (low == null || low.met(content)) {
      return (error: '별표 2 일반기준 가 — 사고대비물질이므로 ${_id(x)}를 적용해야 합니다(src: 별표3, no: ${x.no})', note: null);
    }
    return (
      error: null,
      note: '같은 CAS가 ${_id(x)}에 있으나 함량이 그 함량기준(${low.raw}%) 미만이라 ${_id(e)}로 계산했다(별표 2 일반기준 가)',
    );
  }
  return (error: null, note: null);
}

/// 함량(%) 검증. 실패면 사유.
Object _content(_Input f) {
  final c = f.num_('content_pct');
  if (c == null) return 'content_pct(함량 %)는 숫자여야 합니다 — 순물질이면 100';
  if (c <= 0 || c > 100) return 'content_pct는 0 초과 100 이하여야 합니다(받은 값 $c)';
  return c;
}

/// 성상 판단이 필요한 행이 있는데 호출자가 값을 주지 않았을 때의 선택지.
Map<String, Object?> _choices(Entry e, String field, String why) => {
      'field': field,
      'why': why,
      'rows': [
        for (var i = 0; i < e.rows.length; i++)
          {
            'row': i,
            'kind': e.rows[i].kind,
            'content': e.rows[i].content,
            'low': e.rows[i].low,
            'high': e.rows[i].high,
            'condition': conditionOf(e, e.rows[i]),
          },
      ],
    };

/// 이 설비에 대해 평가할 행(성상 선택까지 끝난 후보). 선택이 필요하면 [selection], 입력이 틀리면 [error].
({List<int> rows, bool exclusive, Map<String, Object?>? selection, String? error}) _candidateRows(Entry e, _Input f) {
  final all = [for (var i = 0; i < e.rows.length; i++) i];
  final solution = all.where((i) => _isSolution(e, e.rows[i])).toList();
  final lowDiff = all.where((i) => _isLowDiffusion(e.rows[i])).toList();
  final liquid = f.flag('ambient_liquid');
  final ld = f.flag('low_diffusion');

  if (f.has('ambient_liquid') && liquid == null) return (rows: [], exclusive: false, selection: null, error: 'ambient_liquid는 true/false');
  if (f.has('low_diffusion') && ld == null) return (rows: [], exclusive: false, selection: null, error: 'low_diffusion은 true/false');
  if (liquid == true && solution.isEmpty) {
    return (rows: [], exclusive: false, selection: null, error: '${_id(e)}에는 용액ㆍ* 표시 행이 없어 ambient_liquid: true를 쓸 수 없습니다');
  }
  if (ld == true && lowDiff.isEmpty) {
    return (rows: [], exclusive: false, selection: null, error: '${_id(e)}에는 저확산 행이 없어 low_diffusion: true를 쓸 수 없습니다');
  }

  var rest = all;
  if (solution.isNotEmpty) {
    if (liquid == null) {
      return (
        rows: [],
        exclusive: false,
        error: null,
        selection: _choices(e, 'ambient_liquid',
            '상온ㆍ상압조건에서 성상이 액체이면 용액ㆍ* 표시 행을 적용한다(별표 2 일반기준 나 / 별표 3 일반기준 가) — 액체인지 정해 다시 부를 것'),
      );
    }
    if (liquid) return (rows: solution, exclusive: true, selection: null, error: null);
    rest = rest.where((i) => !solution.contains(i)).toList();
  }
  if (lowDiff.isNotEmpty) {
    if (ld == null) {
      return (
        rows: [],
        exclusive: false,
        error: null,
        selection: _choices(e, 'low_diffusion',
            '취급 과정에서 성상이 액체나 고체이면 저확산 행을 그 물질의 규정수량으로 한다(별표 2 일반기준 다) — 적용 여부를 정해 다시 부를 것'),
      );
    }
    if (ld) return (rows: lowDiff, exclusive: true, selection: null, error: null);
    rest = rest.where((i) => !lowDiff.contains(i)).toList();
  }
  // 별표3에서 구분 없이 함량기준만 다른 행(제46호 질산) — 함량이 맞는 행 중 하나만 적용된다.
  final exclusive = e.src == Source.byeolpyo3;
  return (rows: rest, exclusive: exclusive, selection: null, error: null);
}

/// 후보 행 중 함량이 기준을 넘는 행. 별표3 구간 행은 기준이 가장 높은 하나만.
({List<int> applied, List<Map<String, Object?>> belowContent, List<String> notes}) _apply(
    Entry e, List<int> rows, bool exclusive, double content) {
  final applied = <int>[];
  final below = <Map<String, Object?>>[];
  final notes = <String>[];
  for (final i in rows) {
    final t = thresholdOf(e, e.rows[i]);
    if (t == null) {
      applied.add(i);
      notes.add("행 $i('${e.rows[i].kind}')에 숫자 함량기준이 없어 함량과 비교하지 않고 포함했다");
    } else if (t.met(content)) {
      applied.add(i);
    } else {
      below.add({'row': i, 'kind': e.rows[i].kind, 'threshold': t.toJson()});
    }
  }
  if (exclusive && applied.length > 1) {
    applied.sort((a, b) => (thresholdOf(e, e.rows[b])?.pct ?? 0).compareTo(thresholdOf(e, e.rows[a])?.pct ?? 0));
    notes.add('함량기준만 다른 행이 여럿 맞아 기준이 가장 높은 행 ${applied.first}을 적용했다');
    applied.removeRange(1, applied.length);
  }
  return (applied: applied, belowContent: below, notes: notes);
}

// ───── 작성수준(별지 제1호) ─────

enum Level {
  none('미해당'),
  group2('2군'),
  group1('1군');

  const Level(this.label);
  final String label;
}

Level _levelOf(double total, QuantityRow r) {
  final high = quantityOf(r.high);
  final low = quantityOf(r.low);
  if (high != null && _r(total) >= _r(high)) return Level.group1;
  if (low != null && _r(total) >= _r(low)) return Level.group2;
  return Level.none;
}

/// 취급량. 용량(m³)×비중×[scale] 또는 직접 준 양([direct] 필드, [unit] 단위). 실패면 사유.
/// 작성수준은 톤(scale 1, `quantity_ton`), 예비시나리오는 kg(scale 1000, `quantity_kg`).
Object _amount(_Input f, {required String direct, required double scale, required String unit}) {
  final cap = f.num_('capacity_m3');
  final sg = f.num_('specific_gravity');
  final q = f.num_(direct);
  if (q != null && (cap != null || sg != null)) return '$direct과 capacity_m3ㆍspecific_gravity는 함께 쓸 수 없습니다';
  if (q != null) {
    if (q < 0) return '$direct은 0 이상이어야 합니다';
    if (f.str('basis')?.isNotEmpty != true) return '$direct을 쓰면 산정 근거(basis — 예: 충전량, 보관구획도)를 함께 주어야 합니다';
    return (value: _r(q), formula: '$direct 직접 기재');
  }
  if (cap == null || sg == null) return 'capacity_m3와 specific_gravity(물=1 상대밀도)를 함께 주거나 $direct을 주어야 합니다';
  if (cap < 0) return 'capacity_m3는 0 이상이어야 합니다';
  if (sg <= 0 || sg > maxSpecificGravity) {
    return 'specific_gravity $sg는 물=1 기준 상대밀도(0 초과 $maxSpecificGravity 이하)가 아닙니다 — g/L이면 1000으로 나눈 값을 넣으세요';
  }
  final v = _r(cap * sg * scale);
  return (value: v, formula: scale == 1 ? '$cap m³ × $sg = $v $unit' : '$cap m³ × $sg × ${scale.toInt()} = $v $unit');
}

CalcOutcome calcWritingLevel(Dataset ds, Map<String, Object?> args) {
  final parsed = _facilities(args);
  if (parsed is String) return CalcOutcome(const {}, error: parsed);
  final inputs = parsed as List<_Input>;

  final facilities = <Map<String, Object?>>[];
  final issues = <String>[];
  // 항목 → 행 → 그 행에 들어간 설비 양
  final perRow = <Entry, Map<int, List<({int index, double ton})>>>{};
  final perEntryTotal = <Entry, double>{};
  final notesByEntry = <Entry, Set<String>>{};

  for (final f in inputs) {
    final out = <String, Object?>{
      'index': f.index,
      'unit_plant': ?f.str('unit_plant'),
      'facility': ?f.str('facility'),
      'src': f.raw['src'],
      'no': f.raw['no'],
    };
    facilities.add(out);
    void fail(String why) {
      out['status'] = 'error';
      out['error'] = why;
      issues.add('facilities[${f.index}]: $why');
    }

    final e = _entryOf(ds, f);
    if (e is String) {
      fail(e);
      continue;
    }
    final entry = e as Entry;
    out['substance'] = entry.ko.isNotEmpty ? entry.ko : entry.name;
    final c = _content(f);
    if (c is String) {
      fail(c);
      continue;
    }
    final content = c as double;
    out['content_pct'] = content;
    final ga = _ruleGa(ds, entry, content);
    if (ga.error != null) {
      fail(ga.error!);
      continue;
    }
    final amount = _amount(f, direct: 'quantity_ton', scale: 1, unit: 't');
    if (amount is String) {
      fail(amount);
      continue;
    }
    final a = amount as ({double value, String formula});
    out['amount_ton'] = a.value;
    out['formula'] = a.formula;
    if (f.str('basis') case final b? when b.isNotEmpty) out['basis'] = b;

    final cand = _candidateRows(entry, f);
    if (cand.error != null) {
      fail(cand.error!);
      continue;
    }
    if (cand.selection != null) {
      out['status'] = 'selection_required';
      out['selection'] = cand.selection;
      issues.add('facilities[${f.index}]: ${_id(entry)} 행 선택 필요(${cand.selection!['field']})');
      continue;
    }
    final ap = _apply(entry, cand.rows, cand.exclusive, content);
    final notes = [?ga.note, ...ap.notes];
    if (notes.isNotEmpty) out['notes'] = notes;
    if (ap.belowContent.isNotEmpty) out['below_content_rows'] = ap.belowContent;
    if (ap.applied.isEmpty) {
      out['status'] = '함량미만';
      continue;
    }
    out['status'] = 'included';
    out['rows_applied'] = ap.applied;
    final rows = perRow.putIfAbsent(entry, () => {});
    for (final i in ap.applied) {
      rows.putIfAbsent(i, () => []).add((index: f.index, ton: a.value));
    }
    perEntryTotal[entry] = _r((perEntryTotal[entry] ?? 0) + a.value);
    notesByEntry.putIfAbsent(entry, () => {}).addAll(notes);
  }

  // 물질별 판정 — 행마다 그 행에 들어간 양을 합해 비교하고, 가장 높은 판정이 물질의 판정.
  final substances = <Map<String, Object?>>[];
  final levels = <Entry, Level>{};
  final viaLowDiffusion = <Entry>{};
  for (final MapEntry(key: e, value: rows) in perRow.entries) {
    var best = Level.none;
    int? decisive;
    final rowOut = <Map<String, Object?>>[];
    for (final MapEntry(key: i, value: list) in rows.entries) {
      final r = e.rows[i];
      final total = _r(list.fold(0.0, (s, x) => s + x.ton));
      final lv = _levelOf(total, r);
      rowOut.add({
        'row': i,
        'kind': r.kind,
        'threshold': thresholdOf(e, r)?.toJson(),
        'low': r.low,
        'high': r.high,
        'total_ton': total,
        'facilities': [for (final x in list) x.index],
        'level': lv.label,
      });
      if (decisive == null || lv.index > best.index) {
        best = lv;
        decisive = i;
      }
    }
    levels[e] = best;
    if (_isLowDiffusion(e.rows[decisive!])) viaLowDiffusion.add(e);
    substances.add({
      'src': e.src.id,
      'no': e.no,
      'name': e.ko.isNotEmpty ? e.ko : e.name,
      'cas': e.cas,
      'max_holding_ton': perEntryTotal[e],
      'rows': rowOut,
      'decisive_row': decisive,
      'low': e.rows[decisive].low,
      'high': e.rows[decisive].high,
      'level': best.label,
    });
  }

  // 규정수량 고시 별표 4 비고 3 나 — 저확산으로 판정한 물질은 다른 유해화학물질과 같이 취급하면 결정에서 뺀다.
  // 조건은 "상위 규정수량이 규정되어 있는 물질"과 같이 취급할 때 — 다른 물질이 있어도 평가된 행에 상위가 없으면 저확산 물질을 남긴다.
  final others = levels.keys.where((e) => !viaLowDiffusion.contains(e)).toList();
  final othersHaveHigh = others.any((e) => perRow[e]!.keys.any((i) => quantityOf(e.rows[i].high) != null));
  final deciding = <Entry>[...others];
  if (othersHaveHigh) {
    for (final s in substances) {
      final e = levels.keys.firstWhere((x) => x.src.id == s['src'] && x.no == s['no']);
      if (viaLowDiffusion.contains(e)) {
        s['excluded_from_level'] = '규정수량 고시 별표 4 비고 3 나 — 저확산 구분 물질과 다른 유해화학물질을 같이 취급하면 '
            '상위 규정수량이 있는 물질로 산정한다';
      }
    }
  } else {
    deciding.addAll(viaLowDiffusion);
  }

  final complete = issues.isEmpty;
  Level? site;
  if (complete) {
    site = Level.none;
    for (final e in deciding) {
      if (levels[e]!.index > site!.index) site = levels[e];
    }
  }
  return CalcOutcome({
    'tool': CalcToolName.level,
    'status': complete ? 'ok' : 'incomplete',
    'level': site?.label,
    if (site == Level.group1)
      'level_note': '1군 정의(제2조12의1)에는 규칙 제19조제8항 주요취급시설 운영 요건이 함께 있다 — 이 도구는 그것을 확인하지 않는다',
    if (site == Level.group2) 'level_note': '2군은 외부 비상대응계획(제5조제6호)을 빼고 낼 수 있다(별지 제7호서식은 제외 불가 — 제6조①)',
    if (!complete) 'issues': issues,
    'facilities': facilities,
    'substances': substances,
    'rules': [
      '작성 규정 제2조11(최대보유량 = 모든 시설의 어느 순간 최대 체류량의 합, 탱크로리 제외)ㆍ12의1(1군)ㆍ12의2(2군), 제4조, 별표 1',
      '취급량 = 설계용량 × 비중(혼합물도 전체 양 — 규정수량 고시 별표 4 비고 2 나, 작성 규정 별표 1 제3호). 함량은 함량기준 비교에만 쓴다',
      '유해성 구분 행은 행마다 함량기준을 넘는 설비 양을 합해 그 행의 하위ㆍ상위와 비교 — 가장 높은 판정이 물질의 판정(규정수량 고시 별표 1 비고 2)',
      '경계는 이상(≥). 수량 원문의 *는 별표 3 일반기준 가의 표시',
    ],
    'notice': planNotice,
  });
}

// ───── 예비시나리오 대상 산정(제23조ㆍ별표 2) ─────

/// 성상별 예비시나리오 규정수량(kg). 기체는 독성구분으로.
({double kg, String clause}) _scenarioThreshold(String phase, int? tox) {
  switch (phase) {
    case '고체':
      return (kg: 2000, clause: '별표 2 고체 2,000kg');
    case '액체':
      return (kg: 400, clause: '별표 2 액체 400kg');
    default:
      final liquefied = phase == '액화가스' ? ' — 액화가스는 기체 규정수량(비고 4)' : '';
      if (tox == 1 || tox == 2) return (kg: 5, clause: '별표 2 기체 독성구분 $tox 5kg$liquefied');
      if (tox == 3) return (kg: 100, clause: '별표 2 기체 독성구분 3 100kg$liquefied');
      return (
        kg: 100,
        clause: '별표 2 기체 100kg — 급성독성 구분이 ${tox == null ? '없어' : '$tox(1~3 밖)이라'} 독성구분 3을 따른다(비고 3)$liquefied',
      );
  }
}

const _phases = ['고체', '액체', '기체', '액화가스'];

CalcOutcome screenPreliminaryScenarios(Dataset ds, Map<String, Object?> args) {
  final parsed = _facilities(args);
  if (parsed is String) return CalcOutcome(const {}, error: parsed);
  final inputs = parsed as List<_Input>;
  final facilities = <Map<String, Object?>>[];
  final issues = <String>[];

  for (final f in inputs) {
    final out = <String, Object?>{
      'index': f.index,
      'facility': ?f.str('facility'),
      'src': f.raw['src'],
      'no': f.raw['no'],
    };
    facilities.add(out);
    void fail(String why) {
      out['verdict'] = 'error';
      out['error'] = why;
      issues.add('facilities[${f.index}]: $why');
    }

    final e = _entryOf(ds, f);
    if (e is String) {
      fail(e);
      continue;
    }
    final entry = e as Entry;
    out['substance'] = entry.ko.isNotEmpty ? entry.ko : entry.name;
    final c = _content(f);
    if (c is String) {
      fail(c);
      continue;
    }
    final content = c as double;
    out['content_pct'] = content;
    final ga = _ruleGa(ds, entry, content);
    if (ga.error != null) {
      fail(ga.error!);
      continue;
    }
    if (ga.note != null) out['notes'] = [ga.note];
    final phase = f.str('phase');
    if (phase == null || !_phases.contains(phase)) {
      fail('phase는 운전조건의 성상 ${_phases.join('/')} 중 하나여야 합니다(별표 2 비고 1 — 상온ㆍ상압이 아니라 운전조건)');
      continue;
    }
    out['phase'] = phase;
    final toxRaw = f.raw['acute_toxicity_category'];
    if (toxRaw != null && toxRaw is! int) {
      fail('acute_toxicity_category는 정수(급성독성 구분)여야 합니다');
      continue;
    }
    final tox = toxRaw as int?;
    if (tox != null && (phase == '고체' || phase == '액체')) {
      fail('acute_toxicity_category는 기체ㆍ액화가스에만 씁니다');
      continue;
    }
    final ld = f.flag('low_diffusion');
    if (f.has('low_diffusion') && ld == null) {
      fail('low_diffusion은 true/false');
      continue;
    }
    if (ld == true && !entry.rows.any(_isLowDiffusion)) {
      fail('${_id(entry)}에는 저확산 행이 없어 low_diffusion: true를 쓸 수 없습니다');
      continue;
    }

    final amount = _amount(f, direct: 'quantity_kg', scale: 1000, unit: 'kg');
    if (amount is String) {
      fail(amount);
      continue;
    }
    final (:value, :formula) = amount as ({double value, String formula});
    final kg = value;
    out['amount_kg'] = kg;
    out['formula'] = formula;
    if (f.str('basis') case final b? when b.isNotEmpty) out['basis'] = b;

    // 저확산 행이 있는 물질은 미대상 여부를 호출자가 정해야 한다 — 빠뜨리면 미대상을 조용히 놓친다(작성수준 도구와 같은 규칙).
    if (ld == null && entry.rows.any(_isLowDiffusion)) {
      out['verdict'] = 'selection_required';
      out['selection'] = _choices(entry, 'low_diffusion',
          '취급 과정 성상이 액체ㆍ고체라 저확산 행을 적용하면 그 설비는 예비시나리오 대상에서 빠진다(제23조① 단서) — 적용 여부를 정해 다시 부를 것');
      issues.add('facilities[${f.index}]: ${_id(entry)} 행 선택 필요(low_diffusion)');
      continue;
    }
    if (ld == true) {
      out['verdict'] = '미대상';
      out['reason'] = '저확산물질 취급 설비는 예비시나리오 대상 설비로 선정하지 않는다(제23조① 단서)';
      continue;
    }
    final low = lowestThresholdOf(entry);
    if (low != null && !low.met(content)) {
      out['verdict'] = '함량미만';
      out['reason'] = '함량 $content%가 ${_id(entry)}의 가장 낮은 함량기준(${low.raw}%) 미만';
      continue;
    }
    final t = _scenarioThreshold(phase, tox);
    out['threshold_kg'] = t.kg;
    out['threshold_clause'] = t.clause;
    final target = kg >= t.kg;
    out['verdict'] = target ? '표준시설' : '소량시설';
    out['reason'] = target ? '취급량이 예비시나리오 규정수량 이상(제23조③)' : '취급량이 예비시나리오 규정수량 미만';
  }

  return CalcOutcome({
    'tool': CalcToolName.scenario,
    'status': issues.isEmpty ? 'ok' : 'incomplete',
    if (issues.isNotEmpty) 'issues': issues,
    'facilities': facilities,
    'labels': '표준시설ㆍ소량시설ㆍ함량미만ㆍ미대상은 제출 실무(사례 A 산정표) 표기다 — 고시 원문은 "예비시나리오 규정수량 이상이면 선정"(제23조③)만 정한다',
    'rules': [
      '작성 규정 제23조①(대상 설비, 저확산물질 제외)ㆍ②(취급량 = 설계용량과 성상ㆍ비중 고려)ㆍ③(규정수량 이상이면 선정), 별표 2',
      '취급량 = 설계용량 × 비중 × 1000(kg). 함량은 함량미만 판정에만 쓴다',
      '경계는 이상(≥)',
    ],
    'notice': planNotice,
  });
}

/// 도구 이름으로 실행한다. 모르는 이름이면 null(호출자가 다른 도구로 넘긴다).
CalcOutcome? runCalcTool(Dataset ds, String name, Map<String, Object?> args) => switch (name) {
      CalcToolName.level => calcWritingLevel(ds, args),
      CalcToolName.scenario => screenPreliminaryScenarios(ds, args),
      _ => null,
    };
