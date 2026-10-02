/// A-004 수용 기준 — 계산 도구(작성수준 판정ㆍ예비시나리오 대상 산정). 실제 번들 데이터에 직접 질의한다.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/calc/calc.dart';
import 'package:findchem/mcp/mcp_handler.dart';
import 'package:findchem/parser/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Dataset ds;

  setUpAll(() {
    ds = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
  });

  Map<String, Object?> level(List<Map<String, Object?>> f) {
    final o = calcWritingLevel(ds, {'facilities': f});
    expect(o.isError, false, reason: o.error);
    return o.response;
  }

  Map<String, Object?> scenario(List<Map<String, Object?>> f) {
    final o = screenPreliminaryScenarios(ds, {'facilities': f});
    expect(o.isError, false, reason: o.error);
    return o.response;
  }

  List<Map> facilities(Map<String, Object?> r) => (r['facilities']! as List).cast<Map>();
  List<Map> substances(Map<String, Object?> r) => (r['substances']! as List).cast<Map>();

  // 표본 항목(번들 데이터 원문 — 바뀌면 이 테스트가 먼저 알린다)
  const chlorine3 = {'src': '별표3', 'no': 49}; // 함량 25, 0.4/2
  const chlorine2 = {'src': '별표2', 'no': 1283}; // 급성 1, 생태 2.5, 0.4/2
  const dinoseb = {'src': '별표2', 'no': 46}; // 급성 1% 5/200, 만성 0.3% 40/-, 생태 2.5% 5/200
  const hcl3 = {'src': '별표3', 'no': 42}; // 10% 0.8/4, 염화수소 용액 0.2*/8*/40*
  const nitric3 = {'src': '별표3', 'no': 46}; // 10% 5/400, 70% 초과 1/20
  const leadAcetate = {'src': '별표2', 'no': 15}; // 만성 0.3, 생태 2.5, 저확산(빈 칸) 400/-
  const naoh = {'src': '별표2', 'no': 209}; // 급성 5% 20/250, 저확산 400/-
  const sicl4 = {'src': '별표3', 'no': 96}; // 10% 0.3/1.5

  test('표본 항목이 데이터와 맞다', () {
    Entry e(Map<String, Object> k) => ds.entries.firstWhere((x) => x.src.id == k['src'] && x.no == k['no']);
    expect(e(chlorine3).rows.single.high, '2');
    expect(e(hcl3).rows[1].low, '8*');
    expect(e(nitric3).rows[1].content, '70% 초과');
    expect(e(leadAcetate).rows[2].kind, '저확산');
    expect(e(naoh).rows[1].low, '400');
    expect(e(sicl4).rows.single.content, '10');
  });

  group('공통 입력 검증', () {
    test('없는 항목ㆍ(삭제) 항목 → 그 설비만 error, 나머지는 계산, 판정 incomplete', () {
      final deleted = ds.entries.firstWhere((e) => e.deleted);
      final r = level([
        {'src': '별표2', 'no': 999999, 'content_pct': 100, 'capacity_m3': 1, 'specific_gravity': 1},
        {'src': deleted.src.id, 'no': deleted.no, 'content_pct': 100, 'capacity_m3': 1, 'specific_gravity': 1},
        {...chlorine3, 'content_pct': 100, 'quantity_ton': 3, 'basis': '충전량'},
      ]);
      expect(r['status'], 'incomplete');
      expect(r['level'], isNull);
      final f = facilities(r);
      expect(f[0]['status'], 'error');
      expect(f[1]['error'], contains('삭제'));
      expect(f[2]['status'], 'included');
      expect((r['issues']! as List), hasLength(2));
      expect(substances(r).single['level'], '1군');
    });

    test('비중이 g/L로 보이면 오류 + 물=1 안내, 양 입력이 없거나 겹치면 오류', () {
      final r = level([
        {...sicl4, 'content_pct': 100, 'capacity_m3': 1, 'specific_gravity': 1500},
        {...sicl4, 'content_pct': 100, 'specific_gravity': 1.5},
        {...sicl4, 'content_pct': 100, 'capacity_m3': 1, 'specific_gravity': 1.5, 'quantity_ton': 1, 'basis': 'x'},
        {...sicl4, 'content_pct': 100, 'quantity_ton': 1},
        {...sicl4, 'content_pct': 0, 'capacity_m3': 1, 'specific_gravity': 1.5},
      ]);
      final f = facilities(r);
      expect(f[0]['error'], contains('물=1'));
      expect(f.every((x) => x['status'] == 'error'), true);
      expect(f[3]['error'], contains('basis'));
    });

    test('별표 2 일반기준 가 — 별표3 함량기준 이상이면 오류(별표3 번호 안내), 미만이면 별표2로 계산 + note', () {
      final r = level([
        {...chlorine2, 'content_pct': 50, 'quantity_ton': 1, 'basis': 'x'},
        {...chlorine2, 'content_pct': 10, 'quantity_ton': 1, 'basis': 'x'},
      ]);
      final f = facilities(r);
      expect(f[0]['error'], allOf(contains('일반기준 가'), contains('no: 49')));
      expect(f[1]['status'], 'included');
      expect((f[1]['notes']! as List).single, contains('별표3 제49호'));
    });

    test('별표3 함량기준 미만 → 함량미만 + 같은 CAS의 별표2 항목 안내', () {
      final f = facilities(level([
        {...chlorine3, 'content_pct': 10, 'quantity_ton': 1, 'basis': 'x'},
      ]));
      expect(f.single['status'], '함량미만');
      expect((f.single['notes']! as List).single, contains('별표2 제1283호'));
    });

    test('설비 상한 — 넘으면 계산하지 않고 전체 건수와 상한을 알린다', () {
      final many = [
        for (var i = 0; i < calcFacilityCap + 1; i++) {...sicl4, 'content_pct': 100, 'capacity_m3': 1, 'specific_gravity': 1.5},
      ];
      final o = calcWritingLevel(ds, {'facilities': many});
      expect(o.isError, true);
      expect(o.error, allOf(contains('${calcFacilityCap + 1}'), contains('$calcFacilityCap')));
      expect(calcWritingLevel(ds, {'facilities': many.sublist(0, calcFacilityCap)}).isError, false);
    });
  });

  group('calc_writing_level', () {
    test('취급량 = 용량×비중(6자리 반올림), 물질별 최대보유량 = 합 — 사례 A NaOH 30×1.37 + 1×1.37', () {
      final r = level([
        {...naoh, 'content_pct': 25, 'capacity_m3': 30.0, 'specific_gravity': 1.37, 'low_diffusion': false},
        {...naoh, 'content_pct': 25, 'capacity_m3': 1.0, 'specific_gravity': 1.37, 'low_diffusion': false},
      ]);
      expect(facilities(r).map((f) => f['amount_ton']), [41.1, 1.37]);
      final s = substances(r).single;
      expect(s['max_holding_ton'], 42.47);
      expect(s['level'], '2군'); // 급성 5% 20/250
      expect(r['level'], '2군');
      expect(r['level_note'], contains('외부 비상대응'));
    });

    test('경계는 이상 — 염소 1.5톤 2군, 2톤 1군 + 주요취급시설 문장, 0.39톤 미해당', () {
      Map<String, Object?> one(double t) => level([
            {...chlorine3, 'content_pct': 100, 'quantity_ton': t, 'basis': '충전량'},
          ]);
      expect(one(1.5)['level'], '2군');
      expect(one(2)['level'], '1군');
      expect(one(2)['level_note'], contains('주요취급시설'));
      expect(one(0.39)['level'], '미해당');
    });

    test('다중 유해성 구분 행 — 0.5%는 만성 행만, 5%는 세 행 모두', () {
      final f = facilities(level([
        {...dinoseb, 'content_pct': 0.5, 'capacity_m3': 1, 'specific_gravity': 1},
        {...dinoseb, 'content_pct': 5, 'capacity_m3': 1, 'specific_gravity': 1},
      ]));
      expect(f[0]['rows_applied'], [1]);
      expect((f[0]['below_content_rows']! as List).map((x) => (x as Map)['row']), [0, 2]);
      expect(f[1]['rows_applied'], [0, 1, 2]);
    });

    test('함량이 다른 설비 둘 — 행마다 합이 따로, 가장 높은 판정과 근거 행', () {
      final r = level([
        {...dinoseb, 'content_pct': 5, 'quantity_ton': 210, 'basis': 'x'},
        {...dinoseb, 'content_pct': 0.5, 'quantity_ton': 35, 'basis': 'x'},
      ]);
      final s = substances(r).single;
      final rows = {for (final x in (s['rows']! as List).cast<Map>()) x['row']: x};
      expect(rows[0]!['total_ton'], 210.0);
      expect(rows[0]!['level'], '1군'); // 210 ≥ 200
      expect(rows[1]!['total_ton'], 245.0);
      expect(rows[1]!['level'], '2군'); // 만성 40/-
      expect(s['decisive_row'], 0);
      expect(s['max_holding_ton'], 245.0);
      expect(r['level'], '1군');
    });

    test('염화수소 — ambient_liquid 없으면 selection_required, true면 * 행, false면 첫 행', () {
      final none = level([
        {...hcl3, 'content_pct': 35, 'quantity_ton': 10, 'basis': 'x'},
      ]);
      expect(none['status'], 'incomplete');
      final f = facilities(none).single;
      expect(f['status'], 'selection_required');
      expect((f['selection']! as Map)['field'], 'ambient_liquid');
      final choices = ((f['selection']! as Map)['rows']! as List).cast<Map>();
      expect(choices, hasLength(2));
      expect(choices[1]['condition'], contains('별표 3 일반기준 가'));

      final liquid = level([
        {...hcl3, 'content_pct': 35, 'quantity_ton': 10, 'basis': 'x', 'ambient_liquid': true},
      ]);
      expect(facilities(liquid).single['rows_applied'], [1]);
      expect(substances(liquid).single['low'], '8*');
      expect(liquid['level'], '2군'); // 10 ≥ 8, < 40
      final gas = level([
        {...hcl3, 'content_pct': 35, 'quantity_ton': 10, 'basis': 'x', 'ambient_liquid': false},
      ]);
      expect(facilities(gas).single['rows_applied'], [0]);
      expect(gas['level'], '1군'); // 10 ≥ 4
    });

    test('질산 — 80%는 70% 초과 행, 70%ㆍ50%는 10% 행, 5%는 함량미만', () {
      List<Object?> applied(double c) => facilities(level([
            {...nitric3, 'content_pct': c, 'capacity_m3': 1, 'specific_gravity': 1.4},
          ])).single['rows_applied'] as List<Object?>? ?? const ['함량미만'];
      expect(applied(80), [1]);
      expect(applied(70), [0]);
      expect(applied(50), [0]);
      expect(applied(5), ['함량미만']);
    });

    test('저확산 행 — 값이 없으면 selection_required, true면 저확산 행(빈 함량기준 = 형제 최저 0.3)', () {
      expect(facilities(level([
        {...leadAcetate, 'content_pct': 10, 'capacity_m3': 1, 'specific_gravity': 1},
      ])).single['status'], 'selection_required');
      final r = level([
        {...leadAcetate, 'content_pct': 10, 'capacity_m3': 1, 'specific_gravity': 1, 'low_diffusion': true},
        {...leadAcetate, 'content_pct': 0.2, 'capacity_m3': 1, 'specific_gravity': 1, 'low_diffusion': true},
      ]);
      final f = facilities(r);
      expect(f[0]['rows_applied'], [2]);
      expect(f[1]['status'], '함량미만');
      final t = ((substances(r).single['rows']! as List).single as Map)['threshold'] as Map;
      expect(t['pct'], 0.3);
      expect(t.containsKey('inherited'), true);
    });

    test('ambient_liquidㆍlow_diffusion을 해당 행이 없는 물질에 true로 주면 오류', () {
      final f = facilities(level([
        {...sicl4, 'content_pct': 100, 'capacity_m3': 1, 'specific_gravity': 1.5, 'low_diffusion': true},
        {...sicl4, 'content_pct': 100, 'capacity_m3': 1, 'specific_gravity': 1.5, 'ambient_liquid': true},
      ]));
      expect(f.every((x) => x['status'] == 'error'), true);
    });

    test('별표 4 비고 3 나 — 저확산 판정 물질은 다른 물질과 함께면 결정에서 빠지고, 혼자면 그대로', () {
      final mixed = level([
        {...naoh, 'content_pct': 25, 'quantity_ton': 500, 'basis': 'x', 'low_diffusion': true},
        {...sicl4, 'content_pct': 100, 'capacity_m3': 0.1, 'specific_gravity': 1.5},
      ]);
      final s = {for (final x in substances(mixed)) x['no']: x};
      expect(s[209]!['level'], '2군');
      expect(s[209]!['excluded_from_level'], contains('비고 3 나'));
      expect(s[96]!['level'], '미해당');
      expect(mixed['level'], '미해당');

      final alone = level([
        {...naoh, 'content_pct': 25, 'quantity_ton': 500, 'basis': 'x', 'low_diffusion': true},
      ]);
      expect(alone['level'], '2군');
      expect(substances(alone).single.containsKey('excluded_from_level'), false);
    });

    test('사업장 작성수준 = 물질 판정 중 가장 높은 것', () {
      final r = level([
        {...sicl4, 'content_pct': 100, 'capacity_m3': 0.33, 'specific_gravity': 1.5}, // 0.495 → 2군
        {...chlorine3, 'content_pct': 100, 'quantity_ton': 0.1, 'basis': '충전량'}, // 미해당
      ]);
      expect(substances(r).map((s) => s['level']), ['2군', '미해당']);
      expect(r['level'], '2군');
      expect(r['status'], 'ok');
    });
  });

  group('screen_preliminary_scenarios', () {
    Map f1(Map<String, Object?> f) => facilities(scenario([f])).single;

    test('액체 400kg 경계 — 400 표준시설, 399.9 소량시설. 사례 A NaOH 30×1.37 = 41100kg', () {
      final a = f1({...sicl4, 'content_pct': 100, 'phase': '액체', 'capacity_m3': 0.4, 'specific_gravity': 1.0});
      expect(a['amount_kg'], 400.0);
      expect(a['threshold_kg'], 400.0);
      expect(a['verdict'], '표준시설');
      expect(f1({...sicl4, 'content_pct': 100, 'phase': '액체', 'quantity_kg': 399.9, 'basis': 'x'})['verdict'], '소량시설');
      expect(f1({...naoh, 'content_pct': 25, 'phase': '액체', 'capacity_m3': 30.0, 'specific_gravity': 1.37})['amount_kg'],
          41100.0);
    });

    test('성상별 규정수량 — 고체 2000, 기체 1ㆍ2 = 5, 3 = 100, 없음ㆍ4 = 100(비고 3), 액화가스는 기체(비고 4)', () {
      double t(String phase, [int? tox]) => f1({
            ...chlorine3,
            'content_pct': 100,
            'phase': phase,
            'quantity_kg': 50,
            'basis': '충전량',
            'acute_toxicity_category': ?tox,
          })['threshold_kg'] as double;
      expect(t('고체'), 2000);
      expect(t('기체', 1), 5);
      expect(t('기체', 2), 5);
      expect(t('기체', 3), 100);
      expect(t('기체'), 100);
      expect(t('기체', 4), 100);
      expect(t('액화가스', 1), 5);
      final none = f1({...chlorine3, 'content_pct': 100, 'phase': '기체', 'quantity_kg': 50, 'basis': 'x'});
      expect(none['threshold_clause'], contains('비고 3'));
      expect(none['verdict'], '소량시설');
      final liq = f1({...chlorine3, 'content_pct': 100, 'phase': '액화가스', 'quantity_kg': 50, 'basis': 'x', 'acute_toxicity_category': 1});
      expect(liq['threshold_clause'], contains('비고 4'));
      expect(liq['verdict'], '표준시설');
    });

    test('저확산 — true면 미대상(제23조① 단서), 저확산 행 없는 물질에 true면 오류', () {
      final a = f1({...naoh, 'content_pct': 25, 'phase': '액체', 'capacity_m3': 30.0, 'specific_gravity': 1.37, 'low_diffusion': true});
      expect(a['verdict'], '미대상');
      expect(a['reason'], contains('제23조'));
      expect(f1({...sicl4, 'content_pct': 100, 'phase': '액체', 'capacity_m3': 1, 'specific_gravity': 1.5, 'low_diffusion': true})['verdict'],
          'error');
    });

    test('함량미만 — 사례 A SiCl4 2.25% vs 함량기준 10%', () {
      final a = f1({...sicl4, 'content_pct': 2.25, 'phase': '기체', 'quantity_kg': 30, 'basis': 'x'});
      expect(a['verdict'], '함량미만');
      expect(a['reason'], contains('10'));
    });

    test('입력 오류 — 성상 없음, 액체에 독성구분, 정수 아닌 독성구분 → error, 판정 incomplete', () {
      final r = scenario([
        {...sicl4, 'content_pct': 100, 'capacity_m3': 1, 'specific_gravity': 1.5},
        {...sicl4, 'content_pct': 100, 'phase': '액체', 'capacity_m3': 1, 'specific_gravity': 1.5, 'acute_toxicity_category': 2},
        {...chlorine3, 'content_pct': 100, 'phase': '기체', 'quantity_kg': 5, 'basis': 'x', 'acute_toxicity_category': '1'},
        {...chlorine3, 'content_pct': 100, 'phase': '기체', 'quantity_kg': 5, 'basis': 'x', 'acute_toxicity_category': 1},
      ]);
      expect(r['status'], 'incomplete');
      expect(facilities(r).map((f) => f['verdict']), ['error', 'error', 'error', '표준시설']);
      expect((r['issues']! as List), hasLength(3));
    });
  });

  group('MCP', () {
    test('tools/call calc_writing_level — 결과 JSON, 형식 오류는 isError + 사유', () {
      final logs = <String>[];
      final mcp = McpHandler(ds, version: 'test', log: logs.add);
      Map call(Map<String, Object?> args, [String name = 'calc_writing_level']) =>
          (mcp.handleMessage({
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'tools/call',
            'params': {'name': name, 'arguments': args},
          })!['result']! as Map);
      final ok = call({
        'facilities': [
          {...chlorine3, 'content_pct': 100, 'quantity_ton': 2, 'basis': '충전량'},
        ],
      });
      expect(ok['isError'], false);
      expect((jsonDecode(((ok['content'] as List).single as Map)['text'] as String) as Map)['level'], '1군');

      final bad = call({'facilities': 'x'}, 'screen_preliminary_scenarios');
      expect(bad['isError'], true);
      expect(((bad['content'] as List).single as Map)['text'], contains('facilities'));
    });
  });
}
