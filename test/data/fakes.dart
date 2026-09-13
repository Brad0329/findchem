/// 테스트 공용: 메모리 저장본 자리와 작은 가짜 원천자료(번들과 확실히 구별되는 1건).
library;

import 'package:findchem/data/update_store.dart';
import 'package:findchem/parser/models.dart';

class MemoryUpdateStore implements UpdateStore {
  MemoryUpdateStore([this.value]);

  /// 저장본 JSON(없으면 null).
  String? value;

  /// 설정하면 [write]가 이 예외를 던진다(저장 실패 흉내 — 용량 한도 등).
  Object? writeError;

  /// 설정하면 [delete]가 이 예외를 던진다(지우기 실패 흉내).
  Object? deleteError;

  @override
  Future<String?> read() async => value;

  @override
  Future<void> write(String json) async {
    if (writeError != null) throw writeError!;
    value = json;
  }

  @override
  Future<void> delete() async {
    if (deleteError != null) throw deleteError!;
    value = null;
  }
}

/// 번들에 없는 이름·CAS로 된 1건짜리 원천자료. 검색에 이것이 잡히면 저장본을 쓰고 있다는 뜻.
Dataset tinyDataset() => const Dataset(
  byeolpyo2: PdfInfo(file: 'new2.pdf', created: '2027-01-01T00:00:00+09:00', pages: 1),
  byeolpyo3: PdfInfo(file: 'new3.pdf', created: null, pages: 1),
  extractedAt: '2026-09-12T00:00:00Z',
  entries: [
    Entry(
      src: Source.byeolpyo2,
      no: 1,
      uid: '99-1-1',
      name: '테스트물질 [Testium]',
      ko: '테스트물질',
      en: 'Testium',
      cas: ['1111-11-1'],
      deleted: false,
      rows: [QuantityRow(kind: '급성', content: '1', min: '1', low: '2', high: '3')],
    ),
  ],
);
