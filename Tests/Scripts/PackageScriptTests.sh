#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
package_script="$repository_root/scripts/package.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

write_command() {
  local path="$1"
  local body="$2"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$path"
  chmod +x "$path"
}

expect_rejection() {
  local name="$1"
  local expected="$2"
  local mock_bin="$3"
  local output="$test_root/$name.log"

  if PATH="$mock_bin:$PATH" "$package_script" >"$output" 2>&1; then
    fail "$name unexpectedly succeeded"
  fi
  grep -F "$expected" "$output" >/dev/null || fail "$name did not explain the rejection"
  printf 'PASS  %s\n' "$name"
}

[ -x "$package_script" ] || fail "scripts/package.sh must exist and be executable"

architecture_bin="$test_root/architecture-bin"
mkdir -p "$architecture_bin"
write_command "$architecture_bin/uname" "printf 'x86_64\\n'"
expect_rejection "unsupported architecture" "Apple Silicon (arm64) is required." "$architecture_bin"

xcode_bin="$test_root/xcode-bin"
mkdir -p "$xcode_bin"
write_command "$xcode_bin/xcodebuild" "printf 'Xcode 25.4\\nBuild version TEST\\n'"
expect_rejection "unsupported Xcode" "Xcode 26.6 or newer is required." "$xcode_bin"

sdk_bin="$test_root/sdk-bin"
mkdir -p "$sdk_bin"
write_command "$sdk_bin/xcrun" "printf '14.5\\n'"
expect_rejection "unsupported SDK" "The macOS 15 SDK or newer is required." "$sdk_bin"

symlink_root="$test_root/symlink-package"
symlink_bin="$test_root/symlink-bin"
outside_build="$test_root/outside-build"
mkdir -p "$symlink_root/scripts" "$symlink_bin" "$outside_build"
cp "$package_script" "$symlink_root/scripts/package.sh"
touch "$symlink_root/project.yml"
ln -s "$outside_build" "$symlink_root/build"
write_command "$symlink_bin/uname" "printf 'arm64\\n'"
write_command "$symlink_bin/xcodebuild" "if [ \"\${1:-}\" = '-version' ]; then printf 'Xcode 26.6\\nBuild version TEST\\n'; fi"
write_command "$symlink_bin/xcrun" "printf '26.5\\n'"
for command_name in xcodegen codesign ditto lipo; do
  write_command "$symlink_bin/$command_name" "exit 0"
done
if PATH="$symlink_bin:$PATH" "$symlink_root/scripts/package.sh" >"$test_root/symlink.log" 2>&1; then
  fail "symlinked build directory unexpectedly succeeded"
fi
grep -F "Refusing a symlinked build directory." "$test_root/symlink.log" >/dev/null \
  || fail "symlinked build directory did not explain the rejection"
printf 'PASS  symlinked build directory\n'

missing_identity_root="$test_root/missing-identity-package"
missing_identity_bin="$test_root/missing-identity-bin"
mkdir -p "$missing_identity_root/scripts" "$missing_identity_root/build/Whisper.app" "$missing_identity_bin"
cp "$package_script" "$missing_identity_root/scripts/package.sh"
cp "$repository_root/scripts/local-signing-identity.sh" "$missing_identity_root/scripts/local-signing-identity.sh"
touch "$missing_identity_root/project.yml"
touch "$test_root/login.keychain-db"
touch "$missing_identity_root/build/Whisper.app/preserved"
write_command "$missing_identity_bin/uname" "printf 'arm64\\n'"
write_command "$missing_identity_bin/xcodebuild" "if [ \"\${1:-}\" = '-version' ]; then printf 'Xcode 26.6\\nBuild version TEST\\n'; fi"
write_command "$missing_identity_bin/xcrun" "printf '26.5\\n'"
write_command "$missing_identity_bin/security" "if [ \"\${1:-}\" = 'login-keychain' ]; then printf '%s\\n' '$test_root/login.keychain-db'; else printf '  0 valid identities found\\n'; fi"
write_command "$missing_identity_bin/xcodegen" "touch '$test_root/unexpected-project-generation'; exit 1"
for command_name in codesign ditto lipo; do
  write_command "$missing_identity_bin/$command_name" "exit 0"
done
if PATH="$missing_identity_bin:$PATH" "$missing_identity_root/scripts/package.sh" >"$test_root/missing-identity.log" 2>&1; then
  fail "missing signing identity unexpectedly succeeded"
fi
grep -F "Whisper Local Development signing identity is missing" "$test_root/missing-identity.log" >/dev/null \
  || fail "missing identity did not explain the rejection"
[ -f "$missing_identity_root/build/Whisper.app/preserved" ] \
  || fail "missing identity removed the previous package"
[ ! -e "$test_root/unexpected-project-generation" ] \
  || fail "missing identity generated the project"
printf 'PASS  missing signing identity preserves previous package\n'
