#!/usr/bin/env bash
# Runs the app with build-time secrets injected from env.json.
# Usage: ./run.sh [extra flutter run args]
#   e.g. ./run.sh -d "iPhone 17 Pro"   or   ./run.sh --release
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f env.json ]]; then
  echo "error: env.json not found. Create it with your API keys, e.g.:" >&2
  echo '  { "GOOGLE_BOOKS_API_KEY": "...", "KAKAO_REST_API_KEY": "..." }' >&2
  exit 1
fi

exec flutter run --dart-define-from-file=env.json "$@"
