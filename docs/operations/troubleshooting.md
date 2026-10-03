# Update troubleshooting

Keep the last working `/Applications/Whisper.app`, the prepared staging directory, and every published release asset intact while diagnosing an update. Do not rotate signing keys, replace release assets, weaken Gatekeeper, reset privacy databases, or delete application data as a shortcut.

## Update is not offered

1. Read the installed version in Settings and confirm the app is the copy at `/Applications/Whisper.app`.
2. Use **Check for Updates…** once while the Mac is online. Development `0.0.0` builds intentionally do not run the updater.
3. Verify the public latest `appcast.xml`, its enclosure URL, and the tagged ZIP/public manifest through the release operator workflow. Do not republish or edit an existing asset.
4. If GitHub is temporarily unavailable, leave the installed app untouched and retry later. Offline checks must remain non-destructive.

## Installation is waiting

Whisper intentionally defers installation while dictation, recording, finalization, transcription, transformation, insertion, or other protected processing is active. Finish or cancel the work through Whisper's normal UI, wait for the app to become idle, and let Sparkle retry. Never force-quit or discard work to advance an update.

## Signature, key, feed, or digest failure

- Retain the exact local manifest and staging directory.
- Compare the public ZIP, appcast, and public manifest with their prepared bytes and recorded SHA-256 values.
- Check the configured Sparkle public key and local code-signing certificate fingerprints without printing private keys.
- Rerun publication with the same sealed manifest only when recovering an interrupted publish. The release command reconciles existing remote state and refuses conflicting assets.
- Do not delete a tag/release, overwrite an asset, rotate a key, or generate a new version to hide the failure.

The previously published latest release remains the recovery point. A post-publication verification failure is still a failed release check even if GitHub accepted the publish mutation.

## macOS confirmation or launch warning

The owner handles Touch ID, password, Gatekeeper, Keychain, and privacy confirmations directly in macOS. Never paste authentication into chat or a terminal command. Do not disable Gatekeeper or grant broader permissions than Whisper requests. Record the check as pending until the required local confirmation is completed.

## Permission or data continuity differs

Stop the acceptance run and leave both bundles and app-owned data in place. Record which named permission or synthetic identifier changed; do not inspect API-key contents, transcripts, recordings, clipboard data, or custom instructions. Compare bundle identifier, installed path, certificate, and designated requirement before changing any OS permission. An update-specific continuity regression blocks `WH-M7-004`; the pre-existing Right Option/menu-stop report remains separate under `WH-M6-014`.

## Recover the prior installed bundle

Use the recoverable same-volume backup created immediately before bootstrap installation. First confirm Whisper is idle and quit it normally. Preserve the failed bundle for diagnosis, restore the backup to `/Applications/Whisper.app`, verify its signature and recorded version, then launch it. Restoring a backup is recovery, not evidence that the Sparkle update passed.
