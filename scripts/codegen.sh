#!/usr/bin/env bash
# Regenerates Drift/freezed/json code and localizations.
set -euo pipefail
cd "$(dirname "$0")/.."
flutter pub get
dart run build_runner build
flutter gen-l10n
