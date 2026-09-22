#!/usr/bin/env bash

whisper_signing_name='Whisper Local Development'

whisper_login_keychain() {
  local keychain
  keychain="$(security login-keychain 2>/dev/null)" || return 1
  keychain="${keychain#"${keychain%%[![:space:]]*}"}"
  keychain="${keychain%"${keychain##*[![:space:]]}"}"
  keychain="${keychain#\"}"
  keychain="${keychain%\"}"
  [ -n "$keychain" ] && [ -f "$keychain" ] || return 1
  printf '%s\n' "$keychain"
}

whisper_valid_signing_fingerprints() {
  local keychain="$1"
  local identities
  identities="$(security find-identity -v -p codesigning "$keychain" 2>/dev/null)" || return 1
  printf '%s\n' "$identities" | awk -v expected="\"$whisper_signing_name\"" '
    $2 ~ /^[[:xdigit:]]+$/ && length($2) == 40 {
      label = $0
      sub(/^[[:space:]]*[0-9]+\)[[:space:]]+[[:xdigit:]]+[[:space:]]+/, "", label)
      if (label == expected) print $2
    }
  '
}

whisper_resolve_signing_identity() {
  local keychain="$1"
  local fingerprints
  local count
  fingerprints="$(whisper_valid_signing_fingerprints "$keychain")" || {
    printf 'error: Cannot inspect code-signing identities in the login Keychain.\n' >&2
    return 1
  }
  count="$(printf '%s\n' "$fingerprints" | awk 'NF { count++ } END { print count + 0 }')"
  case "$count" in
    1) printf '%s\n' "$fingerprints" ;;
    0)
      printf 'error: %s signing identity is missing or invalid. Run ./scripts/setup-local-signing.sh.\n' "$whisper_signing_name" >&2
      return 1
      ;;
    *)
      printf 'error: Multiple valid %s signing identities exist. Resolve the duplicate certificates before packaging.\n' "$whisper_signing_name" >&2
      return 1
      ;;
  esac
}
