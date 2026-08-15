# Prompt 2 — Important UI fixes

Act as a senior macOS SwiftUI engineer. Apply these important fixes after the critical prompt passes all tests.

## Repository constraints

- Keep the deployment target at macOS 14.
- Use native SwiftUI controls and existing project styles.
- Do not add a dependency or a new design system.
- Do not change any store API request field, type, endpoint, or payload shape.
- Preserve the current locale, price-point, territory, media, credential, and Boolean input types.
- Preserve the custom Details inspector.
- Use `Button` for actions. Do not use `onTapGesture` for a button action.
- Keep all macOS 27 code behind `#if compiler(>=6.4)` and `if #available(macOS 27.0, *)`.

## I1. Make each collapsible sidebar heading a real button

### Reason

The current text uses `onTapGesture` and adds a button trait. A native button gives correct keyboard, focus, press, and VoiceOver behavior.

### API contract check

This control changes only local sidebar state. It does not write to an API.

### Replace this code

File: `Sources/SuperSubmitter/Shell/Sidebar.swift`

```swift
Text(title)
    .frame(maxWidth: .infinity, alignment: .leading)
    .contentShape(.rect)
    .onTapGesture {
        withMotion(reduceMotion, .easeInOut(duration: 0.22)) { isOpen.toggle() }
    }
    .padding(.trailing, 28)
    .accessibilityAddTraits(.isButton)
    .accessibilityValue(isOpen ? "Open" : "Closed")
```

### With this code

```swift
Button {
    withMotion(reduceMotion, .easeInOut(duration: 0.22)) { isOpen.toggle() }
} label: {
    Text(title)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect)
}
.buttonStyle(.plain)
.padding(.trailing, 28)
.accessibilityValue(isOpen ? "Expanded" : "Collapsed")
.accessibilityHint(isOpen ? "Collapses this section." : "Expands this section.")
```

Keep the trailing padding. It prevents overlap with the system disclosure control.

## I2. Make the Publish and Manage selector self-explanatory

### Reason

The current segmented control hides its visible label. A new user can mistake it for a content filter.

### API contract check

`Mode` controls local navigation only. It is not part of an API payload.

### Replace this code

File: `Sources/SuperSubmitter/Shell/Sidebar.swift`

```swift
Picker("Job", selection: Binding(get: { state.mode },
                                 set: { state.mode = $0 })) {
    ForEach(Mode.allCases) { mode in
        Text(mode.title).tag(mode)
    }
}
.pickerStyle(.segmented)
.labelsHidden()
.accessibilityLabel("What you are doing")
```

### With this code

```swift
Picker("Task", selection: Binding(get: { state.mode },
                                  set: { state.mode = $0 })) {
    ForEach(Mode.allCases) { mode in
        Text(mode.title).tag(mode)
    }
}
.pickerStyle(.segmented)
.accessibilityHint("Choose the app workflow shown in the sidebar.")
```

Do not remove the selector. The current tests show that it prevents a twelve-row sidebar at the minimum window height.

## I3. Reduce the initial text load in the Search Keywords panel

### Reason

The panel shows three long explanations before it shows the task. Keep one short summary visible. Put the detailed API rule in a disclosure.

### API contract check

- Read `docs/appstore-connect-api/AppCustomProductPageLocalizationSearchKeywordsLinkagesRequest/Data-data.dictionary.md`.
- The API accepts an existing keyword resource `id` with type `appKeywords`.
- Do not add a free-text keyword field. Keep the fetched read-only keyword pool and Link or Unlink buttons.

### Replace the explanatory block

File: `Sources/SuperSubmitter/Tabs/SearchKeywordsPanel.swift`

```swift
VStack(alignment: .leading, spacing: 6) {
    Text("Link an approved App Store keyword to a custom product page.")
        .font(Theme.font(size: 11.5))
        .foregroundStyle(Theme.text2)

    DisclosureGroup("How Apple supplies these keywords") {
        Text("Apple builds this read-only list from the Keywords field of the latest approved version. The API links an existing keyword ID. It cannot create a keyword.")
            .font(Theme.font(size: 11.5))
            .foregroundStyle(Theme.text3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
    .font(Theme.font(size: 11.5))

    platformRow
}
```

Keep `Fetch the keywords`, all empty states, the platform picker, and the link confirmation.

Place the fetch button on the same row as the section task or immediately after the disclosure. Do not place it inside the disclosure.

## I4. Reduce the initial text load in the App Store Tags panel

### Reason

The panel repeats the same ownership and reversibility rule three times. Keep the task visible and move the detailed rule into a disclosure.

### API contract check

- Read `docs/appstore-connect-api/AppTag/Attributes-data.dictionary.md`.
- Read `docs/appstore-connect-api/AppTagUpdateRequest.md`.
- The only editable tag attribute is the optional Boolean `visibleInAppStore`.
- Do not add a tag-name field or a delete button.

### Replace the explanatory block

File: `Sources/SuperSubmitter/Tabs/AppTagsPanel.swift`

```swift
VStack(alignment: .leading, spacing: 6) {
    Text("Show or hide the tags that Apple assigned to this app.")
        .font(Theme.font(size: 11.5))
        .foregroundStyle(Theme.text2)

    DisclosureGroup("How App Store tags work") {
        Text("Apple creates the tags. The API only changes visibleInAppStore. Hiding a tag is reversible, and store.yaml does not store it.")
            .font(Theme.font(size: 11.5))
            .foregroundStyle(Theme.text3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
    }
    .font(Theme.font(size: 11.5))
}
```

Keep `Fetch the tags`, the hidden-state pill, and the destructive confirmation before a visible tag becomes hidden.

## I5. Rename the backup command

### Reason

Every field already saves to `store.yaml`. “Save progress” implies unsaved form data. The command creates a recovery copy of all linked apps.

### API contract check

`state.saveDraft()` writes local backup files. It does not call a store endpoint.

### Change the header command

File: `Sources/SuperSubmitter/Shell/RootView.swift`

```swift
QuietButton(title: justSaved ? "Backed up" : "Back Up Apps", glass: true,
            symbol: justSaved ? "checkmark" : "tray.and.arrow.down", tick: tick) {
    tick += 1
    state.saveDraft()
}
.help("Copy every linked app and its store.yaml to the recovery folder")
```

### Change the Settings command

File: `Sources/SuperSubmitter/Tabs/SettingsTab.swift`

```swift
Button("Back Up Apps") { state.saveDraft() }
```

Update source-string tests that expect `Save progress`. Do not rename the underlying draft model or storage directory.

## I6. Keep field search visible with the Xcode 27 toolbar priority API

### Reason

Field search is the main route to a specific field in this large app. It should remain visible when the window toolbar loses space.

### API contract check

This toolbar control changes local navigation only. It does not call a store endpoint.

### Current UI element

File: `Sources/SuperSubmitter/Shell/RootView.swift`

```swift
if state.manifestURL != nil {
    ToolbarItem(placement: .primaryAction) {
        Button { state.showFieldSearch = true } label: {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("Find a field")
        .help("Find a field  ⌘F")
    }
}
```

### Required gated implementation

```swift
if state.manifestURL != nil {
    #if compiler(>=6.4)
    if #available(macOS 27.0, *) {
        ToolbarItem(placement: .primaryAction) {
            Button { state.showFieldSearch = true } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Find a field")
            .help("Find a field  ⌘F")
        }
        .visibilityPriority(.high)
    } else {
        ToolbarItem(placement: .primaryAction) {
            Button { state.showFieldSearch = true } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Find a field")
            .help("Find a field  ⌘F")
        }
    }
    #else
    ToolbarItem(placement: .primaryAction) {
        Button { state.showFieldSearch = true } label: {
            Image(systemName: "magnifyingglass")
        }
        .accessibilityLabel("Find a field")
        .help("Find a field  ⌘F")
    }
    #endif
}
```

Do not add `ToolbarOverflowMenu`. The toolbar has only two commands, and neither command is expendable.

Apple source: `https://developer.apple.com/documentation/swiftui/toolbarcontent/visibilitypriority(_:)`.

## Acceptance checks

- The sidebar group headers work with a mouse, keyboard, and VoiceOver.
- The mode selector has the visible label `Task`.
- Search Keywords shows one short summary before its fetched data.
- App Store Tags shows one short summary before its fetched data.
- Neither API-bound panel adds a field that the API cannot send.
- The backup commands say `Back Up Apps`.
- The Xcode 27 build gives field search high toolbar visibility priority.
- The Xcode 26 build does not parse or resolve the macOS 27 symbol.
- `swift test` passes.
