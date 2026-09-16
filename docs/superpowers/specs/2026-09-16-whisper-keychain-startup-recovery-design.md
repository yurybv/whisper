# Whisper Keychain Startup Recovery Design

**Date:** 2026-09-16
**Status:** Approved, implemented, and delivered
**Related release task:** WH-M6-003

## Problem

The packaged ad-hoc Release build can have a different code-signing hash from the Debug build that originally saved the OpenAI API key. macOS then requires authorization before the new build may decrypt that existing Keychain item.

Whisper currently reads the secret from automatic startup paths, including Settings state construction and meeting-recovery availability. That happens before release acceptance can use the app, so `SecItemCopyMatching` can block behind a system authorization dialog. During release acceptance, macOS placed that dialog on an unavailable external display and the installed app never finished launching.

This also conflicts with the approved MVP specification: the secret value should be read from Keychain on the first OpenAI request of an app session, not during application startup.

## Goals

- Whisper reaches its menu bar and main window without decrypting the API key.
- Settings can distinguish a missing item from a present item without exposing the secret.
- A Keychain item that the current build cannot decrypt produces a safe, recoverable error instead of an automatic authorization dialog or launch hang.
- The secret remains only in Keychain and the existing in-process cache after a successful read.
- Save, Replace, Remove, and Test Connection remain explicit user actions.

## Non-goals

- Rewriting Keychain ACLs or code-signing requirements.
- Copying, exporting, logging, or migrating the secret outside Keychain.
- Changing ad-hoc packaging, Developer ID signing, notarization, or distribution scope.
- Automatically deleting an inaccessible Keychain item.

## Considered approaches

### 1. Noninteractive presence check plus deferred noninteractive secret read — selected

Add a secret-free presence query for Settings and defer the real secret read until an OpenAI operation needs it. Both queries disallow authentication UI. An inaccessible item therefore reports a safe Keychain error without blocking startup.

This matches the approved API-key lifecycle, preserves accurate Settings state, and keeps system authorization under explicit user control.

### 2. Only defer the existing interactive read

The app would launch, but Settings could not accurately distinguish a saved key from a missing one without decrypting it. The first OpenAI action could still open an unexpected system dialog and block its calling thread. This only moves the failure.

### 3. Rewrite the existing Keychain ACL for every packaged build

This would give the current ad-hoc CDHash access to the old item, but requires privileged authorization, mutates security metadata, and must be repeated whenever the build hash changes. It is unsuitable for application behavior and release automation.

## Design

### Secure-store contract

Extend `SecureStore` with a presence operation that answers whether the configured item exists without returning its data. Implementations behave as follows:

- `KeychainSecureStore` performs an attributes-only lookup with authentication interaction disabled. A fresh noninteractive `LAContext` covers the Data Protection keychain path, while a short serialized `SecKeychainSetUserInteractionAllowed(false)` scope covers older login-keychain items and restores the previous process setting immediately after each automatic lookup.
- `InMemorySecureStore` checks whether its in-memory value exists.
- `CachingSecureStore` returns `true` when it already has a nonempty cached key; otherwise it delegates the presence lookup without populating the secret cache.

The existing read method remains responsible for returning the secret. Its Keychain query uses the same modern and legacy interaction suppression. If macOS requires authorization, the method returns the existing safe `FeatureError.keychain` rather than presenting UI. Explicit save, replace, and remove operations are serialized against those short noninteractive scopes but continue to permit user interaction.

### Startup and Settings flow

`SettingsModel` uses the presence operation during initialization and refresh. It never calls the secret-reading method merely to render `Saved in Keychain` or `Not configured`.

Startup meeting recovery also uses presence rather than reading the secret merely to decide whether processing is available, and it skips that availability check entirely when no durable captured, transcribing, or processing job needs it. A resumed job reads the secret only when its actual OpenAI request begins.

The application can therefore finish `AppRuntime` initialization even when the current ad-hoc build cannot decrypt an older item. If the presence lookup itself fails, Settings uses its existing safe Keychain-read error and treats the key as unavailable.

### OpenAI flow

The first Test Connection, dictation transcription, meeting transcription, or processing request calls the existing cached secret read. Outcomes are:

- accessible nonempty key: cache it for the current process and continue;
- missing or empty key: use the existing missing-key recovery;
- inaccessible key: use the existing Keychain error and direct the user to Settings;
- subsequent request after a successful read: use only the in-process cache.

Save, Replace, and Remove continue to run only after explicit user actions. The app does not silently delete or overwrite an inaccessible item. If macOS requires authorization for one of those explicit mutations, the operating system may request it at that point.

## Error handling and privacy

- No OSStatus detail, Keychain payload, API key, Authorization header, or provider response body is logged or displayed.
- Presentation uses the existing generic Keychain error text.
- Failed presence and secret reads are not cached so recovery remains possible after the user repairs Keychain access.
- No authorization dialog is triggered by application launch, window opening, navigation, or Settings refresh.

## Testing

Automated coverage will verify:

- presence checks do not read or cache the secret;
- cached keys report present without another backing-store call;
- Settings initialization and refresh use presence, not secret read;
- missing, present, and failed-presence states remain recoverable and secret-safe;
- Keychain read and presence queries carry a noninteractive authentication context;
- existing save, replace, remove, cache, and OpenAI missing-key tests continue to pass.

Release verification will rebuild and install the current package, launch it against the existing mismatched development Keychain ACL without cursor automation, and confirm through process/window state that initialization completes without a SecurityAgent window. Live API and permission acceptance remain separate because they require explicit system authorization and the external-display constraint still applies.

## Acceptance criteria

- Launching a newly ad-hoc-signed package with an older Whisper Keychain item does not block the main thread or create an automatic authorization dialog.
- The app reaches a usable window or menu-bar state and shows a safe recoverable Keychain status.
- The key value remains undisclosed and is read only when an OpenAI operation explicitly needs it.
- Unit, UI, privacy, packaging, and signature checks pass.
