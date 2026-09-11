# Phase 002: 프로젝트 세팅 (완료일: 2026-09-11)

## 실패한 접근과 원인 ★
- **CLAUDE.md의 템플릿 초기화 블록이 Phase 001 내내 남아 있었다.** 블록 전체가 HTML 주석(`<!-- -->`)이라 세션 시작 때
  AI에게 주입되는 CLAUDE.md에서 빠져 보이지 않았다. 이번 세션도 못 보고 지나갔고, Phase 완료 게이트(qa-tester)가
  파일을 직접 읽어서 찾았다 → 삭제. 교훈: **AI가 따라야 할 지시를 HTML 주석 안에 두지 않는다**(템플릿 쪽 결함).
- `cupertino_icons`를 YAGNI로 뺐다 → 웹 빌드가 "CupertinoIcons 폰트 없음" 경고를 냈다(프레임워크 내부가 참조한다)
  → 원복. 이유는 `pubspec.yaml` 주석에 적었다.
- 아이콘 모서리 알파 검사가 불투명 이미지에서 실패했다 → 원인: Chrome 헤드리스는 꽉 찬 이미지를 알파 없는 RGB로
  저장한다 → RGB는 불투명으로 처리한다(`scripts/make_icons.py`).

## 다음 세션이 알아야 할 것
- Flutter 프로젝트 위치: 저장소 루트(사용자 결정). `app/` 하위 안은 기각했다 — 명령마다 cd가 필요하고, cd 드리프트
  위험이 있다. 그 결과 테스트 폴더가 둘이다. `test/`는 Dart, `tests/`는 동봉 파이썬 도구용이다.
- 아이콘: SVG를 고친 뒤 `python scripts/make_icons.py`를 돌린다. `flutter_launcher_icons`는 기각했다 — 새 의존성이고,
  PNG 입력이라 어차피 SVG를 래스터화해야 한다. 스크립트는 Chrome 경로가 고정이다.
- 웹 빌드는 `.claude/launch.json`의 `web-build`로 미리 본다(`build/web`을 python http.server로 띄운다).
- 로컬 Flutter SDK를 올리면 `scripts/cloud_setup.sh`의 버전과 SHA256을 함께 바꾸고, 클라우드 환경의 웹 화면
  Setup script 칸에도 다시 붙여 넣는다.
- 릴리스 APK는 debug 키로 서명돼 있다. Phase 006에서 정한다(plan.md).
