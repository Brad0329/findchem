/// 실측(2026-09-13): Dart `String.compareTo`로 한글 국문명을 정렬하면 가나다 순이 되는가(F-005 목록 정렬의 전제).
///
/// `compareTo`는 UTF-16 코드 단위를 비교한다. 한글 음절(U+AC00~U+D7A3)은 초성·중성·종성 순으로 배열돼 있어
/// 사전 순과 같을 것으로 **추정**되지만, 추정으로 넘어가지 않고 값을 못박는다(F-004 `selection_copy_probe_test.dart` 선례).
/// 이 값이 바뀌면(로캘 비교로 바뀌는 등) 정렬 규칙을 다시 봐야 한다.
library;

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('한글끼리: 초성 → 중성 → 종성 순(ㄱ < ㄲ < ㄴ, 가 < 개, 가 < 각)', () {
    expect('가'.compareTo('까'), lessThan(0), reason: '된소리 ㄲ은 ㄱ 뒤');
    expect('까'.compareTo('나'), lessThan(0), reason: 'ㄲ은 ㄴ 앞');
    expect('가'.compareTo('개'), lessThan(0), reason: '중성 ㅏ < ㅐ');
    expect('가'.compareTo('각'), lessThan(0), reason: '받침 없음 < 받침 있음');
    expect('각'.compareTo('갂'), lessThan(0));
    expect('하'.compareTo('힣'), lessThan(0));
    // 코드 포인트 그대로 — 가 U+AC00, 힣 U+D7A3
    expect('가'.codeUnitAt(0), 0xAC00);
    expect('힣'.codeUnitAt(0), 0xD7A3);
  });

  test('실제 국문명: 리누론 → 말라티온 → 헥사클로로시클로헥산, 에 → 왈 → 자', () {
    final names = ['헥사클로로시클로헥산', '말라티온', '리누론']..sort();
    expect(names, ['리누론', '말라티온', '헥사클로로시클로헥산']);
    final heads = ['자이레놀', '에틸헥산산 납', '왈파린']..sort();
    expect(heads, ['에틸헥산산 납', '왈파린', '자이레놀']);
  });

  test('앞머리를 그대로 두면 숫자·기호·영문이 전부 한글 앞에 몰린다(접두 건너뛰기가 필요한 이유)', () {
    final names = ['리누론', '2-에틸헥산산 납', '(S)-왈파린', 'o-톨루이딘', '가나']..sort();
    expect(names, ['(S)-왈파린', '2-에틸헥산산 납', 'o-톨루이딘', '가나', '리누론']);
  });

  test('앞부분이 같으면 짧은 쪽이 앞, 공백은 한글보다 앞', () {
    expect('납'.compareTo('납 화합물'), lessThan(0));
    expect('납 화합물'.compareTo('납화합물'), lessThan(0));
  });
}
