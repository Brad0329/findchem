/// KOSHA MSDS 조회 — CAS 하나 → 목록 → 상세 2·8·9절 → 도구 응답(A-003 2차, REQUIREMENTS_AGENT A-003).
///
/// 서비스: data.go.kr 15157612 `https://apis.data.go.kr/B552468/msdschem1`(XML 전용). 응답 원문은 `test/fixtures/msds/`(2026-10-02 녹화).
/// - 호출: `getChemList001`(searchCnd=1) → `casNo` **완전 일치** → `getChemDetail021`·`081`·`091`. 상세는 쪽 정보가 없다(녹화 확인).
/// - **예외를 던지지 않는다** — 실패는 [MsdsStatus.failed]·필드별 `fetch_failed`로 돌려주고 원인은 [MsdsLog]에(키는 가린다).
/// - 판정·환산·노출기준 고르기는 하지 않는다(A-004·스킬). 원문은 항목 전부 [MsdsSection.items]에.
///
/// **Flutter를 import하지 않는다**(Q1) — 원격 MCP 서버(순수 Dart)가 같이 쓴다.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../lookup/portal.dart';
import '../parser/cas.dart';
import 'msds_value.dart';

const msdsProvider = '15157612';
const msdsEndpoint = 'https://apis.data.go.kr/B552468/msdschem1';

/// 목록 한 쪽 크기와 최대 쪽 수 — 넘으면 자르지 않고 실패로 돌려준다(조용한 절단 금지).
const msdsListPageSize = 100;
const msdsListMaxPages = 10;

/// 정상 결과 코드(2026-10-02 녹화: `<resultCode>00</resultCode><resultMsg>NORMAL SERVICE.</resultMsg>`).
const msdsOkCode = '00';

/// 부르는 상세 절과 서비스 이름.
const msdsSections = {'02': 'getChemDetail021', '08': 'getChemDetail081', '09': 'getChemDetail091'};

/// 요청 주소. 디코딩 키는 인코딩하고 인코딩 키(`%` 포함)는 그대로 — 둘이 같은 주소가 된다.
/// 녹화 스크립트(`scripts/record_msds.dart`)도 이것을 쓴다.
Uri msdsRequestUri(String key, String service, String query) {
  final k = key.contains('%') ? key : Uri.encodeQueryComponent(key);
  return Uri.parse('$msdsEndpoint/$service?serviceKey=$k&$query');
}

/// 해석하는 항목 코드(2026-10-02 녹화 8물질에서 확인).
abstract final class MsdsCode {
  static const pictograms = 'B0402'; // 그림문자
  static const hazardStatements = 'B0406'; // 유해·위험문구
  static const exposureParent = 'H02'; // 노출기준(하위: 국내규정·ACGIH·생물학적·기타)
  static const appearance = 'I0202'; // 성상
  static const explosionLimits = 'I20'; // 인화 또는 폭발 범위의 상한/하한
  static const vaporPressure = 'I22'; // 증기압
  static const specificGravity = 'I28'; // 비중
}

enum MsdsStatus { found, notFound, ambiguous, failed }

/// 목록의 한 행(완전 일치 후보).
class MsdsCandidate {
  const MsdsCandidate({required this.chemId, required this.casNo, required this.nameKor, required this.lastDate});

  final String chemId, casNo, nameKor, lastDate;

  Map<String, Object?> toJson() => {'chemId': chemId, 'casNo': casNo, 'nameKor': nameKor, 'lastDate': lastDate};
}

/// 상세 항목 하나 — 원문 그대로. [detail]이 null이면 응답에 `itemDetail`이 없는 머리 항목이다.
class MsdsItem {
  const MsdsItem({
    required this.code,
    required this.parentCode,
    required this.level,
    required this.nameKor,
    required this.detail,
    required this.order,
  });

  final String code, parentCode, level, nameKor;
  final String? detail;

  /// 원문 `ordrIdx`(KOSHA 전체 항목 순서).
  final String? order;

  Map<String, Object?> toJson() => {
    'code': code,
    'parentCode': parentCode,
    'level': level,
    'nameKor': nameKor,
    'detail': detail,
    'order': order,
  };
}

/// 상세 한 절. 실패하면 [items]가 비고 [error]에 화면 문구.
class MsdsSection {
  const MsdsSection.ok(this.items) : error = null;
  const MsdsSection.failed(String this.error) : items = const [];

  final List<MsdsItem> items;
  final String? error;
  bool get ok => error == null;

  MsdsItem? item(String code) => items.where((i) => i.code == code).firstOrNull;

  Map<String, Object?> toJson() => {'ok': ok, 'error': error, 'items': [for (final i in items) i.toJson()]};
}

/// 도구 응답.
class MsdsResult {
  MsdsResult._({
    required this.status,
    this.message,
    this.source,
    this.candidates = const [],
    this.droppedPartialMatches = 0,
    this.sections = const {},
  });

  final MsdsStatus status;

  /// 실패·없음의 사유(화면 문구).
  final String? message;

  /// provider·endpoint·chemId·casNo·nameKor·lastDate(원문)·retrievedAt.
  final Map<String, String>? source;

  /// ambiguous일 때, 그리고 준 chemId가 후보에 없어 failed일 때 후보.
  final List<MsdsCandidate> candidates;

  /// 목록에서 버린 부분 일치 행 수(`50-00-0` 검색에 섞여 온 `13150-00-0` 등).
  final int droppedPartialMatches;

  /// `02`·`08`·`09` → 절.
  final Map<String, MsdsSection> sections;

  // ───── 해석 필드(found일 때만 의미가 있다) ─────

  /// 항목 원문, 또는 원문이 없는 이유(절 실패 → fetch_failed, 코드 없음 → item_missing).
  (String?, MsdsValue?) _raw(String sec, String code) {
    final s = sections[sec];
    if (s == null || !s.ok) return (null, _status(ValueStatus.fetchFailed, s?.error ?? '절을 부르지 않음'));
    final item = s.item(code);
    if (item == null) return (null, _status(ValueStatus.itemMissing, '항목 코드 $code 없음'));
    return (item.detail ?? '', null);
  }

  MsdsValue _field(String sec, String code, MsdsValue Function(String raw) parse) {
    final (raw, why) = _raw(sec, code);
    return why ?? parse(raw!);
  }

  static MsdsValue _status(ValueStatus st, String why) =>
      MsdsValue(raw: '', text: '', origin: null, status: st, parseError: why);

  MsdsValue specificGravity({MsdsLog? log}) => _field('09', MsdsCode.specificGravity, (r) => parseNumberValue(r, log: log));
  MsdsValue vaporPressure({MsdsLog? log}) => _field('09', MsdsCode.vaporPressure, (r) => parseNumberValue(r, log: log));
  MsdsValue appearance() => _field('09', MsdsCode.appearance, parseTextValue);

  ExplosionLimits explosionLimits({MsdsLog? log}) {
    final (raw, why) = _raw('09', MsdsCode.explosionLimits);
    return why != null ? ExplosionLimits(upper: why, lower: why) : parseExplosionLimits(raw!, log: log);
  }

  /// 8절 노출기준 하위 항목 전부(국내규정·ACGIH·생물학적·기타) — 하나를 고르지 않는다.
  List<MsdsItem> exposureLimits() => [
    for (final i in sections['08']?.items ?? const <MsdsItem>[])
      if (i.parentCode == MsdsCode.exposureParent) i,
  ];

  /// 노출기준의 상태 — 절 실패 fetch_failed / 하위 항목이 하나도 없으면 item_missing(기준 없음과 구분) / 그 밖 value.
  ValueStatus exposureStatus() {
    if (sections['08']?.ok != true) return ValueStatus.fetchFailed;
    return exposureLimits().isEmpty ? ValueStatus.itemMissing : ValueStatus.value;
  }

  MsdsValue hazardStatementsRaw() => _field('02', MsdsCode.hazardStatements, parseTextValue);
  MsdsValue pictogramsRaw() => _field('02', MsdsCode.pictograms, parseTextValue);

  List<HazardStatement> hazardStatements({MsdsLog? log}) {
    final v = hazardStatementsRaw();
    return v.status == ValueStatus.value ? parseHazardStatements(v.raw, log: log) : const [];
  }

  List<Pictogram> pictograms({MsdsLog? log}) {
    final v = pictogramsRaw();
    return v.status == ValueStatus.value ? parsePictograms(v.raw, log: log) : const [];
  }

  /// 도구가 돌려주는 JSON — 원문 그대로의 값·출처와 판본·적용 조건·없다는 사실.
  Map<String, Object?> toJson({MsdsLog? log}) => {
    'status': status.name,
    'message': message,
    'source': source,
    'droppedPartialMatches': droppedPartialMatches,
    if (candidates.isNotEmpty) 'candidates': [for (final c in candidates) c.toJson()],
    if (status == MsdsStatus.found) ...{
      'fields': {
        'appearance': appearance().toJson(),
        'specificGravity': specificGravity(log: log).toJson(),
        'vaporPressure': vaporPressure(log: log).toJson(),
        'explosionLimits': explosionLimits(log: log).toJson(),
        'hazardStatements': {
          ...hazardStatementsRaw().toJson(),
          'list': [for (final h in hazardStatements(log: log)) h.toJson()],
        },
        'pictograms': {
          ...pictogramsRaw().toJson(),
          'list': [for (final p in pictograms(log: log)) p.toJson()],
        },
        'exposureLimits': {
          'status': exposureStatus().name,
          'error': sections['08']?.error,
          'items': [for (final i in exposureLimits()) i.toJson()],
        },
      },
      'sections': {for (final e in sections.entries) e.key: e.value.toJson()},
    },
  };
}

/// 실패 하나(내부용) — 화면 문구.
class _Fail implements Exception {
  const _Fail(this.message);

  final String message;
}

class MsdsClient {
  MsdsClient({
    required http.Client httpClient,
    required String key,
    DateTime Function()? clock,
    MsdsLog? log,
    this.timeout = const Duration(seconds: 20),
  }) : _http = httpClient,
       _key = key.trim(),
       _clock = clock ?? DateTime.now,
       _log = log;

  final http.Client _http;
  final String _key;
  final DateTime Function() _clock;
  final MsdsLog? _log;
  final Duration timeout;

  void _warn(String m) => _log?.call(maskKey('A-003 MSDS $m', _key, onWarn: (w) => _log.call('A-003 MSDS $w')));

  Uri requestUri(String service, String query) => msdsRequestUri(_key, service, query);

  /// CAS 하나를 조회한다. 완전 일치가 여럿이면 [chemId]로 고른다.
  Future<MsdsResult> lookup(String cas, {String? chemId}) async {
    final c = cas.trim();
    if (_key.isEmpty) {
      _warn('호출 안 함: 키 없음');
      return MsdsResult._(status: MsdsStatus.failed, message: 'data.go.kr API 키가 없습니다');
    }
    if (!casPattern.hasMatch(c)) {
      _warn('호출 안 함: CAS 형식 아님 "$c"');
      return MsdsResult._(status: MsdsStatus.failed, message: 'CAS 형식이 아닙니다: $c');
    }

    final List<MsdsCandidate> exact;
    final int dropped;
    try {
      (exact, dropped) = await _list(c);
    } on _Fail catch (f) {
      return MsdsResult._(status: MsdsStatus.failed, message: f.message);
    }

    if (exact.isEmpty) {
      return MsdsResult._(
        status: MsdsStatus.notFound,
        message: LookupText.noResult,
        droppedPartialMatches: dropped,
      );
    }
    final MsdsCandidate pick;
    if (chemId != null) {
      final hit = exact.where((e) => e.chemId == chemId.trim()).firstOrNull;
      if (hit == null) {
        _warn('chemId $chemId는 CAS $c의 완전 일치 후보(${exact.map((e) => e.chemId).join(',')})가 아님');
        return MsdsResult._(
          status: MsdsStatus.failed,
          message: 'chemId $chemId는 CAS $c의 후보가 아닙니다',
          candidates: exact,
          droppedPartialMatches: dropped,
        );
      }
      pick = hit;
    } else if (exact.length > 1) {
      return MsdsResult._(
        status: MsdsStatus.ambiguous,
        message: 'CAS $c에 MSDS가 ${exact.length}건 있습니다 — chemId로 고르세요',
        candidates: exact,
        droppedPartialMatches: dropped,
      );
    } else {
      pick = exact.single;
    }

    final sections = <String, MsdsSection>{};
    for (final e in msdsSections.entries) {
      try {
        final doc = await _get(e.value, 'chemId=${Uri.encodeQueryComponent(pick.chemId)}');
        sections[e.key] = MsdsSection.ok([
          for (final it in doc.findAllElements('item'))
            MsdsItem(
              code: _text(it, 'msdsItemCode') ?? '',
              parentCode: _text(it, 'upMsdsItemCode') ?? '',
              level: _text(it, 'lev') ?? '',
              nameKor: _text(it, 'msdsItemNameKor') ?? '',
              detail: it.getElement('itemDetail')?.innerText,
              order: it.getElement('ordrIdx')?.innerText,
            ),
        ]);
      } on _Fail catch (f) {
        sections[e.key] = MsdsSection.failed(f.message);
      }
    }

    return MsdsResult._(
      status: MsdsStatus.found,
      source: {
        'provider': msdsProvider,
        'endpoint': msdsEndpoint,
        'chemId': pick.chemId,
        'casNo': pick.casNo,
        'nameKor': pick.nameKor,
        'lastDate': pick.lastDate,
        'retrievedAt': _clock().toUtc().toIso8601String(),
      },
      droppedPartialMatches: dropped,
      sections: sections,
    );
  }

  /// 목록 전부(쪽 나눔) → (완전 일치, 버린 부분 일치 수).
  Future<(List<MsdsCandidate>, int)> _list(String cas) async {
    final exact = <MsdsCandidate>[];
    var dropped = 0, received = 0;
    for (var page = 1; ; page++) {
      final doc = await _get(
        'getChemList001',
        'searchWrd=${Uri.encodeQueryComponent(cas)}&searchCnd=1&numOfRows=$msdsListPageSize&pageNo=$page',
      );
      final rows = doc.findAllElements('item').toList();
      final total = int.tryParse(doc.findAllElements('totalCount').firstOrNull?.innerText.trim() ?? '');
      if (total == null) {
        _warn('목록에 totalCount 없음');
        throw _Fail(LookupText.failed('응답 형식'));
      }
      received += rows.length;
      for (final r in rows) {
        if ((_text(r, 'casNo') ?? '') == cas) {
          exact.add(
            MsdsCandidate(
              chemId: _text(r, 'chemId') ?? '',
              casNo: cas,
              nameKor: _text(r, 'chemNameKor') ?? '',
              lastDate: _text(r, 'lastDate') ?? '',
            ),
          );
        } else {
          dropped++;
        }
      }
      if (received >= total) break;
      if (total > msdsListPageSize * msdsListMaxPages) {
        _warn('목록이 상한을 넘음: 전체 $total건, 받은 $received건');
        throw _Fail('목록이 $total건으로 상한(${msdsListPageSize * msdsListMaxPages}건)을 넘습니다 — $received건만 받음');
      }
      if (rows.isEmpty) {
        _warn('목록 $page쪽이 비었는데 전체 $total건 중 $received건만 받음');
        throw _Fail('목록이 전체 $total건 중 $received건에서 끊겼습니다');
      }
    }
    return (exact, dropped);
  }

  /// 한 번 부르고 XML로. 실패는 [_Fail](화면 문구), 원인은 로그.
  Future<XmlDocument> _get(String service, String query) async {
    final http.Response res;
    try {
      res = await _http.get(requestUri(service, query)).timeout(timeout);
    } on TimeoutException {
      _warn('$service 시간 초과 ${timeout.inSeconds}초');
      throw const _Fail(LookupText.offline);
    } catch (e) {
      _warn('$service 접속 실패: $e');
      throw const _Fail(LookupText.offline);
    }
    final body = utf8.decode(res.bodyBytes, allowMalformed: true);
    final portal = portalReasonCode(body);
    if (res.statusCode != 200 || portal != null) {
      _warn('$service HTTP ${res.statusCode}, 포털 코드 $portal, 본문 앞부분: ${body.length > 300 ? body.substring(0, 300) : body}');
      throw _Fail(failureMessage(res.statusCode, portal));
    }
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } on XmlException catch (e) {
      _warn('$service XML 아님: ${e.runtimeType}: $e');
      throw _Fail(LookupText.failed('응답 형식'));
    }
    final code = doc.findAllElements('resultCode').firstOrNull?.innerText.trim();
    if (code != msdsOkCode) {
      _warn('$service 결과 코드 $code: ${doc.findAllElements('resultMsg').firstOrNull?.innerText}');
      throw _Fail(LookupText.failed(code ?? '응답 형식'));
    }
    return doc;
  }

  static String? _text(XmlElement e, String name) => e.getElement(name)?.innerText.trim();
}
