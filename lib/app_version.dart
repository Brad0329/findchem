/// 앱 버전(F-006) — 원본은 `pubspec.yaml`의 `version`이다. 여기 값은 화면 표시용 사본이고,
/// `test/release_test.dart`가 pubspec과 같은지 대조한다(어긋나면 테스트 실패). 버전을 올릴 때 둘 다 고친다.
library;

/// pubspec `version`의 `+` 앞(릴리스 태그는 `v` + 이 값).
const appVersion = '1.3.0';

/// pubspec `version`의 `+` 뒤(Android 빌드 번호 — 친구에게 줄 때마다 +1).
const appBuildNumber = 4;
