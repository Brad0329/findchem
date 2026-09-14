/// F-007 공공데이터 API 3종 호출 — 주소 만들기, 응답 해석, 실패 문구(REQUIREMENTS F-007).
///
/// 명세·실측 근거: plan.md 보류 항목 '외부 원천 조사'(2026-09-14), 실호출 도구 `scripts/probe_chem_api.py`.
/// 화면 오류에는 상태만 쓰고, 원문 응답은 로그에만 — 키는 로그에서도 가린다(보안 3층 ①).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'api_settings.dart';

/// 화면 문구(테스트가 같은 상수를 본다).
abstract final class LookupText {
  static const badKey = '키가 올바르지 않습니다';
  static const notApproved = '이 서비스의 활용신청이 승인되지 않았습니다';
  static const overLimit = '오늘 호출 한도를 넘었습니다';
  static const offline = '접속하지 못했습니다';
  static String failed(String code) => '조회하지 못했습니다 (코드 $code)';

  static const noKey = '설정 → data.go.kr API 키에서 키를 넣으세요';
  static const noService = '설정 → 연동 데이터에서 조회할 정보를 고르세요';
  static const settingsUnreadable = '설정을 읽지 못했습니다';

  static const loading = '조회 중…';
  static const noResult = '조회 결과 없음';
  static String title(String cas) => 'CAS $cas 공공데이터 조회';
  static String truncated(int total, int shown) => '$total건 중 $shown건 표시 · 더 있음';
}

/// [키 인증]에 쓰는 CAS(세 서비스 모두 결과가 있는 포르말린).
const verifyCas = '50-00-0';

/// 한 번에 받는 건수. 넘으면 '더 있음'을 보인다(조용한 절단 금지).
const pageRows = 10;

String endpointOf(ChemService s) => switch (s) {
  ChemService.chem => 'https://apis.data.go.kr/B552584/kecoapi/ncissbstn/chemSbstnList',
  ChemService.ghs => 'https://apis.data.go.kr/B552584/kecoapi/ncisghs/ghsList',
  ChemService.safety => 'https://apis.data.go.kr/1480802/iciskischem/kischemlist',
};

/// 요청 주소. 포털 키는 '인코딩 키'(%가 들어 있음)와 '디코딩 키' 두 가지다 — 인코딩 키를 다시 인코딩하면 인증 실패가 난다
/// (probe_chem_api.py 선례). 둘은 같은 주소가 된다.
Uri buildRequestUri(ChemService s, String key, String cas) {
  final k = key.contains('%') ? key : Uri.encodeQueryComponent(key);
  final c = Uri.encodeQueryComponent(cas);
  final query = switch (s) {
    // 안전관리정보는 CAS로만 찾고 결과 형식 파라미터가 없다(XML 전용)
    ChemService.safety => 'pageNo=1&numOfRows=$pageRows&casNo=$c',
    _ => 'pageNo=1&numOfRows=$pageRows&searchGubun=2&searchNm=$c&returnType=JSON',
  };
  return Uri.parse('${endpointOf(s)}?serviceKey=$k&$query');
}

/// [text]에서 키(넣은 형태와 인코딩/디코딩한 형태 둘 다)를 `<KEY>`로 바꾼다.
String maskKey(String text, String key) {
  if (key.isEmpty) return text;
  var out = text.replaceAll(key, '<KEY>');
  String? other;
  try {
    other = key.contains('%') ? Uri.decodeQueryComponent(key) : Uri.encodeQueryComponent(key);
  } on ArgumentError catch (e) {
    // 잘못된 % 표기라 다른 형태가 없다 — 넣은 형태만 가린다(키 자체는 로그에 쓰지 않는다)
    debugPrint('F-007 키의 다른 표기를 만들지 못해 원형만 가림: ${e.runtimeType}');
  }
  if (other != null && other.isNotEmpty && other != key) out = out.replaceAll(other, '<KEY>');
  // Uri는 %xx를 대문자로 바꿔 적는다 — 소문자로 넣은 인코딩 키가 요청 주소(접속 오류 문구)에서 새지 않게
  final upper = key.replaceAllMapped(RegExp('%[0-9a-fA-F]{2}'), (m) => m[0]!.toUpperCase());
  if (upper != key) out = out.replaceAll(upper, '<KEY>');
  return out;
}

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
    required this.signal,
    required this.pictograms,
    required this.unNumbers,
    required this.mFactor,
    required this.classNumbers,
    required this.hazards,
  });

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

/// 포털 공통 오류(키 미등록·한도 초과 등)의 사유 코드. HTTP 200으로도 온다. 없으면 null.
String? portalReasonCode(String body) =>
    RegExp(r'returnReasonCode\W+(\d+)').firstMatch(body)?.group(1);

/// 실패 판정(REQUIREMENTS F-007 '실패 문구').
String failureMessage(int status, String? portalCode) {
  if (status == 401) return LookupText.badKey;
  if (status == 403 || portalCode == '30') return LookupText.notApproved;
  if (portalCode == '22') return LookupText.overLimit;
  return LookupText.failed(portalCode ?? '$status');
}

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

// ───── 호출 ─────

class ChemApiClient {
  ChemApiClient({http.Client? httpClient, this.timeout = const Duration(seconds: 20)})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Duration timeout;

  /// 서비스 하나를 CAS로 부른다. **예외를 던지지 않는다** — 실패는 [ServiceFailed]로(원인은 로그에).
  Future<ServiceResult> fetch(ChemService service, String key, String cas) async {
    void log(String what) => debugPrint('F-007 ${service.name} 조회 실패: ${maskKey(what, key)}');

    final http.Response res;
    try {
      res = await _http.get(buildRequestUri(service, key, cas)).timeout(timeout);
    } on TimeoutException {
      log('시간 초과 ${timeout.inSeconds}초');
      return const ServiceFailed(LookupText.offline);
    } catch (e) {
      // 접속 실패(웹 CORS 거부도 여기로 온다 — 브라우저가 사유를 알려 주지 않는다)
      log('접속 실패: $e');
      return const ServiceFailed(LookupText.offline);
    }

    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    final portal = portalReasonCode(body);
    if (res.statusCode != 200 || portal != null) {
      log('HTTP ${res.statusCode}, 포털 코드 $portal, 본문 앞부분: ${body.length > 300 ? body.substring(0, 300) : body}');
      return ServiceFailed(failureMessage(res.statusCode, portal));
    }
    try {
      final result = switch (service) {
        ChemService.chem => parseChemResponse(body),
        ChemService.ghs => parseGhsResponse(body),
        ChemService.safety => parseSafetyResponse(body),
      };
      if (result is ServiceFailed) log('결과 코드 실패: ${result.message}');
      return result;
    } catch (e) {
      log('응답 해석 실패: ${e.runtimeType}: $e');
      return ServiceFailed(LookupText.failed('응답 형식'));
    }
  }
}

// ───── CAS 누르기 → 조회 시작 ─────

sealed class LookupStart {
  const LookupStart();
}

/// 부르지 않았다(키 없음·체크 0개·설정 파일 깨짐) — 결과 영역에 [message].
final class LookupBlocked extends LookupStart {
  const LookupBlocked(this.message);

  final String message;
}

/// 체크한 서비스만 동시에 부른 중. 순서는 [ChemService] 선언 순서.
final class LookupRunning extends LookupStart {
  const LookupRunning(this.calls);

  final Map<ChemService, Future<ServiceResult>> calls;
}

Future<LookupStart> startLookup(ApiSettingsController settings, ChemApiClient client, String cas) async {
  await settings.load();
  if (settings.loadError != null) return const LookupBlocked(LookupText.settingsUnreadable);
  final key = settings.serviceKey;
  if (key == null || key.isEmpty) return const LookupBlocked(LookupText.noKey);
  final services = settings.enabledServices;
  if (services.isEmpty) return const LookupBlocked(LookupText.noService);
  return LookupRunning({for (final s in services) s: client.fetch(s, key, cas)});
}
