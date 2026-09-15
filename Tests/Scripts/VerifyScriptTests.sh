#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
verify_script="$repository_root/scripts/verify.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

pass() {
  printf 'PASS  %s\n' "$1"
}

write_command() {
  local path="$1"
  local body="$2"
  printf '#!/usr/bin/env bash\n%s\n' "$body" > "$path"
  chmod +x "$path"
}

[ -x "$verify_script" ] || fail "scripts/verify.sh must exist and be executable"

fixture_root="$test_root/repository"
mock_bin="$test_root/bin"
mkdir -p "$fixture_root/scripts" "$fixture_root/Sources" "$fixture_root/Tests/Scripts" "$mock_bin"
cp "$verify_script" "$fixture_root/scripts/verify.sh"
touch "$fixture_root/project.yml" "$fixture_root/Sources/Placeholder.swift"

export VERIFY_TEST_LOG="$test_root/commands.log"
: > "$VERIFY_TEST_LOG"

write_command "$fixture_root/scripts/check-environment.sh" "printf 'environment ready\\n'"
write_command "$fixture_root/scripts/package.sh" "mkdir -p \"\$(cd \"\$(dirname \"\${BASH_SOURCE[0]}\")/..\" && pwd)/build/Whisper.app\"; printf 'package\\n' >> \"\$VERIFY_TEST_LOG\""
write_command "$fixture_root/Tests/Scripts/FixtureTests.sh" "printf 'shell-test\\n' >> \"\$VERIFY_TEST_LOG\""
write_command "$mock_bin/git" "exit 0"
write_command "$mock_bin/xcodegen" "printf 'xcodegen\\n' >> \"\$VERIFY_TEST_LOG\""
write_command "$mock_bin/xcodebuild" "printf 'xcodebuild %s\\n' \"\$*\" >> \"\$VERIFY_TEST_LOG\""
write_command "$mock_bin/codesign" "printf 'codesign %s\\n' \"\$*\" >> \"\$VERIFY_TEST_LOG\""

full_output="$test_root/full.log"
PATH="$mock_bin:$PATH" "$fixture_root/scripts/verify.sh" > "$full_output" 2>&1 \
  || fail "full verification fixture unexpectedly failed"

for stage in \
  "Environment" \
  "Clean generated state" \
  "Project generation" \
  "Repository diff" \
  "Privacy patterns" \
  "Shell script tests" \
  "Build for testing" \
  "Unit tests" \
  "UI tests" \
  "Release package" \
  "Signature verification"; do
  grep -F "$stage" "$full_output" >/dev/null || fail "missing stage output: $stage"
done
grep -F -- "-only-testing:WhisperTests" "$VERIFY_TEST_LOG" >/dev/null \
  || fail "unit tests were not selected"
grep -F -- "-only-testing:WhisperUITests" "$VERIFY_TEST_LOG" >/dev/null \
  || fail "UI tests were not selected"
grep -F "shell-test" "$VERIFY_TEST_LOG" >/dev/null || fail "shell tests were not run"
grep -F "package" "$VERIFY_TEST_LOG" >/dev/null || fail "package stage was not run"
grep -F "codesign" "$VERIFY_TEST_LOG" >/dev/null || fail "signature stage was not run"
pass "required stages run and are named"

: > "$VERIFY_TEST_LOG"
skip_output="$test_root/skip-ui.log"
PATH="$mock_bin:$PATH" "$fixture_root/scripts/verify.sh" --skip-ui-tests > "$skip_output" 2>&1 \
  || fail "verification with explicit UI exception unexpectedly failed"
grep -F "UI tests (skipped: --skip-ui-tests)" "$skip_output" >/dev/null \
  || fail "UI-test exception was not explicit"
if grep -F -- "-only-testing:WhisperUITests" "$VERIFY_TEST_LOG" >/dev/null; then
  fail "UI tests ran despite --skip-ui-tests"
fi
pass "UI-test exception is explicit and scoped"

write_command "$mock_bin/xcodegen" "exit 29"
: > "$VERIFY_TEST_LOG"
failure_output="$test_root/failure.log"
if PATH="$mock_bin:$PATH" "$fixture_root/scripts/verify.sh" --skip-ui-tests > "$failure_output" 2>&1; then
  fail "verification continued after a required stage failed"
fi
if grep -F "package" "$VERIFY_TEST_LOG" >/dev/null; then
  fail "package ran after project generation failed"
fi
pass "required-stage failure stops verification"

write_command "$mock_bin/xcodegen" "exit 0"
printf 'print("private fixture")\n' > "$fixture_root/Sources/Placeholder.swift"
privacy_output="$test_root/privacy.log"
if PATH="$mock_bin:$PATH" "$fixture_root/scripts/verify.sh" --skip-ui-tests > "$privacy_output" 2>&1; then
  fail "runtime logging pattern unexpectedly passed"
fi
grep -F "runtime logging API" "$privacy_output" >/dev/null \
  || fail "privacy rejection did not explain the logging risk"
pass "runtime logging pattern fails verification"

usage_output="$test_root/usage.log"
if PATH="$mock_bin:$PATH" "$fixture_root/scripts/verify.sh" --unknown > "$usage_output" 2>&1; then
  fail "unknown option unexpectedly succeeded"
fi
grep -F "usage: scripts/verify.sh [--skip-ui-tests]" "$usage_output" >/dev/null \
  || fail "unknown option did not print usage"
pass "unknown option is rejected"
