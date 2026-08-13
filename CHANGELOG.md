# Changelog

## 1.2 (297) - 2026-08-13

### Build

- A version can ship a build App Store Connect already processed. The Build tab lists what the store holds and one press names the build the next apply attaches, so a build that is ready and is not the newest can be shipped without opening the console.
- An artifact whose number is above the run still reaches the store.
- The build selection and the preflight states were repaired.

### App Store review

- A submission that is with the store says so on screen.
- A version Apple already has is no longer held back, and the app names which half of review it is in.
- The summary and the release button answer from the store rather than from the session.

### Listing, details and media

- Every screenshot the App Store shows is named by the screen size it belongs to, largest first, the same order Media Manager uses. One phone group used to merge up to nine Apple sizes into a single unlabelled row.
- The custom product pages and the product page optimization treatments are read and shown, each as its own strip with its name and its state. They are read only, and the app writes to none of them.
- Live store pictures are drawn from the copy the import downloaded instead of being fetched again on every appearance.
- The live picture count is the store's real count. Every read used to add the live set to the set the last read left behind, and the total grew on every read and across launches.
- A prose box can be dragged taller and keeps the height.
- Screenshots are counted the way Apple counts them, and the package name can be typed.

### Products and money

- The products the App Store already holds are brought in, and the app says what changing one of them costs.
- A purchase that names no locale in `store.yaml` is left alone. The plan used to report every purchase as changed forever, and the apply deleted the names Apple held for it.

### Stores, apps and identifiers

- Every required identifier can be typed, and each store gets its own project folder.
- The identifiers a store already holds are fetched, and a shipped app is told apart from a draft.
- Each store carries its own release version, and only the apps a store has shipped are managed.
- Every app is shown the way a customer meets it in the store, and the icons the stores answer with are kept.
- An app's store page opens from its own name.

### Beta testing

- Beta testing has a tab of its own.
- A beta group carries every switch TestFlight offers, and it is handed the build a tester is waiting for.

### Game Center

- A game carries everything Game Center holds, and it is sent from the tab that edits it.
- The App Store Connect side of Game Center management is complete.

### Reports and analytics

- The numbers both stores report are drawn, and a report is read by its own header.
- The app measures which screen a developer is on and who is using it, and the token stays out of the tree.

### Publishing

- The export compliance answer is asked of the build before it is written. Apple takes that answer from the binary while it processes the build and refuses to change it afterwards, so the run used to stop on a conflict it could not name.
- Territory availability is always created and never patched. `appAvailabilities` takes no update, and the 403 Apple returns for one was reported as a permission the key was missing.
- A blocker that belongs to one store no longer disables an unrelated apply.
- The stores and the disk are read for what they already hold before anything is planned.

### Release pipeline

- A release that cannot report is refused.

## 1.1 (273) - 2026-08-11

This entry covers the 24 hours to 2026-08-11, so it repeats the work that
1.0.4 (269) shipped part way through that day.

### Build

- A build number App Store Connect already holds no longer stops the build. The chosen number reaches `xcodebuild` as a setting override, and the preflight reads the same number, so the project file stays untouched.
- A failed build reports what the tool actually printed. Both output streams are read and named, and the tail of the log is kept.
- A release version that disagrees with the project is named on the preflight, before the archive, with one press to build the version store.yaml holds. The project file is still neither opened nor written.
- An artifact this app built can be deleted from the build screen, and every retained archive from Settings. Only what Super Submitter wrote: an Android App Bundle is Gradle's own output inside your project, so it is never one of them.
- Settings became its own tab, the build screen settled, and the preflight columns hold their width.
- A built archive says why it is held back.

### App Store review

- The sidebar marks the review state of every linked app.
- A version under review offers a choice, locks the fields Apple holds, and states the outcome.
- Every send is held while the App Store has the version, and one vocabulary says so.
- A screenshot run still stands where review holds the version.
- A store hold is reported as a hold, not as an error.

### Listing, details and media

- Listing resources moved to the Details tab, and the field boxes close.
- The one listing field the App Store still takes live is marked. The rest say once, in the store's name, why they do not accept typing.
- A custom product page carries its own screenshots, with a way in from Media.
- A media row says why a set of screenshots is being sent again.
- The media controls hold instead of disappearing.

### Marketing, analytics and money

- Marketing has a column per store and rows that say where each page stands.
- A repeated marketing apply creates nothing new. One store identity rule decides.
- An experiment result has its own line and names its count.
- The analytics segments are fetched, and a report says what it really carries.
- The crash rate says whether the release made it worse.
- The Live App tab leads with the answer.
- Monetization reads the store's price, purchases and subscriptions without overwriting local edits.

### Account and offer

- The account tab carries the offer, the plans and the checkout.
- The offer leads with the price and with the release waiting.
- A release can be answered from any screen.

### Recovery

- A draft holds every linked app and its manifest, including an edit that has not reached the disk yet. The newest twenty are kept, a restore never writes over a file that is still there, and Save sits in the corner of every tab.

### Shell and layout

- An edit clears a failed or finished run, so the Summary tab no longer stays stuck and Retry works again.
- Every fold animates the same way, the sidebar groups are divided, and the credential header shows the name and the state instead of machine identifiers.
- The sidebar has the switch between the two jobs again, and each tab says what it does.
- The runway steps have a boundary the eye can find.
- Lists whose rows already open no longer fold.
- The tick that unlocks a refused apply sits where the refusal is said.

### Release pipeline

- The test suite runs beside the release instead of in front of it.

## 1.0.4 (269) - 2026-08-10

- Redesigned the Stores, Build, Details, Media, Monetization, Marketing, Review Info, Summary, Release, Live App, Account, and Settings screens around the work each store supports.
- Added Google OAuth sign-in and clearer account, plan, checkout, and release controls.
- Added store-specific screenshots, listing fields, prices, purchases, subscriptions, custom product pages, tests, events, review details, and export-compliance handling.
- Added live App Store review state, ratings, crash, sales, and analytics reporting, including safe handling for versions already under review.
- Restored build platform and scheme selection, persisted the selected platform, and improved build and release blockers.
- Fixed disappearing media controls, repeated marketing creates, rejected-version writes, delayed listing input, and several layout and wording issues.
- The Monetization tab now imports the existing App Store price, purchases, and subscriptions without overwriting local edits.
