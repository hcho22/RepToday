#!/bin/bash
# Offline selected-candidate gate. No native production entry, credentials or live requests.
set -euo pipefail
repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)
cd "$repo_root"
node tools/coach-tail-ready.cjs --self-check
node tools/test-coach-tail-ready.cjs
python3 tools/test-coach-capture-guard-tail.py
bash -n tools/migrate-coach-runtime.sh
node --check tools/coach-runtime-migrate.mjs
(
  cd proxy
  npm run typecheck
  npm test
  npm run test:runtime
)
bash tools/test-coach-runtime-migration.sh
git diff --check
