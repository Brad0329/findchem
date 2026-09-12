# Phase 005 — F-002 원천자료 update

## ① 실패한 접근과 원인

- **웹에서 '선택'을 누르면 파일 창도 안 뜨고 즉시 "PDF를 가져오지 못했습니다"**(2026-09-12 사용자 실테스트).
  폰(Android)은 같은 코드로 정상이었다.
  - 앱 코드와 file_picker 웹 구현을 읽어도 **즉시** 예외를 던질 자리가 없어 한동안 헤맸다. 화면 사유에서 원본
    예외를 빼 둔 정책(보안 3층 ①) 때문에 문구만으로는 원인을 알 수 없다 — 이런 진단은 **로그나 빌드 산출물**로 한다.
  - 원인: 증분 웹 빌드가 `.dart_tool/flutter_build/<해시>/web_plugin_registrant.dart`를 **file_picker를 넣기 전
    것(전날 22:29) 그대로 재사용**했다. `FilePickerWeb.registerWith`가 없으니 MethodChannel 구현으로 떨어져
    MissingPluginException. `.flutter-plugins-dependencies`에는 file_picker가 제대로 들어 있어서 그것만 보면 정상으로 보인다.
  - 해결: `flutter clean` → `flutter pub get` → `flutter build web`. 등록 파일에 `FilePickerWeb.registerWith`가
    생기고 `main.dart.js`에 웹 구현 문자열이 들어간다.
  - **Android가 멀쩡했던 이유**는 등록 경로가 달라서다(GeneratedPluginRegistrant). 한 플랫폼 통과가 다른 플랫폼의
    근거가 되지 못한다는 실사례 — 자동 테스트(VM)로도 잡히지 않는다.
- 진단 중 `build/web/main.dart.js`(수 MB 한 줄)에서 `share_plus`·`FilePickerWeb`이 grep에 안 잡혀 "grep이 이 파일에서
  안 도는구나"로 오해할 뻔했다. **클래스명은 minify로 사라지고 문자열 리터럴만 남는다.** 반드시 남는 문자열로 먼저
  grep이 도는지 재고 판단해야 한다.

## ② 다음 세션이 알아야 할 것

- 위 함정은 CLAUDE.md '알려진 함정' 한 줄 + `docs/playbooks/팩_웹_PWA.md`('웹 플러그인 등록')에 옮겨 놨다.
  **웹 지원 플러그인을 추가할 때마다 걸린다** — 다음에 의존성을 추가하면 첫 웹 빌드는 clean 뒤에.
- F-002 설계에서 버린 대안: 저장본을 `shared_preferences` 한 벌로 두 플랫폼에 쓰는 안. Android에서 0.6MB 문자열이
  SharedPreferences XML에 통째로 들어가는 것이 부담이라, 파일(Android)·localStorage(웹)로 갈랐다
  (`lib/data/update_store*.dart`, 조건부 import).
- 웹 파싱은 메인 스레드를 2~3초 잡는다(사용자 결정으로 허용). 그래서 '적용'은 **표시를 먼저 그린 뒤**
  (`endOfFrame` + 짧은 지연) 파싱한다 — 이 순서를 지우면 "PDF를 읽는 중…"이 사용자에게 안 보인다(변이 확인으로 검증).
- **웹 저장본은 자동 테스트가 0건이다**(qa-tester 2026-09-12 지적). `flutter test`는 VM에서 돌아
  `update_store_io.dart`(파일)만 실행하고, `update_store_web.dart`(localStorage)와 조건부 import 배선은
  **웹 실테스트로만** 검증된다. 같은 인터페이스의 두 구현인데 대조 테스트가 없다 — 웹 저장을 건드리면 실테스트가 필수다.
- 폰은 릴리스 AOT라 파싱이 0.3초쯤이라 표시가 거의 안 보인다. "너무 빨라서 이상하다"는 인상은 정상이다
  (Phase 003 실측: 별표2 284ms, 별표3 17ms).
