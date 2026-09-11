/// 원문 물질명 `국문 [영문]`을 국문·영문으로 나눈다.
///
/// 규칙(Phase 001 실측, 2026-09-11 정답지 전수로 재확인): 국문에도 대괄호가 흔하다(`벤조[d]이소티아졸`, 156건).
/// 영문은 항상 마지막 대괄호 덩어리이고, 그 안에는 한글이 없다. 그래서 **뒤에 한글이 하나도 없는 첫 `[`**를
/// 경계로 잡는다. 원문의 괄호 짝이 틀린 4건(별표2 341·654·1083·1429)도 이 규칙으로 3건이 맞고,
/// 1429(`5-데신 [5-Decyne]]`)만 예외 목록으로 잡는다.
/// 예외 형식 하나(별표3 33): `…[Sodium cyanide]다만, 베를린청(…) … 제외`처럼 영문 뒤에 국문 단서가 붙는다.
/// 이때는 "뒤에 한글 없는 `[`"가 없으므로, 짝이 맞는 대괄호 중 한글 없는 가장 긴 것을 영문으로 하고 앞뒤 국문을
/// 공백으로 이어 국문명으로 둔다(단서를 버리지 않는다).
/// 예외 목록은 연번이 아니라 **원문 이름 전체**를 키로 둔다 — PDF가 바뀌어 그 이름이 사라지면 예외가 그냥
/// 적용되지 않고, 데이터 테스트가 "쓰이지 않은 예외"로 잡아낸다.
library;

final _hangul = RegExp(r'[ᄀ-ᇿㄱ-ㆎ가-힣]');

/// [name]의 [open] 위치 `[`와 짝이 맞는 `]`의 위치. 없으면 -1.
int _matchingClose(String name, int open) {
  var depth = 0;
  for (var i = open; i < name.length; i++) {
    if (name[i] == '[') depth++;
    if (name[i] == ']') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

/// 손으로 만든 예외: 원문 이름 → (국문, 영문). 자동 검증: test/parser/name_split_test.dart와
/// 번들 데이터 테스트가 "모든 예외가 실제로 한 번씩 쓰였는가"를 확인한다.
const Map<String, ({String ko, String en})> nameSplitExceptions = {
  '5-데신 [5-Decyne]]': (ko: '5-데신', en: '5-Decyne'),
};

/// 분리 결과. [usedException]은 예외 목록이 적용됐는지(검증용).
typedef SplitName = ({String ko, String en, bool usedException});

SplitName splitName(String rawName) {
  final name = rawName.trim();
  final exception = nameSplitExceptions[name];
  if (exception != null) {
    return (ko: exception.ko, en: exception.en, usedException: true);
  }

  var cut = -1;
  for (var i = 0; i < name.length; i++) {
    if (name[i] == '[' && !_hangul.hasMatch(name.substring(i))) {
      cut = i;
      break;
    }
  }
  if (cut < 0) {
    // 영문 뒤에 국문 단서가 붙은 형식(별표3 33): 짝 맞는 한글 없는 대괄호 중 가장 긴 것.
    var bestOpen = -1;
    var bestClose = -1;
    for (var i = 0; i < name.length; i++) {
      if (name[i] != '[') continue;
      final close = _matchingClose(name, i);
      if (close <= i + 1 || _hangul.hasMatch(name.substring(i + 1, close))) continue;
      if (close - i > bestClose - bestOpen) {
        bestOpen = i;
        bestClose = close;
      }
    }
    if (bestOpen < 0) {
      // 영문 부분이 없다(별표3의 '염화수소 용액' 같은 둘째 행).
      return (ko: name, en: '', usedException: false);
    }
    final before = name.substring(0, bestOpen).trim();
    final after = name.substring(bestClose + 1).trim();
    return (
      ko: after.isEmpty ? before : '$before $after',
      en: name.substring(bestOpen + 1, bestClose).trim(),
      usedException: false,
    );
  }

  final ko = name.substring(0, cut).trim();
  var en = name.substring(cut + 1).trim();
  if (en.endsWith(']')) en = en.substring(0, en.length - 1).trim();
  return (ko: ko, en: en, usedException: false);
}
