/// F-007 설정 파일(SCHEMA.md 'API 키·연동 선택') — 저장·다시 읽기·삭제·깨진 파일·쓰기 실패. 저장 자리는 메모리.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/lookup/api_settings.dart';
import 'package:flutter_test/flutter_test.dart';

import '../data/fakes.dart';
import 'fake_api.dart';

void main() {
  Future<ApiSettingsController> loaded(MemoryUpdateStore store) async {
    final c = ApiSettingsController(store: store);
    await c.load();
    return c;
  }

  test('파일이 없으면 키 없음, 세 서비스 모두 체크(기본값)', () async {
    final c = await loaded(MemoryUpdateStore());
    expect(c.serviceKey, isNull);
    expect(c.loadError, isNull);
    expect(c.enabledServices, ChemService.values);
  });

  test('saveKey → 앞뒤 공백을 떼고 저장, 다시 읽어도 같은 키. 파일에는 version 1과 체크 3개', () async {
    final store = MemoryUpdateStore();
    await (await loaded(store)).saveKey('  KEY123 ');
    final json = jsonDecode(store.value!) as Map;
    expect(json['version'], 1);
    expect(json['serviceKey'], 'KEY123');
    expect(json['services'], {'chem': true, 'ghs': true, 'safety': true});
    expect((await loaded(store)).serviceKey, 'KEY123');
  });

  test('setService → 바로 저장되고 다시 읽어도 유지. 키는 그대로', () async {
    final store = MemoryUpdateStore(apiSettingsJson(key: 'K'));
    await (await loaded(store)).setService(ChemService.ghs, false);
    final again = await loaded(store);
    expect(again.enabled(ChemService.ghs), isFalse);
    expect(again.enabledServices, [ChemService.chem, ChemService.safety]);
    expect(again.serviceKey, 'K');
  });

  test('delete → 파일을 지우고 키 없음·체크 기본값', () async {
    final store = MemoryUpdateStore(apiSettingsJson(key: 'K', services: {'chem': false}));
    final c = await loaded(store);
    await c.delete();
    expect(store.value, isNull);
    expect(c.serviceKey, isNull);
    expect(c.enabledServices, ChemService.values);
  });

  test('쓰기가 실패하면 예외, 저장·상태는 그대로', () async {
    final before = apiSettingsJson(key: 'OLD');
    final store = MemoryUpdateStore(before);
    final c = await loaded(store);
    store.writeError = const FileSystemException('용량 부족');
    await expectLater(c.saveKey('NEW'), throwsA(isA<FileSystemException>()));
    await expectLater(c.setService(ChemService.chem, false), throwsA(isA<FileSystemException>()));
    expect(store.value, before);
    expect(c.serviceKey, 'OLD');
    expect(c.enabled(ChemService.chem), isTrue);
  });

  test('깨진 파일: 기본값으로 조용히 대체하지 않고 사유를 남긴다. 덮지 않고, delete로만 복구', () async {
    const broken = '{"version": 1, "serviceKey": ';
    final store = MemoryUpdateStore(broken);
    final c = await loaded(store);
    expect(c.loadError, ApiSettingsController.unreadableMessage);
    expect(c.serviceKey, isNull);
    await expectLater(c.saveKey('NEW'), throwsStateError);
    expect(store.value, broken);
    await c.delete();
    expect(c.loadError, isNull);
    expect(store.value, isNull);
    await c.saveKey('NEW');
    expect((await loaded(store)).serviceKey, 'NEW');
  });

  test('형식 버전이 1이 아니면 깨진 파일로 본다', () async {
    final c = await loaded(MemoryUpdateStore(jsonEncode({'version': 2, 'serviceKey': 'K'})));
    expect(c.loadError, isNotNull);
  });

  group('기본 키(F-007)', () {
    test('기본 키가 있고 파일이 없으면 기본 키를 쓴다. 사용자 키는 null', () async {
      final c = ApiSettingsController(store: MemoryUpdateStore(), defaultKey: ' DEFAULTKEY ');
      await c.load();
      expect(c.serviceKey, isNull);
      expect(c.usingDefaultKey, isTrue);
      expect(c.effectiveKey, 'DEFAULTKEY');
    });

    test('내 키를 저장하면 우선, 삭제하면 기본 키로 돌아간다. 기본 키는 파일에 쓰지 않는다', () async {
      final store = MemoryUpdateStore();
      final c = ApiSettingsController(store: store, defaultKey: 'DEFAULTKEY');
      await c.load();
      await c.setService(ChemService.ghs, false);
      expect(store.value, isNot(contains('DEFAULTKEY')), reason: '체크만 바꿔도 기본 키가 파일로 새지 않는다');
      await c.saveKey('MINE');
      expect((c.effectiveKey, c.usingDefaultKey), ('MINE', false));
      await c.delete();
      expect((c.effectiveKey, c.usingDefaultKey), ('DEFAULTKEY', true));
    });

    test('기본 키가 없으면 종전과 같다(키 없음)', () async {
      final c = ApiSettingsController(store: MemoryUpdateStore(), defaultKey: '');
      await c.load();
      expect((c.effectiveKey, c.usingDefaultKey), (null, false));
    });

    test('배포 워크플로가 Secret을 넣는 이름과 코드가 읽는 이름이 같다(어긋나면 기본 키가 조용히 사라진다)', () {
      final workflow = File('.github/workflows/deploy-web.yml').readAsStringSync();
      final code = File('lib/lookup/api_settings.dart').readAsStringSync();
      final defined = RegExp(r'flutter build web[^\n]*--dart-define=(\w+)="\$(\w+)"').firstMatch(workflow);
      expect(defined, isNotNull, reason: '빌드 줄에 --dart-define=NAME="\$ENV"가 있어야 한다');
      expect(code, contains("String.fromEnvironment('${defined!.group(1)}')"));
      expect(workflow, contains('${defined.group(2)}: \${{ secrets.DATA_GO_KR_KEY }}'));
    });
  });

  test('모르는 서비스 이름은 무시하고, 빠진 이름은 체크된 것으로 본다', () async {
    final c = await loaded(MemoryUpdateStore(jsonEncode({
      'version': 1,
      'services': {'ghs': false, 'future_service': false},
    })));
    expect(c.loadError, isNull);
    expect(c.enabledServices, [ChemService.chem, ChemService.safety]);
  });
}
