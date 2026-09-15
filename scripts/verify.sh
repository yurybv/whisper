#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

stage_number=0
stage_total=12

stage() {
  stage_number=$((stage_number + 1))
  printf '\n[%s/%s] %s\n' "$stage_number" "$stage_total" "$1"
}

skip_ui_tests=false
case "${1:-}" in
  "") ;;
  --skip-ui-tests) skip_ui_tests=true ;;
  *) fail "usage: scripts/verify.sh [--skip-ui-tests]" ;;
esac
[ "$#" -le 1 ] || fail "usage: scripts/verify.sh [--skip-ui-tests]"

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="$repository_root/build"
derived_data="$build_root/VerificationDerivedData"
project_path="$repository_root/Whisper.xcodeproj"
destination="platform=macOS"

[ -f "$repository_root/project.yml" ] || fail "project.yml is missing."
[ -x "$repository_root/scripts/check-environment.sh" ] \
  || fail "scripts/check-environment.sh is missing or not executable."
[ -x "$repository_root/scripts/package.sh" ] \
  || fail "scripts/package.sh is missing or not executable."
[ ! -L "$build_root" ] || fail "Refusing a symlinked build directory."
[ ! -L "$project_path" ] || fail "Refusing a symlinked generated project."

cd "$repository_root"

stage "Environment"
for command_name in bash codesign git rg xcodebuild xcodegen; do
  command -v "$command_name" >/dev/null 2>&1 || fail "$command_name is required."
done
"$repository_root/scripts/check-environment.sh"

stage "Clean generated state"
rm -rf "$project_path" "$derived_data"

stage "Project generation"
xcodegen generate --spec project.yml

stage "Repository diff"
git diff --check

stage "Privacy patterns"
if rg --quiet --glob '*.swift' \
  '\b(print|debugPrint|dump|NSLog|os_log|Logger)[[:space:]]*\(' Sources; then
  fail "A runtime logging API is present under Sources; review it for private-data exposure."
fi
if rg --quiet --hidden \
  --glob '!.git/**' \
  --glob '!build/**' \
  --glob '!Tests/**' \
  --glob '!docs/**' \
  'sk-(proj|live)-[A-Za-z0-9_-]{8,}' .; then
  fail "A value matching a live OpenAI credential pattern is present in runtime files."
fi

stage "Shell lint"
if command -v shellcheck >/dev/null 2>&1; then
  while IFS= read -r script_path; do
    shellcheck "$script_path"
  done < <(find scripts Tests/Scripts -type f -name '*.sh' -print | sort)
else
  printf 'SKIP  ShellCheck is unavailable; bash syntax checks remain required.\n'
  while IFS= read -r script_path; do
    bash -n "$script_path"
  done < <(find scripts Tests/Scripts -type f -name '*.sh' -print | sort)
fi

stage "Shell script tests"
while IFS= read -r test_script; do
  bash "$test_script"
done < <(find Tests/Scripts -type f -name '*Tests.sh' -print | sort)

stage "Build for testing"
xcodebuild \
  -project Whisper.xcodeproj \
  -scheme Whisper \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  build-for-testing

stage "Unit tests"
xcodebuild \
  -project Whisper.xcodeproj \
  -scheme Whisper \
  -destination "$destination" \
  -derivedDataPath "$derived_data" \
  test-without-building \
  -only-testing:WhisperTests

if [ "$skip_ui_tests" = true ]; then
  stage "UI tests (skipped: --skip-ui-tests)"
  printf 'SKIP  UI automation is explicitly disabled for this run.\n'
else
  stage "UI tests"
  xcodebuild \
    -project Whisper.xcodeproj \
    -scheme Whisper \
    -destination "$destination" \
    -derivedDataPath "$derived_data" \
    test-without-building \
    -only-testing:WhisperUITests
fi

stage "Release package"
"$repository_root/scripts/package.sh"

stage "Signature verification"
codesign --verify --deep --strict --verbose=2 "$build_root/Whisper.app"

printf '\nPASS  Whisper verification completed.\n'
