# Prompt: build the Super Submitter website

Copy everything below the line into a fresh agent session.

---

Build a marketing website for **Super Submitter**, a macOS app for developers.
The audience is skeptical, technical, and allergic to marketing language. Your
job is to make them understand the product in thirty seconds and trust it in
two minutes.

Read this whole brief before you write anything.

## 1. What the product is

Super Submitter is a native macOS app (macOS 14 or later, SwiftUI, not
sandboxed, Developer ID signed and notarized, distributed as a direct
download). It prepares an iOS, macOS, and Android app for the **App Store** and
**Google Play** from one YAML file and one action.

The developer keeps a single file, `store.yaml`, in their repository. It holds
the listing text, the screenshots, the prices, the in-app purchases, and the
review information for both stores. Super Submitter reads both stores, shows
exactly what will change, writes the changes, and stops at a draft. The
developer presses release themselves, one store at a time.

It also mirrors the same purchase catalog into **RevenueCat** or **Adapty**, and
it can build and upload the binary from the developer's own Xcode project or
Gradle project.

The mental model is `terraform plan` and `terraform apply`. Developers already
know it. Use that comparison early; it does more work than any adjective.

## 2. The one promise

**We prepare a draft. You press release.**

This single line is the product. The whole site should support it. Everything
Super Submitter writes lands in a draft state that no customer can see. Nothing
reaches a review queue, a store listing, or a user without a separate,
deliberate, per-store button press.

## 3. Who it is for

Independent developers and small teams who ship the same app to both stores.
They write the description twice today. They upload the screenshots twice. They
create the in-app purchases twice. They keep the mapping between the two
consoles in their head, and that is where the mistakes happen.

## 4. The strengths, in the order that matters

Lead with 1 to 4. They are the reasons someone installs this.

**1. Nothing an apply does is irreversible.**
Every write ends in a draft. There is no rollback engine because there is
nothing to roll back. A failed run is fixed by running it again. The two
release buttons are the only irreversible actions in the entire app, they are
per store, and no code path chains them. A failure can never leave one store in
review and the other not.

**2. It shows you the diff before it writes.**
The plan reads the live state of both stores, compares it to your file, and
prints one row per change with the exact HTTP request behind it. It writes
nothing. A new app starts in dry run mode: it builds every request, logs it,
and sends none.

**3. One file, two stores, and it knows the mapping.**
Apple and Google disagree about locale codes (`zh-Hans` vs `zh-CN`, `es-MX` vs
`es-419`), screenshot buckets, price models, and character limits. Super
Submitter carries those tables. It warns when your shared text exceeds the
smaller of the two limits, names the store and the overflow count, and **never
truncates your words**. You add a per-store override or you shorten the text.
The decision stays yours.

**4. It names the steps no API can do, instead of hiding them.**
Privacy nutrition labels, the IARC content rating questionnaire, tax and
banking, the Play service account invitation. Super Submitter shows these as a
live checklist with a direct link to the right console page, and it marks each
one done when an API can confirm it. It holds the release button while a step
it can detect is still open. Most tools pretend these do not exist and let you
discover them at submission.

**5. Your secrets never enter your repository.**
The `.p8` key and the service account JSON go straight to the macOS Keychain.
The run log records one JSON line per API call with the method, the path, the
status, and the duration. No token, no request body, no headers. It is safe to
commit and safe to paste into a bug report.

**6. It builds and uploads from your own project.**
It runs your project's `xcodebuild` and your project's own Gradle wrapper. It
never runs a system Gradle, never edits a Gradle file, never asks for a keystore
password, and never answers a prompt on your behalf. Every command is an
executable plus an argument array, so a folder named `; rm -rf ~` is one
argument and never a second command. It shows you the exact artifact and asks
you to confirm before it uploads.

**7. It reads your build with tools every Mac already has.**
It opens an `.ipa`, a `.pkg`, and an `.aab` with `unzip` and `pkgutil` and
pre-fills the version, the build number, the bundle id, the locales, and the
encryption flag. No Xcode and no Android SDK are needed on the machine that
submits. (For the curious: an `.aab` manifest is an aapt2 protobuf, `aapt2 dump`
refuses it, and `bundletool` needs Java. Super Submitter reads the six fields it
needs straight off the wire.)

**8. Applying twice does nothing the second time.**
The plan compares before it writes. Screenshots compare by checksum, so an
image that already landed is never re-uploaded.

**9. Updating a live app takes no console trip.**
It reads what is on the store, creates the next version itself, requires the
version number to climb past the released one, and requires What's New before
it will apply.

**10. It manages the app after it ships.**
A second mode covers the live app: customer reviews from both stores with
replies, crash rate and ANR vitals, TestFlight and Play internal testing, and
Google Play app recovery. Reads and one-button actions, never a silent write.

**11. No server, no account, no database.**
It runs on your machine. Your manifest is the intent, the stores are the state,
git is the history. It updates itself over Sparkle from GitHub releases.

## 5. Real material you should use

A developer site's best asset is the real config file. Use this, or a trimmed
version of it, as hero or near-hero content. Do not invent keys.

```yaml
version: 1

apps:
  apple:
    appId: "1234567890"
    platforms: [IOS, MAC_OS]
    bundleId: com.example.app
  google:
    packageName: com.example.app

release:
  versionName: "3.2.0"
  build:
    ios: build/App.ipa
    android: build/app.aab

listing:
  defaultLocale: en-US
  locales:
    en-US:
      name: "Fast Bill Split"
      subtitle: "Split any bill in seconds"
      description: |
        Split a restaurant bill with your friends. No account. No ads.
      whatsNew: "Faster scanning and a new dark theme."
      keywords: "bill,split,tip,receipt,restaurant"
      google:
        shortDescription: "Split any bill in seconds with your friends"

media:
  screenshots:
    en-US:
      phone: [assets/en/phone/*.png]

pricing:
  base: { amount: 4.99, currency: USD, territory: USA }

purchases:
  - id: com.example.app.pro
    kind: non_consumable
    name: "Pro Unlock"
    price: { amount: 9.99, currency: USD }
    entitlements: [pro]
```

The second best asset is the plan output. Build it as styled HTML or SVG, not a
screenshot. It should read like a diff, one row per change, grouped by system:

```
App Store
  + Create the version 3.2.0                POST /v1/appStoreVersions
  ~ en-US  description, whatsNew            PATCH /v1/appStoreVersionLocalizations/{id}
  + en-US  6 screenshots, APP_IPHONE_67     POST /v1/appScreenshots
Google Play
  + Open an edit                            POST /edits
  ~ en-US  fullDescription, releaseNotes    PATCH /edits/{id}/listings/en-US
  + Upload app.aab  42.1 MB                 POST /edits/{id}/bundles
  = Commit the edit                         POST /edits/{id}:commit
```

Three more things you may show:

- **The rule bar.** The app groups its screens into four zones: edit the
  manifest, check, write the drafts, release. A visual of that progression
  explains the safety model faster than a paragraph.
- **The binding limit.** Apple allows 30 characters for the subtitle; Google
  allows 80 for the short description. The shared value is held to 30 unless you
  override Google. This one example teaches the whole idea.
- **The console checklist.** A short list of the steps no API can perform, each
  with a link. It is a feature, not an apology. Present it that way.

Six real screenshots of the running app live in `design/screenshots/`, each one
2560 by 1578 pixels, which is a 1280 point window at 2x:

| File | Screen |
|---|---|
| `welcome-light.png`, `welcome-dark.png` | The entry screen, with the App Store and Google Play marks and the two doors: submit a new app, or update existing apps. |
| `onboarding-light.png`, `onboarding-dark.png` | Step 1 of 5, "Connect your stores", with the two store toggles. |
| `marketing-light.png`, `marketing-dark.png` | The Marketing tab: custom product pages, a product page experiment, in-app events, and the one write button. |

Use them at half size for a crisp 1x, and pair light with dark if the page has a
theme toggle. `tools/screenshots.sh` regenerates all six, so ask for a retake
rather than editing a picture.

Every value inside them is invented for the picture: no real app, no real
account, no real key. Do not add a caption implying otherwise, and do not
fabricate a screenshot of any screen not in that list. If you need one, ask.

## 6. Limits you must not paper over

Being straight about these buys more trust than hiding them costs. Put them
somewhere honest, such as a short FAQ.

- Two stores only: the App Store and Google Play. No Amazon, Huawei, or
  Microsoft Store.
- Not on the Mac App Store, by design. It needs to run Xcode and Gradle and
  read your build output, so it ships as a notarized direct download.
- It never submits for review by itself. That is the point, not a gap.
- It does not translate your metadata. You own the words.
- It does not do sales or finance reports.
- It does not design your paywall. It creates a paywall holding the right
  products; you style it in the RevenueCat or Adapty dashboard.
- App Store Connect has no sandbox. The dry run default and the plan step exist
  because of that. Say so plainly.
- Some console steps stay manual forever. Section 4, strength 4 turns this into
  a feature. Do not overclaim it away.

## 7. Pricing

**Do not publish prices without confirmation from the person running you.**

Licensing is specified but not shipped. The draft plan is a free tier covering
manifest editing, build inspection, store reads, and previewing a plan, with
payment unlocking raw YAML editing and any write to a store. Draft figures are
USD 4.99 monthly, USD 49.90 annual, USD 449.90 lifetime. **These are unconfirmed
and no checkout exists.** Build the pricing section only if you are told to, and
never wire a real payment flow.

Ask before you write a pricing page. Ask before you claim a download link works;
releases live at `github.com/rafacst/super-submitter-app/releases`, and you
should confirm one is published.

## 8. Voice

Match the product's own voice. It is short, plain, and unhurried.

- Short declarative sentences. One idea per sentence.
- Active voice. "The app reads both stores", not "both stores are read".
- Concrete nouns. Name the file, the endpoint, the limit, the store.
- **No em dashes anywhere.** Use a period, a comma, or a colon.
- No exclamation marks. No "revolutionary", "seamless", "effortless",
  "supercharge", "game changer", "10x". No AI language.
- Never claim a speed multiplier or a time saving you cannot support.
- Prefer showing a real file, a real diff, or a real error message over an
  adjective.
- Second person for the developer. "Your build", "your keys", "your words".

Good: "It warns when your subtitle exceeds 30 characters, names the store, and
never truncates it."
Bad: "Powerful validation keeps your metadata perfectly optimized."

## 9. Design

A tool site, not a startup landing page. Reference points: Terraform, Tailscale,
Raycast, Linear.

- Dark theme first, with a light theme that works. Respect
  `prefers-color-scheme` and any theme toggle.
- One accent color. Use red for nothing except the irreversible action, because
  the app does the same.
- A real monospace face for every file, path, endpoint, and diff. Generous line
  height. Code blocks are content here, not decoration.
- Calm density. Whitespace, a narrow measure for prose (around 65 to 75
  characters), wide only for code and diagrams.
- Motion is minimal and never blocks reading. No scroll hijacking, no parallax.
- The two store marks may appear, but do not imitate Apple or Google branding
  and do not imply either company endorses this.

## 10. Build constraints

- Static site. No backend, no database, no analytics that needs consent.
- Self contained: inline the CSS, inline any JavaScript, embed images as SVG or
  data URIs. No CDN, no external fonts, no remote requests. Assume a strict
  content security policy blocks every external host.
- Semantic HTML. Real headings in order, real landmarks, alt text on every
  image, visible focus states, and a contrast ratio of at least 4.5:1 for body
  text.
- Responsive with relative units and flex or grid. Wide content (diffs, tables,
  code) scrolls inside its own container. **The page body must never scroll
  horizontally.**
- Fast: no blocking requests, no layout shift, usable with JavaScript disabled.

## 11. Pages

Start with a single long landing page. Add more only if the content demands it.

1. **Hero.** The one promise, one sentence of what it is, the platform
   requirement, and the download button. Show `store.yaml` beside it.
2. **The problem.** You do the same work twice, and the two consoles use
   different words for the same thing. Three sentences, no hand wringing.
3. **How it works.** Manifest, plan, apply, release. Four steps with the diff
   visual. This is the center of the page.
4. **Safety.** Draft only, dry run by default, per-store release, secrets in the
   Keychain, redacted logs. This section closes the sale for a cautious
   developer.
5. **What it covers.** Listing text, screenshots and previews, builds,
   in-app purchases and subscriptions, prices, review information, RevenueCat
   and Adapty, TestFlight and Play testing tracks.
6. **After you ship.** Reviews, vitals, app recovery.
7. **The honest part.** The console-only steps and the limits from section 6.
8. **FAQ.** Six to ten real questions. Include: does it submit for me, what
   happens if a run fails halfway, where do my keys live, do I need Xcode
   installed, why is it not on the Mac App Store, what happens on a second
   apply.
9. **Footer.** Download, the GitHub repository, the license, contact.

## 12. Done means

- Every factual claim traces to this brief. If you want to say something not
  written here, ask first.
- No em dashes. Search the output and confirm.
- No invented feature, no invented price, no invented benchmark, no fake
  testimonial, no fake customer logo, no fake screenshot.
- Passes a keyboard-only pass and a zoom-to-200% pass.
- Renders correctly in both light and dark themes.
- Tell the person running you which claims you were unsure about, and what you
  left out.
