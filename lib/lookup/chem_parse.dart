/// F-007 공공데이터 API 3종의 주소·응답 해석 — **Flutter를 import하지 않는다**.
///
/// `chem_api.dart`(Flutter)에서 옮겼다(A-010 — 6호 상수 수집 스크립트가 `dart run`으로 같은 해석을 쓴다. A-003 Q1과 같은 이유).
/// `chem_api.dart`가 다시 내보내므로 쓰는 쪽은 그대로다(F-007 동작 불변 — 기존 테스트가 지킨다).
library;

import 'dart:convert';

import 'package:xml/xml.dart';

import 'portal.dart';

/// 한 번에 받는 건수. 넘으면 '더 있음'을 보인다(조용한 절단 금지).
const pageRows = 10;

const chemEndpoint = 'https://apis.data.go.kr/B552584/kecoapi/ncissbstn/chemSbstnList';
const ghsEndpoint = 'https://apis.data.go.kr/B552584/kecoapi/ncisghs/ghsList';
const safetyEndpoint = 'https://apis.data.go.kr/1480802/iciskischem/kischemlist';

/// 포털 키 → 쿼리 값. '인코딩 키'(%가 들어 있음)를 다시 인코딩하면 인증 실패가 난다(probe_chem_api.py 선례). 둘은 같은 주소가 된다.
String portalKeyParam(String key) => key.contains('%') ? key : Uri.encodeQueryComponent(key);

/// chem·ghs 공통 쿼리(CAS 검색, JSON).
String casJsonQuery(String cas) =>
    'pageNo=1&numOfRows=$pageRows&searchGubun=2&searchNm=${Uri.encodeQueryComponent(cas)}&returnType=JSON';

// ───── 응답 모델 ─────

class ChemType {
  const ChemType({
    required this.name,
    required this.unqNo,
    required this.content,
    required this.exception,
    required this.date,
    required this.notice,
  });

  final String name, unqNo, content, exception, date, notice;
}

class ChemRecord {
  const ChemRecord({
    required this.ko,
    required this.en,
    required this.otherKo,
    required this.otherEn,
    required this.formula,
    required this.weight,
    required this.existingNo,
    required this.types,
  });

  final String ko, en, otherKo, otherEn, formula, weight, existingNo;
  final List<ChemType> types;
}

class GhsHazard {
  const GhsHazard({required this.item, required this.grade, required this.hCode, required this.pCodes});

  final String item, grade, hCode;
  final List<String> pCodes;
}

class GhsRecord {
  const GhsRecord({
    this.casNo = '',
    required this.signal,
    required this.pictograms,
    required this.unNumbers,
    required this.mFactor,
    required this.classNumbers,
    required this.hazards,
  });

  /// 응답의 `casNo` — 검색이 완전 일치만 주는지 확인할 수 없어 받는 쪽이 대조한다(A-010).
  final String casNo;
  final String signal, mFactor;
  final List<String> pictograms, unNumbers;

  /// `분류: 번호` 형태(`기존화학물질: V`).
  final List<String> classNumbers;
  final List<GhsHazard> hazards;
}

class SafetyRecord {
  const SafetyRecord(this.items);

  /// (항목 이름, `·` 문장 목록) — 일반증상·흡입·피부·안구·경구·기타 순. 문장은 원문 그대로(중복·'자료없음' 포함).
  final List<(String, List<String>)> items;
}

const safetyFields = [
  ('symptom', '일반증상'),
  ('inhale', '흡입'),
  ('skin', '피부'),
  ('eyeball', '안구'),
  ('oral', '경구'),
  ('etc', '기타'),
];

sealed class ServiceResult {
  const ServiceResult();
}

final class ServiceOk extends ServiceResult {
  const ServiceOk(this.records, this.total);

  /// [ChemRecord] / [GhsRecord] / [SafetyRecord].
  final List<Object> records;

  /// 응답의 totalCount.
  final int total;

  bool get truncated => total > records.length;
}

final class ServiceFailed extends ServiceResult {
  const ServiceFailed(this.message);

  final String message;
}

// ───── 해석 ─────

String _str(Map<Object?, Object?> m, String k) => (m[k] ?? '').toString().trim();

List<String> _caret(String v) => [
  for (final p in v.split('^'))
    if (p.trim().isNotEmpty) p.trim(),
];

/// JSON 응답(chem·ghs) 공통: 머리 결과 코드 확인, items·totalCount 꺼내기.
ServiceResult _parseJson(String body, Object Function(Map<Object?, Object?>) item) {
  final root = jsonDecode(body);
  if (root is! Map) throw const FormatException('응답이 객체가 아니다');
  final code = (root['header'] is Map) ? _str(root['header'] as Map, 'resultCode') : '';
  if (code != '200' && code != '00') return ServiceFailed(LookupText.failed(code.isEmpty ? '없음' : code));
  final b = root['body'];
  final raw = b is Map ? b['items'] : null;
  final items = raw is List ? raw.whereType<Map<Object?, Object?>>().toList() : const <Map<Object?, Object?>>[];
  final total = b is Map ? int.tryParse('${b['totalCount']}') : null;
  final records = [for (final m in items) item(m)];
  return ServiceOk(records, total ?? records.length);
}

ServiceResult parseChemResponse(String body) => _parseJson(body, (m) {
  final types = m['typeList'] is List ? (m['typeList'] as List).whereType<Map<Object?, Object?>>() : const <Map>[];
  return ChemRecord(
    ko: _str(m, 'sbstnNmKor'),
    en: _str(m, 'sbstnNmEng'),
    otherKo: _str(m, 'sbstnNm2Kor'),
    otherEn: _str(m, 'sbstnNm2Eng'),
    formula: _str(m, 'mlcfrm'),
    weight: _str(m, 'mlcwgt'),
    existingNo: _str(m, 'korexst'),
    types: [
      for (final t in types)
        ChemType(
          name: _str(t, 'sbstnClsfTypeNm'),
          unqNo: _str(t, 'unqNo'),
          content: _str(t, 'contInfo'),
          exception: _str(t, 'excpInfo'),
          date: _str(t, 'ancmntYmd'),
          notice: _str(t, 'ancmntInfo'),
        ),
    ],
  );
});

ServiceResult parseGhsResponse(String body) => _parseJson(body, (m) {
  final list = m['hrmflnList'] is List ? (m['hrmflnList'] as List).whereType<Map<Object?, Object?>>() : const <Map>[];
  return GhsRecord(
    casNo: _str(m, 'casNo'),
    signal: _str(m, 'sfsgwd'),
    pictograms: _caret(_str(m, 'pctgrmCd')),
    unNumbers: _caret(_str(m, 'unnm')),
    mFactor: _str(m, 'mfctrCn'),
    classNumbers: [
      for (final p in _caret(_str(m, 'sbstnTypeUnqno')))
        p.contains(':') ? '${p.substring(0, p.indexOf(':')).trim()}: ${p.substring(p.indexOf(':') + 1).trim()}' : p,
    ],
    hazards: [
      for (final h in list)
        GhsHazard(
          item: _str(h, 'hrmflnClsfArtclNm'),
          grade: _str(h, 'clsfGrd'),
          hCode: _str(h, 'hrmDngrCd'),
          pCodes: _caret(_str(h, 'hrmPrevntCd')),
        ),
    ],
  );
});

ServiceResult parseSafetyResponse(String body) {
  final doc = XmlDocument.parse(body);
  String first(XmlNode n, String tag) {
    final found = n.findAllElements(tag);
    return found.isEmpty ? '' : found.first.innerText.trim();
  }

  final code = first(doc, 'resultCode');
  if (code != '00') return ServiceFailed(LookupText.failed(code.isEmpty ? '없음' : code));
  final records = <SafetyRecord>[
    for (final item in doc.findAllElements('item'))
      SafetyRecord([
        for (final (tag, label) in safetyFields)
          (
            label,
            [
              for (final line in (item.getElement(tag)?.innerText ?? '').split('\n'))
                if (line.trim().isNotEmpty) line.trim(),
            ],
          ),
      ]),
  ];
  return ServiceOk(records, int.tryParse(first(doc, 'totalCount')) ?? records.length);
}
