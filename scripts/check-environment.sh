#!/usr/bin/env bash

set -u

failures=0
manual_actions=0

pass() {
  printf 'PASS  %s\n' "$1"
}

fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

action() {
  printf 'ACTION  %s\n' "$1"
  manual_actions=$((manual_actions + 1))
}

info() {
  printf 'INFO  %s\n' "$1"
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

printf 'Whisper development environment readiness\n\n'

architecture="$(uname -m)"
if [ "$architecture" = "arm64" ]; then
  pass "Architecture: $architecture (Apple Silicon)"
else
  fail "Architecture: $architecture; Apple Silicon arm64 is required"
fi

macos_version="$(sw_vers -productVersion)"
if version_at_least "$macos_version" "15.0"; then
  pass "macOS: $macos_version"
else
  fail "macOS: $macos_version; version 15.0 or newer is required"
fi

developer_directory="$(xcode-select -p 2>/dev/null || true)"
if [ -n "$developer_directory" ]; then
  pass "Xcode developer directory: $developer_directory"
else
  fail "Xcode developer directory is not selected"
fi

xcode_output="$(xcodebuild -version 2>&1 || true)"
xcode_version="$(printf '%s\n' "$xcode_output" | awk '/^Xcode / { print $2; exit }')"
xcode_build="$(printf '%s\n' "$xcode_output" | awk '/^Build version / { print $3; exit }')"
if [ -n "$xcode_version" ] && version_at_least "$xcode_version" "26.6"; then
  pass "Xcode: $xcode_version (build $xcode_build)"
else
  fail "Xcode: ${xcode_version:-unavailable}; version 26.6 or newer is required"
fi

if xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
  pass "Xcode first-launch components are installed"
else
  fail "Xcode first-launch setup is incomplete; run: sudo xcodebuild -runFirstLaunch"
fi

swift_output="$(xcrun swift --version 2>&1 || true)"
swift_version="$(printf '%s\n' "$swift_output" | sed -n 's/.*Apple Swift version \([0-9][^ ]*\).*/\1/p' | head -n 1)"
if [ -n "$swift_version" ] && version_at_least "$swift_version" "6.3"; then
  pass "Swift: $swift_version"
else
  fail "Swift: ${swift_version:-unavailable}; version 6.3 or newer is required"
fi

sdk_version="$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || true)"
sdk_path="$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)"
if [ -n "$sdk_version" ] && version_at_least "$sdk_version" "15.0"; then
  pass "macOS SDK: $sdk_version"
  info "macOS SDK path: $sdk_path"
else
  fail "macOS SDK: ${sdk_version:-unavailable}; version 15.0 or newer is required"
fi

working_brew=""
for brew_candidate in "$(command -v brew 2>/dev/null || true)" /opt/homebrew/bin/brew /usr/local/bin/brew; do
  if [ -n "$brew_candidate" ] && [ -x "$brew_candidate" ] && "$brew_candidate" config >/dev/null 2>&1; then
    working_brew="$brew_candidate"
    break
  fi
done

if [ -n "$working_brew" ]; then
  brew_version="$("$working_brew" --version | awk 'NR == 1 { print $2 }')"
  brew_prefix="$("$working_brew" --prefix)"
  pass "Homebrew: $brew_version at $brew_prefix"
else
  fail "Homebrew is unavailable; install it from https://brew.sh"
fi

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen_path="$(command -v xcodegen)"
  xcodegen_version="$(xcodegen --version 2>/dev/null | sed 's/^Version: //')"
  pass "XcodeGen: $xcodegen_version at $xcodegen_path"
else
  fail "XcodeGen is unavailable"
  if [ -n "$working_brew" ]; then
    action "Install XcodeGen with: $working_brew install xcodegen"
  fi
fi

available_kib="$(df -Pk . | awk 'NR == 2 { print $4 }')"
available_human="$(df -h . | awk 'NR == 2 { print $4 }')"
minimum_kib=$((2 * 1024 * 1024))
if [ "${available_kib:-0}" -ge "$minimum_kib" ]; then
  pass "Workspace disk space: $available_human available"
else
  fail "Workspace disk space: $available_human available; at least 2 GiB is required"
fi

microphone_probe="$(xcrun swift -e '
import AVFoundation

let status = AVCaptureDevice.authorizationStatus(for: .audio)
let statusName: String
switch status {
case .notDetermined: statusName = "not-determined"
case .restricted: statusName = "restricted"
case .denied: statusName = "denied"
case .authorized: statusName = "granted"
@unknown default: statusName = "unknown"
}

let devices = AVCaptureDevice.DiscoverySession(
    deviceTypes: [.microphone],
    mediaType: .audio,
    position: .unspecified
).devices

print("MICROPHONE_PERMISSION=\(statusName)")
print("MICROPHONE_DEVICE_COUNT=\(devices.count)")
for device in devices {
    print("MICROPHONE_DEVICE=\(device.localizedName)")
}
' 2>/dev/null || true)"

microphone_count="$(printf '%s\n' "$microphone_probe" | awk -F= '/^MICROPHONE_DEVICE_COUNT=/ { print $2; exit }')"
microphone_permission="$(printf '%s\n' "$microphone_probe" | awk -F= '/^MICROPHONE_PERMISSION=/ { print $2; exit }')"
if [ "${microphone_count:-0}" -gt 0 ]; then
  pass "Microphone hardware: $microphone_count input device(s)"
  printf '%s\n' "$microphone_probe" | sed -n 's/^MICROPHONE_DEVICE=/INFO  Microphone: /p'
else
  fail "No microphone input device was discovered through AVFoundation"
fi

if [ "$microphone_permission" = "granted" ]; then
  pass "Microphone permission: granted"
else
  action "Microphone permission: ${microphone_permission:-probe-failed}; grant it during onboarding"
fi

screen_probe="$(xcrun swift -e '
import CoreGraphics
import ScreenCaptureKit

print("SCREENCAPTUREKIT=available")
print("SCREEN_RECORDING_PERMISSION=\(CGPreflightScreenCaptureAccess() ? "granted" : "not-granted")")
' 2>/dev/null || true)"

screen_framework="$(printf '%s\n' "$screen_probe" | awk -F= '/^SCREENCAPTUREKIT=/ { print $2; exit }')"
screen_permission="$(printf '%s\n' "$screen_probe" | awk -F= '/^SCREEN_RECORDING_PERMISSION=/ { print $2; exit }')"
if [ "$screen_framework" = "available" ]; then
  pass "ScreenCaptureKit: available"
else
  fail "ScreenCaptureKit could not be imported with the selected SDK"
fi

if [ "$screen_permission" = "granted" ]; then
  pass "Screen Recording permission: granted"
else
  action "Screen Recording permission: ${screen_permission:-probe-failed}; grant it during onboarding"
fi

printf '\nSummary\n'
if [ "$failures" -eq 0 ]; then
  printf 'READY  WH-M1-001 can run on this Mac\n'
  printf 'MANUAL_ACTIONS  %s\n' "$manual_actions"
  exit 0
fi

printf 'NOT_READY  %s required check(s) failed\n' "$failures"
printf 'MANUAL_ACTIONS  %s\n' "$manual_actions"
exit 1
