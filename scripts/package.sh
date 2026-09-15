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

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required."
}

[ "$#" -eq 0 ] || fail "usage: scripts/package.sh"

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="$repository_root/build"
derived_data="$build_root/DerivedData"
product_app="$derived_data/Build/Products/Release/Whisper.app"
output_app="$build_root/Whisper.app"

[ "$(uname -m)" = "arm64" ] || fail "Apple Silicon (arm64) is required."

for command_name in xcodebuild xcrun xcodegen codesign ditto lipo; do
  require_command "$command_name"
done

xcode_output="$(xcodebuild -version 2>&1 || true)"
xcode_version="$(printf '%s\n' "$xcode_output" | awk '/^Xcode / { print $2; exit }')"
[ -n "$xcode_version" ] && version_at_least "$xcode_version" "26.6" \
  || fail "Xcode 26.6 or newer is required."

sdk_version="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
[ -n "$sdk_version" ] && version_at_least "$sdk_version" "15.0" \
  || fail "The macOS 15 SDK or newer is required."

[ -f "$repository_root/project.yml" ] || fail "project.yml is missing."
[ ! -L "$build_root" ] || fail "Refusing a symlinked build directory."
case "$build_root" in
  "$repository_root/build") ;;
  *) fail "Refusing an unexpected build directory." ;;
esac

printf 'Generating project with XcodeGen...\n'
cd "$repository_root"
xcodegen generate --spec project.yml

printf 'Building clean Apple Silicon Release bundle...\n'
rm -rf "$derived_data" "$output_app"
mkdir -p "$build_root"
xcodebuild \
  -project Whisper.xcodeproj \
  -scheme Whisper \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$derived_data" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGNING_ALLOWED=NO \
  build

[ -d "$product_app" ] || fail "Release build did not produce Whisper.app."
ditto "$product_app" "$output_app"

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$output_app/Contents/Info.plist" 2>/dev/null || true)"
[ "$bundle_identifier" = "dev.yury.whisper" ] \
  || fail "Unexpected bundle identifier: ${bundle_identifier:-missing}."

executable="$output_app/Contents/MacOS/Whisper"
[ -x "$executable" ] || fail "Whisper executable is missing."
[ "$(lipo -archs "$executable")" = "arm64" ] \
  || fail "Packaged executable is not arm64-only."

printf 'Applying ad-hoc signature...\n'
codesign --force --deep --sign - --timestamp=none "$output_app"
codesign --verify --deep --strict --verbose=2 "$output_app"

printf 'Packaged Whisper.app: %s\n' "$output_app"
