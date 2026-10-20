// A-010 2단계 — MCP 도구 get_form6_constants 수용 기준(REQUIREMENTS_AGENT A-010 '2단계'). 실제 번들ㆍ실제 생성물에 질의한다.
import 'dart:convert';
import 'dart:io';

import 'package:findchem/form6/form6_tool.dart';
import 'package:findchem/mcp/mcp_handler.dart';
import 'package:findchem/parser/models.dart';
import 'package:flutter_test/flutter_test.dart';

final ds = Dataset.fromJson((jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>());
final data = Form6Data.load('assets/form6/form6_constants.json', (m) => fail(m))!;
final onDisk = jsonDecode(File('assets/form6/form6_constants.json').readAsStringSync()) as Map;

Map<String, Object?> run(List<Object?> cas) {
  final r = form6Constants(ds, data, {'cas': cas});
  expect(r.error, isNull);
  return r.response;
}

List<Map<String, Object?>> items(Map<String, Object?> r) => (r['items'] as List).cast<Map<String, Object?>>();

void main() {
  group('입력', () {
    test('배열이 아니거나 비었으면 오류', () {
      expect(form6Constants(ds, data, {'cas': '108-88-3'}).error, contains('배열'));
      expect(form6Constants(ds, data, {'cas': <Object?>[]}).error, contains('배열'));
      expect(form6Constants(ds, data, {}).error, contains('배열'));
    });

    test('51개면 조회하지 않고 개수와 상한', () {
      final e = form6Constants(ds, data, {'cas': List.filled(form6CasCap + 1, '108-88-3')}).error!;
      expect(e, contains('${form6CasCap + 1}개'));
      expect(e, contains('상한 $form6CasCap개'));
      expect(form6Constants(ds, data, {'cas': List.filled(form6CasCap, '108-88-3')}).error, isNull);
    });

    test('items = 입력과 같은 순서ㆍ같은 개수(하나가 틀려도 나머지는 조회)', () {
      final r = run(['abc', '108-88-3', '123-86-4', '68-12-2', '108-88-3']);
      expect(items(r).map((i) => i['status']), ['invalid', 'found', 'not_listed', 'found', 'found']);
      expect(r['total'], 5);
      expect(r['counts'], {'found': 3, 'not_covered': 0, 'not_listed': 1, 'invalid': 1});
    });
  });

  group('항목', () {
    test('108-88-3 → found, 톨루엔, 물질구분 [사고대비], 고유번호 후보에 사고대비물질: 28, 9칸이 생성물과 같다', () {
      final t = items(run(['108-88-3'])).single;
      expect(t['status'], 'found');
      expect(t['name'], '톨루엔');
      expect(t['material_class'], ['사고대비']);
      expect((t['unique_number_candidates'] as List).map((u) => (u as Map)['value']), contains('사고대비물질: 28'));
      final want = (onDisk['substances'] as List).firstWhere((s) => (s as Map)['cas'] == '108-88-3') as Map;
      expect(jsonEncode(t['fields']), jsonEncode(want['fields']));
    });

    test('000108-88-3 → 108-88-3으로 조회, input에 원래 표기', () {
      final t = items(run(['000108-88-3'])).single;
      expect((t['cas'], t['input'], t['status']), ('108-88-3', '000108-88-3', 'found'));
    });

    test('68-12-2(DMF, 별표 2만) → found(범위 확장) + 물질구분ㆍ별표 2 고유번호 후보 / 123-86-4 → not_listed / abc → invalid', () {
      final [dmf, butyl, bad] = items(run(['68-12-2', '123-86-4', 'abc']));
      expect(dmf['status'], 'found');
      expect(dmf['material_class'], isNotEmpty);
      expect((dmf['material_class'] as List).contains('사고대비'), isFalse);
      expect((dmf['unique_number_candidates'] as List).map((u) => (u as Map)['source']), contains('별표 2 고유번호'));
      expect(butyl['status'], 'not_listed');
      expect(bad['status'], 'invalid');
    });

    test('상수 데이터에 없는 유해화학물질 → not_covered(데이터에서 DMF를 뺀 경우), 칸 없음', () {
      final sub = Form6Data.fromJson({
        ...(onDisk.cast<String, Object?>()),
        'substances': [for (final s in onDisk['substances'] as List) if ((s as Map)['cas'] != '68-12-2') s],
      });
      final dmf = (form6Constants(ds, sub, {'cas': ['68-12-2']}).response['items'] as List).single as Map;
      expect(dmf['status'], 'not_covered');
      expect(dmf.containsKey('fields'), isFalse);
      expect((dmf['unique_number_candidates'] as List), isNotEmpty);
    });

    test('물질구분이 여럿인 사고대비물질(107-13-1 아크릴로니트릴) — 사고대비 먼저', () {
      final t = items(run(['107-13-1'])).single;
      expect((t['material_class'] as List).first, '사고대비');
      expect((t['material_class'] as List).length, greaterThan(1));
    });
  });

  test('응답 머리에 AIHA 고지문 원문과 범위 문장', () {
    final r = run(['108-88-3']);
    expect(r['aiha_notice'] as String, contains('non-commercial, educational, research, and governmental use'));
    expect(r['scope'] as String, contains('CAS ${(onDisk['targets'] as Map)['casCount']}개'));
    expect((onDisk['targets'] as Map)['casCount'], greaterThan(1500));
    expect(r['fill_rules'] as String, contains('주⑨'));
  });

  test('상수 파일 없이 만든 서버: 이 도구는 isError + 사유, classify_cas는 정상', () {
    final logs = <String>[];
    final mcp = McpHandler(ds, version: 'test', log: logs.add); // form6 없음
    Map<String, Object?> call(String name) => (mcp.handleMessage({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'tools/call',
          'params': {
            'name': name,
            'arguments': {
              'cas': ['108-88-3'],
            },
          },
        })!['result']! as Map)
            .cast<String, Object?>();
    final f = call('get_form6_constants');
    expect(f['isError'], true);
    expect(((f['content']! as List).single as Map)['text'], contains('6호서식 상수 데이터가 없어'));
    expect(call('classify_cas')['isError'], false);
  });

  test('파일이 없으면 load는 null + 로그', () {
    final logs = <String>[];
    expect(Form6Data.load('assets/form6/없는파일.json', logs.add), isNull);
    expect(logs.single, contains('get_form6_constants는 실패로 답한다'));
  });

  test('MCP 서버(상수 있음)에서 tools/call get_form6_constants — JSON 응답', () {
    final mcp = McpHandler(ds, version: 'test', log: (m) => fail(m), form6: data);
    final r = (mcp.handleMessage({
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'tools/call',
      'params': {
        'name': 'get_form6_constants',
        'arguments': {
          'cas': ['108-88-3'],
        },
      },
    })!['result']! as Map);
    expect(r['isError'], false);
    final body = jsonDecode(((r['content']! as List).single as Map)['text'] as String) as Map;
    expect((body['items'] as List).single['status'], 'found');
  });
}
