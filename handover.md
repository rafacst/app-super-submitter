# Super Submitter handover

Updated: 2026-08-02

## Current state

The original high-fidelity prototype is now functional through Review info
(UI audit items 1–8 / tabs 1–6). All local edits save to the active
`store.yaml`; secrets save to macOS Keychain.

1. **New app**
   - Creates `store.yaml`, persists the linked app, loads it, and selects it.
2. **Add locale**
   - Validates and normalizes locale codes, adds the manifest block, and
     updates the locale picker.
3. **Stores**
   - Adds/removes store manifest blocks, edits identifiers, imports Apple and
     Google credentials into Keychain, tests both connections, and links to
     the relevant consoles.
4. **Build / listing import**
   - Selects or drops `.ipa`, `.pkg`, and `.aab` builds; parses real package
     metadata; detects identifier/version mismatches; imports current Apple
     and Google listing text.
5. **Details**
   - Every field is a native `TextField` or `TextEditor` bound to the active
     locale. Counters, limit errors, store-only visibility, Google overrides,
     and both store previews derive from the manifest.
6. **Media**
   - Image and Apple preview selection/drop are live. File types, image
     readability, Apple bucket dimensions, Google size/aspect rules, preview
     duration (15–30 seconds), and per-bucket counts are checked before paths
     are saved. Invalid Apple dimensions report the nearest accepted size.
     Paths inside the app repository remain relative. Tiles show actual
     thumbnails/dimensions and support removal.
     The Google YouTube URL edits the active locale.
7. **Money**
   - Provider, base price, purchases, subscription groups/plans,
     entitlements/access levels, and offerings/paywalls are editable and
     persisted.
   - RevenueCat's v2 secret is in Keychain; project lookup and authentication
     testing are live. The result explicitly states that write scopes are not
     yet verified. Adapty CLI status/whoami, copy, signup, and Console links
     are live.
8. **Review info**
   - Contact, notes, demo-account requirement, categories, age-rating answers,
     data-safety answers, and export compliance are manifest-backed.
   - Reviewer username/password are Keychain-backed. Review actions open live
     forms or navigate to the relevant tab/console.

The user-supplied icon is bundled as an executable resource and applied to
`NSApplication` at startup. The original Icon Composer folder remains at
`super-submitter-icon.icon/` for a future signed Xcode app target.

Relevant implementation files:

- `Sources/SuperSubmitter/AppState.swift`
- `Sources/SuperSubmitter/SuperSubmitterApp.swift`
- `Sources/SuperSubmitter/Tabs/DetailsTab.swift`
- `Sources/SuperSubmitter/Tabs/MediaTab.swift`
- `Sources/SuperSubmitter/Tabs/MoneyTab.swift`
- `Sources/SuperSubmitter/Tabs/ReviewInfoTab.swift`
- `Sources/SubmitKit/Assets/AssetInspector.swift`
- `Sources/SubmitKit/Clients/ProviderConnectionClient.swift`
- `Sources/SubmitKit/Credentials/Credentials.swift`
- `Sources/SubmitKit/Manifest/ManifestEditing.swift`
- `Tests/SubmitKitTests/ManifestEditingTests.swift`

## Verification completed

```sh
swift build
swift test
```

Both pass. There are 29 Swift Testing tests. Run a launch smoke test after
future UI changes. Live store/provider calls were not executed because this
workspace has no user credentials.

## Remaining UI audit work

Continue in this order.

### 9. Plan — audit item 9, SPEC 7.2 and 10

- Build Apple, Google, and provider read clients and actual-state models.
- Replace `DemoData.diffColumns`, counts, and validation rows with a real
  planner in SubmitKit.
- Implement every validation in SPEC section 10 with unit tests.
- Make “Read the stores again” refresh actual state.
- Dry run must build/log requests without sending them; it currently affects
  only labels.

### 10. Submit/apply — audit item 10, SPEC 7.3–7.8 and 11

- Replace the timer-driven `DemoData.runItems` with a Runner in SubmitKit.
- Implement ordered Apple/Google apply flows, uploads, provider sync,
  retry/rate-limit handling, idempotency, cancellation, and Google edit
  cleanup.
- Append redacted JSONL call records under
  `.super-submitter/runs/<timestamp>.jsonl`.

### 11. Release/status — audit item 11, SPEC 7.9–7.10 and 16.6

- Wire checklist copy/open/re-check actions to real shared state.
- Implement separate Apple review-submission and Google track-commit flows.
- Poll released stores, post macOS notifications on changes, and drive the
  menu-bar status from actual reads.

### 12–13. Settings and shell status — audit items 12–13

- Connect poll interval to the status poller.
- Initialize new-app Plan dry run from `dryRunByDefault`.
- Add the manifest-path row required by SPEC 16.5.
- Replace hardcoded menu-bar timestamps/status and demo app health.

## Follow-up work within tabs 1–6

The controls are wired, but the following service/deployment work remains:

- Add the per-tab raw YAML editor/toggle from SPEC 16.1.
- Add media reordering and implement Apple reservation/chunk uploads plus
  Google multipart uploads.
- Read Apple price points and territory availability, warn on a price
  difference over 5%, and implement store purchase/subscription clients.
- Implement the full RevenueCat scope check/mirroring and Adapty mutation
  wrapper, including archive-not-delete behavior.
- Use per-store review notes if the schema is extended; implement Apple age
  rating/privacy writes and Google data-safety writes.
- Share Console-only checklist state between Review and Release in
  `.super-submitter/console-state.json`.
- Add Open existing app, app removal/rename, signed Xcode target, sandbox
  bookmarks/entitlements, production icon catalog, signing, and notarization.
- Add redacted HTTP record/replay fixtures and signed-host Keychain tests.

## Safety constraints

- Plan reads only. Apply leaves drafts. Release is the only review action.
- Never combine Apple and Google release buttons.
- Apple has no sandbox; keep dry run on by default for new apps.
- Always delete a temporary Google edit on failure or cancellation.
- Never log, persist to YAML, or commit Apple, Google, RevenueCat, or reviewer
  secrets.
- The stores are the source; providers mirror them.
- Keep store/provider business logic in SubmitKit and SwiftUI views thin.
