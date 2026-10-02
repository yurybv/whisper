#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
setup_script="$repository_root/scripts/setup-update-signing.sh"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/whisper-update-signing.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

make_fixture() {
  fixture_root="$1"
  mkdir -p "$fixture_root/Resources" "$fixture_root/mock-bin"
  cp "$repository_root/Resources/Info.plist" "$fixture_root/Resources/Info.plist"
  /usr/libexec/PlistBuddy -c 'Delete :SUPublicEDKey' "$fixture_root/Resources/Info.plist" \
    >/dev/null 2>&1 || true
  cat >"$fixture_root/mock-bin/xcodebuild" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$fixture_root/mock-bin/xcodebuild"
}

write_key_tool() {
  fixture_root="$1"
  lookup_key="$2"
  generated_key="$3"
  cat >"$fixture_root/mock-bin/generate_keys" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\\n' "\$*" >> "$fixture_root/calls.log"
if [ "\${1:-}" = "-p" ]; then
  [ -n "$lookup_key" ] || exit 1
  printf '%s\\n' "$lookup_key"
  exit 0
fi
printf '%s\\n' "$generated_key"
EOF
  chmod +x "$fixture_root/mock-bin/generate_keys"
}

public_key='abcdefghijklmnopqrstuvwxyzABCDEFGHijklmno0123456789+/'
public_key="${public_key:0:43}="
other_key='ZYXWVUTSRQPONMLKJIHGFEDCBA9876543210abcdefghijklmnopqrs='

[ -x "$setup_script" ] || fail "scripts/setup-update-signing.sh must exist and be executable"

existing_root="$test_root/existing"
make_fixture "$existing_root"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $public_key" "$existing_root/Resources/Info.plist"
write_key_tool "$existing_root" "$public_key" ''
WHISPER_REPOSITORY_ROOT="$existing_root" \
WHISPER_SPARKLE_GENERATE_KEYS="$existing_root/mock-bin/generate_keys" \
PATH="$existing_root/mock-bin:$PATH" \
"$setup_script" --check >"$existing_root/output.log" 2>&1
grep -qx -- '-p' "$existing_root/calls.log" || fail "existing key was not checked"
[ "$(wc -l < "$existing_root/calls.log" | tr -d ' ')" = '1' ] \
  || fail "existing key lookup rotated or regenerated a key"
printf 'PASS  existing matching public key is reused\n'

conflict_root="$test_root/conflict"
make_fixture "$conflict_root"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $other_key" "$conflict_root/Resources/Info.plist"
write_key_tool "$conflict_root" "$public_key" ''
if WHISPER_REPOSITORY_ROOT="$conflict_root" \
  WHISPER_SPARKLE_GENERATE_KEYS="$conflict_root/mock-bin/generate_keys" \
  PATH="$conflict_root/mock-bin:$PATH" \
  "$setup_script" --check >"$conflict_root/output.log" 2>&1; then
  fail "conflicting public key was accepted"
fi
grep -qx -- '-p' "$conflict_root/calls.log" || fail "conflict did not inspect existing key"
[ "$(wc -l < "$conflict_root/calls.log" | tr -d ' ')" = '1' ] \
  || fail "conflicting public key attempted rotation"
printf 'PASS  conflicting public key is rejected without rotation\n'

missing_root="$test_root/missing"
make_fixture "$missing_root"
write_key_tool "$missing_root" '' "$public_key"
if WHISPER_REPOSITORY_ROOT="$missing_root" \
  WHISPER_SPARKLE_GENERATE_KEYS="$missing_root/mock-bin/generate_keys" \
  PATH="$missing_root/mock-bin:$PATH" \
  "$setup_script" --check >"$missing_root/check.log" 2>&1; then
  fail "missing public key passed check mode"
fi
[ ! -f "$missing_root/calls.log" ] || fail "check mode invoked the key tool when configuration was missing"
WHISPER_REPOSITORY_ROOT="$missing_root" \
WHISPER_SPARKLE_GENERATE_KEYS="$missing_root/mock-bin/generate_keys" \
PATH="$missing_root/mock-bin:$PATH" \
"$setup_script" --configure >"$missing_root/configure.log" 2>&1
/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$missing_root/Resources/Info.plist" \
  | grep -Fx "$public_key" >/dev/null || fail "configured public key was not saved"
grep -qx -- '' "$missing_root/calls.log" || fail "missing key was not created exactly once"
if rg -i 'private|secret' "$missing_root/configure.log"; then
  fail "setup output exposed private key material"
fi
printf 'PASS  missing public key requires explicit configuration without secret output\n'
