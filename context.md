# Context for an AI agent

Read this file first. Read `SPEC.md` only for the section you touch.

## 1. The product

Super Submitter is a macOS 14+ SwiftUI app. It prepares an iOS, macOS, and
Android app for the App Store and for Google Play from one YAML file and one
action. It mirrors the purchases into RevenueCat or Adapty. It leaves every
store as a **draft**. The developer presses one release button per store.

Distribution: direct download, Developer ID signed, hardened runtime,
notarized, **not sandboxed**. There is no Mac App Store variant. Do not add an
App Sandbox entitlement.

## 2. Build, test, run

```bash
swift test
```

`swift build` produces a plain executable. It is good enough for tests and for
a quick run. Sparkle and the asset catalog are absent from it (`#if
SWIFT_PACKAGE` guards them).

The shipping build is the Xcode project, regenerated from `project.yml`:

```bash
xcodegen generate && xcodebuild build -project SuperSubmitter.xcodeproj -scheme SuperSubmitter -destination "platform=macOS"
```

`SuperSubmitter.xcodeproj` is checked in but generated. **Edit `project.yml`,
never the `.pbxproj`.** Every push to `main` runs
`.github/workflows/release.yml`, which signs, notarizes, and publishes a
GitHub release plus a Sparkle appcast. `RELEASING.md` holds the one-time
setup.

Tests use **swift-testing** (`import Testing`, `@Test`, `#expect`), never
XCTest. 33 test files, no network, no Xcode needed.

## 3. The one architectural rule

| Target | Contains |
|---|---|
| `Sources/SubmitKit` | Every rule, every API call, every mapping. No UI. Fully tested. |
| `Sources/SuperSubmitter` | SwiftUI views and `AppState`. No logic. |

If you write a rule, a limit, a mapping, or an HTTP call in
`Sources/SuperSubmitter`, it is in the wrong target. `AppState` moves values
between the kit and the screen and does nothing else.

## 4. The four concepts

1. **Manifest** — `store.yaml`, beside the developer's app. The only desired
   state. Tabs 1 to 7 are a form over it.
2. **Plan** — read every API, diff against the manifest, write nothing.
3. **Apply** — perform the writes. Idempotent. Ends in a draft everywhere.
4. **Release** — one store, one button. The only irreversible action.

Same model as `terraform plan` / `terraform apply`.

## 5. The data flow

```
store.yaml
  -> ManifestFile.load        Manifest/ManifestFile.swift
  -> Manifest (Codable)       Manifest/Manifest.swift
     +
     ActualState              Plan/ActualState.swift   (filled by Plan/StateReader)
  -> Planner.plan(Input)      Plan/Planner.swift       -> PlanResult ([PlanStep])
     Validator.findings       Plan/Validator.swift     -> [Finding] (error blocks, warning needs an ack)
  -> Runner.run()             Run/Runner.swift         -> switch on PlanOperation
  -> Apple/Google/Provider    Run/AppleApply, GoogleApply, ProviderApply
  -> StoreAPI                 Run/StoreAPI.swift       (one actor: signs, retries, rate limits, records)
  -> RunLog                   Run/RunLog.swift         -> .super-submitter/runs/<stamp>.jsonl
```

`PlanStep.operation` is a `PlanOperation` enum. One model serves the diff
screen and the run, so the two screens can never disagree.

## 6. Where a change goes

**A new manifest field:** `Manifest.swift` struct -> `store.schema.json` ->
the tab view -> `Planner.plan` emits a `PlanStep` -> a new `PlanOperation`
case -> `Runner.perform` dispatch -> the `*Apply.swift` method ->
`StateReader` reads it back -> `Validator` if it has a limit -> a test.

**A read-only store call (reviews, vitals, health):** it is **not** a desired
state. Put it in `Sources/SubmitKit/Clients/`, expose it through
`AppStateAppleActions` or `AppStateGoogleActions`, and put it on a Managing
tab. It never enters `store.yaml` and never becomes a plan row.

**A new tab:** `Tab.swift` (case, title, symbol, question, `modes`, `zone`),
then `TabContent.swift`, then the view in `Tabs/`.

**A new local build step:** `Sources/SubmitKit/Build/` plus
`Sources/SuperSubmitter/Build/`. `upload-spec.md` is the authority there.

## 7. Invariants. Do not break these.

- **Nothing in an apply is irreversible.** Every write ends in a draft. There
  is no rollback engine because a re-run fixes a failed run.
- **Release never chains two stores.** No method releases both. A failure
  between two irreversible calls must be impossible.
- **A missing manifest key means "do not manage".** A `null` key means
  "clear". `Managed<Value>` in `Manifest/Managed.swift` carries the three
  states. A plain `Optional` loses the intent and the file goes back into the
  developer's repository.
- **The app never truncates text.** Over a binding limit is an error the
  developer fixes. `Mapping/BindingLimits.swift` holds the limits.
- **The app archives, it never deletes.**
- **Dry run is on by default for a new app.** An app with a run log keeps its
  own toggle. See `applyDryRunDefault()`.
- **No secret reaches a log, the UI, or `store.yaml`.** Credentials live in
  the Keychain (`Credentials/Credentials.swift`). `Build/Redaction.swift`
  masks at the source. `RunLog` records no token, no body, no header.
- **No shell strings.** `ToolInvocation` keeps the executable and the
  arguments separate, so a folder named `; rm -rf ~` stays one argument.
- **Nothing writes inside the developer's repository** except `store.yaml` and
  `.super-submitter/`. Archives and scratch go to Application Support
  (`Build/BuildStorage.swift`).
- **Red means irreversible** and nothing else in the app may use it
  (`Design/Theme.swift`).
- **Every store mutation passes an `AccessGate`.** A non-dry `Runner`, both
  upload calls, and all five `ReleaseClient` mutations take one and ask it
  first. It has no default parameter, so a new write cannot inherit an open
  gate. Everything else, including editing, validation, local builds, store
  reads, the plan, and the dry run, is free.
- **No em dashes in any user-visible string.**

## 8. The two modes and the tabs

`Mode` is Publishing or Managing (`Tab.swift`). Stores is the only shared tab.

Publishing: Stores, Build, Details, Media, Monetization, Review info, Summary
(plan), Submit (apply), Release.
Managing: Stores, Marketing, Reviews, Analytics, App health.

Tabs group into four zones: edits, reads, writes, releases. The sidebar draws
a hairline between them. That is the whole mental model.

## 9. File map

```
Sources/SubmitKit/
  Manifest/     store.yaml <-> Manifest, per-tab YAML blocks, Managed<T>
  Plan/         Planner, PlanStep/PlanOperation, ActualState, StateReader, Validator
  Run/          Runner, StoreAPI, RunLog, AppleApply, GoogleApply, ProviderApply,
                AppleMarketing, AppleSubscriptions, AppleTestFlight, GoogleCatalog
  Clients/      read-only and out-of-plan calls: reviews, vitals, import,
                diagnostics, Xcode Cloud, RevenueCat/Adapty connection
  Build/        local build and upload: toolchains, discovery, ToolProcess,
                UploadRun state machine, UploadService, Redaction, BuildStorage
  Package/      reads .ipa/.pkg/.aab, hand-written aapt2 protobuf reader
  Release/      ReleaseClient (the two irreversible calls), StatusReader
  Console/      the "finish in the console" checklist
  Mapping/      BindingLimits, PriceDraft
  Assets/       image dimension reader and checksums
  Access/       the paywall: capabilities, signed entitlement, Ed25519 verifier,
                AccessController, LicensingClient. `licensing-api.md` is the
                contract.
  Credentials/  Keychain
  Resources/    store.schema.json, screenshot-sizes.json

Sources/SuperSubmitter/
  AppState.swift + AppState*.swift   one @Observable @MainActor class, split by area
  Shell/        RootView, Sidebar, TopBar
  Tabs/         one file per tab, plus panels
  Overlays/     onboarding, settings, sheets, menu bar popover
  Build/        BuildFlow (@Observable) and its views
  Design/       Theme, StoreMark
```

## 10. Technology choices, already decided

`URLSession` only. `Codable` structs hand-written, not generated (~40 types
out of Apple's 1393). Yams for YAML, the only runtime dependency of SubmitKit.
CryptoKit for ES256 and RS256. `Process` for the Adapty CLI. `unzip` and
`pkgutil` to read a build, so no Xcode and no Android SDK are needed on the
submitting machine. No database: the stores hold the state, the manifest holds
the intent, git holds the history.

Every command runner and process is injected as a protocol
(`CommandRunning`, `ToolRunning`), so tests inject a fake and assert on the
exact argument array. Use that seam instead of hitting the network.

## 11. Documents

| File | What it decides |
|---|---|
| `SPEC.md` | The product. Sections 5 to 17 are the authority for the manifest, the mapping, the workflows, the validation, and the UI. |
| `upload-spec.md` | The local build and upload flow (Xcode, Gradle, states, recovery). |
| `stripe-spec.md` | The licensing product rules, the Stripe setup, and the server. The client half is implemented; raw YAML is **not** gated. |
| `licensing-api.md` | The wire contract the shipped client speaks. Read it before you build the service. |
| `RELEASING.md` | Signing, notarization, Sparkle, GitHub secrets. |
| `.design-notes/`, `design/` | The HTML mockup the SwiftUI screens follow. |

## 12. Style

Comments explain **why**, never what. A deliberate simplification carries a
`// ponytail:` comment that names the ceiling and the upgrade path. Prose in
the code and the docs is short and plain. Commit messages are Conventional
Commits with a lowercase sentence subject, and work lands through a merge
commit from a `feat/`, `fix/`, or `chore/` branch.

## 13. Known gaps

- Saving `store.yaml` loses comments and block scalars. Yams re-encodes the
  whole file. Values survive and a test proves it. See SPEC open question 8.
- Licensing: the client and Supabase sign-in are in `Sources/SubmitKit/Access/`
  and every gate is live. Debug points at the test Worker. Release stays closed
  until `LICENSING_BASE_URL` reaches the build. The deployed test and live
  Workers still report zero configured Stripe Prices, so do not set that
  Release value yet.
- SPEC section 3.1 rows 3 to 10 and section 3.3 name the store endpoints that
  no code calls yet. Read them before you add a call, so you do not
  re-discover the surface.
- `POSTHOG_PROJECT_TOKEN` and `POSTHOG_HOST` come from the environment. A
  missing value is loud in a debug build and silent in a release build.
