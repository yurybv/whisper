#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

[ "$#" -eq 0 ] || fail "usage: scripts/setup-local-signing.sh"

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/local-signing-identity.sh
source "$repository_root/scripts/local-signing-identity.sh"

for command_name in security openssl mktemp; do
  command -v "$command_name" >/dev/null 2>&1 || fail "$command_name is required."
done

login_keychain="$(whisper_login_keychain)" || fail "The login Keychain is unavailable."
valid_fingerprints="$(whisper_valid_signing_fingerprints "$login_keychain")" \
  || fail "Cannot inspect code-signing identities in the login Keychain."
valid_count="$(printf '%s\n' "$valid_fingerprints" | awk 'NF { count++ } END { print count + 0 }')"
case "$valid_count" in
  1)
    printf '%s signing identity is already available.\n' "$whisper_signing_name"
    exit 0
    ;;
  0) ;;
  *) fail "Multiple valid $whisper_signing_name signing identities exist. Resolve them before continuing." ;;
esac

existing_certificates="$(security find-certificate -a -c "$whisper_signing_name" -Z "$login_keychain" 2>/dev/null || true)"
if printf '%s\n' "$existing_certificates" | grep -q '^keychain:'; then
  fail "$whisper_signing_name certificate already exists but no valid signing identity is available. Repair that Keychain item instead of replacing it."
fi

umask 077
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/whisper-local-signing.XXXXXX")" \
  || fail "Cannot create a private temporary directory."
trap 'rm -rf -- "$temporary_directory"' EXIT
private_key="$temporary_directory/private-key.pem"
certificate="$temporary_directory/certificate.pem"
archive="$temporary_directory/identity.p12"
archive_password="$(openssl rand -hex 24)" \
  || fail "Cannot create the temporary identity archive password."

printf 'Creating %s in the login Keychain...\n' "$whisper_signing_name"
openssl req -x509 -newkey rsa:3072 -sha256 -days 3650 -noenc \
  -subj "/CN=$whisper_signing_name" \
  -addext 'basicConstraints=critical,CA:TRUE' \
  -addext 'keyUsage=critical,digitalSignature,keyCertSign' \
  -addext 'extendedKeyUsage=codeSigning' \
  -keyout "$private_key" -out "$certificate" >/dev/null 2>&1 \
  || fail "Cannot create the local Code Signing certificate."
openssl pkcs12 -export -inkey "$private_key" -in "$certificate" \
  -out "$archive" -passout "pass:$archive_password" -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES -macalg sha1 >/dev/null 2>&1 \
  || fail "Cannot prepare the local Code Signing identity."

security import "$archive" -k "$login_keychain" -f pkcs12 -P "$archive_password" -x \
  -T /usr/bin/codesign >/dev/null \
  || fail "Cannot import the local Code Signing identity into the login Keychain."
unset archive_password
security add-trusted-cert -r trustRoot -p codeSign -k "$login_keychain" "$certificate" >/dev/null \
  || fail "The identity was imported, but Code Signing trust could not be set. Repair the Keychain entry before retrying."

signing_fingerprint="$(whisper_resolve_signing_identity "$login_keychain")" \
  || fail "The new Code Signing identity is not valid. Repair the Keychain entry before retrying."
printf '%s is ready (certificate SHA-1: %s).\n' "$whisper_signing_name" "$signing_fingerprint"
