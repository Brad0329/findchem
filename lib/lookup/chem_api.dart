/// F-007 공공데이터 API 3종 호출 — 주소 만들기, 응답 해석, 실패 문구(REQUIREMENTS F-007).
///
/// 명세·실측 근거: plan.md 보류 항목 '외부 원천 조사'(2026-09-14), 실호출 도구 `scripts/probe_chem_api.py`.
/// 화면 오류에는 상태만 쓰고, 원문 응답은 로그에만 — 키는 로그에서도 가린다(보안 3층 ①).
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'api_settings.dart';
import 'chem_parse.dart';
import 'portal.dart';

// 화면 문구·키 가리기·포털 실패 판정은 Flutter 없는 portal.dart로 옮겼다(A-003 Q1) — 쓰는 쪽은 그대로 이 파일을 import한다
export 'portal.dart';
// 응답 모델·해석은 Flutter 없는 chem_parse.dart로 옮겼다(A-010 — 6호 상수 수집 스크립트가 같이 쓴다)
export 'chem_parse.dart';

/// [키 인증]에 쓰는 CAS(세 서비스 모두 결과가 있는 포르말린).
const verifyCas = '50-00-0';

String endpointOf(ChemService s) => switch (s) {
  ChemService.chem => chemEndpoint,
  ChemService.ghs => ghsEndpoint,
  ChemService.safety => safetyEndpoint,
};

/// 요청 주소. 포털 키는 '인코딩 키'(%가 들어 있음)와 '디코딩 키' 두 가지다 — [portalKeyParam]. 둘은 같은 주소가 된다.
Uri buildRequestUri(ChemService s, String key, String cas) {
  final query = switch (s) {
    // 안전관리정보는 CAS로만 찾고 결과 형식 파라미터가 없다(XML 전용)
    ChemService.safety => 'pageNo=1&numOfRows=$pageRows&casNo=${Uri.encodeQueryComponent(cas)}',
    _ => casJsonQuery(cas),
  };
  return Uri.parse('${endpointOf(s)}?serviceKey=${portalKeyParam(key)}&$query');
}

// ───── 호출 ─────

class ChemApiClient {
  ChemApiClient({http.Client? httpClient, this.timeout = const Duration(seconds: 20)})
    : _http = httpClient ?? http.Client();

  final http.Client _http;
  final Duration timeout;

  /// 서비스 하나를 CAS로 부른다. **예외를 던지지 않는다** — 실패는 [ServiceFailed]로(원인은 로그에).
  Future<ServiceResult> fetch(ChemService service, String key, String cas) async {
    void log(String what) =>
        debugPrint('F-007 ${service.name} 조회 실패: ${maskKey(what, key, onWarn: (m) => debugPrint('F-007 $m'))}');

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
  final key = settings.effectiveKey; // 사용자 키가 우선, 없으면 기본 키(F-007 '기본 키')
  if (key == null || key.isEmpty) return const LookupBlocked(LookupText.noKey);
  final services = settings.enabledServices;
  if (services.isEmpty) return const LookupBlocked(LookupText.noService);
  return LookupRunning({for (final s in services) s: client.fetch(s, key, cas)});
}
