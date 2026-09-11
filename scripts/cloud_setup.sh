#!/bin/bash
# Claude Code 클라우드 세션(claude.ai/code) 환경의 Setup script — 원본은 이 파일이다.
# 이 파일 전체를 환경 설정 대화상자의 "Setup script" 칸에 붙여 넣는다. 환경은 웹 화면에서만
# 만들 수 있고 저장소 파일을 읽어 가지 않으므로, **이 파일을 고치면 칸에도 다시 붙여 넣는다.**
#
# 전제 (2026-09-11 문서 확인, code.claude.com/docs/en/cloud-environments):
# - root로, Ubuntu 24.04 x86_64에서 돈다. 약 5분 안에 끝나야 하고, 0이 아니면 세션이 뜨지 않는다.
# - 결과는 파일시스템 스냅숏으로 약 7일 캐시된다. 이 스크립트나 허용 도메인을 바꾸면 다시 돈다.
# - 네트워크 등급은 Trusted면 된다(storage.googleapis.com·pub.dev 허용).
# - Android SDK는 설치하지 않는다. dl.google.com·maven.google.com이 Trusted에 없고, APK 빌드는
#   로컬 PC에서 한다. 클라우드에서는 analyze·test·웹 빌드까지 한다.
set -euo pipefail

FLUTTER_VERSION=3.35.6   # 로컬 PC와 같은 버전 (flutter --version, revision 9f455d2486)
FLUTTER_SHA256=87493b72916f12054176c2a8bbf9547fe63cb5754bdddfe300219d9b57e626af  # releases_linux.json
FLUTTER_URL="https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz"

# 1) 훅(.claude/settings.json)은 `python`으로 불린다. 이 명령이 없으면 훅이 실행에 실패하고
#    하네스는 막지 않고 통과시켜 훅 4개가 조용히 꺼진다(hook_io.py의 2026-08-22 사고와 같은 모양).
#    Ubuntu는 python3만 두는 것이 기본이라 python으로도 부를 수 있게 한다.
if ! command -v python >/dev/null; then
  ln -s "$(command -v python3)" /usr/local/bin/python
fi
python --version

# 2) Flutter SDK — 해시가 다르면 sha256sum이 실패해 세션이 뜨지 않는다(받은 실행물을 검증 없이 쓰지 않는다).
if [ ! -x /opt/flutter/bin/flutter ]; then
  tarball=/tmp/flutter.tar.xz
  curl -fsSL -o "$tarball" "$FLUTTER_URL"
  echo "${FLUTTER_SHA256}  ${tarball}" | sha256sum -c -
  tar --no-same-owner -xJf "$tarball" -C /opt
  rm -f "$tarball"
fi
# flutter는 SDK 자체가 git 저장소라 소유자가 실행 사용자와 다르면 git이 버전을 못 읽는다.
# 세션 사용자가 root가 아닐 수 있으므로(문서에 없음) 첫 flutter 실행 전에 연다.
git config --system --add safe.directory /opt/flutter
ln -sf /opt/flutter/bin/flutter /usr/local/bin/flutter
ln -sf /opt/flutter/bin/dart /usr/local/bin/dart

flutter --disable-analytics
flutter precache --web

# 세션 사용자가 root가 아니면 flutter가 bin/cache에 쓰지 못한다 — precache가 만든 파일까지 포함하도록 맨 뒤에서.
chmod -R a+rwX /opt/flutter
flutter --version
