# Changelog

## 1.1 (272) - 2026-08-11

This entry covers the 24 hours to 2026-08-11, so it repeats the work that
1.0.4 (269) shipped part way through that day.

### Build

- A build number App Store Connect already holds no longer stops the build. The chosen number reaches `xcodebuild` as a setting override, and the preflight reads the same number, so the project file stays untouched.
- A failed build reports what the tool actually printed. Both output streams are read and named, and the tail of the log is kept.
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
