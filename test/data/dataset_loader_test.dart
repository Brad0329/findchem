/// 데이터 로딩 경로(저장본 우선, 없으면 번들)와 저장본 자리 — F-002 적용·되돌리기의 바탕.
library;

import 'dart:convert';
import 'dart:io';

import 'package:findchem/data/dataset_loader.dart';
import 'package:findchem/data/update_store_io.dart';
import 'package:findchem/parser/models.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  late Dataset bundled;

  setUpAll(() {
    bundled = Dataset.fromJson(
      (jsonDecode(File('assets/data/findchem_data.json').readAsStringSync()) as Map).cast<String, Object?>(),
    );
  });

  Future<Dataset> loadBundled() async => bundled;

  test('저장본이 없으면 번들', () async {
    final d = await loadDataset(store: MemoryUpdateStore(), loadBundled: loadBundled);
    expect(d.origin, DataOrigin.bundled);
    expect(d.dataset.entries.length, 1657);
    expect(d.storedError, isNull);
    expect(d.hasStored, isFalse);
  });

  test('저장본이 있으면 저장본을 쓴다', () async {
    final store = MemoryUpdateStore(jsonEncode(tinyDataset().toJson()));
    final d = await loadDataset(store: store, loadBundled: loadBundled);
    expect(d.origin, DataOrigin.updated);
    expect(d.dataset.entries.single.ko, '테스트물질');
    expect(d.dataset.byeolpyo2.created, '2027-01-01T00:00:00+09:00');
  });

  test('저장본이 깨졌으면 번들로 떨어지고 사유를 남긴다(저장본은 지우지 않는다)', () async {
    final store = MemoryUpdateStore('{"source": 1');
    final d = await loadDataset(store: store, loadBundled: loadBundled);
    expect(d.origin, DataOrigin.bundled);
    expect(d.dataset.entries.length, 1657);
    expect(d.storedError, startsWith('저장된 update 원천자료를 읽지 못해'));
    expect(d.storedError, isNot(contains('FormatException')), reason: '원인은 로그에만');
    expect(d.hasStored, isTrue, reason: '깨진 저장본도 되돌리기로 지울 대상');
    expect(store.value, '{"source": 1');
  });

  test('DataController: 되돌리기 중 번들을 못 읽으면 저장본을 지우지 않는다', () async {
    final before = jsonEncode(tinyDataset().toJson());
    final store = MemoryUpdateStore(before);
    final c = DataController(store: store, loadBundled: () async => throw StateError('번들 없음'));
    await c.load(); // 저장본으로 시작 — 이때는 번들을 읽지 않는다
    await expectLater(c.reset(), throwsA(isA<StateError>()));
    expect(store.value, before);
    expect(c.data!.origin, DataOrigin.updated);
  });

  test('DataController: apply → 저장본을 쓰고 알린다, reset → 지우고 번들로', () async {
    final store = MemoryUpdateStore();
    final c = DataController(store: store, loadBundled: loadBundled);
    var notified = 0;
    c.addListener(() => notified++);
    await c.load();
    expect(c.data!.origin, DataOrigin.bundled);

    await c.apply(tinyDataset());
    expect(c.data!.origin, DataOrigin.updated);
    expect(c.data!.dataset.entries.single.ko, '테스트물질');
    final stored = Dataset.fromJson((jsonDecode(store.value!) as Map).cast<String, Object?>());
    expect(jsonEncode(stored.toJson()), jsonEncode(tinyDataset().toJson()), reason: '저장본 = 번들과 같은 형식');

    await c.reset();
    expect(store.value, isNull);
    expect(c.data!.origin, DataOrigin.bundled);
    expect(c.data!.dataset.entries.length, 1657);
    expect(notified, 3);
  });

  test('DataController: 저장이 실패하면 예외, 현재 데이터와 저장본은 그대로', () async {
    final before = jsonEncode(tinyDataset().toJson());
    final store = MemoryUpdateStore(before)..writeError = const FileSystemException('용량 부족');
    final c = DataController(store: store, loadBundled: loadBundled);
    await c.load();
    await expectLater(c.apply(bundled), throwsA(isA<FileSystemException>()));
    expect(c.data!.origin, DataOrigin.updated);
    expect(c.data!.dataset.entries.single.ko, '테스트물질');
    expect(store.value, before);
  });

  test('FileUpdateStore(Android 쪽): 쓰기·읽기·덮어쓰기·지우기, 임시 파일이 남지 않는다', () async {
    final dir = Directory.systemTemp.createTempSync('findchem_store_');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = FileUpdateStore(directory: dir);

    expect(await store.read(), isNull);
    await store.delete(); // 없어도 예외 없음
    await store.write('{"a":1}');
    await store.write('{"b":2}');
    expect(await store.read(), '{"b":2}');
    expect(dir.listSync().map((e) => e.uri.pathSegments.last), [FileUpdateStore.fileName]);
    await store.delete();
    expect(await store.read(), isNull);
    expect(dir.listSync(), isEmpty);
  });
}
