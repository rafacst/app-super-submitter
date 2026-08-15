# Prompt 1 — Critical UI fixes

Act as a senior macOS SwiftUI engineer. Implement only the critical UI fixes below in this repository.

## Repository constraints

- Keep the deployment target at macOS 14.
- Use native SwiftUI controls and existing project styles.
- Do not add a dependency or a new design system.
- Do not change an API request field, type, endpoint, or payload shape.
- Read the cited local API documents before each change.
- Preserve every current confirmation for a store write, submission cancellation, version deletion, and build expiry.
- Keep the custom Details inspector. The source comments explain why SwiftUI `.inspector` does not fit this window.
- Keep locale, price-point, territory, media-file, YouTube URL, credential, and Boolean controls in their current data types.
- For an API that exists only with Xcode 27 and macOS 27, use both gates below. Keep the current fallback.

```swift
#if compiler(>=6.4)
if #available(macOS 27.0, *) {
    // Xcode 27 and macOS 27 API
} else {
    // Existing fallback
}
#else
// Existing fallback
#endif
```

Do not use `#if macOS 27`. Swift does not support that syntax.

## C1. Make Dry Run safe by default for every app

### Reason

The current code turns Dry Run off whenever an app has shipped. This creates a live-write default for the highest-risk app state. The Settings preference must decide the initial state for every app. Its default value must remain `true`.

### API contract check

- `Sources/SubmitKit/Run/StoreAPI.swift` states that a dry run builds every request and sends none.
- `dryRun` is a client safety state. It is not an App Store Connect or Google Play request field.
- `Sources/SuperSubmitter/AppStateRun.swift` sends `is_dry_run` only to local product analytics.
- This change must not alter any store API payload.

### Replace this code

File: `Sources/SuperSubmitter/AppState.swift`

```swift
private func applyDryRunDefault() {
    guard isAppLive(appKey: currentAppKey) else {
        dryRun = defaults.object(forKey: "dryRunByDefault") as? Bool ?? true
        return
    }
    dryRun = false
}
```

### With this code

```swift
private func applyDryRunDefault() {
    dryRun = defaults.object(forKey: "dryRunByDefault") as? Bool ?? true
}
```

Update the visible Settings label in `Sources/SuperSubmitter/Tabs/SettingsTab.swift`.

```swift
Toggle(isOn: $dryRun) {
    Text("Start each app with Dry Run on")
    Text("A dry run logs every request and sends none.")
}
```

Do not remove app-liveness storage. Other product features use it.

### Required test changes

Update `Tests/SuperSubmitterUITests/DryRunDefaultTests.swift`.

- A published app must follow `dryRunByDefault`.
- The default must remain `true` when the preference does not exist.
- An explicit `false` preference must remain supported.
- App switches must recompute the preference without an app-liveness exception.

## C2. Replace the custom Dry Run switch with the native macOS switch

### Reason

The custom switch copies a native control. The native control supplies keyboard operation, focus, VoiceOver state, and system metrics.

### API contract check

The switch changes only `AppState.dryRun`. It does not change an endpoint parameter or a request body.

### Replace this code

File: `Sources/SuperSubmitter/Shell/RootView.swift`

```swift
HeaderCluster(morphOn: shape) {
    Text("Dry run").font(Theme.font(size: 12)).foregroundStyle(Theme.text2)
    SmallToggle(isOn: Binding(
        get: { state.dryRun },
        set: { value in
            guard value || state.requirePaid(.storeWrite, .apply) else { return }
            if value { state.dryRun = true } else { armingLiveWrites = true }
        }))
}
```

### With this code

```swift
HeaderCluster(morphOn: shape) {
    Toggle("Dry run", isOn: Binding(
        get: { state.dryRun },
        set: { value in
            guard value || state.requirePaid(.storeWrite, .apply) else { return }
            if value { state.dryRun = true } else { armingLiveWrites = true }
        }))
        .toggleStyle(.switch)
        .controlSize(.small)
        .accessibilityHint("When on, Super Submitter builds each request and sends none.")
}
```

Delete `SmallToggle` from `Sources/SuperSubmitter/Design/Theme.swift` after `rg "SmallToggle"` shows no caller.

Keep this destructive confirmation when the user turns Dry Run off:

```swift
.confirmationDialog("Turn the dry run off?", isPresented: $armingLiveWrites,
                    titleVisibility: .visible) {
    Button("Turn it off", role: .destructive) { state.dryRun = false }
    Button("Keep the dry run on", role: .cancel) {}
}
```

## C3. Replace the ambiguous Apply labels with exact draft-write labels

### Reason

“Apply” does not state whether the app writes a draft, submits a review, or publishes to customers. Use labels that state the result.

### API contract check

- Apple draft metadata uses update endpoints such as `docs/appstore-connect-api/PATCH-v1-appStoreVersions-_id_.md`.
- Google listing updates use `docs/google-play-developer-api/methods/edits.listings.update.md`.
- Google publishes an edit only through `docs/google-play-developer-api/methods/edits.commit.md`.
- Keep the Release tab separate. Do not move a commit or review-submission call into these buttons.

### Change the Summary runway

File: `Sources/SuperSubmitter/Tabs/PlanTab.swift`

```swift
RunwayEntry(number: 4, title: "Update Drafts",
            caption: RunwayStep.apply(state), tab: nil),
```

Keep the internal `apply` function names. Only change visible UI text.

### Change the Summary primary action

Replace:

```swift
Menu(state.dryRun ? "Dry run" : "Apply") {
```

With:

```swift
Menu(state.dryRun ? "Preview Requests" : "Update Drafts") {
```

Replace the write confirmation strings with exact draft language:

```swift
.confirmationDialog("Update \(confirmingStore?.storeName ?? state.storeListText) drafts?",
                    isPresented: $confirmingApply,
                    titleVisibility: .visible) {
    Button(confirmingStore == nil ? "Update the drafts" : "Update the draft") {
        if let store = confirmingStore { state.startRun(to: store) }
        else { state.startRun() }
        confirmingStore = nil
    }
    Button("Cancel", role: .cancel) {}
}
```

The confirmation message must keep the write count, upload count, destination, and “nothing reaches a customer” statement.

### Change the direct-update action

File: `Sources/SuperSubmitter/Tabs/DirectApplyBar.swift`

Replace:

```swift
Button(running ? "Writing…" : "Write to \(destination)") { confirming = true }
```

With:

```swift
Button(running ? "Updating drafts…" : "Update Drafts in \(destination)") {
    confirming = true
}
```

Replace:

```swift
.confirmationDialog("Write these to \(destination)?", isPresented: $confirming) {
    Button("Write them") { state.applyDirectly(target) }
```

With:

```swift
.confirmationDialog("Update drafts in \(destination)?", isPresented: $confirming) {
    Button("Update the drafts") { state.applyDirectly(target) }
```

Do not change `state.applyDirectly(target)` or its API behavior.

### Change the live-write warning

File: `Sources/SuperSubmitter/Shell/RootView.swift`

```swift
Text("Dry Run is off. Update Drafts sends changes to \(state.storeListText).")

Button("Enable Dry Run") { state.dryRun = true }
    .buttonStyle(.bordered)
    .controlSize(.small)
```

Remove `.underline()` and `.buttonStyle(.plain)` from this warning action.

## Acceptance checks

- A first launch uses Dry Run.
- A published app also follows the Dry Run preference.
- Turning Dry Run off still requires confirmation.
- The Summary action says `Preview Requests` when Dry Run is on.
- The Summary action says `Update Drafts` when Dry Run is off.
- A direct update says that it updates a draft.
- No button implies that a draft write publishes to customers.
- VoiceOver announces the native switch label, value, and hint.
- All existing destructive confirmations still exist.
- `swift test` passes.
- The Xcode project builds for macOS 14 and macOS 26.
