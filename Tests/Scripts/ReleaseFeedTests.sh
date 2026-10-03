#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
manifest_source="$repository_root/scripts/release-manifest.swift"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/whisper-release-feed.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

expect_failure() {
  local name="$1"
  local expected="$2"
  shift 2
  if "$@" >"$test_root/$name.log" 2>&1; then
    fail "$name unexpectedly succeeded"
  fi
  grep -F "$expected" "$test_root/$name.log" >/dev/null \
    || fail "$name did not explain the rejection"
  printf 'PASS  %s\n' "$name"
}

[ -f "$manifest_source" ] || fail "scripts/release-manifest.swift must exist"
xcrun swiftc "$manifest_source" -o "$test_root/release-manifest"

archive="$test_root/Whisper-1.0.1.zip"
printf 'synthetic signed update archive\n' >"$archive"

cat >"$test_root/SignFixture.swift" <<'SWIFT'
import CryptoKit
import Foundation

let archive = URL(fileURLWithPath: CommandLine.arguments[1])
let data = try Data(contentsOf: archive)
let key = Curve25519.Signing.PrivateKey()
print(key.publicKey.rawRepresentation.base64EncodedString())
print(try key.signature(for: data).base64EncodedString())
SWIFT
xcrun swiftc "$test_root/SignFixture.swift" -o "$test_root/sign-fixture"
fixture_output="$("$test_root/sign-fixture" "$archive")"
public_key="$(printf '%s\n' "$fixture_output" | sed -n '1p')"
signature="$(printf '%s\n' "$fixture_output" | sed -n '2p')"
archive_size="$(stat -f %z "$archive")"

plist="$test_root/Info.plist"
plutil -create xml1 "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.yury.whisper' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 1.0.1' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1.0.1' "$plist"
/usr/libexec/PlistBuddy -c 'Add :SUFeedURL string https://github.com/yurybv/whisper/releases/latest/download/appcast.xml' "$plist"
/usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $public_key" "$plist"

write_appcast() {
  local output="$1"
  local url="$2"
  local length="$3"
  local version="$4"
  local ed_signature="$5"
  cat >"$output" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
  <channel><item>
    <title>Whisper $version</title>
    <sparkle:version>$version</sparkle:version>
    <sparkle:shortVersionString>$version</sparkle:shortVersionString>
    <description><![CDATA[Synthetic notes]]></description>
    <enclosure url="$url" length="$length" type="application/octet-stream" sparkle:edSignature="$ed_signature" />
  </item></channel>
</rss>
XML
}

appcast="$test_root/appcast.xml"
expected_url='https://github.com/yurybv/whisper/releases/download/v1.0.1/Whisper-1.0.1.zip'
write_appcast "$appcast" "$expected_url" "$archive_size" '1.0.1' "$signature"

"$test_root/release-manifest" verify-feed \
  --appcast "$appcast" \
  --archive "$archive" \
  --bundle-plist "$plist" \
  --public-key "$public_key" \
  --version '1.0.1'
printf 'PASS  valid signed feed and bundle metadata\n'

printf 'tampered\n' >>"$archive"
expect_failure 'tampered archive' 'EdDSA signature verification failed' \
  "$test_root/release-manifest" verify-feed --appcast "$appcast" --archive "$archive" \
  --bundle-plist "$plist" --public-key "$public_key" --version '1.0.1'
printf 'synthetic signed update archive\n' >"$archive"

wrong_key_output="$("$test_root/sign-fixture" "$archive")"
wrong_key="$(printf '%s\n' "$wrong_key_output" | sed -n '1p')"
expect_failure 'wrong public key' 'configured public key does not match the bundle' \
  "$test_root/release-manifest" verify-feed --appcast "$appcast" --archive "$archive" \
  --bundle-plist "$plist" --public-key "$wrong_key" --version '1.0.1'

write_appcast "$test_root/wrong-url.xml" 'https://example.invalid/Whisper-1.0.1.zip' "$archive_size" '1.0.1' "$signature"
expect_failure 'wrong enclosure URL' 'unexpected enclosure URL' \
  "$test_root/release-manifest" verify-feed --appcast "$test_root/wrong-url.xml" --archive "$archive" \
  --bundle-plist "$plist" --public-key "$public_key" --version '1.0.1'

write_appcast "$test_root/wrong-version.xml" "$expected_url" "$archive_size" '1.0.2' "$signature"
expect_failure 'wrong feed version' 'feed versions do not match the release' \
  "$test_root/release-manifest" verify-feed --appcast "$test_root/wrong-version.xml" --archive "$archive" \
  --bundle-plist "$plist" --public-key "$public_key" --version '1.0.1'

write_appcast "$test_root/wrong-length.xml" "$expected_url" '1' '1.0.1' "$signature"
expect_failure 'wrong enclosure length' 'enclosure length does not match the archive' \
  "$test_root/release-manifest" verify-feed --appcast "$test_root/wrong-length.xml" --archive "$archive" \
  --bundle-plist "$plist" --public-key "$public_key" --version '1.0.1'

sed 's#</item>#<enclosure url="https://example.invalid/extra.zip" length="1" /></item>#' \
  "$appcast" >"$test_root/multiple-enclosures.xml"
expect_failure 'multiple feed enclosures' 'appcast XML is malformed' \
  "$test_root/release-manifest" verify-feed --appcast "$test_root/multiple-enclosures.xml" --archive "$archive" \
  --bundle-plist "$plist" --public-key "$public_key" --version '1.0.1'

sed 's#</item>#<sparkle:releaseNotesLink>https://example.invalid/missing.md</sparkle:releaseNotesLink></item>#' \
  "$appcast" >"$test_root/external-notes.xml"
expect_failure 'external release notes' 'appcast XML is malformed' \
  "$test_root/release-manifest" verify-feed --appcast "$test_root/external-notes.xml" --archive "$archive" \
  --bundle-plist "$plist" --public-key "$public_key" --version '1.0.1'

printf '<rss>' >"$test_root/malformed.xml"
expect_failure 'malformed feed' 'appcast XML is malformed' \
  "$test_root/release-manifest" verify-feed --appcast "$test_root/malformed.xml" --archive "$archive" \
  --bundle-plist "$plist" --public-key "$public_key" --version '1.0.1'

staging="$test_root/staging"
mkdir -p "$staging/artifacts"
cp "$archive" "$staging/artifacts/Whisper-1.0.1.zip"
cp "$appcast" "$staging/artifacts/appcast.xml"
printf '%s\n' 'Release WH-M7-003 with synthetic verification evidence.' >"$staging/release-notes.md"
source_sha='1111111111111111111111111111111111111111'
base_sha='0000000000000000000000000000000000000000'
signing_fingerprint='2222222222222222222222222222222222222222'
public_key_fingerprint='3333333333333333333333333333333333333333333333333333333333333333'

"$test_root/release-manifest" write \
  --staging-dir "$staging" \
  --task-id 'WH-M7-003' \
  --source-sha "$source_sha" \
  --base-tag 'v1.0.0' \
  --base-sha "$base_sha" \
  --version '1.0.1' \
  --bootstrap-phase 'none' \
  --verification-source './scripts/verify.sh' \
  --verification-evidence 'canonical gate passed' \
  --signing-fingerprint "$signing_fingerprint" \
  --public-key-fingerprint "$public_key_fingerprint" \
  --zip-relative 'artifacts/Whisper-1.0.1.zip' \
  --appcast-relative 'artifacts/appcast.xml' \
  --release-notes-relative 'release-notes.md' \
  --commit "$source_sha:task" \
  --commit '4444444444444444444444444444444444444444:closure'

local_manifest="$staging/release-manifest.local.json"
public_manifest="$staging/artifacts/release-manifest.json"
[ -f "$local_manifest" ] || fail "local manifest was not written"
[ -f "$public_manifest" ] || fail "public manifest was not written"
if grep -F "$staging" "$public_manifest" >/dev/null; then
  fail "public manifest exposed its local staging path"
fi
"$test_root/release-manifest" validate \
  --manifest "$local_manifest" \
  --staging-dir "$staging" \
  --signing-fingerprint "$signing_fingerprint" \
  --public-key-fingerprint "$public_key_fingerprint"
[ "$("$test_root/release-manifest" field --manifest "$local_manifest" --name version)" = '1.0.1' ] \
  || fail "manifest field lookup returned the wrong version"
printf 'PASS  typed local and sanitized public manifests\n'

cp "$local_manifest" "$test_root/path-escape.json"
plutil -replace artifacts.0.path -string '../outside.zip' "$test_root/path-escape.json"
expect_failure 'manifest path escape' 'artifact path must remain inside the staging directory' \
  "$test_root/release-manifest" validate --manifest "$test_root/path-escape.json" \
  --staging-dir "$staging" --signing-fingerprint "$signing_fingerprint" \
  --public-key-fingerprint "$public_key_fingerprint"

expect_failure 'changed signing identity' 'signing identity fingerprint changed' \
  "$test_root/release-manifest" validate --manifest "$local_manifest" \
  --staging-dir "$staging" --signing-fingerprint '5555555555555555555555555555555555555555' \
  --public-key-fingerprint "$public_key_fingerprint"
expect_failure 'changed update key' 'update public-key fingerprint changed' \
  "$test_root/release-manifest" validate --manifest "$local_manifest" \
  --staging-dir "$staging" --signing-fingerprint "$signing_fingerprint" \
  --public-key-fingerprint '6666666666666666666666666666666666666666666666666666666666666666'

printf 'tamper\n' >>"$staging/artifacts/Whisper-1.0.1.zip"
expect_failure 'changed prepared artifact' 'artifact digest or size changed' \
  "$test_root/release-manifest" validate --manifest "$local_manifest" \
  --staging-dir "$staging" --signing-fingerprint "$signing_fingerprint" \
  --public-key-fingerprint "$public_key_fingerprint"

printf '{}\n' >"$test_root/malformed-manifest.json"
expect_failure 'malformed manifest' 'release manifest is incomplete or unsupported' \
  "$test_root/release-manifest" validate --manifest "$test_root/malformed-manifest.json" \
  --staging-dir "$staging" --signing-fingerprint "$signing_fingerprint" \
  --public-key-fingerprint "$public_key_fingerprint"
