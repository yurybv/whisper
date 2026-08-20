#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

version_at_least() {
  awk -v current="$1" -v minimum="$2" 'BEGIN {
    split(current, actual, ".")
    split(minimum, required, ".")
    for (part = 1; part <= 4; part++) {
      actualPart = actual[part] + 0
      requiredPart = required[part] + 0
      if (actualPart > requiredPart) exit 0
      if (actualPart < requiredPart) exit 1
    }
    exit 0
  }'
}

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

[ "$(uname -m)" = "arm64" ] || fail "Apple Silicon (arm64) is required."

xcode_output="$(xcodebuild -version 2>&1 || true)"
xcode_version="$(printf '%s\n' "$xcode_output" | awk '/^Xcode / { print $2; exit }')"
[ -n "$xcode_version" ] && version_at_least "$xcode_version" "26.6" \
  || fail "Xcode 26.6 or newer is required."

sdk_version="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
[ -n "$sdk_version" ] && version_at_least "$sdk_version" "15.0" \
  || fail "The macOS 15 SDK or newer is required."

if ! command -v xcodegen >/dev/null 2>&1; then
  working_brew=""
  for brew_candidate in "$(command -v brew 2>/dev/null || true)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [ -n "$brew_candidate" ] && [ -x "$brew_candidate" ] && "$brew_candidate" config >/dev/null 2>&1; then
      working_brew="$brew_candidate"
      break
    fi
  done
  [ -n "$working_brew" ] \
    || fail "XcodeGen is unavailable and a working Homebrew installation is required to install it."
  "$working_brew" install xcodegen
fi

cd "$repository_root"
xcodegen generate --spec project.yml
printf '%s\n' 'Generated Whisper.xcodeproj'
printf '%s\n' 'Run: xcodebuild -project Whisper.xcodeproj -scheme Whisper -destination "platform=macOS" build'
