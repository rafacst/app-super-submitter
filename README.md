<h1 align="center">Super Submitter</h1>

<p align="center"><strong>We prepare a draft. You press release.</strong></p>

<p align="center">
  A native macOS app. It prepares your iOS, macOS, and Android app for the
  App Store and Google Play, in one action.
</p>

<p align="center">
  <a href="https://github.com/rafacst/app-super-submitter/releases/latest/download/SuperSubmitter.zip"><img alt="Download for macOS" src="https://img.shields.io/badge/download-macOS-0a84ff"></a>
  <a href="https://github.com/rafacst/app-super-submitter/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/rafacst/app-super-submitter"></a>
  <img alt="macOS 14 or later" src="https://img.shields.io/badge/macOS-14%2B-lightgrey">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6.0-orange">
</p>

<p align="center"><a href="https://apps.rafacst.me/super-submitter-app/">Website and screenshots</a></p>

---

## You do the work twice

You ship the same app to two stores. You write the description twice, you
upload the screenshots twice, and you create the in-app purchases twice.

Apple and Google use different words for the same thing. The mapping between
the two consoles lives in your head, and that is where the mistakes happen.

Super Submitter reads both stores, shows you what it would change, writes the
drafts, and stops there.

## Describe, plan, apply, release

Four steps, in one direction. You decide when the last one happens.

| Step | What it does |
| --- | --- |
| **1. Describe** | You describe your app once. The listing text, the screenshots, the prices, and the review information for both stores, in one place. |
| **2. Plan** | The plan reads both stores, compares them to your app, and lists the changes it would make. It writes nothing. |
| **3. Apply** | Apply sends those changes. What it writes lands in a draft that no customer can see. |
| **4. Release** | You press release yourself, in the app, one store at a time. |

## It knows which limit binds

The App Store allows 30 characters for the subtitle. Google Play allows 80 for
the short description. One shared value is held to 30, and Super Submitter
tells you which store set that limit.

It never truncates your words. You shorten the text, or you add a per-store
override. The decision stays yours.

## It stops before the store

App Store Connect has no sandbox, so you cannot rehearse a submission. The app
is built around that.

- **Every write ends in a draft.** Nothing reaches a review queue, a store
  listing, or a user without a separate button press from you.
- **A new app starts in dry run.** It prepares every change, logs it, and sends
  none. You turn that off yourself, once you have read a plan and agree with it.
- **One release button per store.** A failure can never leave one store in
  review and the other not.
- **Your keys stay in the Keychain.** The Apple key and the Google service
  account file go to the macOS Keychain. Nothing you commit holds a credential.

## What it covers

One sidebar, in the order of the work.

| Tab | The question it answers |
| --- | --- |
| Stores | Which store accounts do I use? |
| Build | What do I submit? |
| Details | What does the listing say? |
| Media | What does the listing show? |
| Monetization | What does it cost, and what is for sale inside it? |
| Marketing | How does the App Store sell it? |
| Review info | What does the reviewer need? |
| Summary | What changes, exactly? |
| Release | Is it ready, and shall I send it? |
| Live app | What are the customers seeing, and what can I fix? |

## Install

[**Download SuperSubmitter.zip**](https://github.com/rafacst/app-super-submitter/releases/latest/download/SuperSubmitter.zip),
unzip it, and move the app to Applications.

macOS 14 or later. Apple silicon and Intel. Developer ID signed and notarized.
The app updates itself through Sparkle, so you download it once.

To reach a store you need an App Store Connect API key, a Google Play service
account file, or both. The app asks for them on the Stores tab and puts them in
the Keychain.

## Build it yourself

The whole app is in this repository. Xcode 26 and macOS 14 or later.

```bash
swift test
```

`SubmitKit` builds and tests with SwiftPM alone. It holds every rule, and it has
no UI.

```bash
xcodegen generate && open SuperSubmitter.xcodeproj
```

`project.yml` is the source of the Xcode project. Regenerate it after you change
the file list or a build setting. A local build talks to the live licensing
service, so store writes still need a plan on your account.

## How the code is arranged

| Path | What lives there |
| --- | --- |
| `Sources/SubmitKit` | No UI. Every rule in the spec, and each one has a test. Store clients, the planner, the manifest, the runner. |
| `Sources/SuperSubmitter` | Views only. No logic. |
| `Tests/` | The suite. The release workflow runs it beside the release, not in front of it. |
| `project.yml` | The Xcode project, written by XcodeGen. |
| `.github/workflows/release.yml` | Test, build, sign, notarize, sign the appcast, publish. |

Your app is described in one `store.yaml`. Every tab edits that file, and
nothing else holds the desired state. It is plain YAML, so you can read the
diff before you apply it.

## Pricing

Everything up to the point of writing to a store is free. You pay for the
writing: the applies, the uploads, and the releases.

| Plan | Price | What it covers |
| --- | --- | --- |
| Free | $0 | Set up your app, edit every field, read both stores, and preview a plan. |
| Monthly | $4.99 | Everything in Free, plus the applies, the uploads, and the releases. |
| Annual | $49.90 | The same access as Monthly. Billed once a year. |
| Lifetime | $449.90 | The same access, paid one time. |

Prices in US dollars.

### Free for indie developers

If you ship your own apps and the price is in the way, you do not have to pay.
There is no form to fill in and nothing to prove. Send a message to
[@rafacst on Threads](https://www.threads.net/@rafacst) and ask how to get it.
You get a code, you enter it in the app, and you get the full version.

## Questions

**Does it submit my app for review?**
No. What an apply writes lands in a draft that no customer can see. Nothing
reaches a review queue or a store listing until you press release, in the app,
for one store.

**What happens if a run fails halfway?**
You run it again. The plan compares both stores before it writes, so the second
run only does the part that did not land.

**Where do my keys live?**
In the macOS Keychain. The Apple key and the Google service account file go
straight there and never enter your repository.

**Do I need Xcode installed?**
Only to build. Super Submitter reads a finished build with the tools every Mac
already has. If you want it to build the binary too, it runs your own project's
build commands.

**Where does my app data go?**
It stays on your machine. Super Submitter talks to Apple and Google directly,
and the stores hold the state. You sign in only to buy a plan or to restore one.

**Why is it not on the Mac App Store?**
It runs your build tools and reads files across your disk, which the sandbox
does not allow. So it ships as a Developer ID signed and notarized download,
and it updates itself.

## Contact

[contato@rafacst.me](mailto:contato@rafacst.me) or
[@rafacst on Threads](https://www.threads.net/@rafacst).
Bugs and feature requests go in
[Issues](https://github.com/rafacst/app-super-submitter/issues).

---

App Store is a trademark of Apple Inc. Google Play is a trademark of Google LLC.
Super Submitter is not affiliated with, or endorsed by, either company.
