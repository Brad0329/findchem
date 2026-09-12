# 팩: Flutter / Android (모바일 앱 프로젝트일 때)

> 선택형 팩 — 이 프로젝트에 해당 없으면 이 파일을 삭제한다.
> 출처: hanjadic 프로젝트 실측(2026-08).

## 빌드·설치

- **`flutter install`은 빌드하지 않는다.** `flutter build apk` 먼저, 그다음 `adb install -r`.
  APK가 없으면 `does not exist`로 실패한다.
- **백그라운드 빌드 완료 전에 `adb install`하면 직전 APK가 성공 메시지와 함께 설치된다.**
  낡은 APK 설치는 성공으로 보여 알아채기 어렵다 — APK 파일의 LastWriteTime으로 확인한다.
- **APK 크기는 `--split-per-abi`로만 줄어든다.** `--target-platform android-arm64`만 줘도
  fat APK가 그대로 나온다(실측 49.3MB → split 후 17.8MB).
- **asset은 빌드 시점에 박힌다.** 데이터를 고쳤으면 재빌드했는지 확인한다. 앱이 asset을 다시
  꺼내는 조건(크기 비교 등)도 알아 둘 것 — 크기가 같고 내용만 다르면 다시 안 꺼낸다.
- **Android asset은 APK 안에 압축돼 파일 경로가 없다.** 경로를 요구하는 라이브러리(sqlite 등)는
  첫 실행 때 앱 디렉토리로 꺼내 둔다.
- **`adb devices`가 비면 OS가 기기를 보는지부터 확인한다**(`Get-PnpDevice` 등).
  USB 테더링이 켜져 있으면 ADB 인터페이스가 안 열리고, 제조사 보안 기능(삼성 Auto Blocker)이
  USB 명령을 막기도 한다.
- **adb는 PATH에 없다 — 전체 경로를 글자 그대로(리터럴) 쓴다.** `& (Join-Path …)` 같은
  변수 시작 형태는 허용 규칙에 안 걸려 매번 확인을 묻는다(실측 대기 77.8초, adb 실행은 2~5초).
  허용 규칙도 그 리터럴 경로로 `settings.local.json`에 등록한다(`settings.json`의 allow는 무효) —
  `노하우_승인_대기_최소화.md` §5 스타터에 3종(devices/install/logcat)이 들어 있다.

## 릴리스 서명 키 (2026-09-12, Phase 006에서 확정)

- **debug 키로 배포하면 안 된다.** Flutter 기본 `build.gradle.kts`는 release를 debug 키로 서명한다.
  debug 키는 PC마다 다르고 재생성되기도 해서, 키가 바뀌면 이미 설치된 앱 위에 업데이트가 안 되고
  `INSTALL_FAILED_UPDATE_INCOMPATIBLE`로 막힌다 — 지우고 다시 깔아야 하고 저장본도 함께 날아간다.
- **이 저장소의 구조**: `android/app/build.gradle.kts`가 `android/key.properties`를 읽는다.
  그 파일이 없으면 릴리스 빌드를 **거부한다**(fail-closed) — debug 키로 조용히 서명하지 않는다.
  디버그 빌드·테스트는 키 없이도 그대로 돈다.
- **비밀정보라 저장소에 넣지 않는다**: `key.properties`와 `*.jks`는 `.gitignore`에 있다.
  keystore 파일 자체는 저장소 **밖**(예: `C:\Users\user\keys\`)에 두고 절대경로로 가리킨다.
- **keystore를 잃으면 그 앱은 다시 업데이트할 수 없다.** 파일과 비밀번호를 따로 백업한다.
- 만들기(사용자가 직접 실행한다 — 비밀번호를 묻는 대화형 명령이다). **`-storetype PKCS12`로 만든다**:
  ```
  & "C:\Program Files\Android\Android Studio\jbr\bin\keytool.exe" -genkeypair -v -keystore C:\Users\user\keys\findchem-release.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias findchem
  ```
  (keytool은 PATH에 없다. Android Studio 번들 JDK 경로를 리터럴로 쓴다 — `flutter doctor -v`의 "Java binary at".
  PowerShell에서는 경로에 공백이 있어 **호출 연산자 `&`가 없으면** `예기치 않은 '-genkeypair' 토큰`으로 죽는다.)
- **★ 비밀번호는 ASCII여야 한다 — 한/영이 한글 상태면 한글이 들어간다**(findchem 2026-09-12, 두 시간 샌 진짜 원인).
  비밀번호 입력은 화면에 찍히지 않아서 IME 상태를 눈으로 확인할 수 없다. `dmsw0114`를 한글 상태로 치면
  `으뭐0114`가 들어가고, **JKS는 그대로 받아 준다**. 그러면 파일에 적은 ASCII 비밀번호와 영영 안 맞고,
  Gradle은 `Keystore was tampered with, or password was incorrect`로만 실패해 원인을 가리킨다.
  PKCS12는 생성 시점에 `Password is not ASCII`로 **거부해서 바로 드러난다** — PKCS12를 쓰는 두 번째 이유다.
  `keytool -list`가 통과해도 안심할 수 없다: 그때도 IME가 같은 상태면 같은 한글이 들어가 통과한다.
- **JKS로 만들면 키 비밀번호와 저장소 비밀번호가 갈릴 수 있다 — PKCS12는 그럴 수 없다**(findchem 2026-09-12 실측).
  JKS는 마지막에 키 비밀번호를 따로 묻고(엔터 = 저장소와 동일), 거기서 다른 값이 들어가면
  Gradle이 `Keystore was tampered with, or password was incorrect`로만 실패한다 — 어느 쪽 비밀번호가
  틀렸는지 말해 주지 않는다. **가르는 법**: `keytool -list -v -keystore <파일> -alias <alias>`가
  성공하면 저장소 비밀번호는 맞는 것이고, 남은 건 키 비밀번호다. PKCS12는 둘이 같아야 해서 이 갈림이 없다.
- `android/key.properties` 형식 (`\`는 `\\`로, 또는 `/`로 쓴다):
  ```
  storePassword=<위에서 넣은 keystore 비밀번호>
  keyPassword=<키 비밀번호 — 엔터만 쳤으면 storePassword와 같다>
  keyAlias=findchem
  storeFile=C:/Users/user/keys/findchem-release.jks
  ```
- **확인**: `flutter build apk --split-per-abi` 후 **`apksigner`로** 본다 —
  ```
  "C:/Users/user/AppData/Local/Android/Sdk/build-tools/36.1.0/apksigner.bat" verify --print-certs <APK>
  ```
  `Signer #1 certificate DN`이 debug 키(`CN=Android Debug`)가 아니라 위에서 넣은 값이어야 한다.
  **`keytool -printcert -jarfile`은 쓸 수 없다** — "서명된 jar 파일이 아닙니다"가 뜬다.
  그 명령은 v1(JAR) 서명만 읽는데, 요즘 Flutter APK는 v2/v3 서명만 붙기 때문이다(findchem 2026-09-12).

## 테스트

- **`testWidgets` 안에서 진짜 파일 I/O를 `await`하면 타임아웃까지 매달린다.** FakeAsync가
  시계를 잡고 있어 영영 안 끝난다. 파일 준비는 동기 API(`createTempSync`·`writeAsStringSync`)로
  하거나 `tester.runAsync`로 감싼다. (같은 함정을 세 번 밟았다 — 증상이 "테스트가 그냥
  안 끝남"이라 원인을 알아보기 어렵다.)
- **위젯 테스트가 넘침을 예외로 올려 주는 것은 `RenderFlex`(Row·Column)뿐이다.** `Text`가
  컨테이너보다 넓으면 잘리기만 하고 예외가 없다 — `expect(find.text(...), findsWidgets)`는
  잘려도 통과한다. 픽셀 검증은 `TextPainter`로 폭을 직접 재서 비교한다.
- **SnackBar는 큐에 쌓인다.** 앞선 안내가 사라질 때까지(최대 3초) 새 안내가 안 뜬다 —
  테스트에서는 "탭해도 무반응"으로 보이고, 사용자에게는 옛 안내가 지금 것으로 읽힌다.
  새 안내 전에 `clearSnackBars()`.
- **finder는 화면 전체를 훑는다.** `find.byType(...)` 전체 카운트는 앱바·다른 영역까지 세고,
  텍스트 매칭도 여러 곳에 걸린다 — 대상의 조상(ancestor)으로 범위를 좁힌다.
- **골든 이미지는 기본 폰트가 모든 글자를 네모로 그려 쓸모없다.** 화면을 보여줘야 할 때는
  렌더 트리의 Text 위젯을 순서대로 덤프해 재현한다(글자 크기까지 실제 값으로 나온다).
- **`find.text`로는 rich text를 못 잡는다.** `라벨 : 값`을 하나의 RichText로 그리면 `Text.data`가
  없다 — 자유 양식 카드류 위젯 테스트는 `find.textContaining`을 쓴다.
- **색을 손대면 다크 모드를 눈으로 다시 봐야 한다.** 팔레트가 시드(`ColorScheme.fromSeed`)
  하나에서 자동 생성되면 테스트는 "어둡게가 걸렸다"까지만 본다 — 대비가 죽는지는 사람만 안다.
  색 하드코딩 건수를 0에 가깝게 유지하는 것이 그 구조를 지키는 방법이다.
- **밝기와 글자 배율은 서로 다른 자리에 걸린다**: 배율은 `MaterialApp`의 `builder:` **안쪽**,
  밝기는 `themeMode` 속성이라 **바깥**에서 감싼다. 한쪽을 옮기다 다른 쪽을 떨어뜨리기 쉬워
  **둘을 함께 보는 테스트**를 그 자리에 둔다.
- **렌더러를 갈아끼우면 그 카드가 갖고 있던 상호작용이 함께 오지 않는다.** 카드를 자유 렌더러로
  옮기자 "눌러서 다음 동작"(탭)이 발음 듣기와 탭을 다투다 죽었고 **아무 오류도 안 났다** —
  `onTap`이 옛 위젯 경로에만 연결돼 있었다. 옮길 때 확인한 것은 "연결에 쓸 데이터가 남는가"였지
  "그 데이터를 쓰는 UI가 여전히 있는가"가 아니었다. → 한 요소에 두 동작이 걸리면 하나는
  **버튼으로 분리**한다. 위젯 테스트는 "보인다"까지만 본다 — **"보인다"와 "눌린다"는 다르다.**
- **카드의 역할이 자리를 정한다.** "누르는 카드"(거기서 다음 작업을 시작하는 것)는 맨 위에
  고정한다 — "새것이 위"만 넣은 첫 판에서 그 카드가 밀려 매번 내려가야 했고 사용자가 폰에서
  잡았다. **배치는 테스트가 순서까지는 지켜도 "쓰기 편한가"는 못 본다** — 실기기 확인이 잡는 층이다.

## 코딩

- **위젯 API를 기억으로 쓰지 말고 analyze를 믿는다.** deprecated가 버전마다 생긴다.
  낯선 API는 SDK 소스에서 확인하고 착수한다.
- **`dart format`은 건드린 파일만 지정해서 돌린다.** 포맷 기준으로 정리 안 된 저장소에서
  전체 실행하면 무관한 파일 수십 개가 바뀐다(실측 28개·약 1,000줄). 포맷 뒤에는 analyze를
  다시 본다 — 한 줄 `if`가 펼쳐지며 lint가 새로 생긴다. 포맷이 줄을 옮기면 편집 도구의
  대상 문자열도 안 맞게 된다.
- **패키지 간 이름 충돌(예: `Row`)은 import alias로 푼다.**
- **동기/비동기 API 선택이 다언어 이식본의 대조 가능성을 좌우한다.** 비동기는 로직 전체를
  물들여 이식본들의 모양이 갈라진다 — 코어 로직은 동기로 유지할 수 있는지 먼저 본다.

## 플랫폼

- **Android 11+는 `AndroidManifest`의 `<queries>` 없이 다른 시스템 서비스(TTS 등)를 못 찾는다.**
  **오류 없이 조용히 아무 일도 안 일어난다** — 기기에 해당 서비스가 없을 때와 증상이 똑같아
  원인을 가리기 어렵다. "조용히 아무 일도 안 일어나면 매니페스트부터 본다."
- **권한 목록의 부재는 구조적 보증이다.** 예: INTERNET 권한이 없으면 "통신이 구조적으로
  불가능"이 비행기 모드 테스트보다 강한 증거다. 권한이 생기는 순간 그 보증이 사라지므로,
  그 시점부터는 규칙("핵심 기능은 네트워크 무관")으로 지켜야 한다.
- **데스크톱 Flutter의 `getApplicationDocumentsDirectory`는 Windows '내 문서'다.** 앱 데이터는
  `getApplicationSupportDirectory`. 두 번째 플랫폼 빌드가 첫 플랫폼에선 안 보이던 문제를
  드러낸다 — 멀티플랫폼 빌드의 부수 가치.
