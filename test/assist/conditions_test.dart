/// F-008 1단계 수용 기준 — 행별 적용 조건 문장과 배타적 선택지. 실제 번들 데이터에 직접 질의한다(모킹 없음).
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/assist/conditions.dart';
import 'package:findchem/parser/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Dataset ds;

  setUpAll(() {
    ds = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map)
          .cast<String, Object?>(),
    );
  });

  Entry entry(Source src, int no) => ds.entries.firstWhere((e) => e.src == src && e.no == no);
  List<String> conditions(Entry e) => [for (final r in e.rows) conditionOf(e, r)];

  // ── 전수 ───────────────────────────────────────────────────────────────────
  test('수량 행 2,458건 전부에 조건 문장이 있고 빈 문장이 0건', () {
    var rows = 0;
    final empty = <String>[];
    for (final e in ds.entries) {
      for (final r in e.rows) {
        rows++;
        final s = conditionOf(e, r);
        if (s.trim().isEmpty) empty.add('${e.src.id} ${e.no} ${r.kind}');
      }
    }
    expect(rows, 2458, reason: '항목은 1,657건이고 수량 행은 그보다 많다');
    expect(empty, isEmpty);
  });

  test('함량기준이 빈 행 261건(별표2 258 + 별표3 3)에는 그 빈칸을 설명하는 문장이 들어간다', () {
    var blank2 = 0;
    var blank3 = 0;
    for (final e in ds.entries) {
      for (final r in e.rows) {
        if (r.content.isNotEmpty) continue;
        final s = conditionOf(e, r);
        expect(s, contains('함량기준이 비어 있다'), reason: '${e.src.id} ${e.no} ${r.kind}');
        if (e.src == Source.byeolpyo2) {
          blank2++;
          // 별표2의 빈칸은 일반기준 나ㆍ다가 해석을 정해 둔 자리다.
          expect(s, contains('가장 낮은 것으로 적용한다'), reason: '${e.no} ${r.kind}');
          expect(s, contains(r.kind == '용액' ? '일반기준 나' : '일반기준 다'), reason: '${e.no} ${r.kind}');
          expect(s, contains('가장 낮은 것은 '), reason: '${e.no} ${r.kind}: 형제 행의 함량기준을 짚어 줘야 한다');
        } else {
          blank3++;
          expect(s, contains('% 이상'), reason: '${e.no} ${r.kind}');
        }
      }
    }
    expect(blank2, 258);
    expect(blank3, 3);
  });

  test('숫자 함량기준이 있는 행은 "미만이면 이 행이 적용되지 않는다"까지 말한다(전수)', () {
    // 1단계 재실행 B1: 함량기준만 적고 미만일 때를 안 적으면 그 빈칸을 모델이 못 채운다.
    // 범위는 '이 행'으로 한정해야 한다 — 메틸알코올은 별표3 85% / 별표2 10%로 행마다 다르다.
    final numeric = RegExp(r'^[0-9.]+$');
    var checked = 0;
    for (final e in ds.entries) {
      for (final r in e.rows) {
        if (!numeric.hasMatch(r.content)) continue;
        checked++;
        final s = conditionOf(e, r);
        expect(s, contains('함량이 ${r.content}% 미만인 혼합물에는 이 행의 규정수량이 적용되지 않는다'),
            reason: '${e.src.id} ${e.no} ${r.kind}');
        expect(s, contains('별표 4 비고 제2호 가목'), reason: '${e.src.id} ${e.no} ${r.kind}');
        expect(s, isNot(contains('이 물질')), reason: '${e.src.id} ${e.no}: 범위를 행이 아니라 물질로 넓히면 틀린다');
      }
    }
    // 2,458행 − 빈 함량 261 − '-'(삭제) 19 − '70% 초과' 1 = 2,177
    expect(checked, 2177);
  });

  test("'톨루엔'(별표3 28, 행 하나)은 선택지가 없는 대신 조건 문장이 함량 갈래를 진다", () {
    final e = entry(Source.byeolpyo3, 28);
    expect(selectionOf(e), isNull);
    final s = conditions(e).single;
    expect(s, contains('함량기준 85% 이상'));
    expect(s, contains('함량이 85% 미만인 혼합물에는 이 행의 규정수량이 적용되지 않는다'));
  });

  test('조건 문장은 지어내지 않는다 — 고시에 없는 "더 엄격한"·"작은 쪽" 류가 어느 행에도 없다', () {
    // spike ③ D3의 실패 모양(모델이 지어낸 규칙)이 자산 쪽에서 먼저 새어 나오지 않도록 건다.
    for (final e in ds.entries) {
      for (final s in conditions(e)) {
        expect(s, isNot(contains('엄격')), reason: '${e.src.id} ${e.no}');
        expect(s, isNot(contains('작은 쪽')), reason: '${e.src.id} ${e.no}');
      }
    }
  });

  // ── 개별 항목 ──────────────────────────────────────────────────────────────
  test("'암모니아' 사고대비물질(별표3 44): 기체 행과 용액 행의 조건이 서로 다르다", () {
    final e = entry(Source.byeolpyo3, 44);
    final c = conditions(e);
    expect(c, hasLength(2));
    expect(c[0], isNot(c[1]));
    expect(c[0], contains("'암모니아 용액' 행을 적용한다"));
    expect(c[0], contains('그 경우가 아닐 때의 값이다'));
    expect(c[0], contains('함량기준 10% 이상'));
    expect(c[1], contains('성상이 액체인 경우'));
    expect(c[1], contains('별표 3 일반기준 가 — 제44호'));
    expect(c[1], contains('*')); // 별표(*)의 뜻을 문장이 지킨다
  });

  test("'암모니아' 별표2 282: 용액 행의 빈 함량기준이 일반기준 나로 풀린다(10, 25 → 10)", () {
    final e = entry(Source.byeolpyo2, 282);
    final sol = e.rows.firstWhere((r) => r.kind == '용액');
    final s = conditionOf(e, sol);
    expect(s, contains('별표 2 일반기준 나 — 제282호, 제557호'));
    expect(s, contains('이 항목의 다른 행 함량기준: 10, 25 → 가장 낮은 것은 10'));
    // 유해성 구분 행은 용액 행의 존재를 가리킨다(조용히 감추지 않는다)
    expect(conditionOf(e, e.rows.first), contains("'용액' 행을 적용한다"));
  });

  test("'염화수소' 별표3 42도 같은 갈래를 가진다", () {
    final c = conditions(entry(Source.byeolpyo3, 42));
    expect(c, hasLength(2));
    expect(c[1], contains('별표 3 일반기준 가 — 제42호'));
  });

  test('저확산 행(별표2 14 납)은 일반기준 다를 근거로 성상 조건을 말한다', () {
    final e = entry(Source.byeolpyo2, 14);
    final low = e.rows.firstWhere((r) => r.kind == '저확산');
    expect(conditionOf(e, low), contains('성상이 액체나 고체인 경우'));
    expect(conditionOf(e, low), contains('별표 2 일반기준 다'));
    expect(conditionOf(e, e.rows.first), contains("'저확산' 구분 행이 있다"));
  });

  test('(삭제) 항목 19건은 적용할 규정수량이 없다고 말한다', () {
    final deleted = ds.entries.where((e) => e.deleted).toList();
    expect(deleted, hasLength(19));
    for (final e in deleted) {
      expect(conditions(e).single, contains('(삭제)되어 적용할 규정수량이 없다'));
    }
  });

  test("별표3 46 질산: 구분 없이 함량기준만 다른 두 행 — 원문 표기 '70% 초과'를 그대로 싣는다", () {
    final c = conditions(entry(Source.byeolpyo3, 46));
    expect(c, hasLength(2));
    expect(c[0], contains('함량기준만 다른 수량 행이 2개'));
    expect(c[1], contains("'70% 초과'"));
  });

  // ── 배타적 선택지 ──────────────────────────────────────────────────────────
  test("'암모니아'·'염화수소'에는 선택지가 있고, 행이 하나뿐인 '톨루엔'(사고대비물질)에는 없다", () {
    for (final e in [entry(Source.byeolpyo3, 44), entry(Source.byeolpyo3, 42)]) {
      final s = selectionOf(e)!;
      expect(s['required'], isTrue);
      expect(s['note'], contains('성상ㆍ구분을 확인'));
      expect((s['choices'] as List), hasLength(e.rows.length));
      expect(((s['choices'] as List).last as Map)['label'], endsWith('용액'));
    }
    final toluene = entry(Source.byeolpyo3, 28);
    expect(toluene.rows, hasLength(1));
    expect(selectionOf(toluene), isNull);
  });

  test('유해성 구분 행이 여럿인 항목의 선택지는 "하나를 고르라"가 아니라 별표 1 비고 제2호를 가리킨다', () {
    final s = selectionOf(entry(Source.byeolpyo2, 917))!;
    expect(s['note'], contains('별표 1 비고 제2호'));
    expect(s['note'], contains('하나를 고르는 것이 아니다'));
  });

  test('선택지는 행이 둘 이상인 항목에만 붙는다(전수)', () {
    for (final e in ds.entries) {
      expect(selectionOf(e) == null, e.rows.length < 2, reason: '${e.src.id} ${e.no}');
    }
  });
}
