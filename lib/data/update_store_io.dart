/// 저장본 — Android(및 VM): 앱 전용 저장소의 파일 하나. 다른 앱은 읽지 못하고, 앱을 지우면 함께 지워진다.
library;

import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'update_store.dart';

UpdateStore createUpdateStore() => FileUpdateStore();

UpdateStore createFavoritesStore() => FileUpdateStore(name: FileUpdateStore.favoritesFileName);

class FileUpdateStore implements UpdateStore {
  /// [directory]를 주지 않으면 앱 지원 디렉토리(Android: 앱 내부 저장소 files/)를 쓴다.
  FileUpdateStore({Directory? directory, this.name = fileName}) : _directory = directory;

  /// F-002 저장본.
  static const fileName = 'findchem_update.json';

  /// F-005 자주보는 Chem 목록.
  static const favoritesFileName = 'findchem_favorites.json';

  final Directory? _directory;

  /// 이 저장소의 파일 이름.
  final String name;

  Future<File> _file() async {
    final dir = _directory ?? await getApplicationSupportDirectory();
    return File('${dir.path}${Platform.pathSeparator}$name');
  }

  @override
  Future<String?> read() async {
    final f = await _file();
    return await f.exists() ? f.readAsString() : null;
  }

  @override
  Future<void> write(String json) async {
    // 임시 파일에 다 쓴 뒤 이름을 바꾼다 — 쓰다 멈춰도 기존 저장본이 반쯤 덮이지 않는다.
    final f = await _file();
    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(f.path);
  }

  @override
  Future<void> delete() async {
    final f = await _file();
    if (await f.exists()) await f.delete();
  }
}
