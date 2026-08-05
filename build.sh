#!/usr/bin/env bash
# Builds the app with build-time secrets injected from env.json.
# Usage: ./build.sh <target> [extra flutter build args]
#   e.g. ./build.sh ios --release      or   ./build.sh apk --release
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -lt 1 ]]; then
  echo "usage: ./build.sh <target> [extra flutter build args]" >&2
  echo "  e.g. ./build.sh ios --release" >&2
  exit 1
fi

if [[ ! -f env.json ]]; then
  echo "error: env.json not found. Create it with your API keys, e.g.:" >&2
  echo '  { "GOOGLE_BOOKS_API_KEY": "...", "KAKAO_REST_API_KEY": "..." }' >&2
  exit 1
fi

exec flutter build "$@" --dart-define-from-file=env.json
