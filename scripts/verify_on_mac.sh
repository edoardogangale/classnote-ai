#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
python3 scripts/check_project.py
swift test --package-path Packages/ClassNoteCore
xcodebuild -project ClassNoteAI.xcodeproj -scheme ClassNoteAI -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
if [[ -n "${CLASSNOTE_TEST_DESTINATION:-}" ]]; then
  xcodebuild -project ClassNoteAI.xcodeproj -scheme ClassNoteAI -destination "$CLASSNOTE_TEST_DESTINATION" CODE_SIGNING_ALLOWED=NO test
else
  echo 'App compiled. To run Apple integration tests, set CLASSNOTE_TEST_DESTINATION to an installed iPad simulator destination.'
fi
