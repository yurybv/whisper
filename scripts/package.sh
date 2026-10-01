#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

validate_release_version() {
  local candidate="$1"
  local major minor patch component

  [[ "$candidate" =~ ^([0]|[1-9][0-9]*)\.([0]|[1-9][0-9]*)\.([0]|[1-9][0-9]*)$ ]] || return 1
  IFS='.' read -r major minor patch <<< "$candidate"
  for component in "$major" "$minor" "$patch"; do
    if [ "${#component}" -gt 10 ] || { [ "${#component}" -eq 10 ] && [[ "$component" > "2147483647" ]]; }; then
      return 1
    fi
  done
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

release_version="0.0.0"
case "$#" in
  0) ;;
  2)
    [ "$1" = "--release-version" ] || fail "usage: scripts/package.sh [--release-version MAJOR.MINOR.PATCH]"
    validate_release_version "$2" || fail "Invalid release version. Expected MAJOR.MINOR.PATCH with 32-bit decimal components."
    release_version="$2"
    ;;
  *) fail "usage: scripts/package.sh [--release-version MAJOR.MINOR.PATCH]" ;;
esac

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

[ -f "$repository_root/scripts/local-signing-identity.sh" ] \
  || fail "Local signing identity helper is missing."
# shellcheck source=scripts/local-signing-identity.sh
source "$repository_root/scripts/local-signing-identity.sh"
login_keychain="$(whisper_login_keychain)" \
  || fail "The login Keychain is unavailable."
signing_fingerprint="$(whisper_resolve_signing_identity "$login_keychain")" || exit 1

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

bundle_plist="$output_app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $release_version" "$bundle_plist" \
  || fail "Could not set packaged short version."
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $release_version" "$bundle_plist" \
  || fail "Could not set packaged build version."

bundle_identifier="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$bundle_plist" 2>/dev/null || true)"
[ "$bundle_identifier" = "dev.yury.whisper" ] \
  || fail "Unexpected bundle identifier: ${bundle_identifier:-missing}."

executable="$output_app/Contents/MacOS/Whisper"
[ -x "$executable" ] || fail "Whisper executable is missing."
[ "$(lipo -archs "$executable")" = "arm64" ] \
  || fail "Packaged executable is not arm64-only."

printf 'Applying stable local signature...\n'
codesign --force --deep --sign "$signing_fingerprint" --keychain "$login_keychain" --timestamp=none "$output_app"
codesign --verify --deep --strict --verbose=2 "$output_app"

signature_details="$(codesign --display --verbose=4 "$output_app" 2>&1)" \
  || fail "Cannot inspect the packaged signature."
case "$signature_details" in
  *'Signature=adhoc'*) fail "Packaged app still has an ad-hoc signature." ;;
esac
printf '%s\n' "$signature_details" | grep -Fx "Authority=$whisper_signing_name" >/dev/null \
  || fail "Packaged app was not signed by $whisper_signing_name."
requirement="$(codesign --display --requirements - "$output_app" 2>&1)" \
  || fail "Packaged app has no designated requirement."
case "$requirement" in
  *'designated =>'*'identifier "dev.yury.whisper"'*) ;;
  *) fail "Packaged app has an unexpected designated requirement." ;;
esac
printf '%s\n' "$requirement" | grep -Fi "certificate leaf = H\"$signing_fingerprint\"" >/dev/null \
  || fail "Packaged app has a designated requirement for a different certificate."

printf 'Packaged Whisper.app version %s: %s\n' "$release_version" "$output_app"
