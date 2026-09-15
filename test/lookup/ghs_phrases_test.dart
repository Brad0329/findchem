/// F-007 H·P 코드 → `(코드)문구` 찾기 규칙(REQUIREMENTS F-007 'H·P 문구').
library;

import 'package:findchem/lookup/ghs_phrase_data.dart';
import 'package:findchem/lookup/ghs_phrases.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const table = {'P320': '긴급히 처치를 하시오.', 'P321': '특별히 처치를 하시오.', 'P320+P330': '합친 문구'};

  test('문구표에 있는 코드는 (코드)문구 — 낱개·합성 모두', () {
    expect(ghsPhraseLine('P320', table), '(P320)긴급히 처치를 하시오.');
    expect(ghsPhraseLine('P320+P330', table), '(P320+P330)합친 문구');
    expect(hPhraseLine('H300'), '(H300)삼키면 치명적임');
    expect(hPhraseLine('H300+H310'), '(H300+H310)삼키거나 피부에 접촉하면 치명적임');
  });

  test('문구표에 없는 코드는 (코드)문구없음', () {
    expect(ghsPhraseLine('H99', table), '(H99)문구없음');
    expect(hPhraseLine('H99'), '(H99)문구없음');
  });

  test('문구표에 없는 합성 코드는 낱개 문구를 공백으로 잇고 (문구표 없음)', () {
    expect(ghsPhraseLine('P320+P321', table), '(P320+P321)긴급히 처치를 하시오. 특별히 처치를 하시오.(문구표 없음)');
    // 실제 문구표: P320+P321은 없고 낱개는 있다(사용자 예시)
    expect(ghsPPhrases.containsKey('P320+P321'), isFalse);
    expect(pPhraseLine('P320+P321'), '(P320+P321)${ghsPPhrases['P320']!} ${ghsPPhrases['P321']!}(문구표 없음)');
  });

  test('합성 코드의 낱개 중 없는 것은 그 자리에 문구없음, 하나도 없으면 그냥 문구없음', () {
    expect(ghsPhraseLine('P999+P321', table), '(P999+P321)문구없음 특별히 처치를 하시오.(문구표 없음)');
    expect(ghsPhraseLine('P998+P999', table), '(P998+P999)문구없음');
  });

  test('앞뒤 공백은 떼고 찾는다', () {
    expect(ghsPhraseLine(' P320 ', table), '(P320)긴급히 처치를 하시오.');
  });
}
