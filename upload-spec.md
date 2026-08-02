# Super Submitter — Local Build and Upload Specification

This document specifies how Super Submitter links a local Apple or Android
project, discovers its distributable application, builds and signs the next
artifact with the project's native command-line tools, asks the developer to
confirm the exact artifact, uploads it, and follows server-side processing.

- Status: implementation specification, draft v1
- Date: 2026-08-02
- Product: Super Submitter for macOS
- Super Submitter distribution: direct download, Developer ID signed,
  hardened-runtime enabled, notarized, and **not sandboxed**
- Apple build tool: `xcodebuild`, selected by the active Xcode developer directory
- Android build tool: the selected project's Gradle wrapper, `gradlew`
- Apple upload destination: App Store Connect
- Android upload destination: Google Play Console

---

## 1. Decision and scope

Super Submitter is a local developer tool. It needs to run Xcode and Gradle,
read build outputs, use signing material already configured on the developer's
Mac, and retain archives outside a selected source repository. It is therefore
distributed outside the Mac App Store as a notarized, non-sandboxed app.

There is no Mac App Store distribution variant of Super Submitter. Do not add
an App Sandbox entitlement, an XPC helper intended to escape that sandbox, or
two capability branches. The direct-download build is the only product.

This choice does not mean unrestricted or invisible access. The app still:

1. asks the developer to select each source-project folder;
2. describes that builds can execute scripts, plug-ins, macros, and other code
   supplied by that project;
3. restricts discovery to that selected folder;
4. shows the selected product, version, build, signing state, and destination;
5. separates reversible build work from an upload that mutates a store;
6. never changes a version, build number, signing configuration, project file,
   Gradle file, certificate, profile, or keystore by itself; and
7. never submits a release for review as part of this workflow.

The phrase **review the code** in this feature means inspect project and build
configuration well enough to discover a build. It does not mean perform a
source-code security review, correctness review, or dependency audit.

### 1.1 Supported target applications

| Platform | Local source | Build artifact | Upload target |
|---|---|---|---|
| iOS | Xcode project or workspace | `.xcarchive`, exported/uploaded app | App Store Connect |
| macOS | Xcode project or workspace | `.xcarchive`, exported/uploaded app | App Store Connect |
| Android | Gradle project | signed `.aab` | Google Play Console |

An Apple target application's Mac App Store submission remains supported. The
removed option is specifically distribution of **Super Submitter itself** in
the Mac App Store.

### 1.2 Non-goals

This feature does not:

- automate Xcode or Android Studio user interfaces;
- require an IDE plug-in;
- edit source code or project configuration;
- increment `CURRENT_PROJECT_VERSION`, `versionCode`, or any other version;
- create or replace Apple certificates, private keys, provisioning profiles,
  Android keystores, or keystore passwords;
- accept interactive secret prompts during a build;
- build or upload Android APK files;
- distribute target applications outside App Store Connect or Google Play;
- notarize a target macOS application for direct distribution;
- submit an Apple version or Google release for review;
- choose a project, scheme, module, variant, or artifact by guessing when more
  than one valid choice remains; or
- promise that every arbitrary custom Xcode or Gradle build is discoverable.

---

## 2. User outcome

The shortest successful flow is:

1. The developer clicks **Link Project Folder**.
2. The developer selects the root folder of an iOS, macOS, or Android project.
3. Super Submitter discovers the build system and, where unambiguous, the
   product to distribute.
4. The app presents project, product, bundle/package identifier, version,
   build number/version code, scheme or variant, signing readiness, toolchain,
   and remote-store conflicts.
5. The developer confirms the build.
6. Super Submitter invokes `xcodebuild` or that project's `gradlew` without a
   shell and streams redacted progress.
7. Super Submitter inspects the generated artifact. The artifact, not the
   preliminary configuration, is authoritative.
8. The developer confirms the exact artifact to upload. This second
   confirmation is mandatory on Android and whenever Apple archive metadata
   differs from the preflight summary. The UI may combine the two actions for
   Apple only when all authoritative fields match exactly.
9. Super Submitter uploads the artifact.
10. The app waits for App Store Connect processing or validates and commits the
    Google Play edit as a draft.
11. The processed build becomes available to the existing Plan, Apply, and
    Release workflows.

The developer may stop after step 7, keep the artifact, and upload it later.
Build and upload are separate operations internally even when the UI offers a
single **Build & Upload** button.

---

## 3. Safety invariants

These rules are implementation requirements, not recommendations.

1. **No shell command construction or evaluation.** Launch a fixed executable with an argument array. Never pass
   project-controlled text to `/bin/sh -c`, `zsh -c`, command substitution, or
   an interpolated script.
2. **No silent project writes.** Discovery, preflight, build, and upload do not
   rewrite the selected repository. Generated output produced normally by the
   project's own build is allowed.
3. **No automatic version changes.** If a version/build conflicts with the
   store, stop and explain the exact value the developer must change.
4. **The artifact is authoritative.** Re-read identity and version from the
   final archive or AAB before upload.
5. **Exact remote matching.** Match a remote build by app, platform, marketing
   version, build number/version code, and, when locally known, artifact hash.
   Never assume that the newest remote object is this run's object.
6. **One selected root.** Discovery cannot wander outside the chosen folder by
   following symlinks. Build tools may resolve dependencies according to the
   project after the developer confirms execution.
7. **No logged secrets.** Tokens, authorization headers, `.p8` contents,
   service-account JSON, passwords, private signing data, and secret environment
   values never enter logs, previews, analytics, or error reports.
8. **Draft only.** An upload may create or update a draft. It never sends a
   release for review or makes it available to users.
9. **Recover before retry.** After an ambiguous network result, query actual
   store state before issuing another upload or commit.
10. **Cancellation is truthful.** A cancelled local process does not prove that
    a remote upload was rejected. Reconcile remote state before displaying a
    final cancellation result.

---

## 4. Shared domain model

### 4.1 LinkedSourceProject

Store this machine-local record under Super Submitter's Application Support
directory. It is not part of `store.yaml` and should not be committed to the
developer's repository.

| Field | Meaning |
|---|---|
| `id` | Stable local UUID |
| `platform` | `apple` or `android` |
| `rootPath` | Last resolved selected folder |
| `folderBookmark` | Security-scoped or ordinary bookmark data used to detect moves; optional in the non-sandboxed build but recommended |
| `containerPath` | `.xcworkspace`, `.xcodeproj`, or Gradle settings root |
| `containerKind` | `workspace`, `project`, or `gradle` |
| `selection` | Apple scheme/configuration/destination or Android module/variant |
| `productIdentifier` | Expected bundle ID or application ID |
| `createdAt` | First link time |
| `lastValidatedAt` | Last successful rediscovery |

Never treat this record as proof that the folder still contains the same
project. Resolve the bookmark/path and rediscover before every build.

### 4.2 BuildCandidate

`BuildCandidate` is immutable after inspection.

| Field | Meaning |
|---|---|
| `id` | Local UUID |
| `platform` | `ios`, `macos`, or `android` |
| `productName` | Display name read from artifact |
| `productIdentifier` | Bundle ID or Android application ID |
| `marketingVersion` | Apple `CFBundleShortVersionString` or Android `versionName` |
| `buildVersion` | Apple `CFBundleVersion` or Android `versionCode` |
| `artifactPath` | `.xcarchive` or `.aab` path |
| `artifactSize` | Bytes |
| `sha256` | SHA-256 of the retained upload input where available |
| `signingSummary` | Team/certificate/profile or signing certificate summary, without secrets |
| `sourceRevision` | Git commit, branch, and dirty flag when available; informational only |
| `createdAt` | Artifact inspection time |
| `preflightSnapshot` | The fields shown before build |
| `mismatches` | Differences between preflight and artifact |

### 4.3 UploadRun

| Field | Meaning |
|---|---|
| `runID` | UUID used for logs and scratch paths |
| `state` | State from section 5 |
| `linkedProjectID` | Source project used for the build |
| `candidateID` | Artifact being uploaded |
| `commandPreviews` | Redacted, human-readable command descriptions |
| `remoteIDs` | App Store Connect build/upload IDs or Google edit/version-code IDs |
| `startedAt`, `updatedAt`, `finishedAt` | Lifecycle timestamps |
| `cancelRequestedAt` | Optional cancellation timestamp |
| `cleanupState` | `notNeeded`, `pending`, `complete`, or `needsAttention` |
| `lastError` | Structured stage, category, message, diagnostics, and recovery action |

Persist enough state to resume server polling after an app restart. Do not
persist a bearer token or decrypted secret.

### 4.4 Manifest relationship

`store.yaml` remains desired release metadata. Local project links and remote
opaque IDs remain machine-local. The manifest may later add these optional
expectations:

```yaml
release:
  versionName: "3.2.0"
  apple:
    buildNumber: "42"
  google:
    versionCode: 4200
```

When present, they are validation constraints, not commands to edit a project.
If they do not match the final artifact, block upload.

---

## 5. Shared workflow state machine

```text
unlinked
  -> discovering
  -> needsSelection
  -> preflight
  -> readyToBuild
  -> building
  -> inspectingArtifact
  -> needsUploadConfirmation
  -> uploading
  -> processingOrValidating
  -> complete
```

Every active state may enter `cancelling`, then `cancelled`. Any state may enter
`failed`. An uncertain remote result enters `recoveryRequired`, not `failed`.

### 5.1 State rules

- `needsSelection` contains one or more explicit choices and cannot start a
  build until all required selections are resolved.
- `readyToBuild` means local prerequisites and remote version checks passed.
- `building` owns exactly one top-level child process.
- `inspectingArtifact` cannot make a network mutation.
- `needsUploadConfirmation` displays immutable `BuildCandidate` data.
- `uploading` begins only after user confirmation and a fresh remote conflict
  check.
- `processingOrValidating` may outlive the app process and must be resumable.
- `complete` means the exact build is identifiable in the destination store. On
  Google, the edit is validated and committed with draft track status.
- `recoveryRequired` means an operation may have succeeded remotely. Recovery
  queries actual state and chooses complete, retryable failure, or manual help.

### 5.2 Run identity and idempotency

Use this logical identity:

```text
platform + productIdentifier + marketingVersion + buildVersion + artifactSHA256
```

Before an upload:

1. fetch current remote state;
2. if the exact build/version code already exists, do not upload it again;
3. offer **Use Existing Build** when it is compatible;
4. block when the numeric/string identifier exists but represents a conflicting
   artifact or cannot safely be distinguished; and
5. never make an upload idempotent merely by selecting the most recent build.

### 5.3 Dry run

Dry run performs discovery, selection, preflight, remote read-only checks,
command rendering, and request rendering. It does not launch a build process,
create a Google edit, upload a file, or mutate any store.

---

## 6. Process execution contract

All local tools use a shared `ProcessRunner` abstraction.

### 6.1 Required inputs

- absolute executable URL;
- ordered argument array;
- explicit working directory;
- sanitized environment;
- optional standard-input policy, normally closed;
- line-oriented stdout and stderr handlers;
- cancellation handle; and
- timeout policy appropriate to the phase.

The executable and arguments used for execution must remain separate. A command
preview is presentation only and must not be copied into a shell.

### 6.2 Environment

Start with the current GUI process environment, then apply a documented
allowlist/denylist policy:

- preserve normal toolchain inputs such as `PATH`, `HOME`, locale, temporary
  directory, Xcode developer selection, `JAVA_HOME`, and Android SDK locations;
- allow explicit user-configured project environment variables;
- redact values whose names or sources indicate secrets;
- never inject credentials into an environment when a tool supports a safer
  file or API mechanism;
- record variable names needed for diagnostics, not secret values; and
- do not change `DEVELOPER_DIR`, `JAVA_HOME`, or SDK paths silently.

The preflight screen must show which Xcode and JDK/Gradle installation will be
used.

### 6.3 Output and logs

- Stream combined progress to the UI while retaining stdout and stderr as
  distinct channels internally.
- Save redacted structured JSONL records under Super Submitter's run storage.
- Bound in-memory logs and rotate retained logs.
- Parse progress as a convenience; preserve the raw redacted line when parsing
  fails.
- Label diagnostics with the command phase, exit code, and signal.
- Never infer success from output text alone. Require exit status plus artifact
  or remote-state verification.

### 6.4 Cancellation

1. Mark the run `cancelling`.
2. Stop accepting new phase work.
3. Interrupt the owned top-level process.
4. Allow a short configurable grace period.
5. Terminate only the process tree owned by this run if it does not exit.
6. Never kill all `xcodebuild`, Java, Gradle, or Gradle daemon processes on the
   machine.
7. Perform platform cleanup and remote reconciliation.
8. Report `cancelled` only after cleanup/reconciliation reaches a known state.

---

## 7. Source folder access and discovery

### 7.1 Folder selection

Use `NSOpenPanel` configured for one directory. Explain before selection:

> Super Submitter will inspect this project and run its build. Building may
> execute scripts, package plug-ins, compiler macros, and other code supplied by
> the project.

Although the app is not sandboxed, explicit selection is still the consent and
trust boundary. Do not scan the developer's home directory or drives for
projects.

### 7.2 Path handling

- Standardize and resolve the chosen root.
- During discovery, do not follow symlinks whose resolved path leaves the root.
- Ignore generated and dependency directories where appropriate: `.git`,
  `.build`, `build`, `DerivedData`, hidden caches, package checkouts, vendored
  Pods internals, and IDE output.
- Apply bounded recursion and report when a depth/entry limit excluded results.
- Store both a display path and a resolved path.
- If a saved link is moved or unavailable, ask the developer to locate it.
- Revalidate access immediately before build.

### 7.3 Discovery result

Discovery returns candidates; it does not automatically authorize a build.
Every candidate includes:

- build system and container path;
- selectable products/schemes/modules/variants;
- likely platform;
- reasons it is or is not buildable;
- missing tools or configuration; and
- warnings generated by best-effort inspection.

---

## 8. Apple workflow

### 8.1 Toolchain preflight

Use the selected active developer directory. Run read-only checks through
`/usr/bin/xcrun`:

```text
/usr/bin/xcrun xcodebuild -version
/usr/bin/xcrun xcodebuild -showsdks -json
```

Also resolve and display the active developer directory. Detect these failures
before project discovery proceeds:

- Xcode is not installed or selected;
- only Command Line Tools are selected when full Xcode is required;
- the Xcode license or first-launch setup is incomplete;
- no required platform SDK is installed; or
- the selected Xcode is incompatible with the project.

Do not run `sudo`, accept licenses, install components, or change the active
developer directory automatically. Provide a precise remediation and a retry
button.

### 8.2 Container discovery

Search the selected folder for user-owned `.xcworkspace` and `.xcodeproj`
containers. Exclude `*.xcodeproj/project.xcworkspace` because it is Xcode's
internal workspace representation.

Rules:

1. If exactly one user workspace exists and it represents the project, it is a
   recommended candidate. Workspaces are commonly required by CocoaPods and
   multi-project setups.
2. A workspace must not silently win when multiple independent workspaces or
   projects exist.
3. Present each valid container with its relative path and type.
4. Preserve the developer's selection for later builds, but rediscover it.

For every candidate run one of:

```text
/usr/bin/xcrun xcodebuild -workspace <path> -list -json
/usr/bin/xcrun xcodebuild -project <path> -list -json
```

Use the JSON output. Do not scrape the human-readable format if JSON succeeds.

### 8.3 Scheme selection

A distributable scheme must be visible to command-line Xcode, normally because
it is shared. If no usable scheme appears, explain how to mark a scheme shared
in Xcode.

When more than one usable scheme exists, show a chooser with:

- scheme name;
- likely application product(s);
- supported platform(s);
- archive action availability where discoverable; and
- prior selection, if still valid.

Do not choose a scheme solely because its name matches the folder or repository.

### 8.4 Build settings inspection

For a chosen container, scheme, configuration, and destination, request JSON
build settings. Use the exact destination intended for archive where possible.

```text
/usr/bin/xcrun xcodebuild <container arguments> \
  -scheme <scheme> \
  -configuration <configuration> \
  -destination <generic destination> \
  -showBuildSettings -json
```

Read at least:

- `PRODUCT_NAME`
- `PRODUCT_BUNDLE_IDENTIFIER`
- `MARKETING_VERSION`
- `CURRENT_PROJECT_VERSION`
- `DEVELOPMENT_TEAM`
- `CODE_SIGN_STYLE`
- `CODE_SIGN_IDENTITY`
- `PROVISIONING_PROFILE_SPECIFIER`
- `SDKROOT`
- `SUPPORTED_PLATFORMS`
- `TARGETED_DEVICE_FAMILY`
- `INFOPLIST_FILE`
- `WRAPPER_EXTENSION`
- `SKIP_INSTALL`
- `INSTALL_PATH`

Build settings may contain expansions or values that change during scripts.
Treat them as the preflight snapshot, never as final artifact truth.

### 8.5 Product and platform selection

Identify application products using target/product type, wrapper extension,
archive eligibility, and bundle identifier together. Support extensions,
widgets, frameworks, and test bundles as nested products, but never select them
as the primary application.

Use generic archive destinations:

- iOS: `generic/platform=iOS`
- macOS: `generic/platform=macOS`

Use `xcodebuild -showdestinations` when the destination or platform remains
ambiguous. Catalyst and multiplatform projects require an explicit developer
choice. Do not infer Catalyst from a bundle identifier or target name.

The primary selected distributable must match the expected bundle ID from
`store.yaml` when one is configured. A mismatch blocks the build until the
developer changes the selection or manifest.

### 8.6 Signing readiness

Super Submitter orchestrates the project's signing configuration; it does not
replace Xcode's signing system.

Preflight displays:

- automatic or manual signing;
- development team;
- requested signing identity;
- provisioning profile specifier, when manual;
- whether an apparently suitable signing certificate and private key are
  available in the keychain; and
- whether Xcode-managed provisioning updates are allowed for this run.

`-allowProvisioningUpdates` is off by default. Enabling it requires explicit
consent because Xcode may communicate with Apple's developer services and
create or update App IDs, certificates, or provisioning profiles. Remembering
the preference is allowed, but show it on every confirmation screen.

If the project requires manual signing, missing certificates/profiles block the
build. Provide an **Open in Xcode** recovery action. Do not attempt to create or
import signing identities.

### 8.7 App Store Connect authentication for Xcode

Preferred authentication uses the App Store Connect API key already saved in
Super Submitter's Keychain-backed connection:

- key ID;
- issuer ID; and
- private `.p8` key content.

`xcodebuild` needs a path for the authentication key. Immediately before a
command that needs it:

1. create a unique app-owned run scratch directory with mode `0700`;
2. write the key to a uniquely named `.p8` file with mode `0600`;
3. pass the path, key ID, and issuer ID as separate arguments;
4. do not display the full temporary path or any key content in logs; and
5. delete the file in unconditional cleanup on success, error, or cancellation.

The arguments are:

```text
-authenticationKeyPath <temporary path>
-authenticationKeyID <key ID>
-authenticationKeyIssuerID <issuer ID>
```

Xcode Accounts authentication may be offered as a fallback when no API key is
configured, but API-key mode is preferred because it is explicit and
reproducible. The selected authentication mode must be shown at confirmation.

### 8.8 Remote preflight

Before building, query App Store Connect for the configured application and
builds. Validate:

- the App Store Connect application exists and is accessible;
- the selected bundle ID/platform is compatible with it;
- the marketing version is expected by the configured release; and
- the local build number does not already exist and satisfies Apple's current
  version requirements.

If the build number already exists, block upload. Building locally may still be
offered as an explicit artifact-only action, but the UI must say it cannot be
uploaded under that number. Never increment the build number automatically.

### 8.9 Apple pre-build confirmation

Show one confirmation card containing:

- selected folder and Xcode container;
- scheme, configuration, platform, and generic destination;
- application name and bundle ID;
- marketing version and build number;
- active Xcode version and SDK;
- team and signing style;
- provisioning-update preference;
- App Store Connect application and account/team;
- remote conflict result;
- archive retention location; and
- a warning that the build may execute project-controlled code.

The button is **Build Archive** or **Build & Upload**. Even for the combined
label, the implementation must stop before upload when the inspected archive
does not exactly match the confirmed identity.

### 8.10 Archive location

Create an app-owned archive path outside the source repository:

```text
~/Library/Application Support/Super Submitter/Archives/
  <bundle-id>/<UTC timestamp>-<run-id>.xcarchive
```

Do not use a shared predictable temporary filename. Retain successful archives
because they contain the app, dSYMs, and signing metadata needed for diagnosis
or later export. Provide **Reveal in Finder** and explicit **Delete Archive**
actions plus a configurable retention policy. Never delete a retained archive
merely because upload failed.

### 8.11 Archive command

Execute `/usr/bin/xcrun` with an argument array equivalent to:

```text
xcodebuild
-workspace <absolute workspace>       # or -project <absolute project>
-scheme <selected scheme>
-configuration <selected configuration>
-destination generic/platform=iOS     # or generic/platform=macOS
-archivePath <app-owned archive path>
archive
<optional authentication arguments>
<optional -allowProvisioningUpdates>
```

Do not append arbitrary free-form user text to the arguments. If advanced
overrides are introduced later, model them as validated key/value fields and
show every effective override.

An exit status of zero is not enough. Require a readable `.xcarchive` at the
exact requested path.

### 8.12 Authoritative archive inspection

After archive, inspect its `Info.plist` and the top-level archived application's
`Info.plist`. Use archive product paths rather than a global filesystem search.
Record:

- application name;
- bundle identifier;
- `CFBundleShortVersionString`;
- `CFBundleVersion`;
- platform and minimum OS;
- application path;
- archive creation date;
- signing identity/team/profile summaries;
- included dSYMs; and
- archive size and checksum data suitable for local identity.

Run a non-mutating signature diagnostic against the archived app, such as
`/usr/bin/codesign --verify` with appropriate strict/deep behavior for the
product. Treat the Xcode export step as the final authority for App Store
distribution signing and entitlement validation.

Compare every identity field with the preflight snapshot and `store.yaml`.
Build scripts can change values, so any difference is meaningful. If bundle ID,
platform, marketing version, build number, or team differs:

1. stop;
2. display old and new values;
3. rerun remote conflict checks for the authoritative values; and
4. require a new upload confirmation.

### 8.13 Export options

Generate a per-run export options plist in the secure scratch directory. At a
minimum configure:

```plist
method = app-store-connect
destination = upload
manageAppVersionAndBuildNumber = false
uploadSymbols = true
signingStyle = automatic | manual
teamID = <confirmed team>
```

`manageAppVersionAndBuildNumber` must be explicitly `false`. Otherwise Xcode
may change a value the developer just confirmed.

When required, include only validated options:

- `distributionBundleIdentifier` when an archive has multiple eligible apps;
- `signingCertificate` and `provisioningProfiles` for manual signing; or
- `installerSigningCertificate` for a macOS installer when applicable.

Use the selected Xcode installation's `xcodebuild -help` as runtime truth for
supported export keys. Fail with an actionable compatibility error if an option
is unavailable. Delete the generated plist during scratch cleanup.

### 8.14 Final Apple upload confirmation

The upload confirmation uses only archive-derived fields. Show:

- exact application name, bundle ID, platform, version, and build;
- signing team/style and signature verification result;
- archive size and path;
- destination App Store Connect app/account;
- whether the exact build already exists;
- export/upload method; and
- the fact that upload cannot be recalled reliably once accepted.

If the combined **Build & Upload** action was used and no material field changed,
the app may continue automatically only if the first confirmation explicitly
said it would do so. A setting such as **Always review the built artifact before
upload** should default on. Android always pauses because its preflight metadata
is less authoritative.

### 8.15 Export and upload command

Execute `/usr/bin/xcrun` with arguments equivalent to:

```text
xcodebuild
-exportArchive
-archivePath <archive path>
-exportPath <app-owned per-run export path>
-exportOptionsPlist <secure temporary plist>
<authentication arguments>
<optional -allowProvisioningUpdates>
```

The `destination = upload` export option performs the App Store Connect upload.
This is a second `xcodebuild` process behind the UI workflow, not part of the
archive command.

Capture Xcode's result bundle or logs when supported, but redact credentials.
Do not report upload success until the command succeeds and remote reconciliation
finds the exact build or establishes that processing has begun.

### 8.16 Processing in App Store Connect

After Xcode accepts the upload, poll App Store Connect's builds endpoint for the
exact app, platform, version, and build number. Processing can take longer than
the local upload and must survive app relaunch.

Suggested polling behavior:

1. poll quickly for the first few minutes;
2. back off progressively with jitter;
3. respect rate-limit and retry headers;
4. persist last poll time and remote build ID when found;
5. allow **Stop Waiting** without pretending the upload was cancelled; and
6. offer **Resume Checking** later.

States shown to the user:

- upload accepted, waiting to appear;
- processing;
- processed and available;
- processing failed, including Apple's diagnostic when exposed; or
- timed out locally, with remote state still pending.

Once processed, save the exact remote build ID in `UploadRun` and make it the
candidate for the existing Plan/Apply workflow. Do not write opaque remote IDs
to the manifest.

### 8.17 Apple recovery cases

| Failure | Required behavior |
|---|---|
| Xcode missing or uninitialized | Block before discovery; show installation/setup steps |
| Workspace or scheme ambiguous | Require explicit selection |
| Scheme not shared | Explain how to share it; offer Open in Xcode |
| Dependency resolution fails | Preserve diagnostic; do not rewrite dependency files |
| Signing asset missing | Block; identify team/identity/profile; offer Open in Xcode |
| Provisioning update required | Offer a new confirmation with `-allowProvisioningUpdates` |
| Compile/archive fails | Keep logs; no upload; retry build |
| Archive metadata differs | Stop and reconfirm authoritative artifact |
| Build number already exists | Block upload; never auto-bump |
| Export validation fails | Keep archive; show Xcode's validation issue |
| Upload result is ambiguous | Query exact remote build before retry |
| Processing fails | Preserve archive and remote ID; show Apple's diagnostic |

---

## 9. Android workflow

### 9.1 Architectural decision

Super Submitter does not connect to Android Studio. Android Studio is an editor
and frontend to the Android build system; the stable project-owned interface is
the Gradle wrapper. The app runs the wrapper from the selected Gradle root.

Android Studio does not need to be open or installed if the project already has
a wrapper, a compatible JDK, the Android SDK, and resolvable dependencies.

### 9.2 Gradle root discovery

Search the selected root, within the discovery bounds, for:

- `gradlew`;
- `settings.gradle` or `settings.gradle.kts`;
- wrapper configuration under `gradle/wrapper`; and
- candidate Android application modules.

The preferred root contains both `gradlew` and a settings file. If nested,
independent Gradle builds exist, show each root and require selection.

Do not run a system-installed `gradle` as an automatic fallback. The wrapper
pins the project's expected Gradle version. If `gradlew` is not executable,
show a diagnostic and a safe fix the developer can apply; do not silently
change repository permissions.

### 9.3 Toolchain preflight

Before evaluating the project, detect and display:

- wrapper Gradle version/distribution;
- selected Java executable and JDK version;
- Android SDK path and relevant installed platform/build tools;
- project `local.properties` SDK path when present;
- `JAVA_HOME` and Android SDK source used for the run; and
- offline/network expectations.

Allow the developer to select a JDK, including Android Studio's bundled JBR,
when discovery finds more than one compatible option. Persist the explicit
choice per linked project.

Do not download or install a JDK, Android SDK, build tools, or licenses silently.
Gradle may download its pinned distribution and project dependencies as normal
after confirmation; disclose this in preflight.

### 9.4 Safe Gradle invocation

Launch the absolute `gradlew` file directly with an argument array and the
Gradle root as working directory. Do not construct a shell command.

Use machine-readable-friendly flags where compatible:

```text
--console=plain
```

Because Gradle versions differ, any additional convenience flags must be
detected or version-gated. Never pass a password on the command line. Close
standard input so a secret prompt fails visibly rather than hanging forever.

Do not stop all Gradle daemons as cleanup. The launched build may use the
project's normal daemon behavior.

### 9.5 Module and variant discovery

Gradle build scripts are executable programs. Values may be computed by
plug-ins, flavors, environment variables, or convention builds, so static
parsing is only a hint.

Use Gradle's evaluated task model as the practical v1 discovery interface:

1. list projects/modules using wrapper tasks such as `projects` with plain
   console output;
2. identify candidate application modules;
3. list tasks for each candidate module, for example `:<module>:tasks --all`;
4. collect tasks named like Android App Bundle tasks, including flavored
   release variants; and
5. present an explicit module and variant chooser when more than one candidate
   remains.

Do not assume the application module is named `app` or the distributable
variant is named `release`.

A future implementation may use the Gradle Tooling API or a version-gated AGP
model. It must not make the first implementation depend on unstable internal
AGP APIs.

### 9.6 Android preflight metadata

Best-effort preflight collects:

- Gradle root;
- module and exact bundle task;
- variant/build type/flavors;
- expected application ID;
- expected `versionName` and `versionCode`;
- minimum and target SDK;
- signing configuration presence without secret values;
- output directory expectation; and
- Google Play application/account and existing version-code conflict.

Static manifest or Gradle parsing cannot make these values authoritative. Mark
uncertain fields as **To be verified from built bundle**, not as errors.

If `store.yaml` contains an expected package name or version, a known mismatch
blocks the build selection. Unknown preflight values are permitted only because
the app always performs post-build artifact inspection.

### 9.7 Android signing policy

The selected release variant must already be configured to produce a signed
App Bundle noninteractively. Credentials may come from the developer's normal
Gradle properties, environment, credential store, or project-specific plug-in.

Super Submitter must not:

- ask for or persist a keystore password;
- copy a keystore into its own storage;
- add signing configuration to Gradle files;
- put passwords into command arguments or logs; or
- answer an interactive prompt.

If the build cannot sign without a prompt, fail with instructions to configure
noninteractive release signing in the project. Reading public certificate
identity from a built AAB is allowed.

Google Play App Signing does not remove the need to sign the upload bundle with
the app's registered upload key.

### 9.8 Remote Google preflight

Use the existing Google Play service-account connection. Verify:

- the package exists and is accessible;
- the service account has required application/edit permissions;
- configured track exists or can validly be targeted; and
- the expected version code, when known, is greater than and distinct from all
  relevant uploaded version codes.

The Android Publisher API often requires an edit context for reads related to
bundles/tracks. If preflight creates a temporary read-only edit, delete it in
unconditional cleanup on both success and failure. Record `cleanupState` if
deletion cannot be confirmed.

Never increment `versionCode` automatically.

### 9.9 Android pre-build confirmation

Show:

- selected folder and Gradle root;
- module, variant, and exact Gradle task;
- expected package, version name, and version code, with uncertainty labels;
- JDK, Gradle, and Android SDK selections;
- signing configuration readiness;
- Google Play application/account/track;
- remote conflict result;
- expected output location; and
- a warning that Gradle can run arbitrary project-controlled build logic and
  may download dependencies.

The action is **Build App Bundle**. Android always pauses after inspection for a
second confirmation before upload.

### 9.10 Bundle build command

The normal argument array is conceptually:

```text
<absolute project root>/gradlew
:<selected module>:<selected bundle task>
--console=plain
```

For a conventional project this may be:

```text
<root>/gradlew :app:bundleRelease --console=plain
```

The first form is the specification. The second is only an example.

Before launch, snapshot candidate `.aab` files under the selected module's
expected bundle output directories, including modification time, size, and
inode/file identity where available.

### 9.11 Artifact discovery

After a successful Gradle exit:

1. inspect only outputs associated with the selected module and variant;
2. prefer task-declared outputs when a stable mechanism exposes them;
3. otherwise inspect `build/outputs/bundle/<variant>/` and compatible AGP
   layouts;
4. compare against the pre-build snapshot to find files created or changed by
   this run; and
5. require explicit selection if more than one plausible AAB remains.

Never select the globally newest `.aab` in the repository or on the machine.
For a custom build layout that cannot be resolved, offer **Choose Built AAB**
and then subject that file to all normal identity, path, signing, and remote
checks.

### 9.12 Authoritative AAB inspection

Use the existing package-reading layer, extended where needed, to extract:

- package/application ID;
- `versionName`;
- `versionCode`;
- minimum SDK and target SDK when available;
- included permissions and features useful to the existing Plan;
- supported delivery/module information;
- file size; and
- SHA-256.

Verify the bundle's JAR signature using `jarsigner -verify` from the same JDK
selected for Gradle. App Bundles use JAR signing; `apksigner` is for APKs and is
not the verifier for this artifact.

Record a non-secret certificate summary such as subject, issuer, validity,
serial/fingerprint, and signature verification result. Never expose private-key
material.

Compare artifact fields with:

- the preflight snapshot;
- the linked project's expected application ID;
- `store.yaml`; and
- the Google Play application.

A package mismatch blocks upload. A version mismatch requires a new remote
check and explicit confirmation. An unsigned or invalidly signed bundle blocks
upload.

### 9.13 Android upload confirmation

Always show a separate confirmation after building because Gradle configuration
is dynamic. Display:

- exact AAB path and size;
- SHA-256;
- package name, version name, and version code;
- min/target SDK when known;
- signing certificate summary and verification result;
- Google Play application/account and selected target track;
- remote maximum/relevant version codes;
- any difference from preflight or manifest; and
- the statement that Apply creates a draft and does not send it for review.

Run one final read-only conflict check immediately before creating the upload
edit.

### 9.14 Google Play edit transaction

Use one Android Publisher edit as the transaction for the upload and any
metadata changes that the existing Runner combines with it.

Required sequence:

1. Obtain a fresh OAuth access token from the Keychain-backed service-account
   connection.
2. `POST applications/{packageName}/edits` and persist the edit ID in the run.
3. Upload the AAB through the edit's bundle upload endpoint using the media
   upload host and the file as one streaming request.
4. Validate that the returned version code exactly equals the inspected AAB's
   version code.
5. Apply planned listing/assets/catalog operations that belong in this same
   edit, if the existing Runner invokes them.
6. Update the exact selected track with the returned version code and status
   `draft` for Apply.
7. Validate the edit.
8. Commit the edit with `changesNotSentForReview=true` where supported and
   required by the API behavior.
9. Query committed state and record the exact version code/track.

Apply never uses the manifest's eventual production status to publish or send
for review. The later Release action owns review submission.

### 9.15 Edit cleanup and ambiguous outcomes

Before a confirmed commit, an open edit is disposable. Put deletion in a
`defer`/`finally`-equivalent cleanup path that runs after validation errors,
upload failures, cancellation, token expiry, and ordinary exceptions.

- If the edit is definitely uncommitted, delete it with a fresh token when
  necessary.
- If deletion fails, mark cleanup `needsAttention`, retain the edit ID, and
  retry idempotently.
- If commit definitely succeeds, do not attempt deletion.
- If commit response is lost or times out, do not repeat commit or create a new
  edit until actual package/track/version state is queried.
- Once the version code is present in committed state, treat the operation as
  successful even if the original response was lost.

### 9.16 Upload progress and retries

- Stream the AAB and report byte progress without loading it fully into memory.
- Re-authenticate on an expired token when the request is safe to retry.
- Retry rate limits and transient server failures with bounded exponential
  backoff and jitter.
- Do not retry an upload blindly after an ambiguous completed request. Query
  the edit/bundle state using the stored edit ID first.
- Validate content length, local SHA-256, returned version code, and committed
  state.
- Preserve enough run state to continue cleanup after app relaunch.

### 9.17 Android recovery cases

| Failure | Required behavior |
|---|---|
| Wrapper/settings root missing | Explain expected files; allow reselecting root |
| Multiple Gradle roots | Require explicit choice |
| Wrapper not executable | Explain permission fix; do not chmod silently |
| JDK/SDK missing or incompatible | Show detected versions/paths and selection instructions |
| Module/variant ambiguous | Require explicit choice |
| Gradle dependency/configuration failure | Preserve diagnostic; do not edit scripts |
| Signing prompt or unsigned AAB | Block; explain noninteractive upload-key signing |
| Multiple or missing AABs | Require file selection or build-layout correction |
| Artifact identity differs | Stop; rerun remote check and reconfirm |
| Version code already exists | Block; never auto-bump |
| Upload result ambiguous | Inspect the current edit before retry |
| Validation fails | Keep local AAB, delete uncommitted edit, show exact issue |
| Commit result ambiguous | Query track/version state; do not create another edit |
| Edit cleanup fails | Persist edit ID and surface cleanup action |

---

## 10. UI specification

### 10.1 Entry points

Add **Build from Project** next to the existing package-file import. Existing
`.ipa`, `.pkg`, and `.aab` import remains useful and feeds the same
`BuildCandidate` inspection and upload confirmation path.

Entry points may appear in:

- the Builds tab when no build is linked;
- the app detail's build section;
- Submit when a required artifact is missing; and
- a project-link management screen.

### 10.2 Project card

The linked-project card shows:

- folder and build-system icon;
- selected container/scheme or module/variant;
- detected product and identifier;
- last validated time;
- source Git revision/dirty state when available;
- **Change Selection**, **Reveal Folder**, **Open in Xcode/Android Studio**,
  **Recheck**, and **Unlink** actions.

Unlink removes only Super Submitter's local link. It never deletes the project
or build outputs.

### 10.3 Preflight card

Use clear rows for local and remote identity. Statuses are:

- ready;
- warning, confirmation allowed;
- unknown, verified after build; or
- blocking error.

Never hide a conflicting build number inside logs. Put it beside the value and
disable upload. Separate an unavailable store connection from a local build
failure so artifact-only builds remain possible when appropriate.

### 10.4 Live run view

Show a stable sequence of named steps:

1. Validate project
2. Resolve toolchain
3. Check store
4. Build/archive
5. Inspect and verify artifact
6. Confirm upload
7. Upload
8. Process/validate
9. Finish

The view includes elapsed time, current step, compact progress, expandable
redacted logs, cancel/stop-waiting behavior appropriate to the phase, and a
plain-language description of what is happening.

### 10.5 Confirmation language

Build confirmation:

> Build `<scheme or variant>` from `<folder>` using `<toolchain>`. This can run
> scripts and plug-ins supplied by the selected project.

Upload confirmation:

> Upload `<product identifier>` version `<version>` build `<build>` to
> `<store app/account>`. The upload creates or supplies a draft and does not
> submit it for review.

Do not use generic confirmation text such as “Are you sure?”

### 10.6 Success

Apple success shows the exact processed build and a link to App Store Connect,
plus **Reveal Archive** and **Continue to Plan**.

Android success shows exact package/version code/track and a link to Play
Console, plus **Reveal AAB** and **Continue to Plan**.

### 10.7 Error presentation

Every error panel contains:

- failed stage;
- concise cause;
- relevant selected values;
- one primary recovery action;
- optional diagnostic disclosure;
- **Copy Redacted Diagnostics**; and
- whether local artifacts or remote edits were retained.

Recovery actions include retry, reselect project/scheme/variant, change Xcode or
JDK, open the project in its IDE, reconnect the store, reveal the artifact, or
resume remote reconciliation.

---

## 11. Storage and retention

Use app-owned directories under:

```text
~/Library/Application Support/Super Submitter/
```

Suggested layout:

```text
Projects/                 linked-project records
Archives/<bundle-id>/     retained Xcode archives
Artifacts/<package>/      optional retained/imported AAB records
Runs/<run-id>/            run state and redacted JSONL logs
Scratch/<run-id>/         temporary secrets and export options
```

Requirements:

- `Scratch/<run-id>` is mode `0700` and removed unconditionally when no longer
  needed.
- Secret files are mode `0600` and never included in diagnostics.
- Archives/AABs are not secrets but may contain proprietary binaries; never
  upload them anywhere except the confirmed store.
- Provide retention by age/size with a preview and recoverable explicit delete
  where practical.
- Never delete files inside the selected source repository as retention.
- Store bookmarks/paths and run metadata locally; store credentials in Keychain.
- A user-initiated **Delete Run Data** must explain whether it also deletes a
  retained archive or AAB.

---

## 12. Security and privacy

### 12.1 Threat model

The selected project is trusted to execute for the purpose of a developer build
but is not trusted as command-line text. A malicious or compromised repository
may contain scripts that run with the developer's account during Xcode/Gradle.
Super Submitter must disclose this fact; it cannot sandbox the build without
breaking expected toolchain behavior.

The app must still defend its own process construction, credentials, logs,
stored state, and target selection.

### 12.2 Required controls

- Fixed, resolved executables and argument arrays; Super Submitter performs no
  shell evaluation. Project-controlled Xcode and Gradle builds may execute
  their own build scripts after the explicit trust confirmation.
- Project-controlled names remain single arguments even if they contain spaces,
  quotes, semicolons, dollar signs, or newlines.
- Folder-scoped discovery with symlink-escape prevention.
- Keychain for persistent secrets.
- Short-lived secret files with restrictive permissions.
- Redaction at data source, structured-log serialization, UI rendering, copy,
  and export boundaries.
- HTTPS using platform networking for store APIs.
- Explicit account/app/destination display before mutation.
- Checksums and exact identity matching for local artifacts.
- No analytics fields containing project paths, identifiers, logs, or file
  contents without an explicit future privacy design.
- No automatic execution merely because a folder is opened or restored.

### 12.3 Non-sandboxed app distribution

Super Submitter itself must be:

1. signed with the project's Developer ID Application identity;
2. built with the hardened runtime;
3. submitted to Apple's notarization service;
4. stapled where supported;
5. verified with Gatekeeper before release; and
6. updated through a separately secured, signed update mechanism if automatic
   updates are added.

These packaging requirements are for Super Submitter, not the target app upload
pipeline. There is no Mac App Store entitlement/capability variant.

---

## 13. Integration with existing Plan, Apply, and Release

The upload workflow supplies a concrete build to the existing store-management
model; it does not replace that model.

### 13.1 Apple

After processing, bind the exact App Store Connect build to the planned app
version/platform. Plan can then display “select build” as a concrete diff.
Apply associates the build while leaving the version unsubmitted. Release is
the only action that sends the version to review.

### 13.2 Google

The Google edit can combine bundle upload, listing/assets, and track-draft
changes when one Apply run owns all of them. The edit must still validate and
commit as a draft with changes not sent for review. Release later changes the
intended track status and performs review submission explicitly.

If the user runs build/upload independently, the committed draft bundle becomes
an exact candidate discovered by the next Plan.

### 13.3 Imported artifacts

An imported `.ipa`, `.pkg`, or `.aab` skips source discovery and local build but
must not skip:

- authoritative package inspection;
- signing verification where supported;
- manifest/store identity comparison;
- remote conflict check;
- upload confirmation; or
- resumable remote processing/cleanup.

---

## 14. Error taxonomy

Use stable internal categories so UI, telemetry-free diagnostics, tests, and
handover remain consistent.

| Category | Examples |
|---|---|
| `projectAccess` | folder missing, bookmark stale, permission denied |
| `projectDiscovery` | no container/wrapper, bounded search exceeded |
| `selectionRequired` | multiple workspaces, schemes, modules, variants, artifacts |
| `toolchainUnavailable` | Xcode/JDK/SDK missing, license incomplete |
| `configuration` | unsupported platform, nonshared scheme, invalid Gradle model |
| `dependencyResolution` | Swift package, CocoaPods, Maven, or Gradle dependency failure |
| `signing` | certificate/profile/upload key missing or invalid |
| `build` | compile, link, archive, or Gradle task failure |
| `artifactDiscovery` | output missing or ambiguous |
| `artifactValidation` | identity mismatch, invalid signature, malformed package |
| `remoteConflict` | build number/version code already exists |
| `authentication` | API key/service-account invalid or unauthorized |
| `upload` | rejected bytes, transport failure, Xcode export failure |
| `remoteValidation` | App Store processing or Play edit validation failure |
| `remoteAmbiguous` | timeout/lost response after possible mutation |
| `cleanup` | temporary secret or Google edit cleanup unconfirmed |
| `cancelled` | developer-requested cancellation after reconciliation |

Errors retain their original domain/code and redacted diagnostics. Mapping to a
category must not discard the underlying cause.

---

## 15. Testing strategy

### 15.1 Unit tests

Test at minimum:

- Xcode and Gradle argv construction as arrays;
- project-controlled names containing whitespace and shell metacharacters;
- redacted command preview generation;
- environment filtering and secret-name redaction;
- bounded folder discovery and symlink escape;
- parsing `xcodebuild -list -json` and `-showBuildSettings -json` fixtures;
- archive plist/product selection fixtures;
- ExportOptions plist with `manageAppVersionAndBuildNumber = false`;
- Gradle project/task output fixtures for modules and flavors;
- AAB metadata and JAR signature result parsing;
- preflight-to-artifact mismatch detection;
- exact remote build matching;
- state-machine legal/illegal transitions;
- cancellation and cleanup transitions; and
- persisted polling/recovery state restoration.

### 15.2 Process tests

Inject a fake `ProcessRunner` that can:

- stream interleaved stdout/stderr;
- exit successfully or unsuccessfully;
- hang until cancellation;
- create one, multiple, or no artifacts;
- mutate metadata between preflight and artifact;
- attempt to print known secret fixtures; and
- simulate a child process tree.

Assertions must prove Super Submitter never launches a shell to interpret a
constructed command and that no secret reaches retained logs. Fixture build
tools may launch their own scripts, matching real Xcode and Gradle behavior.

### 15.3 API tests

Use protocol-backed fake networking for:

- App Store Connect build pagination and processing transitions;
- exact build appearing after a delay;
- duplicate build conflicts;
- Google edit creation, streaming upload, version-code verification, validation,
  commit, deletion, token refresh, and rate limits;
- ambiguous upload/commit responses followed by reconciliation; and
- cleanup resumed after app restart.

Never use real credentials in automated tests or fixtures.

### 15.4 Apple integration matrix

Cover manually gated fixture projects for:

- `.xcodeproj` and `.xcworkspace`;
- iOS and Mac App Store target apps;
- automatic and manual signing diagnostics;
- apps with extensions/widgets;
- CocoaPods and Swift Package dependencies;
- multiple schemes and multiplatform schemes;
- archive scripts that intentionally change a version field; and
- build, export validation, upload, cancellation, and processing recovery.

External uploads run only against dedicated test applications/accounts with
explicit operator confirmation.

### 15.5 Android integration matrix

Cover:

- Groovy and Kotlin settings/build scripts;
- single and multiple modules;
- product flavors and multiple release variants;
- conventional and custom output locations;
- signed, unsigned, and incorrectly signed bundles;
- multiple outputs and stale outputs;
- incompatible JDK/Gradle/AGP combinations;
- duplicate Google Play version codes;
- upload/validation/commit failures; and
- edit cleanup and recovery after restart.

### 15.6 Release verification for Super Submitter

Before distributing Super Submitter, verify its own direct-download artifact:

- Developer ID signature;
- hardened runtime;
- notarization acceptance;
- stapled ticket where applicable;
- `spctl` Gatekeeper assessment on a clean test Mac;
- behavior when launched from a quarantined download; and
- Xcode/Gradle execution permissions without App Sandbox assumptions.

---

## 16. Implementation milestones

### Milestone 1 — Shared foundation

- Add linked-project, build-candidate, and upload-run models.
- Implement persistent state and run scratch/retention directories.
- Implement `ProcessRunner`, streaming logs, redaction, cancellation, and fake
  runner tests.
- Add folder selection, bounded discovery utilities, and trust warning.
- Route existing imported packages through `BuildCandidate` validation.

Exit criterion: a fake project can traverse the state machine through inspected
artifact without running a real build or making a network mutation.

### Milestone 2 — Apple local archive

- Detect Xcode/SDK readiness.
- Discover containers/schemes and parse build settings.
- Implement platform/product selection and preflight UI.
- Run an archive to app-owned storage.
- Inspect archive identity and signing; detect mismatches.

Exit criterion: fixture iOS and macOS projects produce retained, correctly
identified archives, and no upload occurs.

### Milestone 3 — Apple upload and processing

- Materialize API key securely for `xcodebuild`.
- Generate version-gated ExportOptions.
- Add final artifact confirmation.
- Run export/upload and reconcile App Store Connect builds.
- Persist and resume processing polls.

Exit criterion: a dedicated test app's exact build is uploaded, found after
processing, and handed to Plan without automatic review submission.

### Milestone 4 — Android local bundle

- Detect wrapper/JDK/SDK readiness.
- Discover Gradle roots, modules, variants, and bundle tasks.
- Run a selected bundle task.
- Discover only this run's output.
- Inspect AAB metadata and verify its JAR signature.

Exit criterion: fixture projects with modules/flavors yield an exact immutable
`BuildCandidate`, while unsigned or ambiguous outputs are blocked.

### Milestone 5 — Google Play upload transaction

- Add remote version-code preflight.
- Create edits and stream bundle uploads.
- Verify returned version code, update draft track, validate, and commit.
- Implement unconditional edit cleanup and ambiguous-outcome reconciliation.

Exit criterion: a dedicated test package receives the exact AAB in a committed
draft edit, with no release sent for review.

### Milestone 6 — Hardening and handoff

- Complete error/recovery UI and accessibility.
- Add retention controls and copyable redacted diagnostics.
- Run the integration matrices.
- Validate notarized non-sandboxed Super Submitter distribution on clean Macs.
- Update `handover.md`, user documentation, and support runbook.

Exit criterion: all acceptance criteria below pass and no known path can upload
without an exact artifact confirmation and remote conflict check.

---

## 17. Acceptance criteria

### 17.1 Shared

- [ ] The developer explicitly selects a folder before discovery.
- [ ] The app warns that builds execute project-controlled code.
- [ ] Discovery remains within the selected root and handles symlink escapes.
- [ ] Every top-level process uses an executable plus argv; Super Submitter
  constructs and evaluates no shell command.
- [ ] The app never edits a version, project, signing configuration, or source.
- [ ] Final artifact metadata is displayed before upload.
- [ ] A fresh remote conflict check runs immediately before upload.
- [ ] Secrets do not appear in UI logs, files, diagnostics, or tests.
- [ ] Cancellation and relaunch recovery reach a truthful final state.
- [ ] Apply never sends a release for review.

### 17.2 Apple

- [ ] The app discovers projects/workspaces and requires a choice when ambiguous.
- [ ] The app discovers shared schemes and selected generic archive destination.
- [ ] Preflight shows Xcode, SDK, product, bundle ID, version/build, team, and signing.
- [ ] `-allowProvisioningUpdates` is never used without explicit consent.
- [ ] The archive is stored outside the source repository and retained on failure.
- [ ] Archive metadata and signature are inspected after a successful command.
- [ ] Any material metadata mismatch stops automatic upload and requires confirmation.
- [ ] Export options explicitly disable Xcode's version/build management.
- [ ] Temporary `.p8` and plist files use restrictive permissions and are removed.
- [ ] The exact App Store Connect build is found and processing can resume after relaunch.

### 17.3 Android

- [ ] The project wrapper is used; Android Studio and system Gradle are not required.
- [ ] Module and variant are selected explicitly when ambiguous.
- [ ] The app uses the compatible JDK/SDK chosen in preflight.
- [ ] Signing credentials are neither requested nor stored by Super Submitter.
- [ ] Artifact discovery cannot choose an unrelated stale/global newest AAB.
- [ ] AAB identity and version are authoritative and its JAR signature is verified.
- [ ] A separate post-build upload confirmation is always shown.
- [ ] Duplicate/non-increasing version codes are blocked without automatic changes.
- [ ] Returned upload version code must equal the inspected AAB version code.
- [ ] The edit is validated and committed as draft, with cleanup on pre-commit failure.
- [ ] Ambiguous commit results are reconciled before retry.

### 17.4 Super Submitter distribution

- [ ] Only a non-sandboxed direct-download build is produced.
- [ ] The app is Developer ID signed, hardened, notarized, and Gatekeeper verified.
- [ ] There is no Mac App Store product variant or sandbox/XPC workaround branch.

---

## 18. Open implementation decisions

These choices may be resolved during implementation without changing the core
workflow:

1. Whether Apple defaults to always pause at artifact confirmation or permits a
   clearly opted-in combined Build & Upload path when metadata is identical.
2. Exact archive/AAB automatic retention duration and size threshold.
3. Whether a linked-project bookmark is security-scoped or an ordinary bookmark
   in the non-sandboxed build; either must detect moved folders gracefully.
4. The minimum supported Xcode, Gradle, AGP, and JDK versions.
5. Whether the first Android implementation parses plain Gradle task output or
   adds a small versioned init script that emits structured discovery data. Any
   init script must be app-owned, reviewed, non-mutating, and shown in diagnostics.
6. Whether an independently uploaded Google bundle should be committed to a
   dedicated draft track immediately or held for a combined Apply edit. It must
   never be sent for review in either case.
7. The exact public certificate fields shown for Apple and Android signatures.

No open decision permits a Mac App Store distribution version of Super
Submitter, shell command construction, automatic version changes, hidden
signing changes, or automatic review submission.

---

## 19. Implementation references

Use installed tool help as the final authority for the selected local toolchain,
especially `xcodebuild -help` export keys and wrapper Gradle capabilities.

- [Apple: Distributing your app for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases)
- [Apple: Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Apple: App Store Connect API builds](https://developer.apple.com/documentation/appstoreconnectapi/builds)
- [Apple: Xcode 15 release notes](https://developer.apple.com/documentation/xcode-release-notes/xcode-15-release-notes)
- [Android: Build your app from the command line](https://developer.android.com/build/building-cmdline)
- [Android: Build for release](https://developer.android.com/build/build-for-release)
- [Android: Sign your app](https://developer.android.com/studio/publish/app-signing)
- [Google Play Developer API: Edits](https://developers.google.com/android-publisher/edits)
- [Google Play Developer API: Edits bundles](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.bundles)
- [Google Play Developer API: Edits tracks](https://developers.google.com/android-publisher/api-ref/rest/v3/edits.tracks)
