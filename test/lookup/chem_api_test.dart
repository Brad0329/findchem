/// F-007 응답 해석·주소·실패 문구 — 2026-09-14 CAS 50-00-0 실호출 원문(fixture)으로 돈다.
library;

import 'dart:convert';

import 'package:findchem/lookup/api_settings.dart';
import 'package:findchem/lookup/chem_api.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../data/fakes.dart';
import 'fake_api.dart';

void main() {
  group('응답 해석(fixture)', () {
    test('화학물질 정보: 이름·분자식·기존화학물질 번호, 분류 6건. 공백뿐인 값은 빈 문자열', () {
      final r = parseChemResponse(fixtures[ChemService.chem]!) as ServiceOk;
      expect(r.records, hasLength(1));
      expect(r.total, 1);
      expect(r.truncated, isFalse);
      final c = r.records.single as ChemRecord;
      expect((c.ko, c.en, c.formula, c.weight, c.existingNo), ('포르말린', 'Formaldehyde', 'CH2O', '30.03', 'KE-17074'));
      expect(c.otherKo, startsWith('폼알데하이드; 포름알데히드'));
      expect(c.types.map((t) => t.name), [
        '기존화학물질',
        '인체등유해성물질',
        '제한물질',
        '사고대비물질',
        '등록대상기존화학물질',
        '중점관리물질',
      ]);
      expect(c.types[1].content, '인체급성유해성 : 1%, 인체만성유해성 : 0.1%');
      expect(c.types[3].date, '', reason: '원문은 공백 8칸 — 빈 값으로 보고 화면에서 뺀다');
    });

    test('유독물 GHS 정보: 신호어·UN번호·그림문자·M계수, 분류·고유번호 6건, 유해성 분류 9건. ^는 풀고 코드는 원문 그대로', () {
      final r = parseGhsResponse(fixtures[ChemService.ghs]!) as ServiceOk;
      final g = r.records.single as GhsRecord;
      expect(g.signal, '위험');
      expect(g.unNumbers, ['1198', '2209']);
      expect(g.pictograms, ['GHS02', 'GHS04', 'GHS05', 'GHS06', 'GHS08']);
      expect(g.mFactor, '-');
      expect(g.classNumbers, hasLength(6));
      expect(g.classNumbers.first, '기존화학물질: V');
      expect(g.hazards, hasLength(9));
      expect(g.hazards.first.item, '급성독성-경피');
      expect(g.hazards.first.pCodes, ['P280', 'P302+P352', 'P312', 'P321', 'P361+P364', 'P405', 'P501']);
    });

    test('안전관리정보: 6항목, 문장은 원문 그대로 — 중복 문장과 자료없음을 지우지 않는다', () {
      final r = parseSafetyResponse(fixtures[ChemService.safety]!) as ServiceOk;
      final s = r.records.single as SafetyRecord;
      expect(s.items.map((i) => i.$1), ['일반증상', '흡입', '피부', '안구', '경구', '기타']);
      expect(s.items.map((i) => i.$2.length), [4, 9, 16, 6, 6, 1]);
      final skin = s.items[2].$2;
      expect(skin.where((l) => l == '·반복 노출은 홍반, 부어오름, 수포 등의 접촉성 피부염을 유발시킬 수 있음'), hasLength(2));
      expect(s.items.last.$2, ['·자료없음']);
    });

    test('totalCount가 받은 건수보다 크면 truncated(더 있음)', () {
      final body = (jsonDecode(fixtures[ChemService.chem]!) as Map)..['body']['totalCount'] = 12;
      final r = parseChemResponse(jsonEncode(body)) as ServiceOk;
      expect((r.total, r.records.length, r.truncated), (12, 1, true));
    });

    test('결과 0건이면 records가 비어 있다', () {
      final body = (jsonDecode(fixtures[ChemService.ghs]!) as Map)
        ..['body']['items'] = []
        ..['body']['totalCount'] = 0;
      final r = parseGhsResponse(jsonEncode(body)) as ServiceOk;
      expect(r.records, isEmpty);
    });

    test('결과 코드가 정상이 아니면 그 코드로 실패', () {
      final xml = fixtures[ChemService.safety]!.replaceFirst('<resultCode>00</resultCode>', '<resultCode>99</resultCode>');
      expect((parseSafetyResponse(xml) as ServiceFailed).message, LookupText.failed('99'));
    });
  });

  group('요청 주소', () {
    test('인코딩 키(% 포함)와 디코딩 키가 같은 주소를 만든다 — 두 번 인코딩하지 않는다', () {
      const decoded = 'ab+cd/ef==';
      const encoded = 'ab%2Bcd%2Fef%3D%3D';
      for (final s in ChemService.values) {
        expect(buildRequestUri(s, decoded, '50-00-0').toString(), buildRequestUri(s, encoded, '50-00-0').toString());
      }
      expect(buildRequestUri(ChemService.chem, decoded, '50-00-0').toString(), contains('serviceKey=$encoded&'));
    });

    test('chem·ghs는 CAS 검색(searchGubun=2)·JSON, safety는 casNo(결과 형식 파라미터 없음)', () {
      final chem = buildRequestUri(ChemService.chem, 'K', '50-00-0');
      expect(chem.queryParameters, containsPair('searchGubun', '2'));
      expect(chem.queryParameters, containsPair('searchNm', '50-00-0'));
      expect(chem.queryParameters, containsPair('returnType', 'JSON'));
      final safety = buildRequestUri(ChemService.safety, 'K', '50-00-0');
      expect(safety.queryParameters, containsPair('casNo', '50-00-0'));
      expect(safety.queryParameters.containsKey('returnType'), isFalse);
    });
  });

  group('실패 문구(ChemApiClient)', () {
    Future<String> failWith(Future<http.Response> Function() response, {Duration? timeout}) async {
      final api = FakeApi()..overrides[ChemService.chem] = response;
      final r = await api.client(timeout: timeout ?? const Duration(seconds: 20)).fetch(ChemService.chem, 'K', '50-00-0');
      return (r as ServiceFailed).message;
    }

    test('401 → 키가 올바르지 않습니다', () async {
      expect(await failWith(() async => utf8Response(portalError('20'), 401)), LookupText.badKey);
    });
    test('403 → 활용신청이 승인되지 않았습니다', () async {
      expect(await failWith(() async => utf8Response('Forbidden', 403)), LookupText.notApproved);
    });
    test('HTTP 200이어도 포털 코드 30 → 활용신청, 22 → 한도 초과', () async {
      expect(await failWith(() async => utf8Response(portalError('30'), 200)), LookupText.notApproved);
      expect(await failWith(() async => utf8Response(portalError('22'), 200)), LookupText.overLimit);
    });
    test('그 밖 → 조회하지 못했습니다 (코드 N)', () async {
      expect(await failWith(() async => utf8Response('oops', 500)), LookupText.failed('500'));
    });
    test('접속 실패·시간 초과 → 접속하지 못했습니다', () async {
      expect(await failWith(() async => throw http.ClientException('XMLHttpRequest error')), LookupText.offline);
      expect(
        await failWith(
          () => Future.delayed(const Duration(milliseconds: 200), () => utf8Response('late', 200)),
          timeout: const Duration(milliseconds: 10),
        ),
        LookupText.offline,
      );
    });
    test('JSON이 아닌 200 응답 → 응답 형식 실패(예외를 던지지 않는다)', () async {
      expect(await failWith(() async => utf8Response('<html>', 200)), LookupText.failed('응답 형식'));
    });

    test('키는 로그에 나오지 않는다 — 넣은 형태와 인코딩 형태 모두 가린다', () async {
      final logs = <String>[];
      final old = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) => logs.add(m ?? '');
      addTearDown(() => debugPrint = old);

      const key = 'SECRET+KEY/abc==';
      final encoded = Uri.encodeQueryComponent(key);
      final api = FakeApi()
        ..overrides[ChemService.chem] = () async => utf8Response('echo $key $encoded ${portalError('30')}', 403);
      final r = await api.client().fetch(ChemService.chem, key, '50-00-0');
      expect(r, isA<ServiceFailed>());
      final all = logs.join('\n');
      expect(all, contains('<KEY>'));
      expect(all, isNot(contains('SECRET')));
    });

    test('소문자로 인코딩한 키도 요청 주소(대문자 %xx) 표기까지 가린다', () {
      const key = 'ab%2bcd%3d';
      final uri = buildRequestUri(ChemService.chem, key, '50-00-0').toString();
      final masked = maskKey('ClientException: failed, uri=$uri', key);
      expect(masked, isNot(contains('ab%2')));
      expect(masked, isNot(contains('ab+cd')));
      expect(masked, contains('serviceKey=<KEY>'));
    });
  });

  group('조회 시작(startLookup)', () {
    Future<(LookupStart, FakeApi)> start(String? stored) async {
      final api = FakeApi();
      final settings = ApiSettingsController(store: MemoryUpdateStore(stored));
      return (await startLookup(settings, api.client(), '50-00-0'), api);
    }

    test('키가 없으면 부르지 않고 안내', () async {
      final (s, api) = await start(apiSettingsJson(key: null));
      expect((s as LookupBlocked).message, LookupText.noKey);
      expect(api.calls, isEmpty);
    });
    test('체크가 0개면 부르지 않고 안내', () async {
      final (s, api) = await start(apiSettingsJson(services: {'chem': false, 'ghs': false, 'safety': false}));
      expect((s as LookupBlocked).message, LookupText.noService);
      expect(api.calls, isEmpty);
    });
    test('설정 파일이 깨졌으면 부르지 않고 안내', () async {
      final (s, api) = await start('{"version": 1,');
      expect((s as LookupBlocked).message, LookupText.settingsUnreadable);
      expect(api.calls, isEmpty);
    });
    test('사용자 키가 없고 기본 키가 있으면 기본 키로 부른다. 사용자 키가 있으면 사용자 키', () async {
      final api = FakeApi();
      final withDefault = ApiSettingsController(store: MemoryUpdateStore(), defaultKey: 'DEFAULTKEY');
      final s = await startLookup(withDefault, api.client(), '50-00-0') as LookupRunning;
      await Future.wait(s.calls.values);
      expect(api.calls.map((u) => u.queryParameters['serviceKey']).toSet(), {'DEFAULTKEY'});

      api.calls.clear();
      final mine = ApiSettingsController(store: MemoryUpdateStore(apiSettingsJson(key: 'MINE')), defaultKey: 'DEFAULTKEY');
      final s2 = await startLookup(mine, api.client(), '50-00-0') as LookupRunning;
      await Future.wait(s2.calls.values);
      expect(api.calls.map((u) => u.queryParameters['serviceKey']).toSet(), {'MINE'});
    });

    test('체크한 서비스만 부른다', () async {
      final (s, api) = await start(apiSettingsJson(services: {'chem': true, 'ghs': false, 'safety': true}));
      final running = s as LookupRunning;
      expect(running.calls.keys, [ChemService.chem, ChemService.safety]);
      await Future.wait(running.calls.values);
      expect(api.callsTo(ChemService.ghs), 0);
      expect(api.calls, hasLength(2));
    });
  });
}
