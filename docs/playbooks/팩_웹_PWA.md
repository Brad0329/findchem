# 팩: 웹 / PWA (브라우저에서 도는 것을 만들 때)

> 선택형 팩 — 이 프로젝트에 해당 없으면 이 파일을 삭제한다.
> 출처: hanjadic 프로젝트 실측(2026-08).

## 서비스워커·오프라인

- **평문 HTTP의 LAN 주소로는 폰에서 서비스워커가 등록되지 않는다**(보안 컨텍스트 아님).
  `localhost`는 평문이어도 보안 컨텍스트다. 폰 오프라인 검증은 USB 포트 포워딩
  (`chrome://inspect` → 폰에서 `http://localhost:...`)이 추가 설치 없는 가장 싼 방법.
  레이아웃 확인까지는 LAN으로 충분하다.
- **서비스워커는 캐시 우선이다.** sw 파일이 바이트 단위로 안 바뀌면 install이 다시 돌지 않아
  사용자가 낡은 자산을 계속 본다 — **자산을 고치면 캐시 버전을 올린다.** 캐시를 지우고 같은
  sw를 재등록하면 install이 안 돌아 캐시가 빈 채로 남는 실사례도 있다.
- **실기기 검증이 인프라 제약으로 Phase 안에서 자동으로 안 끝날 수 있다** — 착수 전에
  검증 경로(어떻게 폰에서 확인할 것인가)부터 확인한다.
- **Flutter 웹 빌드를 다시 띄우면 서비스워커가 옛 `main.dart.js`를 보여준다**(findchem 2026-09-11 실사례 — 새
  진입점으로 빌드했는데 이전 화면이 떴다). 확인 전에 서비스워커 해제 + `caches` 삭제 후 재로드.

## 웹 플러그인 등록

- **웹 지원이 있는 플러그인을 추가한 뒤 첫 `flutter build web`은 `flutter clean` 다음에 해야 한다**
  (findchem 2026-09-12 실사례: file_picker 추가 → 증분 웹 빌드가 `.dart_tool/flutter_build/<해시>/
  web_plugin_registrant.dart`를 **의존성 추가 이전 것 그대로 재사용** → `FilePickerWeb.registerWith`가 빠진 채
  컴파일 → 버튼을 누르는 즉시 MissingPluginException). **Android는 등록 경로가 달라(GeneratedPluginRegistrant)
  정상이었다 — 한쪽 플랫폼에서 됐다고 다른 쪽이 된 것이 아니다.**
- 확인법 두 가지: ① 등록 파일에 그 플러그인의 `registerWith`가 있는가
  ② `build/web/main.dart.js`에 그 플러그인의 **문자열 리터럴**이 있는가(file_picker면 `__file_picker_web-file-input`).
  클래스명은 minify돼 사라지므로 클래스명으로 grep하면 있어도 안 잡힌다 — 반드시 남는 문자열
  (`findchem_data.json` 등)로 grep이 동작하는지 먼저 재 보고 판단한다.

## Flutter 웹 자산

- **한글·대괄호 파일명 asset은 Windows 웹 빌드가 실패한다** — URL 인코딩된 이름(`%5B%EB%B3%84…`)이 경로 길이를
  넘겨 `PathNotFoundException`(errno 123). 번들할 자산은 ASCII 파일명으로(findchem 2026-09-11, 원천 PDF 임시 등록 때).

## 하위 경로 호스팅 (GitHub Pages 등)

- **저장소 이름 하위 경로로 서비스되면 `--base-href`를 줘야 한다**: `flutter build web --base-href /findchem/`.
  빠뜨리면 `index.html`의 `<base href="/">` 때문에 `main.dart.js`·asset이 전부 404가 되고
  화면은 흰 채로 뜬다(콘솔에만 404가 보인다). 빌드 산출물의 `<base href>`로 확인한다.
- `web/manifest.json`의 `start_url`·`icons.src`는 **상대 경로**여야 한쪽 경로에서도 맞는다
  (`"."`, `"icons/…"`). `/`로 시작하면 하위 경로 호스팅에서 깨진다.
- **로컬에서 `build/web`을 루트로 띄우면 base-href를 준 산출물은 안 뜬다** — 확인은 배포된 주소에서 한다.

## 개발 서버·모듈

- **python 기본 `http.server`는 `.wasm`·`.webmanifest` MIME을 모른다** — 브라우저가 wasm을
  거부한다. 개발 서버에서 MIME 보정이 필요하다.
- **ES 모듈의 상대 import는 cwd가 아니라 파일 위치 기준이다.**
- **CJK 혼용 텍스트에는 `lang` 속성이 필수다** — 같은 코드포인트가 언어별로 다른 자형으로
  렌더링된다.
