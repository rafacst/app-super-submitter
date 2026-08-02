# Super Submitter handover

Updated: 2026-08-02

## Current state

Every tab of the design is functional. The app reads both stores, plans the
diff, applies the drafts, and releases one store per button. No screen renders
demo data any more. Until a real `store.yaml` is created or opened, the app
shows a true empty state and keeps all manifest-backed tabs disabled.

### Tabs 1 to 6 — the manifest form

1. **New app** creates a blank `store.yaml`, persists the linked app, and
   selects it. **Open store.yaml** links an existing manifest without changing
   it.
2. **Stores** adds and removes store blocks, imports Apple and Google
   credentials into the Keychain, tests both connections, and links to the
   consoles.
3. **Build** selects or drops `.ipa`, `.pkg`, and `.aab` builds, parses real
   package metadata, and reports an identifier or version mismatch.
4. **Details** binds every field to the active locale, with counters, limit
   errors, store-only visibility, Google overrides, and both previews.
5. **Media** validates the file type, the dimensions, the Google size rules,
   the preview duration, and the per-bucket count before a path is saved.
   Tiles now reorder with the two arrows, because the list order is the order
   both stores show.
6. **Money** edits the provider, the base price, the purchases, the
   subscriptions, the entitlements, and the offerings. It shows the resolved
   App Store price point next to the request and marks a gap over 5 percent.
7. **Review info** is manifest-backed, and the reviewer credentials stay in the
   Keychain. Its Console-only rows come from the same list that tab 9 reads.

Every editing tab holds a **YAML** toggle in its toolbar. The toggle shows the
raw block that the tab owns, and both sides write the same file. An edit that
names a key from another tab is refused instead of merged (SPEC 16.1).

### Tab 7 — Plan

`StateReader` reads App Store Connect, Android Publisher, and the provider.
`Planner` diffs the manifest against that state and emits the operation list.
`Validator` runs every rule of SPEC section 10. The tab shows the real write
count, upload count, and upload size; an error blocks the apply and a warning
needs one acknowledgement. The plan opens no Google edit that outlives the
read, creates no Apple resource, and writes nothing.

### Tab 8 — Submit

`Runner` executes the plan in the order of SPEC 7.3 and 7.4: the Apple
reversible writes first, then the reservation uploads, then one Google edit
that opens first and commits last with `changesNotSentForReview=true` and
`Release.status: draft`. The provider sync runs last.

- A dry run builds and logs every request and sends none.
- Every call appends one redacted JSON line to
  `.super-submitter/runs/<timestamp>.jsonl`.
- A failure stops the run and offers **Retry from the failed step** and
  **Undo what this run created**, with both limits of that undo stated.
- A provider failure never holds a store draft. The run finishes and offers
  **Retry the provider sync**.
- A cancellation deletes the Google edit.

### Tab 9 — Release

The console checklist of SPEC 16.6 with the four states, hand-made marks in
`.super-submitter/console-state.json` (cleared when the version changes),
**Copy as checklist**, and **Re-check**. Then one status row per store, then
the two red buttons. Each button releases one store, guards itself with its
own sheet, and names its own recovery. The app polls a store only after a
release, at the Settings interval, and reports every state change.

### Settings and the shell

Navigation, the poll interval (which restarts the poller), the dry-run default
for a new app, and the manifest path with **Show in Finder** and **Copy path**.
The menu bar item and the sidebar health chips read the live plan and the live
status.

## Build from Project (upload-spec.md)

Tab 2 now holds two sources: **Import a package** and **Build from project**.
The second one links a folder, runs the project's own build tool, inspects
what it produced, and uploads that exact file.

- **No shell command construction or evaluation.** Super Submitter launches
  every top-level tool as an absolute executable plus an argument array. A
  folder named `Evil; rm -rf ~` stays one argument, and a test asserts it.
  The selected project's own tools may still run their own scripts as part of
  a normal Xcode or Gradle build, which the confirmation states explicitly.
- **The artifact is authoritative.** The preflight is a snapshot; the built
  archive or App Bundle decides what uploads. Any difference stops the run,
  reruns the remote check, and asks for a new confirmation.
- **Apple.** `xcrun xcodebuild` for the toolchain check, `-list -json`,
  `-showBuildSettings -json`, `archive`, and `-exportArchive` with
  `destination = upload`. The archive lands in Application Support, never in
  the repository, and it survives a failed upload. The `.p8` reaches the disk
  as a `0600` file in a `0700` folder for the length of one command.
  `manageAppVersionAndBuildNumber` is always false.
  `-allowProvisioningUpdates` is off unless the developer turns it on, and
  every confirmation says which way it is set.
- **Android.** The project's own `gradlew`, never a system Gradle. Modules and
  variants come from Gradle's evaluated task model. Artifact discovery
  compares a before and after snapshot, so it can never pick a stale or a
  global newest `.aab`. `jarsigner -verify` from the selected JDK must pass.
- **Google upload.** One edit is the transaction. The returned version code
  must equal the inspected bundle's code. The track is written as `draft` and
  the commit sends `changesNotSentForReview=true`.
- **Ambiguity is not failure.** A lost commit response queries the actual
  state before anything repeats. A failed cleanup marks the run
  `needsAttention` and offers an idempotent retry. A poll survives a relaunch.
- **Nothing is written to the project.** No version, no `versionCode`, no
  signing configuration, no Gradle file, no permission bit.
- An imported `.ipa`, `.pkg`, or `.aab` skips the source build and skips
  nothing else: the same inspection, signature check, identity comparison,
  remote conflict check, and upload confirmation.

New files live under `Sources/SubmitKit/Build/` and
`Sources/SuperSubmitter/Build/`.

## Verification completed

```sh
swift build
swift test
```

Both pass with no warnings. There are 134 Swift Testing tests. A launch smoke
test runs the binary and it stays up.

No live store call was executed, because this workspace holds no credential.
No real Xcode or Gradle build was executed, because this workspace holds no
fixture project. Every request path, body, header, and argument array comes
from the two specs, not from a recorded response.

## What remains

### Deployment, not features

- An Xcode app target: Developer ID signing, the hardened runtime,
  notarization, stapling, and a Gatekeeper check on a clean Mac
  (upload-spec 12.3 and 17.4). The package still builds a plain executable, so
  `UNUserNotificationCenter` is unavailable and a status change bounces the
  Dock icon instead. There is no Mac App Store variant and no sandbox branch,
  which is the decision upload-spec section 1 fixed.
- Remove or rename a linked app.

### Service work behind a live account

- Redacted HTTP record and replay fixtures, so the apply and upload flows run
  under test without an account. This is the largest remaining gap in the test
  suite; the process layer already has a fake runner.
- The manually gated integration matrices of upload-spec 15.4 and 15.5. They
  need fixture projects and dedicated test store accounts.
- Signed-host Keychain tests.
- Apple in-app purchase localizations, price schedules, and availability per
  product. The runner writes the products; the per-product price schedule of
  SPEC 7.7 step 4 is not written yet.
- RevenueCat write scopes. The plan verifies the read scopes and names a
  missing one; a write scope only proves itself on a write.
- Per-store review notes, if the schema grows a second field.

### Open decisions that were settled, and how

upload-spec section 18 left seven choices open. These are the ones this
implementation made, so a later change is a decision and not a bug fix.

1. Apple pauses at the artifact confirmation by default. **Always review the
   built artifact before upload** is on; turn it off and a build whose archive
   matches the confirmed summary exactly continues to the upload by itself.
   Android always pauses.
2. Retention is manual: Settings deletes run data older than 30 days and never
   deletes a retained archive or bundle.
3. The linked folder keeps an ordinary bookmark, and the app rediscovers the
   container before every build.
4. Android discovery parses the plain `tasks --all` output. No init script is
   written into the developer's project.
5. Google commits an independently uploaded bundle to the configured track as
   a draft at once.
6. The certificate summary shows the subject and the fingerprint only.

### One spec conflict to settle

SPEC 16.3 (tab 6) calls the Google data safety form "API writable", and SPEC
16.6 lists it as a Console-only row. The app follows 16.6 and shows it as a
Console row. The manifest answers pre-fill nothing on the Google side, because
the Play `dataSafety` endpoint takes a labelled CSV and no honest mapping from
the boolean answers exists. Decide which section wins before anyone writes
that mapping.

## Safety constraints

- Super Submitter never constructs or evaluates a shell command. Every
  top-level local tool runs as an executable plus an argument array; selected
  Xcode and Gradle projects can execute their own build scripts.
- The app never edits a version, a project file, a Gradle file, a signing
  configuration, a certificate, a profile, or a keystore.
- The built artifact, not the preflight, decides what uploads.
- A fresh remote conflict check runs immediately before every upload.
- Plan reads only. Apply leaves drafts. Release is the only review action.
- Never combine the Apple and Google release buttons.
- Apple has no sandbox; keep the dry run on by default for a new app.
- Always delete a temporary Google edit on failure or cancellation.
- Never log, persist to YAML, or commit an Apple, Google, RevenueCat, or
  reviewer secret.
- The stores are the source; the providers mirror them.
- Keep the store and provider business logic in SubmitKit and the SwiftUI
  views thin.
