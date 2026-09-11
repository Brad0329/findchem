# Phase 003: Dart PDF 파서 (구현·웹 확인 2026-09-11, Android 실기기 확인 대기)

## 실패한 접근과 원인 ★
- **정답지(pdfplumber)에서 셀의 `\n`을 지웠더니 정보가 사라졌다.** 별표3 98번 CAS 셀은 `95-47-6⏎106-42-3`처럼 쉼표
  없이 줄바꿈만으로 나뉘어 있어, 지우면 `95-47-6106-42-3`이 되고 어디서 갈라야 할지 복원할 수 없다(두 자리 분할이
  모두 CAS 형식에 맞는다) → 정답지는 원시 그대로(`\n`·줄 끝 공백 유지), 줄바꿈 규칙은 Dart 빌더 한 곳에만.
- **oracle이 `text_keep_blank_chars`를 `find_tables`에만 넘겨 줄 끝 공백이 빠졌다.** pdfplumber는 표 탐지 설정과
  텍스트 설정을 따로 받는다 — `extract(keep_blank_chars=True)`로 넘겨야 `Lead ⏎2,4,6`(단어 경계)과
  `Fo⏎rmaldehyde`(단어 중간)가 갈린다. Phase 001의 "`\n`만 제거" 규칙은 이 설정에서만 맞고, 그 상태로 재확인했다.
- **1쪽에서 가짜 괘선 경계가 96개 나왔다.** 서문의 Type3 폰트 글리프가 경로(획)로 인터프리터를 거쳐 장치에 들어온다
  → 8pt 미만 선분과 길이 합 10pt 미만 군집을 버림. 그래도 서문 밑줄 5개가 행 경계로 남아 → 수직 괘선의 y 범위 밖
  수평선을 제외.
- 폭 0 런(U+200B)이 같은 x의 이웃과 정렬 순서가 뒤바뀌어 43쪽 한 셀이 어긋남 → x 동률은 내용 스트림 순서로.
- **웹 빌드가 원천 PDF를 asset으로 못 넣었다.** 한글·대괄호 파일명이 URL 인코딩되어 Windows 경로 길이를 넘긴다
  (`PathNotFoundException`, errno 123) → 확인용으로는 `build/check_assets/byeolpyo2.pdf`처럼 ASCII 이름으로 복사해
  임시 등록. (`팩_웹_PWA.md`)
- 웹 확인 첫 화면이 옛 빌드였다 — Flutter 웹 서비스워커가 이전 `main.dart.js`를 캐시. 서비스워커 해제+캐시 삭제 후
  재로드해야 새 빌드가 보인다.
- **Phase_001.md 수치 정정(정답지 전수 재실측)**: 복수 CAS는 별표2 55건(54 아님)·별표3 1건, 원문 괄호 짝 오류는
  4건(341·654·1083·1429 — 654는 영문 쪽), 별표3 33번은 `[Sodium cyanide]` 뒤에 국문 단서("다만, … 제외")가 붙는
  유일한 형식이라 이름 분리에 fallback 규칙이 필요했다.

## 다음 세션이 알아야 할 것
- **라이브러리 = pdf_graphics + pdf_document + pdf_cos 4.4.0 정확 고정**(Apache-2.0, 순수 Dart). 사용자 결정 2026-09-11.
  버린 대안: `syncfusion_flutter_pdf`(`dart:ui` 의존이라 `dart run` 불가 + Community 라이선스에 "오픈소스 프로젝트에
  바이너리 배포 금지"(4.2.n.b)·"AI 에이전트 사용 금지"(4.2.c.ii) 조항), `pdfrx`(최신판 Dart 3.13 필요, 괘선 API 없음,
  웹은 wasm 5MB), 직접 구현(약 800줄). 리스크: 생긴 지 3개월·1인 유지·API 변경이 잦다 — **올릴 때는
  `test/parser/pdf_extractor_test.dart`(정답지 전수 대조)가 통과해야 한다.** 그래도 안 되면 위 대안 순서로.
- **정답지 재생성**: `python scripts/oracle_pdf_cells.py`(pdfplumber 0.11.9) → `test/fixtures/*_cells.json`. 규칙이 없는
  원시 셀 격자라 "두 번째 파서"가 아니다. PDF가 바뀌면 정답지도 다시 만든다.
- 괘선을 못 얻는 라이브러리로 바꿔야 할 때의 근거: 셀 글자의 세로 중심은 셀 중앙에서 최대 1.31pt(전수 2,517셀),
  줄 간격 8.4pt·글자 7pt로 균일 — 마지막 열 글자 중심으로 행 경계를 복원할 수 있다(실측 2026-09-11, 스크립트는 보존 안 함).
- **실측 성능**: 별표2 56쪽 추출 VM 약 1.0초, 웹(dart2js, Chrome) 2.6초. 웹은 메인 스레드라 그동안 화면이 멈춘다 —
  Phase 005 F-002 화면에 진행 표시가 필요하다.
- 이름 분리 한계: 원문이 `Maleichydrazide`처럼 붙어 있는 것은 원문 그대로다(줄바꿈이 아니라 원문). 별표3 33번은
  국문명에 단서가 이어 붙는다(`시안화나트륨(사이안화나트륨) 다만, 베를린청(…) … 제외`). 검색은 `name` 전체도 대상에 넣는 것이 안전하다.
- **기기 확인 절차** = `lib/dev/parse_check_main.dart` 머리 주석. 웹은 2026-09-11 통과("일치 1657/1657"). Android는
  실기기 미연결로 대기 — APK: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`(개발 진입점으로 빌드한 것,
  설치 전 LastWriteTime 확인). 통과하면 plan.md 체크박스와 CLAUDE.md '현재 단계'를 완료로.
- 번들 JSON은 `dart run scripts/build_data.dart`. entries가 같으면 파일을 건드리지 않는다(추출일만 바뀌는 diff 방지).
  낡은 번들은 `test/data/bundled_data_test.dart`가 잡는다.
