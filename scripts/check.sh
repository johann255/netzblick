#!/usr/bin/env bash
# Local equivalent of the CI jobs: kit tests, then the app build for the simulator.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Hinweis: Netzblick braucht macOS mit Xcode. Auf diesem System ($(uname -s)) lässt sich nichts bauen oder testen."
  echo "Die Checks laufen auf einem Mac oder in der CI (.github/workflows/ci.yml)."
  exit 1
fi

echo "==> Kit-Tests (NetzblickKit)"
(cd Packages/NetzblickKit && swift test)

if command -v xcodegen >/dev/null 2>&1; then
  echo "==> Xcode-Projekt generieren"
  xcodegen generate

  echo "==> App für Simulator bauen"
  xcodebuild -project Netzblick.xcodeproj \
    -scheme Netzblick \
    -destination 'generic/platform=iOS Simulator' \
    -configuration Debug \
    build \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    | { command -v xcbeautify >/dev/null 2>&1 && xcbeautify || cat; }
else
  echo "==> xcodegen nicht gefunden, App-Build übersprungen (brew install xcodegen)."
fi

echo "Fertig."
