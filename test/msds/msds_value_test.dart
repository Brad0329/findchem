// A-003 1차 — KOSHA MSDS 값 해석(REQUIREMENTS_AGENT A-003 '1차 — 값 해석'·'1차 — 구조').
// 원문 문자열은 2026-10-01 실호출 실측 기록(plan.md 'KOSHA MSDS 조회 서비스 실측')에서 옮겼다.
// 녹화 fixture로 도는 호출·목록·상세 테스트는 2차(녹화 후)에 붙는다.
import 'dart:io';

import 'package:findchem/msds/msds_value.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('출처 꼬리', () {
    test('`|   ※출처 : ECHA`는 origin으로 분리되고 raw는 원문 그대로', () {
      const raw = '0.79 (물=1, 20℃)|   ※출처 : ECHA';
      final v = parseNumberValue(raw);
      expect(v.origin, 'ECHA');
      expect(v.text, '0.79 (물=1, 20℃)');
      expect(v.raw, raw);
      expect(v.parsed!.value, 0.79);
    });

    test('꼬리가 없으면 origin null', () {
      expect(parseNumberValue('1.15').origin, isNull);
    });
  });

  group('비중', () {
    test('`1.15` → 단위 없음, 종류 unknown(무차원으로 단정하지 않는다)', () {
      final p = parseNumberValue('1.15').parsed!;
      expect(p.value, 1.15);
      expect(p.unit, isNull);
      expect(p.basis, isNull);
      expect(p.unitKind, UnitKind.unknown);
      expect(p.condition, isNull);
    });

    test('`0.8623 (g/cu cm at 20℃)` → 밀도, 조건 20℃', () {
      final p = parseNumberValue('0.8623 (g/cu cm at 20℃)').parsed!;
      expect(p.value, 0.8623);
      expect(p.unit, 'g/cu cm');
      expect(p.unitKind, UnitKind.density);
      expect(p.condition, '20℃');
    });

    test('`0.79 (물=1, 20℃)`·`1.8 (물=1, 20℃)` → 상대밀도(물=1), 조건 20℃', () {
      for (final (raw, value) in [('0.79 (물=1, 20℃)', 0.79), ('1.8 (물=1, 20℃)', 1.8)]) {
        final p = parseNumberValue(raw).parsed!;
        expect(p.value, value, reason: raw);
        expect(p.basis, '물=1', reason: raw);
        expect(p.unitKind, UnitKind.relativeDensity, reason: raw);
        expect(p.condition, '20℃', reason: raw);
      }
    });
  });

  group('없음·해석 실패', () {
    test('`자료없음` → no_data, 해석값 없음', () {
      final v = parseNumberValue('자료없음|   ※출처 : ECHA');
      expect(v.status, ValueStatus.noData);
      expect(v.parsed, isNull);
    });

    test('숫자로 시작하지 않으면 unparsed + 원문·사유, 로그에 한 줄', () {
      final logs = <String>[];
      final v = parseNumberValue('해당없음', log: logs.add);
      expect(v.status, ValueStatus.unparsed);
      expect(v.raw, '해당없음');
      expect(v.parseError, isNotNull);
      expect(v.parsed, isNull);
      expect(logs, hasLength(1));
      expect(logs.single, contains('해당없음'));
    });
  });

  test('지어낸 숫자 0건 — 해석에 성공한 값의 숫자 문자열이 raw 안에 그대로 있다', () {
    const samples = [
      '1.15',
      '0.8623 (g/cu cm at 20℃)',
      '0.79 (물=1, 20℃)',
      '1.8 (물=1, 20℃)',
      '0.79 (물=1, 20℃)|   ※출처 : ECHA',
      '6,780 hPa',
    ];
    for (final raw in samples) {
      final v = parseNumberValue(raw);
      expect(v.status, ValueStatus.value, reason: raw);
      expect(raw.contains(v.parsed!.number), isTrue, reason: '$raw → ${v.parsed!.number}');
    }
    expect(parseNumberValue('6,780 hPa').parsed!.value, 6780); // 천 단위 쉼표
  });

  test('H코드 `|` 구분 → 코드·문구 목록, 형식이 어긋난 조각은 원문만', () {
    final logs = <String>[];
    final list = parseHazardStatements('H220 : 극인화성 가스|H280 : 고압가스; 가열하면 폭발할 수 있음|이상한 조각', log: logs.add);
    expect(list, hasLength(3));
    expect(list[0].code, 'H220');
    expect(list[0].phrase, '극인화성 가스');
    expect(list[1].code, 'H280');
    expect(list[2].code, isNull);
    expect(list[2].raw, '이상한 조각');
    expect(logs, hasLength(1));
    expect(parseHazardStatements('자료없음'), isEmpty);
  });

  test('그림문자 — KOSHA 03·04는 표준과 바꾸고 원문 파일명은 남긴다', () {
    final list = parsePictograms('GHS02.gif|GHS03.gif|GHS04.gif|GHS06.gif');
    expect([for (final p in list) p.standard], ['GHS02', 'GHS04', 'GHS03', 'GHS06']);
    expect([for (final p in list) p.koshaRaw], ['GHS02.gif', 'GHS03.gif', 'GHS04.gif', 'GHS06.gif']);

    final logs = <String>[];
    final odd = parsePictograms('skull.png', log: logs.add);
    expect(odd.single.standard, isNull);
    expect(odd.single.koshaRaw, 'skull.png');
    expect(logs, hasLength(1));
  });

  test('구조 — lib/msds/와 lib/lookup/portal.dart는 Flutter를 import하지 않는다(원격 MCP 서버가 같이 쓴다)', () {
    final files = [
      ...Directory('lib/msds').listSync().whereType<File>().where((f) => f.path.endsWith('.dart')),
      File('lib/lookup/portal.dart'),
    ];
    expect(files.length, greaterThanOrEqualTo(2));
    for (final f in files) {
      expect(f.readAsStringSync().contains('package:flutter'), isFalse, reason: f.path);
    }
  });
}
