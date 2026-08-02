# Super Submitter handover

Updated: 2026-08-02

## Current state

The original UI was a high-fidelity demo. Audit items 1–4 are now wired to
real local/store functionality:

1. **New app**
   - Both New app rows open a save panel.
   - Saving creates `store.yaml`, adds it to the persisted app switcher, loads
     it, and selects the Stores tab.
   - Linked-app records are persisted in `UserDefaults`; the manifest remains
     the source of truth.
2. **Add locale**
   - The locale toolbar uses the manifest's locale keys.
   - Add opens a sheet, normalizes and validates the locale code, creates the
     locale block, saves `store.yaml`, and selects it.
3. **Stores**
   - Store cards add/remove the matching manifest block.
   - App id, bundle id, and package name are editable and saved.
   - `.p8` and service-account JSON files support file selection and drag/drop.
   - Secret contents are copied to generic-password Keychain items using
     `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`; the original files are
     not copied into the repository.
   - Apple connection testing creates a 15-minute ES256 JWT and reads
     `/v1/apps`, including pagination.
   - Google connection testing performs the service-account RS256 OAuth flow
     and makes a read-only Reviews request for the configured package. This
     verifies the mandatory Play Console invitation without writing.
   - Console help links now open real pages.
4. **Build / existing-app import**
   - `.ipa`, `.pkg`, and `.aab` rows support file selection and drag/drop.
   - `PackageReader` parses the real archive and updates build paths,
     identifiers, version, locales, app name, minimum OS, device classes,
     encryption, and privacy hints.
   - Paths below the manifest directory are saved relative to it.
   - Bundle/package mismatches and cross-platform version-name mismatches are
     shown immediately. “Use <version>” updates the manifest.
   - App Store apps come from the authenticated `/v1/apps` result. Android
     Publisher has no list-apps endpoint, so Google uses the package name
     entered and tested on Stores.
   - “Read current listings” imports Apple app-info/version localizations and
     Google listings. The temporary Google edit is deleted on success and on
     failure.

Relevant implementation files:

- `Sources/SuperSubmitter/AppState.swift`
- `Sources/SuperSubmitter/Shell/Sidebar.swift`
- `Sources/SuperSubmitter/Shell/TopBar.swift`
- `Sources/SuperSubmitter/Shell/RootView.swift`
- `Sources/SuperSubmitter/Overlays/AddLocaleSheet.swift`
- `Sources/SuperSubmitter/Tabs/StoresTab.swift`
- `Sources/SuperSubmitter/Tabs/BuildTab.swift`
- `Sources/SubmitKit/Credentials/Credentials.swift`
- `Sources/SubmitKit/Clients/StoreConnectionClient.swift`
- `Sources/SubmitKit/Manifest/ManifestEditing.swift`
- `Tests/SubmitKitTests/ManifestEditingTests.swift`

## Verification completed

```sh
swift build
swift test
```

Both pass. There are 23 Swift Testing tests. The executable was also launched
as a smoke test and opened without a startup crash.

Live store calls were not executed because this workspace has no user
credentials. Before shipping, record/replay one successful and one failure
response for each connection/import path, with all secrets redacted as
required by SPEC sections 12 and 17.

## Remaining UI functionality

Continue in this order. Each item below is still a prototype unless stated
otherwise.

### 1. Details — audit item 5, SPEC 16.3 Tab 3

- Replace every `TextWell` with a bound `TextField` or `TextEditor`.
- Bind the selected locale to `manifest.listing.locales[locale]` and save each
  edit to `store.yaml`.
- Implement the Google short-description and What's New override controls.
- Make counters derive from the edited text and `BindingLimits`.
- Replace “Drop the last two (demo)” with ordinary text editing; never
  truncate automatically.
- Make both store previews derive from the manifest and selected locale.
- Add the per-tab YAML editor/toggle required by SPEC 16.1.

### 2. Media — audit item 6, SPEC 6.3, 7.5, and 16.3 Tab 4

- Implement image/video file selection and drag/drop.
- Resolve globs relative to the manifest; write selected paths back as
  relative paths.
- Read image dimensions, map them through
  `Resources/screenshot-sizes.json`, and reject unknown buckets/types.
- Enforce Apple/Google counts and Apple preview duration/count rules.
- Replace placeholder tiles with thumbnails and add ordering/removal.
- Bind Google's YouTube URL to the selected locale.
- Implement checksum generation and the real Apple reservation/chunk upload
  and Google multipart upload flows.

### 3. Money — audit item 7, SPEC 6.4–6.8, 7.7–7.8, and Tab 5

- Replace styled text with editable pricing, country, purchase, subscription,
  entitlement, and offering controls bound to the manifest.
- Store the RevenueCat secret v2 key in Keychain and implement scope testing.
- Implement the Adapty CLI status/whoami checks and clipboard button.
- Wire signup/console links and Apple territory editing.
- Implement Apple/Google product and subscription clients.
- Implement RevenueCat mirroring and the Adapty `Process` wrapper. Preserve
  all archive-not-delete and provider-failure rules from SPEC 7.8 and 8.

### 4. Review info — audit item 8, SPEC 9.5 and Tab 6

- Bind review contact, notes, required-account toggle, ratings, categories,
  privacy fields, and export compliance to the manifest.
- Store reviewer username/password in Keychain, never YAML.
- Implement Answer/Edit/Review actions and real Console links.
- Share one console-step state model with Release; persist unknown checks in
  `.super-submitter/console-state.json` keyed by app/version.

### 5. Plan — audit item 9, SPEC 7.2 and 10

- Build Apple, Google, and optional provider read clients and actual-state
  models.
- Replace `DemoData.diffColumns`, counts, and validation rows with a real
  planner in SubmitKit.
- Implement every validation in SPEC section 10 with unit tests.
- Make “Read the stores again” refresh actual state.
- Dry run must build/log requests without sending them; it currently affects
  only labels.

### 6. Submit/apply — audit item 10, SPEC 7.3–7.8 and 11

- Replace the timer-driven `DemoData.runItems` sequence with a Runner in
  SubmitKit.
- Implement the ordered Apple and Google apply flows, screenshots/build
  uploads, provider sync, retry/rate-limit handling, and idempotency.
- Implement Cancel. Before Google commit it must delete the open edit.
- Append redacted JSONL call records under
  `.super-submitter/runs/<timestamp>.jsonl`.
- Implement the failure panels and recovery actions from SPEC section 11.

### 7. Release/status — audit item 11, SPEC 7.9–7.10 and 16.6

- Implement Copy as checklist using the pasteboard.
- Make every Open link launch the correct store/provider console.
- Make Re-check perform actual read calls and update shared checklist state.
- Replace local Boolean release confirmation with the real, separate Apple
  review-submission and Google track-commit flows.
- Poll only released stores, post macOS notifications on state changes, and
  drive the menu-bar status from real reads.

### 8. Settings and shell status — audit items 12–13, SPEC 7.10 and 16.5

- Connect poll interval to the status poller.
- Initialize a new app's Plan dry-run state from `dryRunByDefault`.
- Add the manifest-path row required by SPEC 16.5.
- Replace hardcoded menu-bar timestamps/statuses.
- Make app-row health and summaries derive from plan/store state instead of
  the temporary changed/blocked presentation.

## Follow-up hardening for completed items 1–4

- Add an **Open existing `store.yaml`** path and app removal/rename controls.
- Persist security-scoped bookmarks if the app is sandboxed later. The current
  plain SwiftPM executable can reopen paths directly.
- Add an Xcode app target, signing, Keychain access group, sandbox
  entitlements, icon, and notarization before distribution.
- Apple listing import currently reads iOS version localizations. Extend it
  to Mac App Store platforms and import review/category data in the Review
  milestone.
- Google import currently imports listing text only. Extend it to details,
  tracks, purchases, subscriptions, screenshots, and asset download as part
  of SPEC 7.1/M1.
- Add HTTP record/replay fixtures for pagination, 401, 403, rate limiting,
  malformed credentials, Google edit cleanup, and empty listings.
- Add Keychain integration tests in a signed test host. Do not put credential
  material in fixtures or logs.
- The app switcher falls back to the three visual demo apps until the first
  real manifest is created. Remove that fallback when onboarding can create
  or open a real manifest directly.

## Safety constraints for the next agent

- Plan reads only. Apply leaves drafts. Release is the only review action.
- Never combine the two release buttons.
- Apple has no sandbox; keep dry run on by default for new apps.
- Always delete a temporary Google import/edit on failure or cancellation.
- Never log, persist to YAML, or commit Apple, Google, RevenueCat, or reviewer
  secrets.
- Keep store/provider business logic in SubmitKit and SwiftUI views thin.
