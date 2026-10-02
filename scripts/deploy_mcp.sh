#!/usr/bin/env bash
# A-001 원격 MCP 서버를 Cloud Run 서울(asia-northeast3)에 배포한다 — 클라우드 세션에서 부른다.
#
#   bash scripts/gcp_auth.sh          # 세션마다 한 번(gcloud 로그인)
#   bash scripts/deploy_mcp.sh        # 컴파일 → 이미지(Cloud Build) → Cloud Run
#   bash scripts/deploy_mcp.sh --stage-only   # build/mcp/ 에 이미지 재료만 만든다(배포 안 함)
#
# 이미지 재료는 build/mcp/(gitignore)에 모은다: 이 컨테이너에서 `dart compile exe`한 실행 파일 + 번들 JSON + Dockerfile.
# 컴파일을 Cloud Build에서 하지 않는 이유: pubspec이 Flutter SDK에 의존해 dart 이미지에서 `pub get`이 안 된다.
#
# CLOUDSDK_AUTH_ACCESS_TOKEN: 클라우드 세션 환경이 넣는 토큰이 서비스 계정 로그인을 덮어써 인증이 실패한다(2026-10-02 실측)
# — gcloud 호출에서만 뺀다.
set -euo pipefail

service="findchem-mcp"
region="asia-northeast3"
stage="build/mcp"

rm -rf "$stage"
mkdir -p "$stage"
dart compile exe scripts/mcp_http_server.dart -o "$stage/server"
cp assets/data/findchem_data.json "$stage/findchem_data.json"
cat > "$stage/Dockerfile" <<'EOF'
# dart 이미지는 /runtime(실행 파일이 쓰는 최소 libc)만 빌려 온다.
FROM dart:stable AS runtime
FROM scratch
COPY --from=runtime /runtime/ /
COPY server /app/server
COPY findchem_data.json /app/findchem_data.json
ENV FINDCHEM_DATA=/app/findchem_data.json
CMD ["/app/server"]
EOF
echo "이미지 재료: $stage ($(du -sh "$stage" | cut -f1))"

if [ "${1:-}" = "--stage-only" ]; then
  exit 0
fi

env -u CLOUDSDK_AUTH_ACCESS_TOKEN gcloud run deploy "$service" \
  --source "$stage" \
  --region "$region" \
  --allow-unauthenticated \
  --min-instances 0 \
  --max-instances 2 \
  --memory 256Mi \
  --cpu 1 \
  --concurrency 40 \
  --timeout 60 \
  --quiet

url="$(env -u CLOUDSDK_AUTH_ACCESS_TOKEN gcloud run services describe "$service" --region "$region" --format='value(status.url)')"
echo "MCP 주소: $url/mcp"
