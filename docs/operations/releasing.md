# Local release operations

Whisper releases are prepared and published from the owner's Mac. Source pushes do not authorize publication. Run the publish phase only after the owner explicitly requests a release; one request covers preparation, publication, and verification for that release. Never upload the local manifest, verification logs, signing key material, recordings, or transcripts.

## Preconditions

- The delivery checkout is clean, on `master`, and exactly synchronized with `origin/master`.
- `gh api user --jq .login` reports `yurybv` and `origin` is `https://github.com/yurybv/whisper.git`.
- The requested source is a full commit SHA reachable from `origin/master`.
- A normal task is `done` at that source. Its commits must form the next explainable range after the latest release; post-completion commits may only close task metadata.
- `Whisper Local Development` and the Sparkle EdDSA private key are available in the login Keychain. Run `./scripts/setup-update-signing.sh --check` to diagnose either prerequisite without printing secrets.

The command refuses incomplete or duplicate tasks, changed keys, dirty or diverged Git state, unexpected commits, reused versions, conflicting remote assets, and source checkpoints outside `origin/master`.

## Prepare a candidate

Resolve the completed task's final verified SHA from `origin/master`, then run:

```bash
./scripts/release-local.sh --prepare --task WH-MX-XXX --source FULL_40_CHARACTER_SHA
```

Preparation is local and read-only with respect to GitHub. It checks the current release state, assigns the next `1.0.PATCH` version, builds the exact source in a detached worktree, runs the canonical verification gate, packages and signs the app, creates the ZIP with `ditto`, and generates the appcast with the pinned Sparkle tool. It then verifies bundle metadata, architecture, code signing, feed URL/version/length, and the EdDSA enclosure signature.

The output includes an absolute path to `release-manifest.local.json`. Its staging directory lives outside the repository (by default beside the checkout under `.whisper-releases`). Keep that directory intact: publication consumes exactly those immutable artifacts and does not rebuild them. Repeating the same prepare command validates and returns the same candidate.

The staging directory contains:

- `release-manifest.local.json`, including local provenance and the absolute staging path;
- `release-manifest.local.ed25519`, a local-only seal over that provenance using the Sparkle key;
- `release-notes.md`;
- `artifacts/Whisper-<version>.zip`;
- `artifacts/appcast.xml`;
- `artifacts/release-manifest.json`, the sanitized public provenance record.

## Publish the prepared candidate

After confirming that the owner requested publication, use the exact manifest path printed by preparation:

```bash
./scripts/release-local.sh --publish --manifest /absolute/path/release-manifest.local.json
```

Publication reruns the repository, account, source, task/commit classification, bootstrap, key, signed-manifest, artifact, and signed-feed guards before any remote mutation. The public manifest must be the exact canonical sanitized form of the sealed local manifest. It then creates the exact lightweight tag, creates a draft release, uploads each missing artifact without overwriting an existing asset, and downloads all draft assets through authenticated GitHub access. Only a byte-for-byte matching draft is published as latest.

After publication, the command downloads the stable latest appcast and the exact tagged ZIP and public manifest through their public URLs. It verifies their bytes and the enclosure signature again. Success is reported only when GitHub also identifies the new tag as latest.

## Retry and failure behavior

Retry the same publish command after a network timeout or interrupted run. The command reconciles the existing tag, draft, and individual assets and resumes at the first missing step. It never replaces an uploaded asset or increments the version because of a retry. An identical already-published request verifies the public release and returns the same tag.

Before the final publish mutation, a failure leaves the previous latest release and feed unchanged. If the publish request may have succeeded but the response was lost, the retry observes the published release and performs only authenticated and public verification. A failed post-publication public URL check remains an explicit failure; retain the local staging directory and retry diagnosis without deleting or replacing the release.

## Bootstrap exception

The only incomplete-task exception is `WH-M7-004` while it is in `review`, with `WH-M7-001` through `WH-M7-003` already `done`:

```bash
./scripts/release-local.sh --prepare --task WH-M7-004 --source FULL_SHA --bootstrap initial
./scripts/release-local.sh --prepare --task WH-M7-004 --source FULL_SHA --bootstrap update
```

`initial` is restricted to `1.0.0` with no existing release. `update` is restricted to `1.0.1` immediately after a verified `WH-M7-004` initial manifest. The owner command for the bootstrap pair authorizes both publications and the one-time `/Applications/Whisper.app` installation workflow; it does not authorize unrelated releases.

Before requesting that command, commit and push the Task 4 checklist/evidence checkpoint, move `WH-M7-004` to `review`, and prepare the `initial` candidate locally. Report its exact task, source SHA, version, manifest path, artifact checks, and known limitations. Do not create a tag, draft, release, or installed-app replacement during this preparation.

After the bootstrap pair is authorized:

1. Publish the exact sealed `initial` manifest and verify the public latest appcast, tagged ZIP, and public manifest.
2. Download the public assets again, compare them with the prepared artifacts, extract the ZIP, and verify bundle version, identifier, architecture, nested signatures, certificate, and designated requirement.
3. Confirm Whisper has no active dictation, recording, finalization, or processing work. Preserve any existing `/Applications/Whisper.app` as a recoverable same-volume backup, then install the verified public `1.0.0` bundle at that exact path and launch it. Never force-quit active work.
4. Record the sanitized pre-update continuity state. Complete the prepared `1.0.0` checks, then commit and push only Task 4 acceptance evidence or a verified update-specific correction for the second checkpoint.
5. Prepare and publish the exact `update` manifest under the same authorization. Starting from installed `1.0.0`, use **Check for Updates…** and Sparkle's standard install/relaunch flow; do not manually replace the app with `1.0.1`.
6. Verify `1.0.1` remains at `/Applications/Whisper.app`, compare continuity, exercise the isolated failure fixtures, and record only sanitized results in `docs/testing/update-acceptance.md` and `docs/testing/evidence/WH-M7-004/qa.md`.

The acceptance matrix is the authority for pass/pending status. An automated result never substitutes for a live installed-app row. See [troubleshooting.md](troubleshooting.md) for recovery rules that preserve the last working app and immutable release assets.
