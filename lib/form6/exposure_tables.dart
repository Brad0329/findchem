/// A-010 위험노출수준 — `assets/form6/exposure_tables.json`(scripts/extract_exposure.py가 원천에서 원문 문자열로 뽑은 표)을 읽어
/// CAS마다 ERPG-2 → AEGL-2(60분) → PAC-2 순(별지 주⑨ 순서)으로 **있는 값을 전부** 칸 하나에 담는다(D6 — 고르기는 채울 때).
///
/// - ERPG: AIHA(비상업 한정 라이선스 — 사용자 판단 2026-10-19). 항목마다 출처 표시, 고지문은 생성물 머리에.
/// - AEGL: EPA 물질별 페이지 60분 값. `NR`(권고 안 함)은 값이 아니다 — 싣지 않고 메모. `*`는 LEL 10% 이상 표시(원문에 남는다).
/// - PAC: DOE 2025-02 판. 근거 열(`AEGL-1, AEGL-2, AEGL-3` 등)을 메모로.
/// 숫자는 원문 앞머리 숫자만 해석한다(지어낸 숫자 0건 — `number`가 `raw` 안에 있다).
///
/// **Flutter를 import하지 않는다.**
library;

import 'dart:convert';
import 'dart:io';

import 'form6_builder.dart' show Form6Status;

/// 추출 표 파일 읽기. 없으면 null — 생성물의 위험노출수준이 '싣지 않고 만들었음'(확인필요)으로 남는다.
ExposureTables? loadExposureTables(String path) {
  final f = File(path);
  if (!f.existsSync()) return null;
  return ExposureTables.fromJson((jsonDecode(f.readAsStringSync()) as Map).cast<String, Object?>());
}

final _lead = RegExp(r'^\s*(\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?');
// µg/m3: AIHA 베릴륨 ERPG-2 `25 µg/m3`(2026-10-20 범위 확장 대조에서 발견 — 단위를 못 읽어 숫자 25만 남았다)
final _unitInCell = RegExp(r'(ppm|mg/m3|mg/m³|mg/㎥|µg/m3|μg/m3|ug/m3)', caseSensitive: false);

class ExposureTables {
  ExposureTables._(this._erpg, this._aegl, this._pac, this.sources, this.aihaNotice);

  factory ExposureTables.fromJson(Map<String, Object?> j) {
    Map<String, List<Map<String, Object?>>> table(String k) => {
      for (final e in (j[k] as Map).entries)
        e.key as String: [for (final r in e.value as List) (r as Map).cast<String, Object?>()],
    };
    return ExposureTables._(
      table('erpg'),
      table('aegl'),
      table('pac'),
      [for (final s in j['sources'] as List) (s as Map).cast<String, Object?>()],
      j['aihaNotice'] as String,
    );
  }

  final Map<String, List<Map<String, Object?>>> _erpg, _aegl, _pac;

  /// 원천별 주소·받은 날·판·라이선스(raw/exposure/sources.json 그대로).
  final List<Map<String, Object?>> sources;

  /// AIHA 고지문 원문 — 라이선스가 재배포 때 포함을 요구한다.
  final String aihaNotice;

  /// 앞머리 숫자 문자열(`2,500*` → `2,500`). 없으면 null.
  static String? leadNumber(String raw) {
    final m = _lead.firstMatch(raw);
    return m?.group(0)?.trim();
  }

  Map<String, Object?> fieldOf(String cas) {
    final entries = <Map<String, Object?>>[];
    final notes = <String>[];

    for (final r in _erpg[cas] ?? const <Map<String, Object?>>[]) {
      final raw = r['erpg2'] as String;
      final n = leadNumber(raw);
      if (n == null) {
        notes.add("ERPG-2 원문 '$raw'(값 아님)");
        continue;
      }
      final unit = _unitInCell.firstMatch(raw)?.group(1);
      entries.add({
        'kind': 'ERPG-2',
        'value': double.parse(n.replaceAll(',', '')),
        'number': n,
        'unit': unit,
        'raw': raw,
        'source': {'kind': 'AIHA ERPG', 'id': r['name'], 'version': 'Last Update ${r['lastUpdate']}', 'attribution': 'AIHA ERPG®'},
        'note': unit == null ? '단위 표기를 찾지 못함' : null,
        'needsReview': unit == null,
      });
    }

    for (final r in _aegl[cas] ?? const <Map<String, Object?>>[]) {
      final raw = r['aegl2_60'] as String;
      final status = r['status'] as String;
      if (raw.trim() == 'NR') {
        notes.add('AEGL-2(60분) NR — 권고값 없음(${r['page']})');
        continue;
      }
      final n = leadNumber(raw);
      if (n == null) {
        notes.add("AEGL-2(60분) 원문 '$raw'(값 아님, ${r['page']})");
        continue;
      }
      final cellUnit = _unitInCell.firstMatch(raw)?.group(1);
      final unit = cellUnit ?? ((r['unit'] as String).isEmpty ? null : r['unit'] as String);
      entries.add({
        'kind': 'AEGL-2(60분)',
        'value': double.parse(n.replaceAll(',', '')),
        'number': n,
        'unit': unit,
        'raw': raw,
        'source': {'kind': 'EPA AEGL', 'id': r['page'], 'version': status},
        'note': [
          if (status == 'Interim') 'Interim(확정 전 잠정값)',
          if (status == 'unstated') '페이지에 Final/Interim 표시 없음',
          if (raw.contains('*')) 'LEL 표시(*) 있음 — 원문 각주',
          if (unit == null) '단위 표기를 찾지 못함',
        ].join('; ').ifEmptyNull,
        'needsReview': unit == null,
      });
    }

    for (final r in _pac[cas] ?? const <Map<String, Object?>>[]) {
      final raw = r['pac2'] as String;
      final n = leadNumber(raw);
      if (n == null) {
        notes.add("PAC-2 원문 '$raw'(값 아님)");
        continue;
      }
      final src = r['source'] as String;
      entries.add({
        'kind': 'PAC-2',
        'value': double.parse(n.replaceAll(',', '')),
        'number': n,
        'unit': (r['unit'] as String).isEmpty ? null : r['unit'],
        'raw': raw,
        'source': {'kind': 'DOE PAC', 'id': 'No. ${r['no']} ${r['name']}', 'version': '2025-02-07'},
        'note': ['근거: $src', if (src.startsWith('Used')) '다른 물질 값을 빌린 행'].join('; '),
        'pacSource': src,
      });
    }

    final source = {'kind': '위험노출수준 표(AIHA ERPG·EPA AEGL·DOE PAC)', 'id': null, 'version': null, 'section': null, 'collectedAt': '2026-10-19'};
    if (entries.isEmpty) {
      return {
        'value': <Object>[],
        'raw': '',
        'unit': null,
        'condition': null,
        'source': source,
        'status': Form6Status.noData.label,
        'note': ['ERPG·AEGL·PAC 모두 없음', ...notes].join('; '),
      };
    }
    final first = entries.first;
    final review = first['needsReview'] == true;
    return {
      'value': entries,
      'raw': [for (final e in entries) '${e['kind']}: ${e['raw']}'].join('\n'),
      'unit': null,
      'condition': null,
      'source': source,
      'status': (review ? Form6Status.needsReview : Form6Status.confirmed).label,
      'note': [
        '별지 주⑨ 순서(ERPG → AEGL → PAC)로 늘어놓음 — 첫 항목: ${first['kind']}',
        if (review) '첫 항목 단위 확인 필요',
        ...notes,
      ].join('; '),
    };
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
