# Prompt 3 — Polish UI fixes

Act as a senior macOS SwiftUI engineer. Apply these polish fixes after the critical and important prompts pass all tests.

## Repository constraints

- Keep the deployment target at macOS 14.
- Reuse the existing `Theme`, `QuietButton`, `StatePill`, `Section_`, and store-panel styles.
- Do not add a dependency or a new visual abstraction.
- Do not add more Liquid Glass. The app already uses system glass in the toolbar, header clusters, floating surfaces, and scroll edges.
- Keep content cards opaque for contrast.
- Do not change an API request field, type, endpoint, or payload shape.
- Keep all controls at least 24 points high on macOS. Keep larger targets where space permits.
- Do not encode status with color alone.

## P1. Rename the imported-live-media command

### Reason

“Send these again” implies an immediate network write. The action only puts downloaded local files into `store.yaml` for a later plan.

### API contract check

`state.resendLiveMedia(deviceClass:)` changes the local manifest. It does not upload media. The later plan keeps the API-specific file limits and upload endpoints.

### Replace this code

File: `Sources/SuperSubmitter/Tabs/MediaTab.swift`

```swift
QuietButton(title: "Send these \(files.count) again") {
    state.resendLiveMedia(deviceClass: device)
}
Text("Adds the downloaded copies to store.yaml. The App Store serves previews as a stream, so a video cannot go back this way.")
```

### With this code

```swift
QuietButton(title: "Use these \(files.count) screenshots") {
    state.resendLiveMedia(deviceClass: device)
}
Text("Adds the downloaded copies to store.yaml for the next plan. This action sends nothing.")
```

Keep the control hidden when the local media list is not empty.

## P2. Make the Google video field state its accepted content

### Reason

The placeholder shows one example, but the visible label does not state that Google requires YouTube.

### API contract check

- Read `docs/google-play-developer-api/resources/edits.listings.md`.
- `Listing.video` is a string that contains a promotional YouTube URL.
- Keep a single-line `TextField`. Do not replace it with a file picker.
- Keep Apple previews as video files. Do not replace them with a URL field.

### Replace this code

File: `Sources/SuperSubmitter/Tabs/MediaTab.swift`

```swift
HStack(spacing: 6) {
    StoreLabel(store: .google, size: 11.5)
    Text("YouTube URL").font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
}
TextField("https://youtube.com/watch?v=…",
          text: state.listingBinding(.googleVideo))
    .textFieldStyle(.roundedBorder)
Text("Leave blank to omit the video.")
    .font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
```

### With this code

```swift
HStack(spacing: 6) {
    StoreLabel(store: .google, size: 11.5)
    Text("Promotional YouTube URL")
        .font(Theme.font(size: 11.5))
        .foregroundStyle(Theme.text2)
}
TextField("https://youtube.com/watch?v=…",
          text: state.listingBinding(.googleVideo))
    .textFieldStyle(.roundedBorder)
    .accessibilityHint("Enter a YouTube video URL, or leave the field empty.")
Text("Optional. Google Play accepts a YouTube URL, not a local video file.")
    .font(Theme.font(size: 11))
    .foregroundStyle(Theme.text2)
```

Do not add custom URL validation unless the existing validator already owns it. Avoid a second validation path.

## P3. Shorten the Availability helper text without changing the controls

### Reason

The current screen repeats platform rules in several paragraphs. Shorter text improves scan speed and keeps the controls near their labels.

### API contract check

- Apple uses price-point resources. Keep the App Store price-point selector.
- Google `autoConvertMissingPrices` is a Boolean in `docs/google-play-developer-api/methods/inappproducts.update.md`.
- Keep the Google conversion control as a `Toggle`.
- Keep Apple territories as a multi-selection control.
- Keep `Sell in territories the App Store adds later` as a `Toggle`.

### Change the Google helper

File: `Sources/SuperSubmitter/Tabs/AvailabilityTab.swift`

Replace:

```swift
Text("Play takes the base price beside this and converts it into every currency it sells in. There is no price point to resolve.")
```

With:

```swift
Text("Google Play converts the base price for each supported currency.")
```

Replace:

```swift
Text("Every country Play sells in, unless the Play Console says otherwise.")
```

With:

```swift
Text("Manage country exceptions in Play Console.")
```

### Change the Apple territory helper

Replace:

```swift
Text("Apple takes that answer when it first creates the availability record and by no call afterwards. On an app that has ever been on sale, change it in App Store Connect under Pricing and Availability.")
```

With:

```swift
Text("Apple accepts this option only when it creates availability. For a live app, change it in App Store Connect.")
```

Keep all warning states that explain why territory editing is unavailable.

## P4. Verify color-independent status and contrast

### Reason

The app already pairs most colors with symbols or text. Preserve this pattern and correct only regressions in the edited elements.

### Required checks

- The live-write warning must keep its warning symbol and text.
- Hidden App Store tags must keep the `HIDDEN` text pill.
- The selected locale must keep more than a color change. Add `.accessibilityAddTraits(.isSelected)` if it is absent.
- Error, warning, success, and selected states must not rely on color alone.
- Normal text must meet WCAG 2.2 AA contrast of 4.5:1.
- Large text and UI component boundaries must meet their applicable 3:1 contrast requirement.
- Do not reduce the current `Theme.controlEdge` contrast.
- Check Increased Contrast, Reduce Motion, and Differentiate Without Color.

## P5. Verify the existing Liquid Glass scope

### Reason

The app already uses Liquid Glass in the correct navigation and control layers. More glass would reduce clarity.

### Required checks

- Keep `HeaderSurface`, `GlassCluster`, `SoftScrollEdge`, `FloatingSurface`, and glass-enabled `QuietButton` behavior.
- Keep form cards, editors, warning panels, and API data panels opaque.
- Do not place glass behind dense text or inside every card.
- Verify light mode, dark mode, inactive-window state, and the system Liquid Glass tint control on macOS 27.
- Let macOS 27 apply its refreshed Liquid Glass appearance automatically.

## Acceptance checks

- The live-media command cannot be mistaken for an immediate upload.
- The Google field clearly requests a YouTube URL.
- Apple preview controls still accept video files.
- Availability controls retain their API-compatible types.
- The edited helper text is shorter and preserves required limitations.
- Every edited status has text or a symbol in addition to color.
- The interface remains clear with Increased Contrast and Differentiate Without Color.
- Dense form cards remain opaque.
- `swift test` passes.
- The app builds with Xcode 26 and Xcode 27 beta.
