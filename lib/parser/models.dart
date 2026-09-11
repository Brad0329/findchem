/// 데이터 모델 — 번들 JSON과 F-002 저장본이 같이 쓰는 형식. 설계 결정은 docs/SCHEMA.md.
///
/// 셀 값은 원문 문자열 그대로(`"0.2*"`, `"-"`, `"70% 초과"`) 둔다. 계산하지 않는다.
library;

/// 별표 식별자. 내부 값은 `별표2`/`별표3`, 화면 표시는 REQUIREMENTS 용어를 따른다.
enum Source {
  byeolpyo2('별표2', '인체·생태 유해성'),
  byeolpyo3('별표3', '사고대비물질');

  const Source(this.id, this.label);

  /// JSON `src` 값.
  final String id;

  /// 화면 표시 이름(REQUIREMENTS '용어').
  final String label;

  static Source fromId(String id) => values.firstWhere(
    (s) => s.id == id,
    orElse: () => throw FormatException('알 수 없는 src: $id'),
  );
}

/// 구분별 규정수량 한 행.
class QuantityRow {
  const QuantityRow({
    required this.kind,
    required this.content,
    required this.min,
    required this.low,
    required this.high,
  });

  /// 구분(급성/만성/생태/저확산/용액/`급성,생태`…). 별표3은 구분 열이 없어 첫 행은 빈 문자열,
  /// 둘째 행(42~44번 '용액')은 물질명 열의 원문(`염화수소 용액`)이다.
  final String kind;

  /// 함량기준(% 이상). 원문 그대로(`"5"`, `""`, `"70% 초과"`).
  final String content;

  /// 최하위·하위·상위 규정수량(톤). 원문 그대로.
  final String min;
  final String low;
  final String high;

  Map<String, Object?> toJson() => {
    'kind': kind,
    'content': content,
    'min': min,
    'low': low,
    'high': high,
  };

  factory QuantityRow.fromJson(Map<String, Object?> j) => QuantityRow(
    kind: j['kind'] as String,
    content: j['content'] as String,
    min: j['min'] as String,
    low: j['low'] as String,
    high: j['high'] as String,
  );

  @override
  bool operator ==(Object other) =>
      other is QuantityRow &&
      other.kind == kind &&
      other.content == content &&
      other.min == min &&
      other.low == low &&
      other.high == high;

  @override
  int get hashCode => Object.hash(kind, content, min, low, high);

  @override
  String toString() => 'QuantityRow($kind, $content, $min/$low/$high)';
}

/// 표의 한 항목. 키는 (src, no).
class Entry {
  const Entry({
    required this.src,
    required this.no,
    required this.uid,
    required this.name,
    required this.ko,
    required this.en,
    required this.cas,
    required this.deleted,
    required this.rows,
  });

  final Source src;

  /// 연번(별표2) / 번호(별표3).
  final int no;

  /// 고유번호. 별표3에는 없어 null.
  final String? uid;

  /// 원문 물질명 전체.
  final String name;

  /// 원문에서 분리한 국문명·영문명. 영문이 없으면 빈 문자열.
  final String ko;
  final String en;

  /// CAS 번호들. 없으면(`-`) 빈 목록.
  final List<String> cas;

  /// 별표2의 `(삭제)` 항목.
  final bool deleted;

  /// 구분별 규정수량. 1행 이상.
  final List<QuantityRow> rows;

  Map<String, Object?> toJson() => {
    'src': src.id,
    'no': no,
    'uid': uid,
    'name': name,
    'ko': ko,
    'en': en,
    'cas': cas,
    'deleted': deleted,
    'rows': rows.map((r) => r.toJson()).toList(),
  };

  factory Entry.fromJson(Map<String, Object?> j) => Entry(
    src: Source.fromId(j['src'] as String),
    no: j['no'] as int,
    uid: j['uid'] as String?,
    name: j['name'] as String,
    ko: j['ko'] as String,
    en: j['en'] as String,
    cas: (j['cas'] as List).cast<String>(),
    deleted: j['deleted'] as bool,
    rows: (j['rows'] as List)
        .map((r) => QuantityRow.fromJson((r as Map).cast<String, Object?>()))
        .toList(),
  );

  @override
  String toString() => 'Entry(${src.id} $no $name)';
}

/// 원본 PDF 하나의 정보(파일 머리 `source`에 들어간다).
class PdfInfo {
  const PdfInfo({required this.file, required this.created, required this.pages});

  /// 원본 PDF 파일명.
  final String file;

  /// PDF 메타데이터 생성일(ISO 8601). 없으면 null.
  final String? created;

  final int pages;

  Map<String, Object?> toJson() => {'file': file, 'created': created, 'pages': pages};

  factory PdfInfo.fromJson(Map<String, Object?> j) => PdfInfo(
    file: j['file'] as String,
    created: j['created'] as String?,
    pages: j['pages'] as int,
  );
}

/// 번들 JSON / 저장본 파일 전체.
class Dataset {
  const Dataset({
    required this.byeolpyo2,
    required this.byeolpyo3,
    required this.extractedAt,
    required this.entries,
  });

  final PdfInfo byeolpyo2;
  final PdfInfo byeolpyo3;

  /// 추출 시각(ISO 8601).
  final String extractedAt;

  /// 두 별표의 항목을 한 배열에 나란히(별표2 다음 별표3). 병합하지 않는다(SCHEMA.md).
  final List<Entry> entries;

  int count(Source src) => entries.where((e) => e.src == src).length;

  Map<String, Object?> toJson() => {
    'source': {
      'byeolpyo2': byeolpyo2.toJson(),
      'byeolpyo3': byeolpyo3.toJson(),
      'extractedAt': extractedAt,
    },
    'entries': entries.map((e) => e.toJson()).toList(),
  };

  factory Dataset.fromJson(Map<String, Object?> j) {
    final source = (j['source'] as Map).cast<String, Object?>();
    return Dataset(
      byeolpyo2: PdfInfo.fromJson((source['byeolpyo2'] as Map).cast<String, Object?>()),
      byeolpyo3: PdfInfo.fromJson((source['byeolpyo3'] as Map).cast<String, Object?>()),
      extractedAt: source['extractedAt'] as String,
      entries: (j['entries'] as List)
          .map((e) => Entry.fromJson((e as Map).cast<String, Object?>()))
          .toList(),
    );
  }
}
