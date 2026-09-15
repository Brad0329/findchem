/// F-007 H·P 문구 대응표(생성물 lib/lookup/ghs_phrase_data.dart)가 엑셀을 온전히 옮겼는지 — 건수·표본·형식.
library;

import 'package:findchem/lookup/ghs_phrase_data.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('건수: H 82건(합성 13), P 129건(합성 32 — `[+P378]` 행은 +P378 붙인 코드 하나로)', () {
    expect(ghsHPhrases, hasLength(82));
    expect(ghsHPhrases.keys.where((k) => k.contains('+')), hasLength(13));
    expect(ghsPPhrases, hasLength(129));
    expect(ghsPPhrases.keys.where((k) => k.contains('+')), hasLength(32));
  });

  test('키는 H123·P123을 +로 이은 형태뿐, 문구에 줄바꿈·앞뒤 공백이 없다', () {
    for (final (kind, table) in [('H', ghsHPhrases), ('P', ghsPPhrases)]) {
      final key = RegExp('^$kind\\d{3}(\\+$kind\\d{3})*\$');
      for (final e in table.entries) {
        expect(key.hasMatch(e.key), isTrue, reason: e.key);
        expect(e.value, isNotEmpty, reason: e.key);
        expect(e.value.contains('\n'), isFalse, reason: e.key);
        expect(e.value, e.value.trim(), reason: e.key);
      }
    }
  });

  test('표본: 엑셀 원문 그대로(예외 — P250 줄바꿈 제거, P370+P380+P375[+P378]은 +P378 붙인 코드로)', () {
    expect(ghsHPhrases['H200'], '불안정한 폭발성 물질');
    expect(ghsHPhrases['H300+H310+H330'], '삼키거나, 피부에 접촉하거나 흡입하면 치명적임');
    expect(ghsHPhrases['H350'], '암을 일으킬 수 있음(주2)');
    expect(ghsHPhrases['H420'], '대기 상층부의 오존을 파괴함으로써 공공의 건강 및 환경에 유해함');
    expect(ghsPPhrases['P101'], '의학적인 조치가 필요한 경우, 제품의 용기 또는 라벨을 보시오.');
    expect(ghsPPhrases['P301+P310'], '삼켰다면; 즉시 의료기관/의사/···의 진찰을 받으시오..');
    expect(ghsPPhrases['P250'], '연마/충격/마찰/···을 가하지 마시오.');
    expect(ghsPPhrases['P502'], '제조자 또는 공급자가 제공한 재생 또는 재활용에 대한 정보를 참조하시오.');
    // 괄호 없는 코드는 자기 행(108행) 문구, [+P378] 행은 붙인 코드로
    expect(ghsPPhrases['P370+P380+P375'], '화재 시; 주변지역의 사람을 대피시키시오. 폭발의 위험이 있으므로 거리를 유지하면서 불을 끄시오');
    expect(
      ghsPPhrases['P370+P380+P375+P378'],
      '화재 시; 주변지역의 사람을 대피시키시오. 폭발의 위험이 있으므로 거리를 유지하면서 불을 끄시오[불을 끄기 위해 ···을(를) 사용하시오.]',
    );
  });
}
