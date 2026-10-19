// A-010 별지 6호서식 물질 상수 — 수용 기준(REQUIREMENTS_AGENT A-010).
// 실데이터: 번들(assets/data/findchem_data.json) + 커밋된 원문(assets/form6/raw/, 2026-10-19 수집). 실호출은 하지 않는다.
// 녹화에 없는 경우(같은 CAS 2건·특정 단위)는 녹화 XML 모양을 본뜬 응답을 테스트 안에서 만든다.
import 'dart:convert';
import 'dart:io';

import 'package:findchem/form6/form6_build.dart';
import 'package:findchem/form6/form6_builder.dart';
import 'package:findchem/form6/targets.dart';
import 'package:findchem/lookup/chem_parse.dart';
import 'package:findchem/msds/msds_client.dart';
import 'package:findchem/parser/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const rawDir = 'assets/form6/raw';
final ds = Dataset.fromJson((jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>());

String xmlOk(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><response><header><resultCode>00</resultCode>'
    '<resultMsg>NORMAL SERVICE.</resultMsg></header><body>$body</body></response>';

String item(String code, String parent, String name, String detail) =>
    '<item><msdsItemCode>$code</msdsItemCode><upMsdsItemCode>$parent</upMsdsItemCode><lev>2</lev>'
    '<msdsItemNameKor>$name</msdsItemNameKor><itemDetail>$detail</itemDetail><ordrIdx>1</ordrIdx></item>';

/// 가짜 KOSHA — CAS `11-11-1` 하나, 9절·8절 값을 준다. [rows]가 2면 같은 CAS 2건(ambiguous).
Future<MsdsResult> fakeKosha({
  String state = '액체',
  String sg = '1.0',
  String limits = '10 / 1 %',
  String vp = '10 mmHg(20℃)',
  String twa = 'TWA 1 ppm',
  int rows = 1,
}) {
  final rowsXml = [
    for (var i = 0; i < rows; i++)
      '<item><casNo>11-11-1</casNo><chemId>00000$i</chemId><chemNameKor>가짜$i</chemNameKor><lastDate>2026-01-01</lastDate></item>',
  ].join();
  final list = xmlOk('$rowsXml<totalCount>$rows</totalCount>');
  final d09 = xmlOk('<items>${item('I0202', 'I02', '성상', state)}${item('I28', 'I', '비중', sg)}'
      '${item('I20', 'I', '폭발범위', limits)}${item('I22', 'I', '증기압', vp)}</items>');
  final d08 = xmlOk('<items>${item('H02', 'H', '노출기준', '')}${item('H0202', 'H02', '국내규정', twa)}</items>');
  final d02 = xmlOk('<items></items>');
  final client = MockClient((req) async {
    final s = req.url.pathSegments.last;
    final body = switch (s) {
      'getChemList001' => list,
      'getChemDetail091' => d09,
      'getChemDetail081' => d08,
      _ => d02,
    };
    return http.Response.bytes(utf8.encode(body), 200);
  });
  return MsdsClient(httpClient: client, key: 'k').lookup('11-11-1');
}

Map<String, Object?> fieldsOf(Map<String, Object?> sub) => (sub['fields'] as Map).cast<String, Object?>();
Map<String, Object?> f(Map<String, Object?> sub, String name) => (fieldsOf(sub)[name] as Map).cast<String, Object?>();

GhsHazard hz(String item) => GhsHazard(item: item, grade: '1', hCode: 'H000', pCodes: const []);

void main() {
  late Map<String, Object?> built;
  late List<Map<String, Object?>> subs;

  setUpAll(() async {
    built = await buildForm6(dataset: ds, rawDir: rawDir, overrides: const []);
    subs = (built['substances'] as List).cast<Map<String, Object?>>();
  });

  group('대상', () {
    test('대상 = 번들 별표 3 살아 있는 항목의 CAS 전부, 머리에 CAS 수와 CAS 없는 항목', () {
      final want = <String>{
        for (final e in ds.entries)
          if (e.src == Source.byeolpyo3 && !e.deleted) ...e.cas,
      };
      expect(subs.map((s) => s['cas']).toSet(), want);
      expect(subs.length, want.length);
      final t = built['targets'] as Map;
      expect(t['casCount'], want.length);
      final noCas = ds.entries.where((e) => e.src == Source.byeolpyo3 && !e.deleted && e.cas.isEmpty).length;
      expect((t['noCasEntries'] as List).length, noCas);
      expect(t['entryCount'], form6TargetsOf(ds).entryCount);
    });

    test('원문이 없으면 만들지 않고 빠진 파일을 알린다', () async {
      final empty = Directory.systemTemp.createTempSync('form6_empty');
      addTearDown(() => empty.deleteSync(recursive: true));
      await expectLater(
        buildForm6(dataset: ds, rawDir: empty.path, overrides: const []),
        throwsA(isA<Form6BuildError>().having((e) => e.details, 'details', containsAll(['ghs/108-88-3.json', 'kosha/list_108-88-3_p1.xml']))),
      );
    });
  });

  group('값', () {
    test('모든 칸에 출처와 상태가 있고, 상태는 셋 중 하나', () {
      final labels = Form6Status.values.map((s) => s.label).toSet();
      for (final s in subs) {
        expect(fieldsOf(s).keys.toList(), form6FieldNames, reason: '${s['cas']}');
        for (final n in form6FieldNames) {
          final v = f(s, n);
          expect(labels, contains(v['status']), reason: '${s['cas']} $n');
          expect((v['source'] as Map)['kind'], isNotEmpty, reason: '${s['cas']} $n');
        }
      }
    });

    test('지어낸 숫자 0건 — 해석한 숫자 문자열이 원문 안에 있고 값과 같다(전 CAS 전 칸)', () {
      var checked = 0;
      for (final s in subs) {
        for (final n in form6FieldNames) {
          final v = f(s, n);
          final number = v['number'] as String?;
          if (number == null) continue;
          checked++;
          expect(v['raw'] as String, contains(number), reason: '${s['cas']} $n');
          if (n != 'vaporPressure' && v['value'] is num) {
            expect(v['value'], double.parse(number.replaceAll(',', '')), reason: '${s['cas']} $n');
          }
        }
      }
      expect(checked, greaterThan(300)); // 2026-10-19 원문 382칸 — 검사가 비어서 통과하지 않게
    });

    test('톨루엔 108-88-3: 독성구분 = 환경공단 분류 6건 원문 순서, 부식성 무 + 사유', () {
      final t = subs.firstWhere((s) => s['cas'] == '108-88-3');
      final ghs = f(t, 'ghs');
      expect(ghs['status'], '확정');
      expect([for (final h in ghs['value'] as List) '${h['item']}|${h['grade']}|${h['hCode']}'], [
        '흡인 유해성|1|H304',
        '생식독성|2|H361',
        '피부 부식성/자극성|2|H315',
        '인화성 액체|2|H225',
        '특정 표적장기 독성-1회 노출|3|H336',
        '특정 표적장기 독성-반복 노출|2|H373',
      ]);
      final c = f(t, 'corrosive');
      expect(c['value'], '무');
      expect(c['note'], '분류 목록에 금속부식성 없음');
      expect(f(t, 'twa')['value'], 50.0);
      expect(f(t, 'twa')['unit'], 'ppm');
    });

    test('금속부식성 분류가 있으면 부식성 유(실데이터에 1건 이상)', () {
      final yes = subs.where((s) => f(s, 'corrosive')['value'] == '유').toList();
      expect(yes, isNotEmpty);
      for (final s in yes) {
        expect(f(s, 'corrosive')['raw'] as String, contains('금속부식'));
      }
    });

    group('증기압 mmHg 환산(D4)', () {
      for (final (raw, mmHg) in [
        ('10 ㎪(20℃)', 75.01),
        ('10 kPa (20℃)', 75.01),
        ('10 hPa (20℃)', 7.501),
        ('413 ㎩(20℃)', 3.098),
        ('28.4 ㎜Hg(20℃)', 28.4),
        ('1 atm (20℃)', 760.0),
      ]) {
        test('$raw → $mmHg mmHg, 확정, 계수 기록', () async {
          final v = vaporPressureField(await fakeKosha(vp: raw), null);
          expect(v['value'], mmHg);
          expect(v['status'], '확정');
          expect(v['mmHgFactor'], isNotNull);
          expect(v['note'], isNull);
        });
      }

      test('20℃가 아니면 온도를 붙이고 확정, 온도가 없으면 확인필요, 온도가 여럿이면 확인필요', () async {
        final at25 = vaporPressureField(await fakeKosha(vp: '28.4 ㎜Hg(25℃)'), null);
        expect((at25['status'], at25['condition']), ('확정', '25℃'));
        expect(at25['note'], contains('20℃가 아닌'));
        final none = vaporPressureField(await fakeKosha(vp: '50 Pa'), null);
        expect((none['status'], none['note']), ('확인필요', '온도 표기 없음'));
        final two = vaporPressureField(await fakeKosha(vp: '63397 ㎩((21.1 ℃)77,973 Pa(26.6 ℃))'), null);
        expect(two['status'], '확인필요');
      });

      test('실데이터: 환산값 = 원문 숫자 × 계수(유효숫자 4)', () {
        var n = 0;
        for (final s in subs) {
          final v = f(s, 'vaporPressure');
          if (v['mmHgFactor'] == null) continue;
          n++;
          final num = double.parse((v['number'] as String).replaceAll(',', ''));
          expect(v['value'], sig4(num * (v['mmHgFactor'] as double)), reason: '${s['cas']}');
        }
        expect(n, greaterThan(80));
      });
    });

    test('폭발한계 `- / -`: GHS에 인화성이 없으면 해당없음(확정), 있으면 확인필요', () async {
      final r = await fakeKosha(limits: '- / -');
      final (lowNo, _) = explosionFields(r, null, ghsHazards: [hz('급성 독성-흡입')]);
      expect((lowNo['value'], lowNo['status']), ('해당없음', '확정'));
      final (lowYes, _) = explosionFields(r, null, ghsHazards: [hz('인화성 가스')]);
      expect((lowYes['value'], lowYes['status']), (null, '확인필요'));
      final (lowUnknown, _) = explosionFields(r, null);
      expect(lowUnknown['status'], '확인필요');
    });

    test('물질상태: 하나만 걸리면 확정, 여럿·액화는 확인필요', () async {
      expect(stateField(await fakeKosha(state: '무색 액체'), null)['value'], '액체');
      expect(stateField(await fakeKosha(state: '액체 또는 기체'), null)['status'], '확인필요');
      expect(stateField(await fakeKosha(state: '기체 (액화가스)'), null)['status'], '확인필요');
    });

    test('TWA: `|자료없음`은 자료없음, 최고노출기준만 있으면 확인필요', () async {
      expect(twaField(await fakeKosha(twa: '|자료없음'), null)['status'], '자료없음');
      final c = twaField(await fakeKosha(twa: '| |STEL : C4.7ppm'), null);
      expect((c['status'], c['note']), ('확인필요', '국내규정에 TWA 없음(최고노출기준 C만)'));
    });

    test('KOSHA에 같은 CAS가 2건이면 KOSHA 원천 칸 전부 확인필요 + 후보', () async {
      final r = await fakeKosha(rows: 2);
      expect(r.status, MsdsStatus.ambiguous);
      final s = buildSubstance(cas: '11-11-1', kosha: r, ghs: null, ghsRaw: '', pac: null, collectedAt: null);
      for (final n in ['state', 'specificGravity', 'lel', 'uel', 'twa', 'vaporPressure']) {
        expect(f(s, n)['status'], '확인필요', reason: n);
        expect(f(s, n)['note'] as String, contains('000000 가짜0'), reason: n);
      }
    });
  });

  group('생성', () {
    test('같은 원문으로 두 번 만들면 같은 결과', () async {
      final again = await buildForm6(dataset: ds, rawDir: rawDir, overrides: const []);
      expect(jsonEncode(again), jsonEncode(built));
    });

    test('커밋된 생성물이 지금 원문으로 만든 것과 같다(생성 스크립트를 돌리지 않고 원문만 바꾸면 잡힌다)', () {
      final onDisk = jsonDecode(File('assets/form6/form6_constants.json').readAsStringSync());
      final overrides = parseOverrides(File('assets/form6/overrides.json').readAsStringSync(), form6TargetsOf(ds).cas.toSet());
      if (overrides.isEmpty) {
        expect(jsonEncode((onDisk as Map)['substances']), jsonEncode(built['substances']));
      }
    });

    group('보정 파일 검증(D7)', () {
      final targets = form6TargetsOf(ds).cas.toSet();
      String one(Map<String, Object?> o) => jsonEncode([o]);
      final ok = {'cas': '108-88-3', 'field': 'twa', 'value': 50, 'reason': '고용노동부 고시 확인', 'source': '고용노동부고시 제2020-48호'};

      for (final (label, bad, why) in [
        ('대상 밖 CAS', {...ok, 'cas': '123-86-4'}, '대상 밖 CAS'),
        ('없는 칸 이름', {...ok, 'field': 'flash'}, '없는 칸 이름'),
        ('근거 빈칸', {...ok, 'reason': ' '}, '근거'),
      ]) {
        test('$label → 실패 + 사유', () {
          expect(
            () => parseOverrides(one(bad), targets),
            throwsA(isA<Form6BuildError>().having((e) => e.details.join(), 'details', contains(why))),
          );
        });
      }

      test('덮은 칸에 원래 값이 남는다', () async {
        final b = await buildForm6(dataset: ds, rawDir: rawDir, overrides: parseOverrides(one(ok), targets));
        final t = (b['substances'] as List).cast<Map<String, Object?>>().firstWhere((s) => s['cas'] == '108-88-3');
        final v = f(t, 'twa');
        expect((v['value'], v['status'], v['note']), (50, '확정', '고용노동부 고시 확인'));
        expect(((v['overriddenFrom'] as Map)['source'] as Map)['kind'], 'KOSHA MSDS');
        expect(b['overrideCount'], 1);
      });
    });
  });
}
