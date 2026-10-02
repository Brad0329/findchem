// A-003 2차 — KOSHA MSDS 호출·목록·상세·응답 조립(REQUIREMENTS_AGENT A-003 '2차').
// 응답은 2026-10-02 실호출 녹화본(test/fixtures/msds/, scripts/record_msds.dart)으로 돈다 — 실호출은 하지 않는다.
// 녹화에 없는 경우(완전 일치 2건·목록 여러 쪽·상한 초과·HTTP 오류)만 녹화 XML 모양을 본뜬 응답을 테스트 안에서 만든다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:findchem/lookup/portal.dart';
import 'package:findchem/msds/msds_client.dart';
import 'package:findchem/msds/msds_value.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const dir = 'test/fixtures/msds';
const testKey = 'abc+def/ghi==';
final fixedTime = DateTime.utc(2026, 10, 2, 9);

String fixture(String name) => File('$dir/$name').readAsStringSync();

/// 녹화본으로 답하는 가짜 서버. [override]가 응답을 주면 그것을 쓴다. 부른 주소는 [calls]에.
class FakePortal {
  FakePortal({this.override});

  final http.Response? Function(Uri uri)? override;
  final calls = <Uri>[];

  http.Client get client => MockClient((req) async {
    calls.add(req.url);
    final o = override?.call(req.url);
    if (o != null) return o;
    final service = req.url.pathSegments.last;
    final q = req.url.queryParameters;
    final name = service == 'getChemList001'
        ? 'list_${q['searchWrd']}.xml'
        : 'detail${service.substring('getChemDetail'.length, 'getChemDetail'.length + 2)}_${q['chemId']}.xml';
    final f = File('$dir/$name');
    if (!f.existsSync()) return res('녹화 없음 $name', 404);
    return http.Response.bytes(f.readAsBytesSync(), 200, headers: {'content-type': 'application/xml;charset=UTF-8'});
  });

  int count(String service) => calls.where((u) => u.pathSegments.last == service).length;
}

MsdsClient clientOf(FakePortal p, {String key = testKey, List<String>? logs}) =>
    MsdsClient(httpClient: p.client, key: key, clock: () => fixedTime, log: logs?.add);

String xmlOk(String body) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><response><header><resultCode>00</resultCode>'
    '<resultMsg>NORMAL SERVICE.</resultMsg></header><body>$body</body></response>';

String row(String cas, String id, String name) =>
    '<item><casNo>$cas</casNo><chemId>$id</chemId><chemNameKor>$name</chemNameKor><lastDate>2026-01-01</lastDate></item>';

/// 본문을 UTF-8 바이트로(`http.Response(String)`은 charset이 없으면 latin1이라 한글이 깨진다).
http.Response res(String body, [int status = 200]) => http.Response.bytes(utf8.encode(body), status);

int fixtureItemCount(String name) => RegExp('<item>').allMatches(fixture(name)).length;

void main() {
  group('호출·목록', () {
    test('CAS 형식이 아니거나 키가 비면 호출 0회, failed와 사유', () async {
      for (final (cas, key) in [('50-00', testKey), ('abc', testKey), ('50-00-0', ''), ('50-00-0', '   ')]) {
        final p = FakePortal();
        final r = await clientOf(p, key: key).lookup(cas);
        expect(p.calls, isEmpty, reason: '$cas/$key');
        expect(r.status, MsdsStatus.failed);
        expect(r.message, isNotEmpty);
      }
    });

    test('정상 조회 = 목록 1회 + 상세 021·081·091 각 1회', () async {
      final p = FakePortal();
      final r = await clientOf(p).lookup('108-88-3');
      expect(r.status, MsdsStatus.found);
      expect(p.calls, hasLength(4));
      for (final s in ['getChemList001', 'getChemDetail021', 'getChemDetail081', 'getChemDetail091']) {
        expect(p.count(s), 1, reason: s);
      }
      expect(p.calls.first.queryParameters['searchCnd'], '1');
    });

    test('인코딩 키·디코딩 키가 같은 주소를 만든다', () {
      final a = clientOf(FakePortal(), key: testKey).requestUri('getChemList001', 'x=1');
      final b = clientOf(FakePortal(), key: Uri.encodeQueryComponent(testKey)).requestUri('getChemList001', 'x=1');
      expect(a.toString(), b.toString());
      expect(a.queryParameters['serviceKey'], testKey);
    });

    test('50-00-0 목록(부분 일치 13150-00-0 포함) → 완전 일치 1건, 버린 건수 1', () async {
      final r = await clientOf(FakePortal()).lookup('50-00-0');
      expect(r.status, MsdsStatus.found);
      expect(r.droppedPartialMatches, 1);
      expect(r.source!['chemId'], '001097');
      expect(r.source!['nameKor'], '포름알데히드');
    });

    test('totalCount가 받은 건수보다 크면 다음 쪽을 받는다', () async {
      final p = FakePortal(
        override: (u) {
          if (u.pathSegments.last != 'getChemList001') return null;
          final page = u.queryParameters['pageNo'];
          final rows = page == '1'
              ? [for (var i = 0; i < 100; i++) row('1$i-00-0', 'X$i', '부분$i')].join()
              : row('50-00-0', '001097', '포름알데히드');
          return res(xmlOk('<items>$rows</items><totalCount>101</totalCount><pageNo>$page</pageNo><numOfRows>100</numOfRows>'));
        },
      );
      final r = await clientOf(p).lookup('50-00-0');
      expect(p.count('getChemList001'), 2);
      expect(r.status, MsdsStatus.found);
      expect(r.droppedPartialMatches, 100);
    });

    test('10쪽(1,000행)을 넘으면 failed에 전체·받은 건수(조용한 절단 금지)', () async {
      final p = FakePortal(
        override: (u) => u.pathSegments.last == 'getChemList001'
            ? res(xmlOk('<items>${[for (var i = 0; i < 100; i++) row('1$i-00-0', 'X$i', 'n')].join()}</items><totalCount>1001</totalCount>'))
            : null,
      );
      final r = await clientOf(p).lookup('50-00-0');
      expect(r.status, MsdsStatus.failed);
      expect(r.message, contains('1001'));
      expect(r.message, contains('100건'));
      expect(p.count('getChemDetail021'), 0);
    });

    test('없는 CAS → not_found, 상세 0회 / 부분 일치만 있으면 not_found + 버린 건수', () async {
      final p = FakePortal();
      final r = await clientOf(p).lookup('99999-99-9');
      expect(r.status, MsdsStatus.notFound);
      expect(r.droppedPartialMatches, 0);
      expect(p.calls, hasLength(1));

      final p2 = FakePortal(
        override: (u) => u.pathSegments.last == 'getChemList001'
            ? res(xmlOk('<items>${row('13150-00-0', '041946', 'n')}</items><totalCount>1</totalCount>'))
            : null,
      );
      final r2 = await clientOf(p2).lookup('50-00-0');
      expect(r2.status, MsdsStatus.notFound);
      expect(r2.droppedPartialMatches, 1);
      expect(p2.calls, hasLength(1));
    });

    test('완전 일치 2건 → ambiguous + 후보, 상세 0회 / chemId를 주면 그것으로 상세', () async {
      FakePortal portal() => FakePortal(
        override: (u) => u.pathSegments.last == 'getChemList001'
            ? res(xmlOk('<items>${row('50-00-0', '001097', '포름알데히드')}${row('50-00-0', '999999', '포르말린')}</items><totalCount>2</totalCount>'))
            : null,
      );
      final p = portal();
      final r = await clientOf(p).lookup('50-00-0');
      expect(r.status, MsdsStatus.ambiguous);
      expect([for (final c in r.candidates) c.chemId], ['001097', '999999']);
      expect(p.calls, hasLength(1));
      expect(r.toJson()['candidates'], hasLength(2));

      final p2 = portal();
      final r2 = await clientOf(p2).lookup('50-00-0', chemId: '001097');
      expect(r2.status, MsdsStatus.found);
      expect(r2.source!['chemId'], '001097');
      expect(p2.calls.skip(1).every((u) => u.queryParameters['chemId'] == '001097'), isTrue);
      expect(p2.calls, hasLength(4));
    });
  });

  group('응답', () {
    test('source에 provider·endpoint·chemId·casNo·국문명·lastDate(원문)·retrievedAt', () async {
      final r = await clientOf(FakePortal()).lookup('108-88-3');
      expect(r.source, {
        'provider': '15157612',
        'endpoint': 'https://apis.data.go.kr/B552468/msdschem1',
        'chemId': '001032',
        'casNo': '108-88-3',
        'nameKor': '톨루엔',
        'lastDate': RegExp(r'<lastDate>([^<]*)').firstMatch(fixture('list_108-88-3.xml'))!.group(1),
        'retrievedAt': '2026-10-02T09:00:00.000Z',
      });
    });

    test('021·081·091 항목이 하나도 빠지지 않고 원문 그대로 items에(항목 수 = fixture item 수)', () async {
      final r = await clientOf(FakePortal()).lookup('50-00-0');
      for (final s in ['02', '08', '09']) {
        final name = 'detail${s}_001097.xml';
        final items = r.sections[s]!.items;
        expect(items.length, fixtureItemCount(name), reason: name);
        final raw = fixture(name);
        for (final i in items.where((i) => i.detail != null)) {
          final escaped = i.detail!.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');
          expect(raw.contains(i.detail!) || raw.contains(escaped), isTrue, reason: '${i.code}: ${i.detail}');
        }
      }
    });

    // 표본 5개 — 기대값은 녹화 원문(2026-10-02)
    final samples = <String, Map<String, Object?>>{
      '50-00-0': {
        'appearance': '(액체 또는 기체)',
        'sg': (1.15, null, UnitKind.unknown, null),
        'vp': (1.3187, 'hPa', UnitKind.pressure, '20℃'),
        'el': ((73.0, '%'), (7.0, '%')),
      },
      '108-88-3': {
        'appearance': '액체',
        'sg': (0.8623, 'g/cu cm', UnitKind.density, '20℃'),
        'vp': (28.4, '㎜Hg', UnitKind.pressure, '25℃'),
        'el': ((7.8, '%'), (1.0, '%')),
      },
      '67-56-1': {
        'appearance': '액체',
        'sg': (0.79, null, UnitKind.relativeDensity, '20℃'),
        'vp': (127.0, '㎜Hg', UnitKind.pressure, '25℃'),
        'el': ((50.0, '%'), (6.0, '%')),
      },
      '7664-93-9': {
        'appearance': '액체  (오일)',
        'sg': (1.8, null, UnitKind.relativeDensity, '20℃'),
        'vp': (6.0, 'hPa', UnitKind.pressure, '20℃, 90% aqueous sulfuric acid solution'),
        'el': null, // `- / -  (불연성)`
      },
      '13516-27-3': {
        'appearance': '고체  (결정성 고체)',
        'sg': null, // 자료없음
        'vp': (0.000000000162, '㎜Hg', UnitKind.pressure, '25℃'),
        'el': null, // `- / -`
      },
    };

    for (final MapEntry(key: cas, value: want) in samples.entries) {
      test('표본 $cas — 성상·비중·증기압·폭발한계', () async {
        final r = await clientOf(FakePortal()).lookup(cas);
        expect(r.status, MsdsStatus.found);
        expect(r.appearance().status, ValueStatus.value);
        expect(r.appearance().text, want['appearance']);

        void check(MsdsValue v, (double, String?, UnitKind, String?)? w, String what) {
          if (w == null) return;
          expect(v.status, ValueStatus.value, reason: '$cas $what ${v.raw}');
          expect(v.parsed!.value, w.$1, reason: '$cas $what');
          expect(v.parsed!.unit, w.$2, reason: '$cas $what');
          expect(v.parsed!.unitKind, w.$3, reason: '$cas $what');
          expect(v.parsed!.condition, w.$4, reason: '$cas $what');
        }

        check(r.specificGravity(), want['sg'] as (double, String?, UnitKind, String?)?, '비중');
        check(r.vaporPressure(), want['vp'] as (double, String?, UnitKind, String?)?, '증기압');
        final el = r.explosionLimits();
        final w = want['el'] as ((double, String), (double, String))?;
        if (w == null) {
          expect(el.upper.status, ValueStatus.unparsed, reason: el.upper.raw);
          expect(el.lower.status, ValueStatus.unparsed, reason: el.lower.raw);
        } else {
          expect((el.upper.parsed!.value, el.upper.parsed!.unit), w.$1, reason: '$cas 상한');
          expect((el.lower.parsed!.value, el.lower.parsed!.unit), w.$2, reason: '$cas 하한');
          expect(el.upper.parsed!.unitKind, UnitKind.percent);
        }
      });
    }

    test('13516-27-3 비중은 no_data', () async {
      final r = await clientOf(FakePortal()).lookup('13516-27-3');
      expect(r.specificGravity().status, ValueStatus.noData);
      expect(r.specificGravity().parsed, isNull);
    });

    test('지어낸 숫자 0건 — 녹화한 8물질의 해석 성공 값 전부, 숫자 문자열이 raw 안에 있다', () async {
      final cases = ['50-00-0', '108-88-3', '67-56-1', '7664-93-9', '13516-27-3', '7727-37-9', '7722-84-1', '7782-44-7'];
      var checked = 0;
      for (final cas in cases) {
        final r = await clientOf(FakePortal()).lookup(cas);
        final el = r.explosionLimits();
        for (final v in [r.specificGravity(), r.vaporPressure(), el.upper, el.lower]) {
          if (v.status != ValueStatus.value) continue;
          expect(v.raw.contains(v.parsed!.number), isTrue, reason: '$cas ${v.raw} → ${v.parsed!.number}');
          checked++;
        }
      }
      expect(checked, greaterThanOrEqualTo(20)); // 8물질 × 최대 4값 중 해석 성공 수(빈 검사로 통과하지 않게)
    });

    test('8절 노출기준 하위 항목이 이름과 원문 그대로 전부 나온다', () async {
      final r = await clientOf(FakePortal()).lookup('50-00-0');
      final ex = r.exposureLimits();
      expect([for (final i in ex) i.nameKor], ['국내규정', 'ACGIH 규정', '생물학적 노출기준', '기타 노출기준']);
      expect(ex[0].detail, '|TWA : 0.3ppm포름알데히드');
      expect(ex[1].detail, 'STEL 0.3 ppm  TWA 0.1 ppm  ');
    });

    test('그림문자 보정 실데이터: 질소 GHS04 / 과산화수소 GHS03 / 산소 GHS03·GHS04', () async {
      for (final (cas, want) in [
        ('7727-37-9', ['GHS04']),
        ('7722-84-1', ['GHS03', 'GHS05', 'GHS07', 'GHS08']), // 원문 GHS04.gif|GHS05.gif|GHS07.gif|GHS08.gif
        ('7782-44-7', ['GHS04', 'GHS03']),
      ]) {
        final r = await clientOf(FakePortal()).lookup(cas);
        final p = r.pictograms();
        expect([for (final x in p) x.standard], want, reason: cas);
        expect(p.every((x) => x.koshaRaw.endsWith('.gif')), isTrue);
      }
    });

    test('H코드 실데이터(산소) — 코드·문구', () async {
      final h = (await clientOf(FakePortal()).lookup('7782-44-7')).hazardStatements();
      expect([for (final x in h) x.code], ['H270', 'H280']);
    });

    test('항목 코드가 응답에 없으면 그 필드는 item_missing', () async {
      final p = FakePortal(
        override: (u) => u.pathSegments.last == 'getChemDetail091'
            ? res(fixture('detail09_001032.xml').replaceAll('<msdsItemCode>I28<', '<msdsItemCode>I99<'))
            : null,
      );
      final r = await clientOf(p).lookup('108-88-3');
      expect(r.specificGravity().status, ValueStatus.itemMissing);
      expect(r.vaporPressure().status, ValueStatus.value);
    });

    test('toJson — found의 필드가 모두 있고 JSON으로 직렬화된다', () async {
      final j = (await clientOf(FakePortal()).lookup('7782-44-7')).toJson();
      expect(j['status'], 'found');
      final f = j['fields'] as Map;
      expect(f.keys, containsAll(['appearance', 'specificGravity', 'vaporPressure', 'explosionLimits', 'classification', 'signalWord', 'hazardStatements', 'pictograms', 'exposureLimits']));
      expect(((f['pictograms'] as Map)['list'] as List).map((e) => (e as Map)['standard']), ['GHS04', 'GHS03']);
    });
  });

  group('실패(예외를 던지지 않는다)', () {
    Future<MsdsResult> listFails(http.Response Function() res, {List<String>? logs}) =>
        clientOf(FakePortal(override: (_) => res()), logs: logs).lookup('50-00-0');

    test('HTTP·포털 코드별 문구', () async {
      expect((await listFails(() => http.Response('', 401))).message, LookupText.badKey);
      expect((await listFails(() => http.Response('', 403))).message, LookupText.notApproved);
      // 녹화: 등록 안 된 키 → HTTP 403 + 포털 코드 30
      expect((await listFails(() => http.Response.bytes(File('$dir/error_badkey.xml').readAsBytesSync(), 403))).message, LookupText.notApproved);
      expect((await listFails(() => res('<returnReasonCode>22</returnReasonCode>'))).message, LookupText.overLimit);
      expect((await listFails(() => res('<html>점검</html'))).message, LookupText.failed('응답 형식'));
      expect((await listFails(() => http.Response('', 500))).message, LookupText.failed('500'));
      expect(
        (await listFails(() => res(xmlOk('').replaceAll('<resultCode>00', '<resultCode>03')))).message,
        LookupText.failed('03'),
      );
    });

    test('정상 결과 코드는 00(녹화)', () {
      expect(fixture('list_50-00-0.xml'), contains('<resultCode>$msdsOkCode</resultCode>'));
    });

    test('접속 실패·시간 초과 → 접속 문구', () async {
      final down = MsdsClient(
        httpClient: MockClient((_) async => throw const SocketException('reset')),
        key: testKey,
      );
      expect((await down.lookup('50-00-0')).message, LookupText.offline);

      final slow = MsdsClient(
        httpClient: MockClient((_) => Completer<http.Response>().future),
        key: testKey,
        timeout: const Duration(milliseconds: 10),
      );
      final r = await slow.lookup('50-00-0');
      expect(r.status, MsdsStatus.failed);
      expect(r.message, LookupText.offline);
    });

    test('상세 091만 실패하면 found, 9절 필드만 fetch_failed, 2·8절은 정상', () async {
      final p = FakePortal(override: (u) => u.pathSegments.last == 'getChemDetail091' ? http.Response('', 500) : null);
      final r = await clientOf(p).lookup('7782-44-7');
      expect(r.status, MsdsStatus.found);
      expect(r.specificGravity().status, ValueStatus.fetchFailed);
      expect(r.vaporPressure().status, ValueStatus.fetchFailed);
      expect(r.explosionLimits().lower.status, ValueStatus.fetchFailed);
      expect(r.appearance().status, ValueStatus.fetchFailed);
      expect(r.pictograms(), hasLength(2));
      expect(r.exposureLimits(), isNotEmpty);
    });

    test('키는 로그에 나오지 않는다(넣은 형태·인코딩 형태·대문자 %xx 표기 모두)', () async {
      for (final key in [testKey, Uri.encodeQueryComponent(testKey), Uri.encodeQueryComponent(testKey).toLowerCase()]) {
        final logs = <String>[];
        final c = MsdsClient(
          httpClient: MockClient((req) async => throw http.ClientException('reset', req.url)),
          key: key,
          log: logs.add,
        );
        await c.lookup('50-00-0');
        expect(logs, isNotEmpty);
        for (final form in {testKey, Uri.encodeQueryComponent(testKey), key}) {
          expect(logs.any((l) => l.contains(form)), isFalse, reason: '$key → $form in $logs');
        }
        expect(logs.first, contains('<KEY>'));
      }
    });
  });
}
