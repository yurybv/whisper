#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

repository_root="${WHISPER_REPOSITORY_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
plist="$repository_root/Resources/Info.plist"

case "${1:-}" in
  --check|--configure) mode="$1" ;;
  *) fail "usage: scripts/setup-update-signing.sh --check|--configure" ;;
esac

[ -f "$plist" ] || fail "Resources/Info.plist is missing."

configured_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$plist" 2>/dev/null || true)"
if [ "$mode" = "--check" ] && [ -z "$configured_key" ]; then
  fail "SUPublicEDKey is not configured; run --configure after authorizing the one-time Sparkle key setup."
fi

resolve_key_tool() {
  if [ -n "${WHISPER_SPARKLE_GENERATE_KEYS:-}" ]; then
    printf '%s\n' "$WHISPER_SPARKLE_GENERATE_KEYS"
    return
  fi

  xcodebuild -resolvePackageDependencies -project "$repository_root/Whisper.xcodeproj" -scheme Whisper >/dev/null
  local build_directory derived_data tool
  build_directory="$(
    xcodebuild -project "$repository_root/Whisper.xcodeproj" -scheme Whisper -showBuildSettings \
      | awk -F ' = ' '/^[[:space:]]*BUILD_DIR = / { print $2; exit }'
  )"
  [ -n "$build_directory" ] || fail "Could not locate Xcode derived data for the pinned Sparkle package."
  derived_data="${build_directory%%/Build/Products*}"
  tool="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys"
  [ -x "$tool" ] || fail "Pinned Sparkle 2.10.0 generate_keys tool is unavailable."
  printf '%s\n' "$tool"
}

read_public_key() {
  local tool="$1" output
  output="$("$tool" -p 2>/dev/null || true)"
  printf '%s\n' "$output" | grep -Eo '[A-Za-z0-9+/]{43}=' | head -n 1
}

write_public_key() {
  local key="$1"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $key" "$plist"
}

key_tool="$(resolve_key_tool)"
keychain_key="$(read_public_key "$key_tool" || true)"

if [ -n "$configured_key" ]; then
  [ -n "$keychain_key" ] || fail "The configured Sparkle public key has no matching login-Keychain key."
  [ "$configured_key" = "$keychain_key" ] || fail "Configured SUPublicEDKey conflicts with the login-Keychain key; refusing rotation."
  printf 'Sparkle update signing is configured with the existing local key.\n'
  exit 0
fi

[ "$mode" = "--configure" ] || fail "SUPublicEDKey is not configured; run --configure after authorizing the one-time Sparkle key setup."

generated_output="$("$key_tool" 2>/dev/null)"
generated_key="$(printf '%s\n' "$generated_output" | grep -Eo '[A-Za-z0-9+/]{43}=' | head -n 1)"
[ -n "$generated_key" ] || fail "Pinned Sparkle generate_keys did not return a public EdDSA key."
write_public_key "$generated_key"
printf 'Sparkle update signing is configured with a local Keychain-backed key.\n'
