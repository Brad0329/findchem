#!/usr/bin/env bash
# 클라우드 세션에서 gcloud를 서비스 계정으로 로그인시킨다(A-001 배포용).
# 환경 변수 GCP_SA_KEY_B64(서비스 계정 JSON 키의 base64)·GCP_PROJECT는 클라우드 환경 설정에 있다.
# 키 값은 출력하지 않는다. 키 파일은 저장소 밖(~/.config/findchem/)에 둔다.
set -euo pipefail

if [ -z "${GCP_SA_KEY_B64:-}" ] || [ -z "${GCP_PROJECT:-}" ]; then
  echo "GCP_SA_KEY_B64 또는 GCP_PROJECT가 비었다 — 클라우드 환경 설정에 넣고 새 세션을 연다" >&2
  exit 1
fi

key_dir="$HOME/.config/findchem"
key_file="$key_dir/sa.json"
mkdir -p "$key_dir"
umask 077
printf '%s' "$GCP_SA_KEY_B64" | base64 -d > "$key_file"

# 클라우드 세션 환경이 넣는 CLOUDSDK_AUTH_ACCESS_TOKEN이 서비스 계정을 덮어써 CREDENTIALS_MISSING이 난다(2026-10-02 실측)
# — 이 스크립트 안에서만 뺀다. 다른 gcloud 호출도 `env -u CLOUDSDK_AUTH_ACCESS_TOKEN gcloud ...`로 부른다.
unset CLOUDSDK_AUTH_ACCESS_TOKEN
gcloud auth activate-service-account --key-file="$key_file" --quiet
gcloud config set project "$GCP_PROJECT" --quiet
gcloud config set run/region asia-northeast3 --quiet
echo "gcloud 로그인 완료: $(gcloud config get-value account)"
