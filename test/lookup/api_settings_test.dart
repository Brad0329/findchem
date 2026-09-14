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

  test('모르는 서비스 이름은 무시하고, 빠진 이름은 체크된 것으로 본다', () async {
    final c = await loaded(MemoryUpdateStore(jsonEncode({
      'version': 1,
      'services': {'ghs': false, 'future_service': false},
    })));
    expect(c.loadError, isNull);
    expect(c.enabledServices, [ChemService.chem, ChemService.safety]);
  });
}
