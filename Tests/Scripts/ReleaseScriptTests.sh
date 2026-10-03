#!/usr/bin/env bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
release_script="$repository_root/scripts/release-local.sh"
manifest_source="$repository_root/scripts/release-manifest.swift"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/whisper-release-script.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT

fail() {
  printf 'FAIL  %s\n' "$1" >&2
  exit 1
}

[ -x "$release_script" ] || fail "scripts/release-local.sh must exist and be executable"
[ -f "$manifest_source" ] || fail "scripts/release-manifest.swift must exist"

make_fixture() {
  local name="$1"
  local task_status="${2:-done}"
  local fixture="$test_root/$name"
  local work="$fixture/work"
  local bare="$fixture/origin.git"
  local mock_bin="$fixture/mock-bin"

  mkdir -p "$work/scripts" "$work/docs/implementation" "$work/Resources" "$mock_bin"
  git init --bare -q "$bare"
  git -C "$work" init -q -b master
  git -C "$work" config user.name 'Release Test'
  git -C "$work" config user.email 'release-test@example.invalid'
  cp "$release_script" "$work/scripts/release-local.sh"
  cp "$manifest_source" "$work/scripts/release-manifest.swift"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$work/scripts/verify.sh"
  printf '#!/usr/bin/env bash\nexit 0\n' >"$work/scripts/package.sh"
  chmod +x "$work/scripts/verify.sh" "$work/scripts/package.sh" "$work/scripts/release-local.sh"
  cat >"$work/docs/implementation/task-backlog.md" <<EOF
| ID | Task | Status | Depends on |
|---|---|---|---|
| WH-M7-001 | First | done | — |
| WH-M7-002 | Second | done | WH-M7-001 |
| WH-M7-003 | Release | $task_status | WH-M7-002 |
| WH-M7-004 | Bootstrap | blocked | WH-M7-003 |
| WH-M7-005 | Guide | blocked | WH-M7-004 |
EOF
  printf 'Fixture roadmap\n' >"$work/docs/implementation/roadmap.md"
  plutil -create xml1 "$work/Resources/Info.plist"
  /usr/libexec/PlistBuddy -c 'Add :SUPublicEDKey string AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=' "$work/Resources/Info.plist"
  printf 'fixture application source\n' >"$work/source.txt"
  git -C "$work" add .
  git -C "$work" commit -q -m 'feat: fixture task'
  git -C "$work" remote add origin 'https://github.com/yurybv/whisper.git'
  git -C "$work" config "url.file://$bare/.insteadOf" 'https://github.com/yurybv/whisper.git'
  git -C "$work" config protocol.file.allow always
  git -C "$work" push -q -u origin master

  cat >"$mock_bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$MOCK_GH_LOG"
mutation() {
  printf '%s\n' "$1" >>"$MOCK_MUTATION_LOG"
  [ "${MOCK_ALLOW_MUTATIONS:-0}" = '1' ] || exit 97
}
fail_after() {
  [ "${MOCK_FAIL_AFTER:-}" != "$1" ] || exit 98
}
if [ "${1:-}" = api ] && [ "${2:-}" = user ]; then
  printf '%s\n' "${MOCK_GH_ACCOUNT:-yurybv}"
  exit 0
fi
if [ "${1:-}" = api ] && [ "${2:-}" = repos/yurybv/whisper/releases/latest ]; then
  if [ "${MOCK_READ_FAILURE:-}" = latest ]; then
    printf 'network unavailable\n' >&2
    exit 2
  fi
  if [ -f "$MOCK_STATE_DIR/latest-tag" ]; then
    cat "$MOCK_STATE_DIR/latest-tag"
    exit 0
  fi
  printf 'gh: Not Found (HTTP 404)\n' >&2
  exit 1
fi
if [ "${1:-}" = api ] && [[ "${2:-}" == repos/yurybv/whisper/git/ref/tags/* ]]; then
  if [ "${MOCK_READ_FAILURE:-}" = tag ]; then
    printf 'network unavailable\n' >&2
    exit 2
  fi
  tag="${2##*/}"
  if [ ! -f "$MOCK_STATE_DIR/$tag/tag-sha" ]; then
    printf 'gh: Not Found (HTTP 404)\n' >&2
    exit 1
  fi
  cat "$MOCK_STATE_DIR/$tag/tag-sha"
  exit 0
fi
if [ "${1:-}" = api ] && [ "${2:-}" = '--method' ] && [ "${3:-}" = POST ]; then
  mutation tag
  ref=''
  sha=''
  while [ "$#" -gt 0 ]; do
    case "$1" in
      ref=refs/tags/*) ref="${1#ref=refs/tags/}" ;;
      sha=*) sha="${1#sha=}" ;;
    esac
    shift
  done
  [ -n "$ref" ] && [ -n "$sha" ] || exit 2
  mkdir -p "$MOCK_STATE_DIR/$ref"
  printf '%s\n' "$sha" >"$MOCK_STATE_DIR/$ref/tag-sha"
  fail_after tag
  exit 0
fi
if [ "${1:-}" = release ] && [ "${2:-}" = list ]; then
  if [ -f "$MOCK_STATE_DIR/latest-tag" ]; then
    cat "$MOCK_STATE_DIR/latest-tag"
  fi
  exit 0
fi
if [ "${1:-}" = release ] && [ "${2:-}" = view ]; then
  if [ "${MOCK_READ_FAILURE:-}" = release ]; then
    printf 'network unavailable\n' >&2
    exit 2
  fi
  tag="$3"
  if [ ! -f "$MOCK_STATE_DIR/$tag/release-state" ]; then
    printf 'release not found\n' >&2
    exit 1
  fi
  case " $* " in
    *' --jq .isDraft '*)
      [ "$(cat "$MOCK_STATE_DIR/$tag/release-state")" = draft ] && printf 'true\n' || printf 'false\n'
      ;;
    *' --jq .assets[].name '*)
      if [ -d "$MOCK_STATE_DIR/$tag/assets" ]; then
        find "$MOCK_STATE_DIR/$tag/assets" -type f -maxdepth 1 -exec basename {} \; | sort
      fi
      ;;
    *' --jq .name '*)
      if [ -f "$MOCK_STATE_DIR/$tag/release-title" ]; then
        cat "$MOCK_STATE_DIR/$tag/release-title"
      else
        printf 'Whisper %s\n' "${tag#v}"
      fi
      ;;
    *' --jq .isPrerelease '*) printf 'false\n' ;;
    *' --jq .body '*) cat "$MOCK_STATE_DIR/$tag/release-body" ;;
    *) exit 2 ;;
  esac
  exit 0
fi
if [ "${1:-}" = release ] && [ "${2:-}" = create ]; then
  tag="$3"
  mutation draft
  mkdir -p "$MOCK_STATE_DIR/$tag/assets"
  printf 'draft\n' >"$MOCK_STATE_DIR/$tag/release-state"
  while [ "$#" -gt 0 ]; do
    if [ "$1" = '--notes-file' ]; then
      cp "$2" "$MOCK_STATE_DIR/$tag/release-body"
      break
    fi
    shift
  done
  fail_after draft
  exit 0
fi
if [ "${1:-}" = release ] && [ "${2:-}" = upload ]; then
  tag="$3"
  asset="$4"
  name="$(basename "$asset")"
  mutation "upload:$name"
  cp "$asset" "$MOCK_STATE_DIR/$tag/assets/$name"
  fail_after "$name"
  exit 0
fi
if [ "${1:-}" = release ] && [ "${2:-}" = download ]; then
  tag="$3"
  destination=''
  pattern=''
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --dir) destination="$2"; shift 2 ;;
      --pattern) pattern="$2"; shift 2 ;;
      *) shift ;;
    esac
  done
  [ -n "$destination" ] && [ -n "$pattern" ] || exit 2
  mkdir -p "$destination"
  cp "$MOCK_STATE_DIR/$tag/assets/$pattern" "$destination/$pattern"
  exit 0
fi
if [ "${1:-}" = release ] && [ "${2:-}" = edit ]; then
  tag="$3"
  mutation publish
  printf 'published\n' >"$MOCK_STATE_DIR/$tag/release-state"
  printf '%s\n' "$tag" >"$MOCK_STATE_DIR/latest-tag"
  fail_after publish
  exit 0
fi
exit 1
MOCK
  chmod +x "$mock_bin/gh"
  cat >"$mock_bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
output=''
url=''
while [ "$#" -gt 0 ]; do
  case "$1" in
    --output) output="$2"; shift 2 ;;
    http*) url="$1"; shift ;;
    *) shift ;;
  esac
done
[ -n "$output" ] && [ -n "$url" ] || exit 2
case "$url" in
  */releases/latest/download/*)
    tag="$(cat "$MOCK_STATE_DIR/latest-tag")"
    name="${url##*/}"
    ;;
  */releases/download/*/*)
    remainder="${url#*/releases/download/}"
    tag="${remainder%%/*}"
    name="${remainder##*/}"
    ;;
  *) exit 22 ;;
esac
cp "$MOCK_STATE_DIR/$tag/assets/$name" "$output"
MOCK
  chmod +x "$mock_bin/curl"
  printf '%s\n' "$work"
}

run_prepare_task() {
  local work="$1"
  local task_id="$2"
  local source_sha="$3"
  shift 3
  local fixture="$(dirname "$work")"
  MOCK_GH_LOG="$fixture/gh.log" \
  MOCK_MUTATION_LOG="$fixture/mutations.log" \
  MOCK_STATE_DIR="$fixture/release-state" \
  MOCK_READ_FAILURE="${MOCK_READ_FAILURE:-}" \
  WHISPER_RELEASE_ROOT="$fixture/releases" \
  PATH="$fixture/mock-bin:$PATH" \
    "$work/scripts/release-local.sh" --prepare --task "$task_id" --source "$source_sha" "$@"
}

run_prepare() {
  local work="$1"
  local source_sha="$2"
  shift 2
  run_prepare_task "$work" WH-M7-003 "$source_sha" "$@"
}

run_publish() {
  local work="$1"
  local manifest="$2"
  local fixture="$(dirname "$work")"
  MOCK_GH_LOG="$fixture/gh.log" \
  MOCK_MUTATION_LOG="$fixture/mutations.log" \
  MOCK_STATE_DIR="$fixture/release-state" \
  MOCK_ALLOW_MUTATIONS=1 \
  MOCK_SIGNING_FINGERPRINT="${MOCK_SIGNING_FINGERPRINT:-2222222222222222222222222222222222222222}" \
  MOCK_READ_FAILURE="${MOCK_READ_FAILURE:-}" \
  WHISPER_RELEASE_ROOT="$fixture/releases" \
  PATH="$fixture/mock-bin:$PATH" \
    "$work/scripts/release-local.sh" --publish --manifest "$manifest"
}

set_task_status() {
  local work="$1"
  local task_id="$2"
  local status="$3"
  local temporary="$work/docs/implementation/task-backlog.md.tmp"
  awk -F '|' -v OFS='|' -v task="$task_id" -v status="$status" '
    {
      candidate = $2
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", candidate)
      if (candidate == task) $4 = " " status " "
      print
    }
  ' "$work/docs/implementation/task-backlog.md" >"$temporary"
  mv "$temporary" "$work/docs/implementation/task-backlog.md"
}

enable_prepare_pipeline() {
  local work="$1"
  local fixture="$(dirname "$work")"
  local mock_bin="$fixture/mock-bin"
  local sparkle_bin="$fixture/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin"
  mkdir -p "$sparkle_bin"

  cat >"$fixture/FixtureSigner.swift" <<'SWIFT'
import CryptoKit
import Foundation

let command = CommandLine.arguments[1]
let keyURL = URL(fileURLWithPath: CommandLine.arguments[2])
if command == "create" {
    let key = Curve25519.Signing.PrivateKey()
    try key.rawRepresentation.write(to: keyURL)
    print(key.publicKey.rawRepresentation.base64EncodedString())
} else {
    let archive = URL(fileURLWithPath: CommandLine.arguments[3])
    let key = try Curve25519.Signing.PrivateKey(rawRepresentation: Data(contentsOf: keyURL))
    print(try key.signature(for: Data(contentsOf: archive)).base64EncodedString())
}
SWIFT
  xcrun swiftc "$fixture/FixtureSigner.swift" -o "$fixture/fixture-signer"
  public_key="$("$fixture/fixture-signer" create "$fixture/test-private-key")"
  /usr/libexec/PlistBuddy -c 'Delete :SUPublicEDKey' "$work/Resources/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $public_key" "$work/Resources/Info.plist"

  touch "$fixture/login.keychain-db"
  cat >"$work/scripts/local-signing-identity.sh" <<EOF
#!/usr/bin/env bash
whisper_signing_name='Whisper Local Development'
whisper_login_keychain() { printf '%s\n' '$fixture/login.keychain-db'; }
whisper_resolve_signing_identity() { printf '%s\n' "\${MOCK_SIGNING_FINGERPRINT:-2222222222222222222222222222222222222222}"; }
EOF

  cat >"$work/scripts/verify.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
count=0
[ ! -f '$fixture/verify-count' ] || count="\$(cat '$fixture/verify-count')"
printf '%s\n' "\$((count + 1))" >'$fixture/verify-count'
EOF
  cat >"$work/scripts/setup-update-signing.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
[ "${1:-}" = '--check' ]
EOF
  cat >"$work/scripts/package.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
[ "\${1:-}" = '--release-version' ]
version="\$2"
count=0
[ ! -f '$fixture/package-count' ] || count="\$(cat '$fixture/package-count')"
printf '%s\n' "\$((count + 1))" >'$fixture/package-count'
repository_root="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
app="\$repository_root/build/Whisper.app"
mkdir -p "\$app/Contents/MacOS"
printf '#!/usr/bin/env bash\nexit 0\n' >"\$app/Contents/MacOS/Whisper"
chmod +x "\$app/Contents/MacOS/Whisper"
plutil -create xml1 "\$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string dev.yury.whisper' "\$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string \$version" "\$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string \$version" "\$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUFeedURL string https://github.com/yurybv/whisper/releases/latest/download/appcast.xml' "\$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :SUPublicEDKey string $public_key' "\$app/Contents/Info.plist"
EOF
  chmod +x "$work/scripts/verify.sh" "$work/scripts/setup-update-signing.sh" "$work/scripts/package.sh"

  cat >"$mock_bin/xcodebuild" <<EOF
#!/usr/bin/env bash
if [[ " \$* " == *' -showBuildSettings '* ]]; then
  printf '    BUILD_DIR = %s\n' '$fixture/DerivedData/Build/Products'
fi
exit 0
EOF
  cat >"$mock_bin/lipo" <<'EOF'
#!/usr/bin/env bash
printf 'arm64\n'
EOF
  cat >"$mock_bin/codesign" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *' --display --requirements - '* ]]; then
  printf 'designated => identifier "dev.yury.whisper" and certificate leaf = H"2222222222222222222222222222222222222222"\n' >&2
elif [[ " $* " == *' --display --verbose=4 '* ]]; then
  printf 'Authority=Whisper Local Development\n' >&2
fi
exit 0
EOF
  chmod +x "$mock_bin/xcodebuild" "$mock_bin/lipo" "$mock_bin/codesign"

  cat >"$sparkle_bin/generate_appcast" <<EOF
#!/usr/bin/env bash
set -euo pipefail
prefix=''
version=''
archive_dir=''
embed_release_notes=0
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    --download-url-prefix) prefix="\$2"; shift 2 ;;
    --versions) version="\$2"; shift 2 ;;
    --maximum-deltas) shift 2 ;;
    --embed-release-notes) embed_release_notes=1; shift ;;
    *) archive_dir="\$1"; shift ;;
  esac
done
[ "\$embed_release_notes" = 1 ]
archive="\$archive_dir/Whisper-\$version.zip"
signature="\$('$fixture/fixture-signer' sign '$fixture/test-private-key' "\$archive")"
length="\$(stat -f %z "\$archive")"
cat >"\$archive_dir/appcast.xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><item>
<sparkle:version>\$version</sparkle:version><sparkle:shortVersionString>\$version</sparkle:shortVersionString>
<description><![CDATA[Embedded fixture notes]]></description>
<enclosure url="\${prefix}Whisper-\${version}.zip" length="\$length" type="application/octet-stream" sparkle:edSignature="\$signature" />
</item></channel></rss>
XML
EOF
  cat >"$sparkle_bin/sign_update" <<EOF
#!/usr/bin/env bash
set -euo pipefail
[ "\${1:-}" = '-p' ]
'$fixture/fixture-signer' sign '$fixture/test-private-key' "\$2"
EOF
  chmod +x "$sparkle_bin/generate_appcast" "$sparkle_bin/sign_update"

  git -C "$work" add .
  git -C "$work" commit -q -m 'test: add release pipeline fixture'
  git -C "$work" push -q origin master
}

expect_prepare_failure() {
  local name="$1"
  local expected="$2"
  local work="$3"
  local source_sha="$4"
  shift 4
  local output="$test_root/$name.log"
  if run_prepare "$work" "$source_sha" "$@" >"$output" 2>&1; then
    fail "$name unexpectedly succeeded"
  fi
  grep -F "$expected" "$output" >/dev/null || fail "$name did not explain the rejection"
  [ ! -s "$(dirname "$work")/mutations.log" ] || fail "$name attempted a remote mutation"
  printf 'PASS  %s\n' "$name"
}

wrong_account_work="$(make_fixture wrong-account)"
wrong_account_sha="$(git -C "$wrong_account_work" rev-parse HEAD)"
MOCK_GH_ACCOUNT='not-yurybv' expect_prepare_failure \
  'wrong account' 'GitHub account must be yurybv' "$wrong_account_work" "$wrong_account_sha"

wrong_remote_work="$(make_fixture wrong-remote)"
wrong_remote_sha="$(git -C "$wrong_remote_work" rev-parse HEAD)"
git -C "$wrong_remote_work" remote set-url origin 'https://github.com/example/whisper.git'
expect_prepare_failure 'wrong remote' 'origin must be https://github.com/yurybv/whisper.git' \
  "$wrong_remote_work" "$wrong_remote_sha"

wrong_branch_work="$(make_fixture wrong-branch)"
wrong_branch_sha="$(git -C "$wrong_branch_work" rev-parse HEAD)"
git -C "$wrong_branch_work" switch -q -c feature
expect_prepare_failure 'wrong branch' 'delivery branch must be master' "$wrong_branch_work" "$wrong_branch_sha"

dirty_work="$(make_fixture dirty)"
dirty_sha="$(git -C "$dirty_work" rev-parse HEAD)"
printf 'dirty\n' >>"$dirty_work/source.txt"
expect_prepare_failure 'dirty worktree' 'delivery worktree must be clean' "$dirty_work" "$dirty_sha"

invalid_source_work="$(make_fixture invalid-source)"
expect_prepare_failure 'invalid source' 'source must be a full 40-character commit SHA' \
  "$invalid_source_work" 'HEAD'

unpushed_work="$(make_fixture unpushed)"
git -C "$unpushed_work" switch -q -c unpublished-source
printf 'unpushed\n' >>"$unpushed_work/source.txt"
git -C "$unpushed_work" add source.txt
git -C "$unpushed_work" commit -q -m 'feat: unpublished source'
unpushed_sha="$(git -C "$unpushed_work" rev-parse HEAD)"
git -C "$unpushed_work" switch -q master
expect_prepare_failure 'source outside origin' 'source must belong to origin/master' "$unpushed_work" "$unpushed_sha"

incomplete_work="$(make_fixture incomplete in-progress)"
incomplete_sha="$(git -C "$incomplete_work" rev-parse HEAD)"
expect_prepare_failure 'incomplete task' 'WH-M7-003 must be done before a normal release' \
  "$incomplete_work" "$incomplete_sha"

positive_work="$(make_fixture positive in-progress)"
enable_prepare_pipeline "$positive_work"
printf 'second implementation commit\n' >>"$positive_work/source.txt"
git -C "$positive_work" add source.txt
git -C "$positive_work" commit -q -m 'feat: complete release workflow'
set_task_status "$positive_work" WH-M7-003 done
git -C "$positive_work" add docs/implementation/task-backlog.md
git -C "$positive_work" commit -q -m 'docs(tasks): complete release task'
printf 'Release task complete\n' >>"$positive_work/docs/implementation/roadmap.md"
git -C "$positive_work" add docs/implementation/roadmap.md
git -C "$positive_work" commit -q -m 'docs(roadmap): record release task closure'
git -C "$positive_work" push -q origin master
positive_sha="$(git -C "$positive_work" rev-parse HEAD)"
positive_output="$(run_prepare "$positive_work" "$positive_sha")"
printf '%s\n' "$positive_output" | grep -F 'Prepared WH-M7-003 as 1.0.0' >/dev/null \
  || fail "positive preparation did not report the selected task and version"
positive_manifest="$(printf '%s\n' "$positive_output" | sed -n 's/^Manifest: //p')"
[ -f "$positive_manifest" ] || fail "positive preparation did not return a manifest"
[ -s "$(dirname "$positive_manifest")/release-manifest.local.ed25519" ] \
  || fail "positive preparation did not seal the local manifest"
[ ! -s "$(dirname "$positive_work")/mutations.log" ] || fail "preparation attempted a remote mutation"
retry_output="$(run_prepare "$positive_work" "$positive_sha")"
[ "$retry_output" = "$positive_output" ] || fail "identical preparation did not resume the same candidate"
[ "$(cat "$(dirname "$positive_work")/package-count")" = '1' ] \
  || fail "identical preparation rebuilt instead of reusing the candidate"
task_classifications="$(plutil -extract includedCommits json -o - "$positive_manifest")"
[ "$(printf '%s' "$task_classifications" | grep -o '"classification":"closure"' | wc -l | tr -d ' ')" = '1' ] \
  || fail "metadata-only closure commit was not classified separately"
printf 'PASS  multi-commit preparation, closure mapping, and deterministic retry\n'

unexplained_work="$(make_fixture unexplained in-progress)"
enable_prepare_pipeline "$unexplained_work"
set_task_status "$unexplained_work" WH-M7-003 done
git -C "$unexplained_work" add docs/implementation/task-backlog.md
git -C "$unexplained_work" commit -q -m 'docs(tasks): complete release task'
printf 'unrelated post-task application change\n' >>"$unexplained_work/source.txt"
git -C "$unexplained_work" add source.txt
git -C "$unexplained_work" commit -q -m 'feat: unexplained application change'
git -C "$unexplained_work" push -q origin master
unexplained_sha="$(git -C "$unexplained_work" rev-parse HEAD)"
expect_prepare_failure 'unexplained changed files' 'unexplained changes after WH-M7-003 completed' \
  "$unexplained_work" "$unexplained_sha"

bootstrap_work="$(make_fixture bootstrap done)"
enable_prepare_pipeline "$bootstrap_work"
set_task_status "$bootstrap_work" WH-M7-004 review
git -C "$bootstrap_work" add docs/implementation/task-backlog.md
git -C "$bootstrap_work" commit -q -m 'docs(updates): prepare bootstrap acceptance'
git -C "$bootstrap_work" push -q origin master
bootstrap_sha="$(git -C "$bootstrap_work" rev-parse HEAD)"
bootstrap_output="$(run_prepare_task "$bootstrap_work" WH-M7-004 "$bootstrap_sha" --bootstrap initial)"
printf '%s\n' "$bootstrap_output" | grep -F 'Prepared WH-M7-004 as 1.0.0' >/dev/null \
  || fail "valid initial bootstrap preparation failed"
if run_prepare_task "$bootstrap_work" WH-M7-004 "$bootstrap_sha" --bootstrap unexpected \
    >"$test_root/invalid-bootstrap-phase.log" 2>&1; then
  fail "invalid bootstrap phase unexpectedly succeeded"
fi
grep -F 'bootstrap phase must be initial or update' "$test_root/invalid-bootstrap-phase.log" >/dev/null \
  || fail "invalid bootstrap phase did not explain the rejection"
if run_prepare_task "$bootstrap_work" WH-M7-003 "$bootstrap_sha" --bootstrap initial \
    >"$test_root/wrong-bootstrap-task.log" 2>&1; then
  fail "bootstrap exception accepted the wrong task"
fi
grep -F 'bootstrap exception is limited to WH-M7-004' "$test_root/wrong-bootstrap-task.log" >/dev/null \
  || fail "wrong bootstrap task rejection was unclear"
[ ! -s "$(dirname "$bootstrap_work")/mutations.log" ] \
  || fail "bootstrap validation attempted a remote mutation"
printf 'PASS  bootstrap exception is limited to the approved review checkpoint\n'

publish_fixture="$(dirname "$positive_work")"
touch "$publish_fixture/mutations.log"
mutation_count_before="$(wc -l <"$publish_fixture/mutations.log")"
git clone -q -b master "$publish_fixture/origin.git" "$publish_fixture/behind-writer"
git -C "$publish_fixture/behind-writer" config user.name 'Release Test'
git -C "$publish_fixture/behind-writer" config user.email 'release-test@example.invalid'
printf 'Remote metadata closure\n' >>"$publish_fixture/behind-writer/docs/implementation/roadmap.md"
git -C "$publish_fixture/behind-writer" add docs/implementation/roadmap.md
git -C "$publish_fixture/behind-writer" commit -q -m 'docs(roadmap): close remote metadata'
git -C "$publish_fixture/behind-writer" push -q origin master
if run_publish "$positive_work" "$positive_manifest" >"$test_root/behind-publish.log" 2>&1; then
  fail "publication accepted a delivery checkout behind origin/master"
fi
grep -F 'delivery checkout must be synchronized with origin/master' "$test_root/behind-publish.log" >/dev/null \
  || fail "behind publication rejection was unclear"
git -C "$positive_work" pull -q --ff-only origin master
if MOCK_READ_FAILURE=latest run_prepare "$positive_work" "$positive_sha" \
    >"$test_root/latest-read-failure.log" 2>&1; then
  fail "preparation treated a GitHub read failure as an empty release history"
fi
grep -F 'latest-release state could not be inspected' "$test_root/latest-read-failure.log" >/dev/null \
  || fail "latest-release read failure was unclear"
if MOCK_READ_FAILURE=release run_publish "$positive_work" "$positive_manifest" \
    >"$test_root/release-read-failure.log" 2>&1; then
  fail "publication treated a GitHub read failure as a missing release"
fi
grep -F 'release state could not be inspected' "$test_root/release-read-failure.log" >/dev/null \
  || fail "release-state read failure was unclear"
if MOCK_READ_FAILURE=tag run_publish "$positive_work" "$positive_manifest" \
    >"$test_root/tag-read-failure.log" 2>&1; then
  fail "publication treated a GitHub read failure as a missing tag"
fi
grep -F 'tag state could not be inspected' "$test_root/tag-read-failure.log" >/dev/null \
  || fail "tag-state read failure was unclear"
if MOCK_SIGNING_FINGERPRINT=3333333333333333333333333333333333333333 \
    run_publish "$positive_work" "$positive_manifest" >"$test_root/changed-publish-identity.log" 2>&1; then
  fail "publication accepted a changed signing identity"
fi
grep -F 'signing identity fingerprint changed' "$test_root/changed-publish-identity.log" >/dev/null \
  || fail "changed publication identity rejection was unclear"
cp "$positive_manifest" "$publish_fixture/release-manifest.local.json"
if run_publish "$positive_work" "$publish_fixture/release-manifest.local.json" \
    >"$test_root/outside-manifest.log" 2>&1; then
  fail "publication accepted a manifest outside the staging root"
fi
grep -F 'manifest must remain inside the release staging root' "$test_root/outside-manifest.log" >/dev/null \
  || fail "outside manifest rejection was unclear"
public_manifest="$(dirname "$positive_manifest")/artifacts/release-manifest.json"
cp "$positive_manifest" "$test_root/local-manifest.backup"
cp "$public_manifest" "$test_root/public-manifest.backup"
plutil -replace releaseNotes -string 'coordinated provenance rewrite' "$positive_manifest"
plutil -replace releaseNotes -string 'coordinated provenance rewrite' "$public_manifest"
if run_publish "$positive_work" "$positive_manifest" >"$test_root/manifest-signature-mismatch.log" 2>&1; then
  fail "publication accepted rewritten signed provenance"
fi
grep -F 'prepared manifest signature is invalid' "$test_root/manifest-signature-mismatch.log" >/dev/null \
  || fail "rewritten provenance rejection was unclear"
cp "$test_root/local-manifest.backup" "$positive_manifest"
cp "$test_root/public-manifest.backup" "$public_manifest"
plutil -replace taskID -string WH-M7-999 "$public_manifest"
if run_publish "$positive_work" "$positive_manifest" >"$test_root/public-manifest-mismatch.log" 2>&1; then
  fail "publication accepted a changed public manifest"
fi
grep -F 'public manifest does not match' "$test_root/public-manifest-mismatch.log" >/dev/null \
  || fail "changed public manifest rejection was unclear"
cp "$test_root/public-manifest.backup" "$public_manifest"
plutil -insert unexpectedLocalPath -string '/private/tmp/sensitive' "$public_manifest"
if run_publish "$positive_work" "$positive_manifest" >"$test_root/public-manifest-extra-field.log" 2>&1; then
  fail "publication accepted an unknown public-manifest field"
fi
grep -F 'public manifest does not match' "$test_root/public-manifest-extra-field.log" >/dev/null \
  || fail "unknown public-manifest field rejection was unclear"
cp "$test_root/public-manifest.backup" "$public_manifest"
mkdir -p "$publish_fixture/release-state/v1.0.0/assets"
printf '%s\n' "$positive_sha" >"$publish_fixture/release-state/v1.0.0/tag-sha"
printf 'draft\n' >"$publish_fixture/release-state/v1.0.0/release-state"
cp "$(dirname "$positive_manifest")/release-notes.md" "$publish_fixture/release-state/v1.0.0/release-body"
printf 'conflict\n' >"$publish_fixture/release-state/v1.0.0/assets/unexpected.bin"
if run_publish "$positive_work" "$positive_manifest" >"$test_root/unexpected-draft-asset.log" 2>&1; then
  fail "publication accepted an unexpected draft asset"
fi
grep -F 'draft contains an unexpected asset' "$test_root/unexpected-draft-asset.log" >/dev/null \
  || fail "unexpected draft asset rejection was unclear"
rm -rf "$publish_fixture/release-state/v1.0.0"
mkdir -p "$publish_fixture/release-state/v1.0.0/assets"
printf '%s\n' "$positive_sha" >"$publish_fixture/release-state/v1.0.0/tag-sha"
printf 'draft\n' >"$publish_fixture/release-state/v1.0.0/release-state"
cp "$(dirname "$positive_manifest")/release-notes.md" "$publish_fixture/release-state/v1.0.0/release-body"
printf 'Conflicting title\n' >"$publish_fixture/release-state/v1.0.0/release-title"
if run_publish "$positive_work" "$positive_manifest" >"$test_root/conflicting-release-title.log" 2>&1; then
  fail "publication accepted conflicting draft metadata"
fi
grep -F 'release title conflicts with the prepared candidate' "$test_root/conflicting-release-title.log" >/dev/null \
  || fail "conflicting release metadata rejection was unclear"
rm -rf "$publish_fixture/release-state/v1.0.0"
mkdir -p "$publish_fixture/release-state/v1.0.0/assets"
printf '%s\n' "$positive_sha" >"$publish_fixture/release-state/v1.0.0/tag-sha"
printf 'draft\n' >"$publish_fixture/release-state/v1.0.0/release-state"
printf 'Conflicting notes\n' >"$publish_fixture/release-state/v1.0.0/release-body"
if run_publish "$positive_work" "$positive_manifest" >"$test_root/conflicting-release-notes.log" 2>&1; then
  fail "publication accepted conflicting draft release notes"
fi
grep -F 'release notes conflict with the prepared candidate' "$test_root/conflicting-release-notes.log" >/dev/null \
  || fail "conflicting release notes rejection was unclear"
rm -rf "$publish_fixture/release-state/v1.0.0"
[ "$(wc -l <"$publish_fixture/mutations.log")" = "$mutation_count_before" ] \
  || fail "invalid publication state crossed the remote mutation boundary"
printf 'PASS  release-state read failures and invalid candidates stop before mutation\n'

for failure_point in tag draft Whisper-1.0.0.zip appcast.xml release-manifest.json publish; do
  if MOCK_FAIL_AFTER="$failure_point" run_publish "$positive_work" "$positive_manifest" \
      >"$test_root/publish-$failure_point.log" 2>&1; then
    fail "publication unexpectedly ignored the $failure_point timeout"
  fi
  if [ "$failure_point" != publish ] && [ -f "$publish_fixture/release-state/latest-tag" ]; then
    fail "publication exposed a latest release before verified draft completion"
  fi
done
published_output="$(run_publish "$positive_work" "$positive_manifest")"
printf '%s\n' "$published_output" | grep -F 'Published WH-M7-003 as v1.0.0' >/dev/null \
  || fail "published retry did not reconcile the completed release"
idempotent_output="$(run_publish "$positive_work" "$positive_manifest")"
printf '%s\n' "$idempotent_output" | grep -F 'Published WH-M7-003 as v1.0.0' >/dev/null \
  || fail "identical published request was not idempotent"
[ "$(grep -c '^tag$' "$publish_fixture/mutations.log")" = '1' ] \
  || fail "publication retried tag creation"
[ "$(grep -c '^draft$' "$publish_fixture/mutations.log")" = '1' ] \
  || fail "publication retried draft creation"
[ "$(grep -c '^upload:' "$publish_fixture/mutations.log")" = '3' ] \
  || fail "publication replaced an existing asset"
[ "$(grep -c '^publish$' "$publish_fixture/mutations.log")" = '1' ] \
  || fail "publication retried the final publish mutation"
printf 'PASS  publication resumes every mutation boundary and is idempotent\n'

git -C "$positive_work" tag v1.0.0 "$positive_sha"
git -C "$positive_work" push -q origin v1.0.0
mutations_before_retry="$(wc -l <"$publish_fixture/mutations.log")"
if run_prepare "$positive_work" "$positive_sha" >"$test_root/zero-new-source.log" 2>&1; then
  fail "normal release accepted zero new source changes"
fi
grep -F 'normal release has no new source changes' "$test_root/zero-new-source.log" >/dev/null \
  || fail "zero-change rejection was unclear"
set_task_status "$positive_work" WH-M7-004 done
mkdir -p "$positive_work/docs/testing/evidence/WH-M7-004"
printf 'Verified bootstrap closure evidence\n' >"$positive_work/docs/testing/evidence/WH-M7-004/qa.md"
printf 'Verified live update matrix\n' >"$positive_work/docs/testing/update-acceptance.md"
git -C "$positive_work" add docs/implementation/task-backlog.md
git -C "$positive_work" add docs/testing/update-acceptance.md docs/testing/evidence/WH-M7-004/qa.md
git -C "$positive_work" commit -q -m 'docs(tasks): close previous bootstrap task'
git -C "$positive_work" push -q origin master
previous_closure_sha="$(git -C "$positive_work" rev-parse HEAD)"
if run_prepare "$positive_work" "$previous_closure_sha" >"$test_root/duplicate-task.log" 2>&1; then
  fail "normal release accepted a duplicate task ID"
fi
grep -F 'WH-M7-003 is already included in the published release history' "$test_root/duplicate-task.log" >/dev/null \
  || fail "duplicate task rejection was unclear"
set_task_status "$positive_work" WH-M7-005 in-progress
git -C "$positive_work" add docs/implementation/task-backlog.md
git -C "$positive_work" commit -q -m 'docs(tasks): start queued guide task'
printf 'queued guide implementation\n' >>"$positive_work/source.txt"
git -C "$positive_work" add source.txt
git -C "$positive_work" commit -q -m 'docs: add queued guide implementation'
set_task_status "$positive_work" WH-M7-005 done
git -C "$positive_work" add docs/implementation/task-backlog.md
git -C "$positive_work" commit -q -m 'docs(tasks): complete queued guide task'
git -C "$positive_work" push -q origin master
queued_sha="$(git -C "$positive_work" rev-parse HEAD)"
queued_output="$(run_prepare_task "$positive_work" WH-M7-005 "$queued_sha")"
printf '%s\n' "$queued_output" | grep -F 'Prepared WH-M7-005 as 1.0.1' >/dev/null \
  || fail "next queued task did not receive the next separate patch"
[ "$(wc -l <"$publish_fixture/mutations.log")" = "$mutations_before_retry" ] \
  || fail "queued and duplicate preparation attempted remote mutations"
printf 'PASS  zero-change and duplicate releases are rejected while queued tasks stay separate\n'

bootstrap_manifest="$(printf '%s\n' "$bootstrap_output" | sed -n 's/^Manifest: //p')"
bootstrap_fixture="$(dirname "$bootstrap_work")"
mkdir -p "$bootstrap_fixture/release-state/v1.0.0/assets"
cp "$(dirname "$bootstrap_manifest")/artifacts/"* "$bootstrap_fixture/release-state/v1.0.0/assets/"
printf 'published\n' >"$bootstrap_fixture/release-state/v1.0.0/release-state"
printf 'v1.0.0\n' >"$bootstrap_fixture/release-state/latest-tag"
printf '%s\n' "$bootstrap_sha" >"$bootstrap_fixture/release-state/v1.0.0/tag-sha"
git -C "$bootstrap_work" tag v1.0.0 "$bootstrap_sha"
git -C "$bootstrap_work" push -q origin v1.0.0
printf 'Second bootstrap checkpoint\n' >>"$bootstrap_work/docs/implementation/roadmap.md"
git -C "$bootstrap_work" add docs/implementation/roadmap.md
git -C "$bootstrap_work" commit -q -m 'docs(updates): record second bootstrap checkpoint'
git -C "$bootstrap_work" push -q origin master
bootstrap_update_sha="$(git -C "$bootstrap_work" rev-parse HEAD)"
bootstrap_update_output="$(
  run_prepare_task "$bootstrap_work" WH-M7-004 "$bootstrap_update_sha" --bootstrap update
)"
printf '%s\n' "$bootstrap_update_output" | grep -F 'Prepared WH-M7-004 as 1.0.1' >/dev/null \
  || fail "valid bootstrap update did not receive version 1.0.1"
printf 'PASS  bootstrap update requires and follows the verified initial checkpoint\n'
