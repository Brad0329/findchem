/// F-008 규정수량 판정 도우미 — **행별 적용 조건 문장**과 **배타적 선택지**.
///
/// 표는 `kind: "용액", content: ""` 같은 조각이라 사람이 일반기준을 알고 읽어야 뜻이 산다.
/// spike ③에서 모델이 빈칸을 가정으로 채운 자리가 여기였다(B1ㆍB2 — `work_log/spike_mcp_review.md` 4절).
/// 그래서 **응답을 조립할 때** 행마다 "언제 이 행을 적용하는가"를 문장으로 붙인다.
///
/// - **번들 JSONㆍSCHEMAㆍ`lib/search/`는 건드리지 않는다**(REQUIREMENTS F-008 결정 1 — 응답 조립 단계에서만).
/// - 문장의 재료는 **그 행의 원문 필드(구분ㆍ함량기준)와 [rules]의 일반기준 원문뿐**이다. 지어내지 않는다.
///   고시가 정하지 않은 것(저확산 행과 유해성 구분 행 중 무엇이 이기는가)은 **가리키기만 하고 결론짓지 않는다.**
library;

import '../parser/models.dart';

/// 별표3의 '* 표시' 행(제42ㆍ43ㆍ44호). 구분 열이 없어 물질명 원문(`암모니아 용액`)이 [QuantityRow.kind]에 들어 있다.
bool _isSolutionRow3(QuantityRow r) => r.kind.endsWith('용액');

/// 별표2의 용액 구분 행(제282ㆍ557호 — 일반기준 나).
bool _isSolutionRow2(QuantityRow r) => r.kind == '용액';

/// 별표2의 저확산 구분 행(일반기준 다).
bool _isLowDiffusionRow(QuantityRow r) => r.kind == '저확산';

/// 유해성 구분 행(급성ㆍ만성ㆍ생태, `급성,생태`처럼 묶인 것 포함).
bool _isHazardRow(Entry e, QuantityRow r) =>
    e.src == Source.byeolpyo2 &&
    r.kind.isNotEmpty &&
    !_isSolutionRow2(r) &&
    !_isLowDiffusionRow(r) &&
    r.kind != '(삭제)';

final _numeric = RegExp(r'^[0-9.]+$');

/// 이 항목의 다른 행에 적힌 함량기준 중 숫자인 것들(원문 문자열 그대로, 중복 제거).
List<String> _siblingContents(Entry e, QuantityRow self) => {
  for (final r in e.rows)
    if (!identical(r, self) && _numeric.hasMatch(r.content)) r.content,
}.toList();

/// 별표 2 일반기준 나ㆍ다의 "가장 낮은 것" — 문자열이 아니라 수로 비교한다. 못 고르면 null.
String? _lowest(List<String> contents) {
  if (contents.isEmpty) return null;
  final sorted = [...contents]..sort((a, b) => double.parse(a).compareTo(double.parse(b)));
  return sorted.first;
}

String _contentClause(Entry e, QuantityRow r) {
  if (r.content == '-') return "함량기준이 '-'(해당 없음)이다.";
  if (r.content.isNotEmpty) {
    if (_numeric.hasMatch(r.content)) return '함량기준 ${r.content}% 이상.';
    return "함량기준 원문 표기: '${r.content}'.";
  }
  // ── 함량기준이 빈 칸인 행 ──────────────────────────────────────────────
  final siblings = _siblingContents(e, r);
  if (e.src == Source.byeolpyo3) {
    // 별표3은 원문에서 함량기준 칸이 항목당 하나만 표시되어 있다(제42ㆍ43ㆍ44호의 '* 표시' 행).
    if (siblings.isEmpty) {
      return '이 행에는 함량기준이 비어 있고, 이 항목의 다른 행에도 함량기준이 없다.';
    }
    return '이 행에는 함량기준이 비어 있다 — 원문에서 이 항목에 표시된 함량기준은 '
        "'${siblings.join(', ')}% 이상'이다.";
  }
  final clause = _isSolutionRow2(r) ? '나' : '다';
  final lowest = _lowest(siblings);
  if (lowest == null) {
    return '이 행에는 함량기준이 비어 있다 — 별표 2 일반기준 $clause에 따라 인체급성유해성ㆍ인체만성유해성ㆍ'
        '생태유해성 물질별 함량 중 가장 낮은 것으로 적용한다. 이 항목의 다른 행에는 숫자 함량기준이 없다.';
  }
  return '이 행에는 함량기준이 비어 있다 — 별표 2 일반기준 $clause에 따라 인체급성유해성ㆍ인체만성유해성ㆍ'
      '생태유해성 물질별 함량 중 가장 낮은 것으로 적용한다(이 항목의 다른 행 함량기준: '
      '${siblings.join(', ')} → 가장 낮은 것은 $lowest).';
}

String _formClause(Entry e, QuantityRow r) {
  if (e.src == Source.byeolpyo3) {
    if (_isSolutionRow3(r)) {
      return "상온ㆍ상압조건에서 성상이 액체인 경우 이 행('${r.kind}')의 값을 규정수량으로 한다"
          '(별표 3 일반기준 가 — 제${e.no}호). 수량에 붙은 *가 그 일반기준이 말하는 \'* 표시된 값\'이다.';
    }
    final solution = e.rows.where(_isSolutionRow3).firstOrNull;
    if (solution != null) {
      return '별표 3 일반기준 가에 따라 상온ㆍ상압조건에서 성상이 액체인 경우에는 같은 항목의 '
          "'${solution.kind}' 행을 적용한다 — 이 행은 그 경우가 아닐 때의 값이다.";
    }
    if (e.rows.length > 1) {
      return '이 항목에는 구분 없이 함량기준만 다른 수량 행이 ${e.rows.length}개 있다 — 함량기준으로 행을 고른다.';
    }
    return '이 항목의 유일한 수량 행이다(별표 3에는 유해성 구분 열이 없다).';
  }
  // ── 별표2 ────────────────────────────────────────────────────────────
  if (_isSolutionRow2(r)) {
    return '상온ㆍ상압조건에서 성상이 액체인 경우 이 행(용액 구분)의 값을 규정수량으로 한다'
        '(별표 2 일반기준 나 — 제282호, 제557호).';
  }
  if (_isLowDiffusionRow(r)) {
    return '해당물질을 취급하는 과정에서 그 성상이 액체나 고체인 경우 이 행(저확산 구분)의 값을 '
        '그 해당물질의 규정수량으로 한다(별표 2 일반기준 다).';
  }
  final buf = StringBuffer("유해성 구분이 '${r.kind}'인 경우의 값이다.");
  if (e.rows.any(_isSolutionRow2)) {
    buf.write(" 다만 상온ㆍ상압조건에서 성상이 액체이면 별표 2 일반기준 나에 따라 같은 항목의 '용액' 행을 적용한다.");
  }
  if (e.rows.any(_isLowDiffusionRow)) {
    buf.write(" 같은 항목에 '저확산' 구분 행이 있다 — 별표 2 일반기준 다의 조건"
        '(취급 과정에서 성상이 액체나 고체)에 해당하는지 확인해야 한다.');
  }
  return buf.toString();
}

/// 행 [r]을 **언제 적용하는가**. 빈 문자열을 돌려주지 않는다(전수 테스트가 건다).
String conditionOf(Entry e, QuantityRow r) {
  if (e.deleted || r.kind == '(삭제)') {
    return '이 항목은 고시에서 (삭제)되어 적용할 규정수량이 없다.';
  }
  return '${_formClause(e, r)} ${_contentClause(e, r)}';
}

/// 항목 안에서 행을 골라야 하는지와 그 근거. 행이 하나뿐이면 null(응답에 싣지 않는다).
Map<String, Object?>? selectionOf(Entry e) {
  if (e.rows.length < 2) return null;
  final reasons = <String>[];
  if (e.rows.any(_isSolutionRow3) || e.rows.any(_isSolutionRow2)) {
    reasons.add('상온ㆍ상압조건에서 성상이 액체인지에 따라 적용 행이 갈린다 — 액체인 경우의 행과 '
        '그렇지 않은 경우의 행은 함께 적용되지 않는다');
  }
  if (e.rows.any(_isLowDiffusionRow)) {
    reasons.add("취급 과정의 성상이 액체나 고체이면 별표 2 일반기준 다의 '저확산' 행 조건에 해당하는지 확인해야 한다");
  }
  final hazard = e.rows.where((r) => _isHazardRow(e, r)).length;
  if (hazard >= 2) {
    reasons.add('유해성 구분 행이 $hazard개다 — 별표 1 비고 제2호에 따라 2가지 이상 유해성 그룹을 가진 경우 '
        '가장 작은 수량을 적용한다(성상처럼 하나를 고르는 것이 아니다)');
  }
  if (e.src == Source.byeolpyo3 && e.rows.every((r) => r.kind.isEmpty)) {
    reasons.add('함량기준에 따라 행이 갈린다');
  }
  return {
    'required': true,
    'note': '이 항목에는 수량 행이 ${e.rows.length}개다 — 성상ㆍ구분을 확인해야 어느 행을 적용할지 정해진다. '
        '${reasons.join('. ')}.',
    'choices': [
      for (var i = 0; i < e.rows.length; i++)
        {'row': i, 'label': e.rows[i].kind.isEmpty ? '(구분 표시 없음)' : e.rows[i].kind},
    ],
  };
}
