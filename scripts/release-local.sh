#!/usr/bin/env bash

set -euo pipefail

fail() {
  printf 'error: %s\n' "$1" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "$1 is required."
}

task_status_at_ref() {
  local ref="$1"
  local task_id="$2"
  git show "$ref:docs/implementation/task-backlog.md" 2>/dev/null \
    | awk -F '|' -v task="$task_id" '
        $2 ~ "^[[:space:]]*" task "[[:space:]]*$" {
          status = $4
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", status)
          print status
          exit
        }
      '
}

commit_is_metadata_closure() {
  local commit="$1"
  local path saw_path='false'
  while IFS= read -r path; do
    [ -n "$path" ] || continue
    saw_path='true'
    case "$path" in
      docs/implementation/task-backlog.md|docs/implementation/roadmap.md|docs/implementation/tasks/*.md|docs/testing/update-acceptance.md|docs/testing/evidence/WH-M*/qa.md)
        ;;
      *) return 1 ;;
    esac
  done < <(git diff-tree --root --no-commit-id --name-only -r "$commit")
  [ "$saw_path" = 'true' ]
}

classify_normal_commits() {
  local task_id="$1"
  local commit_range="$2"
  local base_sha="$3"
  local commit parent_status current_status

  if [ "$base_sha" != 'none' ] && [ "$(task_status_at_ref "$base_sha" "$task_id")" = 'done' ]; then
    fail "$task_id is already included in the published release history."
  fi

  included_commit_records=()
  while IFS= read -r commit; do
    current_status="$(task_status_at_ref "$commit" "$task_id")"
    [ -n "$current_status" ] || fail "$task_id is missing from commit $commit."
    parent_status=''
    if git rev-parse "$commit^" >/dev/null 2>&1; then
      parent_status="$(task_status_at_ref "$commit^" "$task_id")"
    fi

    if [ "$parent_status" = 'done' ] && [ "$current_status" = 'done' ]; then
      commit_is_metadata_closure "$commit" \
        || fail "unexplained changes after $task_id completed at $commit."
      included_commit_records+=("$commit:closure")
      continue
    fi

    case "$current_status" in
      in-progress|review|done)
        included_commit_records+=("$commit:task")
        ;;
      ready|blocked)
        commit_is_metadata_closure "$commit" \
          || fail "commit $commit is not explained by active work on $task_id."
        included_commit_records+=("$commit:closure")
        ;;
      *)
        fail "commit $commit is not explained by active work on $task_id."
        ;;
    esac
  done < <(git rev-list --reverse "$commit_range")
  [ "${#included_commit_records[@]}" -gt 0 ] || fail "normal release has no new source changes."
}

validate_bootstrap_request() {
  [ "$task_id" = 'WH-M7-004' ] || fail "bootstrap exception is limited to WH-M7-004."
  case "$bootstrap_phase" in
    initial|update) ;;
    *) fail "bootstrap phase must be initial or update." ;;
  esac
  [ "$(task_status_at_ref "$source_sha" WH-M7-004)" = 'review' ] \
    || fail "WH-M7-004 must be in review for bootstrap preparation."
  local prerequisite
  for prerequisite in WH-M7-001 WH-M7-002 WH-M7-003; do
    [ "$(task_status_at_ref "$source_sha" "$prerequisite")" = 'done' ] \
      || fail "$prerequisite must be done before bootstrap preparation."
  done
}

compile_manifest_tool() {
  local output="$1"
  xcrun swiftc "$repository_root/scripts/release-manifest.swift" -o "$output"
}

latest_release_tag() {
  local output
  if output="$(gh api repos/yurybv/whisper/releases/latest --jq .tag_name 2>&1)"; then
    printf '%s\n' "$output"
  elif printf '%s\n' "$output" | grep -F 'HTTP 404' >/dev/null; then
    return 0
  else
    fail "GitHub latest-release state could not be inspected."
  fi
}

next_version_for_tag() {
  local tag="$1"
  if [ -z "$tag" ]; then
    printf '1.0.0\n'
    return
  fi
  [[ "$tag" =~ ^v1\.0\.([0]|[1-9][0-9]*)$ ]] \
    || fail "latest published release tag must match v1.0.PATCH."
  local patch="${BASH_REMATCH[1]}"
  [ "${#patch}" -lt 10 ] || fail "latest published patch version is too large."
  printf '1.0.%s\n' "$((patch + 1))"
}

resolve_public_key_at_ref() {
  local ref="$1"
  local destination="$2"
  git show "$ref:Resources/Info.plist" >"$destination" \
    || fail "source checkpoint has no update configuration."
  /usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$destination" 2>/dev/null \
    || fail "source checkpoint has no Sparkle public key."
}

resolve_release_identity() {
  [ -f "$repository_root/scripts/local-signing-identity.sh" ] \
    || fail "local signing identity helper is missing."
  # shellcheck source=scripts/local-signing-identity.sh
  source "$repository_root/scripts/local-signing-identity.sh"
  login_keychain="$(whisper_login_keychain)" || fail "The login Keychain is unavailable."
  signing_fingerprint="$(whisper_resolve_signing_identity "$login_keychain")" || exit 1
}

resolve_appcast_tool() {
  local checkout="$1"
  xcodebuild -resolvePackageDependencies -project "$checkout/Whisper.xcodeproj" -scheme Whisper >/dev/null
  local build_directory derived_data tool
  build_directory="$(
    xcodebuild -project "$checkout/Whisper.xcodeproj" -scheme Whisper -showBuildSettings \
      | awk -F ' = ' '/^[[:space:]]*BUILD_DIR = / { print $2; exit }'
  )"
  [ -n "$build_directory" ] || fail "Could not locate the pinned Sparkle package tools."
  derived_data="${build_directory%%/Build/Products*}"
  tool="$derived_data/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_appcast"
  [ -x "$tool" ] || fail "Pinned Sparkle generate_appcast tool is unavailable."
  printf '%s\n' "$tool"
}

validate_release_bundle() {
  local app="$1"
  local version="$2"
  local executable="$app/Contents/MacOS/Whisper"
  [ -x "$executable" ] || fail "prepared app executable is missing."
  [ "$(lipo -archs "$executable")" = 'arm64' ] || fail "prepared app is not arm64-only."
  codesign --verify --deep --strict --verbose=2 "$app"
  local details requirement
  details="$(codesign --display --verbose=4 "$app" 2>&1)" \
    || fail "prepared app signature cannot be inspected."
  printf '%s\n' "$details" | grep -Fx "Authority=$whisper_signing_name" >/dev/null \
    || fail "prepared app does not use $whisper_signing_name."
  requirement="$(codesign --display --requirements - "$app" 2>&1)" \
    || fail "prepared app has no designated requirement."
  printf '%s\n' "$requirement" | grep -Fi "certificate leaf = H\"$signing_fingerprint\"" >/dev/null \
    || fail "prepared app requirement uses a different signing identity."
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")" = "$version" ] \
    || fail "prepared app short version is wrong."
  [ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")" = "$version" ] \
    || fail "prepared app build version is wrong."
}

verify_prepared_manifest_seal() {
  local manifest_tool="$1"
  local manifest="$2"
  local public_key="$3"
  local signature_file="$(dirname "$manifest")/release-manifest.local.ed25519"
  [ -f "$signature_file" ] && [ ! -L "$signature_file" ] \
    || fail "prepared manifest signature is missing."
  "$manifest_tool" verify-file-signature \
    --file "$manifest" \
    --signature-file "$signature_file" \
    --public-key "$public_key"
}

cleanup_prepare() {
  if [ -n "${prepare_worktree:-}" ] && [ -d "$prepare_worktree" ]; then
    git worktree remove --force "$prepare_worktree" >/dev/null 2>&1 || true
  fi
  if [ -n "${prepare_temporary_root:-}" ] && [ -d "$prepare_temporary_root" ]; then
    rm -rf "$prepare_temporary_root"
  fi
}

remote_tag_sha() {
  local tag="$1"
  local output
  if output="$(gh api "repos/yurybv/whisper/git/ref/tags/$tag" --jq .object.sha 2>&1)"; then
    printf '%s\n' "$output"
  elif printf '%s\n' "$output" | grep -F 'HTTP 404' >/dev/null; then
    return 0
  else
    fail "GitHub tag state could not be inspected."
  fi
}

release_draft_state() {
  local tag="$1"
  local output
  if output="$(gh release view "$tag" --repo yurybv/whisper --json isDraft --jq .isDraft 2>&1)"; then
    printf '%s\n' "$output"
  elif printf '%s\n' "$output" | grep -F 'release not found' >/dev/null; then
    return 0
  else
    fail "GitHub release state could not be inspected."
  fi
}

release_asset_names() {
  local tag="$1"
  gh release view "$tag" --repo yurybv/whisper --json assets --jq '.assets[].name'
}

release_field() {
  local tag="$1"
  local field="$2"
  local output
  if output="$(gh release view "$tag" --repo yurybv/whisper --json "$field" --jq ".$field" 2>&1)"; then
    printf '%s\n' "$output"
  else
    fail "GitHub release metadata could not be inspected."
  fi
}

validate_release_metadata() {
  local tag="$1"
  local version="$2"
  local manifest_tool="$3"
  local manifest="$4"
  [ "$(release_field "$tag" name)" = "Whisper $version" ] \
    || fail "release title conflicts with the prepared candidate."
  [ "$(release_field "$tag" isPrerelease)" = 'false' ] \
    || fail "prepared releases must not be prereleases."
  [ "$(release_field "$tag" body)" = "$($manifest_tool field --manifest "$manifest" --name releaseNotes)" ] \
    || fail "release notes conflict with the prepared candidate."
}

validate_release_asset_inventory() {
  local names="$1"
  local version="$2"
  local require_complete="$3"
  local name
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$name" in
      "Whisper-$version.zip"|appcast.xml|release-manifest.json) ;;
      *) fail "release draft contains an unexpected asset: $name." ;;
    esac
  done <<<"$names"
  if [ "$require_complete" = 'yes' ]; then
    for name in "Whisper-$version.zip" appcast.xml release-manifest.json; do
      printf '%s\n' "$names" | grep -Fx "$name" >/dev/null \
        || fail "release asset $name is missing."
    done
  fi
}

download_release_asset() {
  local tag="$1"
  local name="$2"
  local destination="$3"
  rm -f "$destination/$name"
  gh release download "$tag" --repo yurybv/whisper --pattern "$name" --dir "$destination" >/dev/null
  [ -f "$destination/$name" ] || fail "release asset $name is missing."
}

verify_release_downloads() {
  local tag="$1"
  local stage="$2"
  local version="$3"
  local manifest_tool="$4"
  local public_key="$5"
  local download_directory="$6"
  local zip_name="Whisper-$version.zip"

  mkdir -p "$download_directory"
  download_release_asset "$tag" "$zip_name" "$download_directory"
  download_release_asset "$tag" appcast.xml "$download_directory"
  download_release_asset "$tag" release-manifest.json "$download_directory"
  cmp -s "$stage/artifacts/$zip_name" "$download_directory/$zip_name" \
    || fail "downloaded release archive differs from the prepared artifact."
  cmp -s "$stage/artifacts/appcast.xml" "$download_directory/appcast.xml" \
    || fail "downloaded appcast differs from the prepared artifact."
  cmp -s "$stage/artifacts/release-manifest.json" "$download_directory/release-manifest.json" \
    || fail "downloaded public manifest differs from the prepared artifact."
  "$manifest_tool" verify-feed-artifacts \
    --appcast "$download_directory/appcast.xml" \
    --archive "$download_directory/$zip_name" \
    --public-key "$public_key" \
    --version "$version"
}

verify_public_release() {
  local tag="$1"
  local stage="$2"
  local version="$3"
  local manifest_tool="$4"
  local public_key="$5"
  local download_directory="$6"
  local zip_name="Whisper-$version.zip"
  local prefix="https://github.com/yurybv/whisper/releases"

  mkdir -p "$download_directory"
  curl --fail --silent --show-error --location \
    "$prefix/latest/download/appcast.xml" --output "$download_directory/appcast.xml"
  curl --fail --silent --show-error --location \
    "$prefix/download/$tag/$zip_name" --output "$download_directory/$zip_name"
  curl --fail --silent --show-error --location \
    "$prefix/download/$tag/release-manifest.json" --output "$download_directory/release-manifest.json"
  cmp -s "$stage/artifacts/$zip_name" "$download_directory/$zip_name" \
    || fail "public release archive differs from the prepared artifact."
  cmp -s "$stage/artifacts/appcast.xml" "$download_directory/appcast.xml" \
    || fail "public latest appcast differs from the prepared artifact."
  cmp -s "$stage/artifacts/release-manifest.json" "$download_directory/release-manifest.json" \
    || fail "public release manifest differs from the prepared artifact."
  "$manifest_tool" verify-feed-artifacts \
    --appcast "$download_directory/appcast.xml" \
    --archive "$download_directory/$zip_name" \
    --public-key "$public_key" \
    --version "$version"
  [ "$(latest_release_tag)" = "$tag" ] || fail "published release is not GitHub latest."
}

cleanup_publish() {
  if [ -n "${publish_temporary_root:-}" ] && [ -d "$publish_temporary_root" ]; then
    rm -rf "$publish_temporary_root"
  fi
}

publish_release() {
  local release_root_physical manifest_directory manifest_tool task version source base_tag base_sha phase
  local source_plist public_key public_key_fingerprint signing_fingerprint tag tag_sha draft_state latest_tag
  local expected_latest expected_version zip_name asset asset_names notes_file
  local commit_range manifest_commit_records expected_commit_records commit_record previous_manifest

  release_root_physical="$(cd "$release_root" && pwd -P)"
  [ ! -L "$manifest_path" ] || fail "manifest path must not be a symbolic link."
  [ "$(basename "$manifest_path")" = 'release-manifest.local.json' ] \
    || fail "manifest must name release-manifest.local.json."
  manifest_directory="$(cd "$(dirname "$manifest_path")" 2>/dev/null && pwd -P)" \
    || fail "manifest directory does not exist."
  case "$manifest_directory/" in
    "$release_root_physical"/*/) ;;
    *) fail "manifest must remain inside the release staging root." ;;
  esac
  manifest_path="$manifest_directory/release-manifest.local.json"
  [ -f "$manifest_path" ] || fail "release manifest does not exist."

  publish_temporary_root="$(mktemp -d "$release_root/.publish.XXXXXX")"
  trap cleanup_publish EXIT
  manifest_tool="$publish_temporary_root/release-manifest"
  compile_manifest_tool "$manifest_tool"
  task="$($manifest_tool field --manifest "$manifest_path" --name taskID)"
  version="$($manifest_tool field --manifest "$manifest_path" --name version)"
  source="$($manifest_tool field --manifest "$manifest_path" --name sourceSHA)"
  base_tag="$($manifest_tool field --manifest "$manifest_path" --name baseTag)"
  base_sha="$($manifest_tool field --manifest "$manifest_path" --name baseSHA)"
  phase="$($manifest_tool field --manifest "$manifest_path" --name bootstrapPhase)"
  tag="v$version"
  zip_name="Whisper-$version.zip"

  git merge-base --is-ancestor "$source" origin/master \
    || fail "manifest source must belong to origin/master."
  [ "$(git rev-parse "$source^{commit}" 2>/dev/null || true)" = "$source" ] \
    || fail "manifest source commit does not exist."
  if [ -n "$phase" ]; then
    task_id="$task"
    source_sha="$source"
    bootstrap_phase="$phase"
    validate_bootstrap_request
  else
    [ "$(task_status_at_ref "$source" "$task")" = 'done' ] \
      || fail "$task is no longer complete at the manifest source."
  fi

  source_plist="$publish_temporary_root/source-Info.plist"
  public_key="$(resolve_public_key_at_ref "$source" "$source_plist")"
  public_key_fingerprint="$($manifest_tool fingerprint-public-key --public-key "$public_key")"
  resolve_release_identity
  "$repository_root/scripts/setup-update-signing.sh" --check >/dev/null
  "$manifest_tool" validate --manifest "$manifest_path" --staging-dir "$manifest_directory" \
    --signing-fingerprint "$signing_fingerprint" \
    --public-key-fingerprint "$public_key_fingerprint"
  verify_prepared_manifest_seal "$manifest_tool" "$manifest_path" "$public_key"
  "$manifest_tool" validate-public --manifest "$manifest_path" \
    --public-manifest "$manifest_directory/artifacts/release-manifest.json"
  "$manifest_tool" verify-feed-artifacts \
    --appcast "$manifest_directory/artifacts/appcast.xml" \
    --archive "$manifest_directory/artifacts/Whisper-$version.zip" \
    --public-key "$public_key" \
    --version "$version"

  if [ -n "$base_sha" ]; then
    git merge-base --is-ancestor "$base_sha" "$source" \
      || fail "manifest base is not an ancestor of its source."
    commit_range="$base_sha..$source"
  else
    commit_range="$source"
  fi
  if [ -n "$phase" ]; then
    if [ "$phase" = 'initial' ]; then
      [ "$version" = '1.0.0' ] && [ -z "$base_tag$base_sha" ] \
        || fail "initial bootstrap manifest must describe version 1.0.0 with no base."
    else
      [ "$version" = '1.0.1' ] && [ "$base_tag" = 'v1.0.0' ] && [ -n "$base_sha" ] \
        || fail "bootstrap update manifest must describe version 1.0.1 after v1.0.0."
    fi
    included_commit_records=()
    while IFS= read -r commit_record; do
      included_commit_records+=("$commit_record:task")
    done < <(git rev-list --reverse "$commit_range")
  else
    classify_normal_commits "$task" "$commit_range" "${base_sha:-none}"
  fi
  expected_commit_records="$(printf '%s\n' "${included_commit_records[@]}")"
  manifest_commit_records="$($manifest_tool field --manifest "$manifest_path" --name commitRecords)"
  [ "$manifest_commit_records" = "$expected_commit_records" ] \
    || fail "manifest commit mapping no longer matches repository history."

  latest_tag="$(latest_release_tag)"
  draft_state="$(release_draft_state "$tag")"
  if [ "$draft_state" = 'false' ]; then
    [ "$latest_tag" = "$tag" ] || fail "existing published release is not latest."
  else
    expected_latest="$base_tag"
    [ "$latest_tag" = "$expected_latest" ] \
      || fail "published release state changed after candidate preparation."
    expected_version="$(next_version_for_tag "$latest_tag")"
    [ "$expected_version" = "$version" ] \
      || fail "manifest version is not the next published patch."
  fi
  if [ -n "$base_tag" ]; then
    [ "$(git rev-parse "$base_tag^{commit}" 2>/dev/null || true)" = "$base_sha" ] \
      || fail "manifest base tag no longer resolves to its recorded source."
  else
    [ -z "$base_sha" ] || fail "manifest base release is inconsistent."
  fi
  if [ "$phase" = 'update' ]; then
    mkdir -p "$publish_temporary_root/base-release"
    download_release_asset "$base_tag" release-manifest.json "$publish_temporary_root/base-release"
    previous_manifest="$publish_temporary_root/base-release/release-manifest.json"
    [ "$($manifest_tool field --manifest "$previous_manifest" --name taskID)" = 'WH-M7-004' ] \
      && [ "$($manifest_tool field --manifest "$previous_manifest" --name sourceSHA)" = "$base_sha" ] \
      && [ "$($manifest_tool field --manifest "$previous_manifest" --name version)" = '1.0.0' ] \
      && [ "$($manifest_tool field --manifest "$previous_manifest" --name bootstrapPhase)" = 'initial' ] \
      || fail "bootstrap update base is not the verified WH-M7-004 initial release."
  fi

  tag_sha="$(remote_tag_sha "$tag")"
  if [ -z "$tag_sha" ]; then
    gh api --method POST repos/yurybv/whisper/git/refs \
      -f "ref=refs/tags/$tag" -f "sha=$source" >/dev/null
    tag_sha="$(remote_tag_sha "$tag")"
  fi
  [ "$tag_sha" = "$source" ] || fail "release tag does not target the manifest source."

  if [ -z "$draft_state" ]; then
    notes_file="$publish_temporary_root/release-notes.md"
    "$manifest_tool" write-release-notes --manifest "$manifest_path" --output "$notes_file"
    gh release create "$tag" --repo yurybv/whisper --verify-tag --draft --latest=false \
      --title "Whisper $version" --notes-file "$notes_file" >/dev/null
    draft_state="$(release_draft_state "$tag")"
  fi
  [ "$draft_state" = 'true' ] || [ "$draft_state" = 'false' ] \
    || fail "release draft could not be reconciled."
  validate_release_metadata "$tag" "$version" "$manifest_tool" "$manifest_path"

  if [ "$draft_state" = 'true' ]; then
    asset_names="$(release_asset_names "$tag")"
    validate_release_asset_inventory "$asset_names" "$version" no
    for asset in "$manifest_directory/artifacts/$zip_name" \
      "$manifest_directory/artifacts/appcast.xml" \
      "$manifest_directory/artifacts/release-manifest.json"; do
      if printf '%s\n' "$asset_names" | grep -Fx "$(basename "$asset")" >/dev/null; then
        mkdir -p "$publish_temporary_root/existing"
        download_release_asset "$tag" "$(basename "$asset")" "$publish_temporary_root/existing"
        cmp -s "$asset" "$publish_temporary_root/existing/$(basename "$asset")" \
          || fail "existing draft asset conflicts with the prepared artifact: $(basename "$asset")."
      else
        gh release upload "$tag" "$asset" --repo yurybv/whisper >/dev/null
      fi
    done
    asset_names="$(release_asset_names "$tag")"
    validate_release_asset_inventory "$asset_names" "$version" yes
    verify_release_downloads "$tag" "$manifest_directory" "$version" "$manifest_tool" \
      "$public_key" "$publish_temporary_root/authenticated"
    gh release edit "$tag" --repo yurybv/whisper --draft=false --latest >/dev/null
  else
    asset_names="$(release_asset_names "$tag")"
    validate_release_asset_inventory "$asset_names" "$version" yes
    verify_release_downloads "$tag" "$manifest_directory" "$version" "$manifest_tool" \
      "$public_key" "$publish_temporary_root/authenticated"
  fi

  verify_public_release "$tag" "$manifest_directory" "$version" "$manifest_tool" \
    "$public_key" "$publish_temporary_root/public"
  printf 'Published %s as %s\nManifest: %s\n' "$task" "$tag" "$manifest_path"
}

prepare_release() {
  local source_plist latest_tag version base_tag_value base_sha_value final_stage existing_manifest
  local previous_manifest previous_task previous_source previous_version previous_phase
  mkdir -p "$release_root"
  [ ! -L "$release_root" ] || fail "release staging root must not be a symbolic link."

  prepare_temporary_root="$(mktemp -d "$release_root/.prepare.XXXXXX")"
  prepare_worktree=""
  trap cleanup_prepare EXIT
  local manifest_tool="$prepare_temporary_root/release-manifest"
  compile_manifest_tool "$manifest_tool"
  source_plist="$prepare_temporary_root/source-Info.plist"
  public_update_key="$(resolve_public_key_at_ref "$source_sha" "$source_plist")"
  public_key_fingerprint="$("$manifest_tool" fingerprint-public-key --public-key "$public_update_key")"
  resolve_release_identity
  [ -x "$repository_root/scripts/setup-update-signing.sh" ] \
    || fail "update signing helper is missing."
  "$repository_root/scripts/setup-update-signing.sh" --check >/dev/null

  latest_tag="$(latest_release_tag)"
  version="$(next_version_for_tag "$latest_tag")"
  base_tag_value='none'
  base_sha_value='none'
  if [ -n "$latest_tag" ]; then
    base_tag_value="$latest_tag"
    base_sha_value="$(git rev-parse "$latest_tag^{commit}" 2>/dev/null || true)"
    [ -n "$base_sha_value" ] || fail "latest published release tag is missing locally."
    git merge-base --is-ancestor "$base_sha_value" "$source_sha" \
      || fail "latest release is not an ancestor of the requested source."
    [ "$base_sha_value" != "$source_sha" ] || fail "normal release has no new source changes."
    previous_manifest="$prepare_temporary_root/release-manifest.json"
    gh release download "$latest_tag" --repo yurybv/whisper \
      --pattern release-manifest.json --dir "$prepare_temporary_root" >/dev/null \
      || fail "latest release manifest is unavailable."
    [ -f "$previous_manifest" ] || fail "latest release manifest is unavailable."
    previous_task="$($manifest_tool field --manifest "$previous_manifest" --name taskID)"
    previous_source="$($manifest_tool field --manifest "$previous_manifest" --name sourceSHA)"
    previous_version="$($manifest_tool field --manifest "$previous_manifest" --name version)"
    previous_phase="$($manifest_tool field --manifest "$previous_manifest" --name bootstrapPhase)"
    [ "$previous_source" = "$base_sha_value" ] \
      || fail "latest release manifest source does not match its tag."
    [ "v$previous_version" = "$latest_tag" ] \
      || fail "latest release manifest version does not match its tag."
    if [ -z "$bootstrap_phase" ]; then
      [ "$previous_task" != "$task_id" ] \
        || fail "$task_id is already included in the published release history."
    fi
  fi

  if [ -n "$bootstrap_phase" ]; then
    if [ "$bootstrap_phase" = 'initial' ]; then
      [ -z "$latest_tag" ] && [ "$version" = '1.0.0' ] \
        || fail "initial bootstrap must prepare version 1.0.0 before any published release."
    else
      [ "$latest_tag" = 'v1.0.0' ] && [ "$version" = '1.0.1' ] \
        || fail "bootstrap update must prepare version 1.0.1 after v1.0.0."
      [ "$previous_task" = 'WH-M7-004' ] && [ "$previous_phase" = 'initial' ] \
        || fail "bootstrap update requires the verified WH-M7-004 initial release."
    fi
  fi

  final_stage="$release_root/$task_id-$source_sha"
  existing_manifest="$final_stage/release-manifest.local.json"
  if [ -e "$final_stage" ]; then
    [ -f "$existing_manifest" ] || fail "existing release staging directory is incomplete."
    "$manifest_tool" validate --manifest "$existing_manifest" --staging-dir "$final_stage" \
      --signing-fingerprint "$signing_fingerprint" \
      --public-key-fingerprint "$public_key_fingerprint"
    verify_prepared_manifest_seal "$manifest_tool" "$existing_manifest" "$public_update_key"
    [ "$("$manifest_tool" field --manifest "$existing_manifest" --name taskID)" = "$task_id" ] \
      || fail "existing prepared candidate belongs to another task."
    [ "$("$manifest_tool" field --manifest "$existing_manifest" --name sourceSHA)" = "$source_sha" ] \
      || fail "existing prepared candidate belongs to another source."
    [ "$("$manifest_tool" field --manifest "$existing_manifest" --name version)" = "$version" ] \
      || fail "existing prepared candidate conflicts with current release state."
    printf 'Prepared %s as %s\nManifest: %s\n' "$task_id" "$version" "$existing_manifest"
    return
  fi

  local commit_range
  if [ "$base_sha_value" = 'none' ]; then
    commit_range="$source_sha"
  else
    commit_range="$base_sha_value..$source_sha"
  fi
  if [ -n "$bootstrap_phase" ]; then
    included_commit_records=()
    while IFS= read -r commit; do
      included_commit_records+=("$commit:task")
    done < <(git rev-list --reverse "$commit_range")
    [ "${#included_commit_records[@]}" -gt 0 ] \
      || fail "bootstrap release has no new source changes."
  else
    classify_normal_commits "$task_id" "$commit_range" "$base_sha_value"
  fi

  prepare_worktree="$prepare_temporary_root/worktree"
  local candidate_stage="$prepare_temporary_root/stage"
  local artifacts="$candidate_stage/artifacts"
  mkdir -p "$artifacts"
  git worktree add --quiet --detach "$prepare_worktree" "$source_sha"
  (
    cd "$prepare_worktree"
    ./scripts/verify.sh >"$prepare_temporary_root/verification.log" 2>&1
    ./scripts/package.sh --release-version "$version" >"$prepare_temporary_root/package.log" 2>&1
  ) || fail "exact-source verification or packaging failed."

  local app="$prepare_worktree/build/Whisper.app"
  validate_release_bundle "$app" "$version"
  local zip_relative="artifacts/Whisper-$version.zip"
  local appcast_relative='artifacts/appcast.xml'
  local notes_relative='release-notes.md'
  ditto -c -k --sequesterRsrc --keepParent "$app" "$candidate_stage/$zip_relative"

  {
    printf '# Whisper %s\n\n' "$version"
    printf -- '- Task: `%s`\n' "$task_id"
    printf -- '- Source: `%s`\n\n' "$source_sha"
    printf '## Changes\n\n'
    git log --reverse --format='- %s' "$commit_range"
    printf '\n## Verification\n\n- Canonical verification and signed artifact validation passed on the release Mac.\n'
    printf '\n## Known personal-testing limitation\n\n- `WH-M6-014` still tracks the unresolved Right Option/menu-started dictation stop report; this release does not claim MVP acceptance.\n'
  } >"$candidate_stage/$notes_relative"
  cp "$candidate_stage/$notes_relative" "$artifacts/Whisper-$version.md"

  local generate_appcast sign_update
  generate_appcast="$(resolve_appcast_tool "$prepare_worktree")"
  sign_update="${generate_appcast%/*}/sign_update"
  [ -x "$sign_update" ] || fail "Pinned Sparkle sign_update tool is unavailable."
  "$generate_appcast" \
    --download-url-prefix "https://github.com/yurybv/whisper/releases/download/v$version/" \
    --embed-release-notes \
    --maximum-deltas 0 \
    --versions "$version" \
    "$artifacts" >/dev/null
  rm "$artifacts/Whisper-$version.md"
  [ -f "$candidate_stage/$appcast_relative" ] || fail "Sparkle did not generate appcast.xml."
  "$manifest_tool" verify-feed \
    --appcast "$candidate_stage/$appcast_relative" \
    --archive "$candidate_stage/$zip_relative" \
    --bundle-plist "$app/Contents/Info.plist" \
    --public-key "$public_update_key" \
    --version "$version"

  local manifest_arguments=(
    write
    --staging-dir "$candidate_stage"
    --recorded-staging-dir "$final_stage"
    --task-id "$task_id"
    --source-sha "$source_sha"
    --base-tag "$base_tag_value"
    --base-sha "$base_sha_value"
    --version "$version"
    --bootstrap-phase "${bootstrap_phase:-none}"
    --verification-source './scripts/verify.sh'
    --verification-evidence 'Canonical verification passed for the exact source checkpoint.'
    --signing-fingerprint "$signing_fingerprint"
    --public-key-fingerprint "$public_key_fingerprint"
    --zip-relative "$zip_relative"
    --appcast-relative "$appcast_relative"
    --release-notes-relative "$notes_relative"
  )
  local commit_record
  for commit_record in "${included_commit_records[@]}"; do
    manifest_arguments+=(--commit "$commit_record")
  done
  "$manifest_tool" "${manifest_arguments[@]}"
  "$sign_update" -p "$candidate_stage/release-manifest.local.json" \
    >"$candidate_stage/release-manifest.local.ed25519"
  verify_prepared_manifest_seal \
    "$manifest_tool" "$candidate_stage/release-manifest.local.json" "$public_update_key"

  git worktree remove --force "$prepare_worktree"
  prepare_worktree=''
  mv "$candidate_stage" "$final_stage"
  local final_manifest="$final_stage/release-manifest.local.json"
  "$manifest_tool" validate --manifest "$final_manifest" --staging-dir "$final_stage" \
    --signing-fingerprint "$signing_fingerprint" \
    --public-key-fingerprint "$public_key_fingerprint"
  printf 'Prepared %s as %s\nManifest: %s\n' "$task_id" "$version" "$final_manifest"
}

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
release_root="${WHISPER_RELEASE_ROOT:-$(dirname "$repository_root")/.whisper-releases}"
mode=""
task_id=""
source_sha=""
bootstrap_phase=""
manifest_path=""

case "${1:-}" in
  --prepare)
    mode='prepare'
    shift
    ;;
  --publish)
    mode='publish'
    shift
    ;;
  *) fail "usage: scripts/release-local.sh --prepare --task WH-ID --source FULL_SHA [--bootstrap initial|update] | --publish --manifest ABSOLUTE_PATH" ;;
esac

while [ "$#" -gt 0 ]; do
  case "$1" in
    --task)
      [ "$#" -ge 2 ] || fail "--task requires a value."
      task_id="$2"
      shift 2
      ;;
    --source)
      [ "$#" -ge 2 ] || fail "--source requires a value."
      source_sha="$2"
      shift 2
      ;;
    --bootstrap)
      [ "$#" -ge 2 ] || fail "--bootstrap requires a value."
      bootstrap_phase="$2"
      shift 2
      ;;
    --manifest)
      [ "$#" -ge 2 ] || fail "--manifest requires a value."
      manifest_path="$2"
      shift 2
      ;;
    *) fail "unknown release argument: $1" ;;
  esac
done

for command_name in git gh xcrun; do
  require_command "$command_name"
done

cd "$repository_root"

account="$(gh api user --jq .login 2>/dev/null || true)"
[ "$account" = 'yurybv' ] || fail "GitHub account must be yurybv; found ${account:-none}."

origin_url="$(git config --get remote.origin.url 2>/dev/null || true)"
[ "$origin_url" = 'https://github.com/yurybv/whisper.git' ] \
  || fail "origin must be https://github.com/yurybv/whisper.git."

branch="$(git branch --show-current)"
[ "$branch" = 'master' ] || fail "delivery branch must be master."
[ -z "$(git status --short)" ] || fail "delivery worktree must be clean."

git fetch --quiet origin master --tags
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] \
  || fail "delivery checkout must be synchronized with origin/master."

if [ "$mode" = 'prepare' ]; then
  [[ "$task_id" =~ ^WH-M[0-9]+-[0-9]{3}$ ]] || fail "--task must be a Whisper task ID."
  [[ "$source_sha" =~ ^[0-9a-f]{40}$ ]] || fail "source must be a full 40-character commit SHA."
  resolved_source="$(git rev-parse "$source_sha^{commit}" 2>/dev/null || true)"
  [ "$resolved_source" = "$source_sha" ] || fail "source commit does not exist."
  git merge-base --is-ancestor "$source_sha" origin/master \
    || fail "source must belong to origin/master."
  task_status="$(task_status_at_ref "$source_sha" "$task_id")"
  if [ -z "$bootstrap_phase" ]; then
    [ "$task_status" = 'done' ] || fail "$task_id must be done before a normal release."
  else
    validate_bootstrap_request
  fi

  prepare_release
  exit 0
fi

[ -n "$manifest_path" ] || fail "--publish requires --manifest."
[ -z "$task_id$source_sha$bootstrap_phase" ] || fail "--publish accepts only --manifest."
[ "${manifest_path#/}" != "$manifest_path" ] || fail "manifest path must be absolute."
[ -d "$release_root" ] || fail "release staging root does not exist."
require_command curl
publish_release
