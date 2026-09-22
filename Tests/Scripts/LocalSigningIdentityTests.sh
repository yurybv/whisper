#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

mock_bin="$test_root/bin"
mkdir -p "$mock_bin"
touch "$test_root/login.keychain-db"

printf '#!/usr/bin/env bash\n' > "$mock_bin/security"
printf 'if [ "$1" = "login-keychain" ]; then printf "    \\"%s\\"\\n" "%s"; exit 0; fi\n' "$test_root/login.keychain-db" >> "$mock_bin/security"
printf 'if [ "$1" = "find-identity" ]; then printf "%%s\\n" "$MOCK_IDENTITIES"; exit 0; fi\n' >> "$mock_bin/security"
printf 'if [ "$1" = "find-certificate" ]; then printf "%%s\\n" "${MOCK_CERTIFICATES:-}"; exit 0; fi\n' >> "$mock_bin/security"
printf 'exit 1\n' >> "$mock_bin/security"
chmod +x "$mock_bin/security"

fingerprint_a='0123456789ABCDEF0123456789ABCDEF01234567'
fingerprint_b='89ABCDEF0123456789ABCDEF0123456789ABCDEF'

MOCK_IDENTITIES="  1) $fingerprint_a \"Whisper Local Development\"
     1 valid identities found" \
  PATH="$mock_bin:$PATH" \
  bash -c 'source "$1"; keychain="$(whisper_login_keychain)"; whisper_resolve_signing_identity "$keychain"' \
  bash "$repository_root/scripts/local-signing-identity.sh" > "$test_root/one.log"
[ "$(<"$test_root/one.log")" = "$fingerprint_a" ] || fail "single identity was not resolved exactly"
printf 'PASS  exact valid identity\n'

MOCK_IDENTITIES="  1) $fingerprint_a \"Whisper Local Development\"
  2) $fingerprint_b \"Whisper Local Development\"
     2 valid identities found" \
  PATH="$mock_bin:$PATH" \
  bash -c 'source "$1"; keychain="$(whisper_login_keychain)"; whisper_resolve_signing_identity "$keychain"' \
  bash "$repository_root/scripts/local-signing-identity.sh" > "$test_root/duplicate.log" 2>&1 \
  && fail "duplicate identity was accepted"
grep -F 'Multiple valid Whisper Local Development signing identities exist' "$test_root/duplicate.log" >/dev/null \
  || fail "duplicate identity did not explain rejection"
printf 'PASS  duplicate identity rejected\n'

MOCK_IDENTITIES="  1) $fingerprint_a \"Another Signing Identity\"
     1 valid identities found" \
  PATH="$mock_bin:$PATH" \
  bash -c 'source "$1"; keychain="$(whisper_login_keychain)"; whisper_resolve_signing_identity "$keychain"' \
  bash "$repository_root/scripts/local-signing-identity.sh" > "$test_root/other.log" 2>&1 \
  && fail "unrelated identity was accepted"
grep -F 'Whisper Local Development signing identity is missing' "$test_root/other.log" >/dev/null \
  || fail "unrelated identity did not explain rejection"
printf 'PASS  unrelated identity rejected\n'

MOCK_IDENTITIES="  1) $fingerprint_a \"Whisper Local Development\"
     1 valid identities found" \
  PATH="$mock_bin:$PATH" \
  bash "$repository_root/scripts/setup-local-signing.sh" > "$test_root/existing.log" 2>&1 \
  || fail "existing valid identity was not reused"
grep -F 'already available' "$test_root/existing.log" >/dev/null \
  || fail "existing identity did not report reuse"
printf 'PASS  setup reuses existing identity\n'

MOCK_IDENTITIES='  0 valid identities found' \
  MOCK_CERTIFICATES='keychain: /tmp/login.keychain-db' \
  PATH="$mock_bin:$PATH" \
  bash "$repository_root/scripts/setup-local-signing.sh" > "$test_root/conflict.log" 2>&1 \
  && fail "conflicting certificate was replaced"
grep -F 'certificate already exists but no valid signing identity' "$test_root/conflict.log" >/dev/null \
  || fail "conflicting certificate did not explain rejection"
printf 'PASS  setup rejects conflicting certificate\n'
