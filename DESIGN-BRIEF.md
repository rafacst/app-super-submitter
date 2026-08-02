# Super Submitter — Design Brief

A complete brief for a design agent. Read this file only. You do not need
`SPEC.md`. Every screen, every field, every state, and every rule is here.

- Product: Super Submitter, a macOS app
- Platform: macOS 14 or later, SwiftUI, native
- Status: the specification is v1 draft, the design is at zero
- Date: 2026-08-01

---

## 0. What you must deliver

Design the nine tabs, the onboarding, the Settings panel, and the
confirmation sheets. Section 16 holds the priority order and the format.

Do not invent features. Every control in this file exists for a reason that
section 1 to section 3 explain. A control that this file does not name does
not belong on the screen.

---

## 1. The product in one page

A developer who ships the same app to the App Store and to Google Play does
the same work twice. The developer writes the description twice, uploads the
screenshots twice, creates the in-app purchases twice, and then watches two
dashboards.

Super Submitter does that work once. The developer fills one set of forms.
The app writes to both stores through their APIs. It leaves a **draft** in
each store. The developer then presses one release button per store.

The app also mirrors the purchases into RevenueCat or into Adapty, which are
the two services that developers use to manage subscriptions. That step is
optional.

The app writes one file, `store.yaml`, in the developer repository. Every
form field in the app writes into that file. The file is the truth. The
screens are a comfortable way to edit it.

---

## 2. The user

A solo developer or a small team. They ship an app to two stores. They know
Xcode and Android Studio. They know `terraform plan` and `terraform apply`,
and this app copies that model on purpose.

**They are afraid of this app.** That fear is correct and the design must
respect it. A wrong write reaches a live store listing that customers see.
Apple offers no sandbox. A submission that goes to review by accident costs a
place in a review queue and days of waiting.

They use the app in bursts. They open it on a release day, they work for
thirty minutes, and they close it for three weeks. The design must survive
that gap. Nothing may depend on what the user remembers.

---

## 3. The one promise

> **We prepare a draft. You press release.**

This sentence is the product. It appears in the onboarding, and the whole
design serves it.

Three consequences for you:

1. **Nothing in tabs 1 to 8 is irreversible.** Those screens may feel light,
   quick, and forgiving. They can afford large drop targets, inline edits,
   and no confirmation dialogs.
2. **Tab 9 holds the only two irreversible buttons in the app.** Those two
   buttons must look different from every other button in the product. They
   must be impossible to press by mistake.
3. **The user must always know which of the two zones they stand in.** A
   glance at the window answers it. This is the main job of the visual
   hierarchy.

---

## 4. Platform and constraints

| Item | Value |
|---|---|
| Platform | macOS 14 or later |
| Framework | SwiftUI. Use native controls. |
| Window | **Exactly one window.** Settings and every confirmation open as a panel over it. |
| Default size | 1280 by 820 points |
| Minimum size | 1040 by 720 points |
| Sidebar width | 240 points, resizable from 200 to 320 |
| Appearance | Light and dark. Both are first class. |
| Language | English in v1. The app edits many languages, and its own interface is English. |
| Icons | SF Symbols first. Draw a custom glyph only when SF Symbols holds none. |

The app is a **native Mac app**, not a web app in a window. It uses the
sidebar, the toolbar, the menu bar, sheets over the window, and system
notifications. A designer who reaches for a web dashboard pattern is
on the wrong path.

---

## 5. The design principles

1. **Show the state, never the guess.** Every number on the screen comes from
   an API read or from a file on disk. Nothing is estimated.
2. **Red means irreversible.** Red is reserved for the two release buttons
   and for a validation error. Never use red for a brand accent, a chart, or
   a decoration.
3. **One store per column, always.** Apple on the left. Google on the right.
   The provider third. This order never changes anywhere in the app.
4. **The error carries the fix.** No error message ends at the diagnosis.
   Each one names the tab that fixes it and offers the button that goes
   there.
5. **A wide window shows more, not bigger.** The forms use the extra width
   for the per-store preview panel, never for larger text.
6. **The user closed the app three weeks ago.** Every screen states where the
   work stands without a memory of the last session.

---

## 6. The information architecture

```
Main window
├── Sidebar (default) or Top bar (a Settings option)
│   ├── App switcher            ← the linked apps, plus "New app"
│   └── Tab list                ← 9 tabs, in the order of the work
│       ├── 1  Stores           the credentials
│       ├── 2  Build            the package
│       ├── 3  Details          the text
│       ├── 4  Media            the images and the videos
│       ├── 5  Money            the price and the purchases
│       ├── 6  Review info      what the reviewer needs
│       ├── 7  Plan             the diff, the gate
│       ├── 8  Submit           the run
│       └── 9  Release          the checklist and the two buttons
└── Content area

Settings panel (⌘,)           over the window, 4 items, no credentials
Onboarding                     5 cards, the first run
Menu bar item                  the state of both stores in one glance
```

**Tabs 1 to 6 edit the file. Tab 7 reads. Tab 8 writes drafts. Tab 9
releases.** Draw that boundary. A subtle divider in the tab list between 6
and 7, and a second one between 8 and 9, carries the whole mental model at no
cost.

**The tabs are not a wizard.** The user opens any tab at any time. There is
no Next button and no locked step. A tab that lacks a prerequisite shows one
line and one button that goes to the tab which holds it.

**The top bar option.** Settings offers `Navigation: Sidebar or Top bar`. The
top bar shows the same nine tabs as a segmented control and moves the app
switcher into the toolbar. The content area does not change. Design the
sidebar first. Then show one screen in the top bar position, to prove that
the content survives it.

---

## 7. The sample data

Use this one data set in every mockup. A consistent example makes the screens
read as one product.

| Field | Value |
|---|---|
| App name | Fast Bill Split |
| Subtitle | Split any bill in seconds |
| Bundle id | `com.fastbillsplit.app` |
| Package name | `com.fastbillsplit.app` |
| Version | 3.2.0 |
| Build | iOS 412, Android version code 412 |
| Locales | `en-US` and `pt-BR` |
| Price | 4.99 USD |
| Products | Pro Unlock 9.99, Premium Monthly 2.99, Premium Yearly 24.99 |
| Provider | RevenueCat |
| Developer | one person |

Apple app id `1234567890`. Use it in the links.

---

## 8. The screens

### 8.0 The shell

**The app switcher** sits at the top of the sidebar. It lists the linked
apps. Each row holds the app icon, the name, and two small state dots, one
for Apple and one for Google. A **New app** row sits at the bottom of the
list.

A row is green when both stores match the file. It is yellow when a change
waits. It is red when a validation error blocks the work.

**The tab list** sits below the switcher. Each row holds an SF Symbol, the
name, and a badge when the tab holds an error or a warning. The badge is a
count, not a dot, because the count tells the user how much work waits.

**The toolbar** holds the tab title on the left. Each tab adds its own
controls on the right. Two controls appear on many tabs:

- A **locale picker**, on tab 3 and tab 4 only.
- A **YAML** toggle, on tabs 1 to 6. It reveals the raw block of
  `store.yaml` behind that tab, in a panel on the right. Both sides edit the
  same file.

**The menu bar item** shows the state of both stores during a run and after a
release. Design it as a small popover: two rows, one per store, with the state
and the time of the last check.

---

### 8.1 The onboarding

It opens on the first run. It opens again from the Help menu. It writes
nothing and one click skips it.

Five cards, one per step of the work, then one **Start** button.

| Card | Text |
|---|---|
| 1 | Choose your stores. Connect each one. |
| 2 | Pick your build, or pick an app to update. |
| 3 | Write the details once. We read what the build already knows. |
| 4 | Add the screenshots and the videos. We check every size. |
| 5 | Set the price and the purchases. We mirror them to RevenueCat or to Adapty. |

A last line, larger than the cards, reads:

> **We prepare a draft. You press release.**

This line is the emotional centre of the whole product. It appears before the
first credential, because it is what makes a developer trust the app with a
private key. Give it the weight it deserves.

**Design decision for you.** Five cards in a row, or one card at a time with
a page control? The app is a Mac app with a wide window, so a single scene
that shows all five at once is likely correct. Show both if you are unsure.

---

### 8.2 Tab 1 — Stores

**Purpose.** Choose the stores. Connect each one.

**The store choice.** Two large selectable cards, App Store and Google Play.
Either one, or both. A card that is not selected greys out the rest of the
app for that store.

**The credential card.** A selected store reveals a credential card below it.

| Store | The card asks for |
|---|---|
| App Store | A `.p8` key file (a drop target), a key id, an issuer id |
| Google Play | A service account JSON file (a drop target) |

Each card holds:

- A **Where do I get this?** disclosure. It opens an inline numbered guide
  with a button that opens the correct console page. Design the open state
  and the closed state.
- A **Test connection** button. On a pass it shows the team name. On a
  failure it shows the cause and the fix.
- One line that states where the secret goes: **the macOS Keychain**.

**Two warnings that the guides must carry.**

- Apple shows the `.p8` file **once**. A developer who loses it creates a new
  key. Put this warning inside the Apple guide, near the download step.
- Google needs **two** places: the Cloud console creates the service account,
  and the Play Console invites it. The invitation is mandatory, and no API
  performs it. A developer who skips it sees a permission error later, with
  no clue about the cause.

**The states to design.** Not connected. Connected and untested. A test in
progress. Connected and verified, with the team name. A failed test, with the
cause.

---

### 8.3 Tab 2 — Build

**Purpose.** Choose what to submit.

Two paths, side by side. Both end in the same state.

1. **Submit a build.** A drop target per platform. It accepts `.ipa`, `.pkg`,
   and `.aab`.
2. **Update an app that exists.** A picker per store, filled from the
   connected account.

**After the drop, the app reads the package.** This is the moment that earns
the product its name, so give it a real screen. Show a card per package with
what the app found:

| Read from the package | Example |
|---|---|
| Bundle id or package name | `com.fastbillsplit.app` |
| Version name | 3.2.0 |
| Build number | 412 |
| App name | Fast Bill Split |
| Locales inside the build | en, pt-BR |
| Minimum OS | iOS 17.0, or Android API 26 |
| Device class | iPhone, iPad. Empty for an Android build. |
| Encryption answer | No non-exempt encryption |
| Privacy hints | Camera, Internet |

The reader is built and it works. Two rows need a design that admits a gap,
because the build does not always hold the value:

- **The Android app name is often empty.** A build that names its label
  `@string/app_name` holds the name in the resource table, not in the
  manifest. The card must not show an empty row as a failure. The developer
  types one field.
- **An Android build declares no device class.** Show the row for an Apple
  build and hide it for an Android one.

The card shows **no icon**. The app reads none from a build, because no
manifest field holds one.

Below the card, one line: **We filled 8 fields on the Details tab.** With a
button that goes there.

**The immediate warnings.** The tab checks three things on the drop and shows
them at once, not later:

- The bundle id does not match the selected app.
- The build number is not greater than the highest build in the store.
- The version name differs between the iOS package and the Android package.

**The states to design.** Empty, with the two paths. A file over the drop
target. A read in progress. A read that succeeded, with the card. A file that
the app cannot read. A mismatch warning.

---

### 8.4 Tab 3 — Details

**Purpose.** The listing text, per language.

A form, one language at a time. The toolbar locale picker changes the
language. The picker holds an **Add a language** row and shows a badge on a
language that holds an error.

**The fields.**

| Field | Limit | Store |
|---|---|---|
| Name | 30 | Both |
| Subtitle | 30 for Apple, 80 for Google | Both, with an override |
| Description | 4000 | Both |
| What is new | 4000 for Apple, 500 for Google | Both, with an override |
| Keywords | 100 | Apple only |
| Promotional text | 170 | Apple only |
| Marketing URL | — | Apple only |
| Support URL | — | Both |
| Short description | 80 | Google only |
| YouTube URL | — | Google only |

**Three rules that shape this screen.**

1. **Every field shows a character counter against the limit.** The counter
   turns red over the limit. This is the most used control on the tab, so
   design it well.
2. **A field that the two stores limit differently shows a `Different for
   Google` button.** It adds a second field for that store. The app never
   shortens text by itself, and the design must never imply that it does.
3. **A field that the package filled shows a small `from the build` label.**
   The user overwrites it freely, and the label disappears on the first
   keystroke.

**The per-store preview panel** sits on the right in a wide window. It shows
the exact text that each store will receive. This panel is where the extra
window width goes.

Mark the Apple-only fields and the Google-only fields with a small store
glyph. A developer who selected one store never sees the fields of the other.

---

### 8.5 Tab 4 — Media

**Purpose.** The screenshots and the videos, per language and per device.

A grid, grouped by device class: phone, tablet 7 inch, tablet 10 inch,
desktop, watch, TV, vision. Each group shows a count against the limit, for
example `7 of 10`.

**The app reads the dimensions on the drop, before any upload.** Three
results, and each one needs a design:

1. **The file matches a bucket.** The tile shows the image, the bucket name
   such as `iPhone 6.7 inch`, and the store glyphs that will receive it.
2. **The file matches no bucket.** The tile turns red. The message names the
   dimensions of the file and the nearest accepted size. **The app offers no
   automatic resize.** A stretched screenshot fails a review, so the design
   must not offer a fix that does not exist.
3. **The file type is wrong.** The tile turns red and names the accepted
   types.

**The video row** sits below the screenshots. It carries a rule that
surprises developers, so state it in one line on the screen:

> Apple takes a video file. Google takes a YouTube link and no file.

The Apple side is a drop target. The Google side is a URL field. The two must
not look alike, because they are not alike.

**The states to design.** An empty grid. A drag over the grid. A tile that
uploads. A good tile. A rejected tile. A group at the limit, which refuses a
further drop.

---

### 8.6 Tab 5 — Money

**Purpose.** The price, the availability, and the purchases.

**The tab opens on the provider choice**, because that choice changes the
rest of the tab.

Three options: **None**, **RevenueCat**, **Adapty**. Each one holds one line
that says what it does. RevenueCat and Adapty are equal choices, and the
design must not prefer one.

A choice of RevenueCat or of Adapty opens a credential panel below the row.

| Provider | The panel holds |
|---|---|
| RevenueCat | An API key field, a project picker, and the required scope list |
| Adapty | No field. It shows the state of the `adapty` command line tool. |

**The Adapty panel has three states**, and all three need a design:

1. **The tool is missing.** With the install command, and a copy button.
2. **Not logged in.** With the `adapty auth login` command, and a copy
   button. The app never runs this command by itself, because a login opens a
   browser and it belongs to the developer.
3. **Logged in as `<user>`.**

Each panel holds an **I have no account yet** link that opens the sign-up
page.

**The rest of the tab.**

- **The price.** One amount, one currency, one base country. Next to the
  request, the app shows the price that Apple actually resolved, because
  Apple uses fixed price points. A difference over 5 percent shows a warning
  with both amounts. **Money is never applied on a guess**, and this row is
  where that promise becomes visible.
- **Availability.** The Apple country list is editable. The Google country
  list is read-only and links to the console. This asymmetry is real and the
  design must show it, not hide it.
- **In-app purchases.** One row per product: the kind, the price, and the
  localized names.
- **Subscriptions.** One group per row, and one plan per line inside it. Each
  plan holds a duration, a base plan id, and a price.
- **Entitlements and offerings.** Two small lists. **The app hides both when
  the provider is None**, because nothing reads them.

---

### 8.7 Tab 6 — Review info

**Purpose.** Everything the reviewer needs, and nothing the customer sees.

**This is the tab a developer forgets.** It causes rejections, and the
rejection arrives days later. So the screen shows the open rows first, at the
top, not in file order.

**The rows.**

| Row | Apple | Google |
|---|---|---|
| The review contact | The API writes it | No equivalent |
| The demo account | The API writes it | Console only |
| The review notes | The API writes it | Console only |
| The age rating questionnaire | The API writes it, as a form | Console only, the IARC form |
| The app categories | The API writes it | Console only |
| The privacy policy URL | The API writes it, per language | Console only |
| The privacy answers | Console only, the nutrition labels | The API writes the data safety form |
| Export compliance | The API writes it, from the build | Inside the Google data safety form |

**The demo account needs a specific treatment.** The password goes to the
**macOS Keychain**, never to `store.yaml`, because that file lives in a
repository. Show one line that states it. A developer who sees a password
field next to a YAML toggle will assume the wrong thing.

**The Console-only rows** use the same four states and the same link style as
tab 9. Section 8.10 defines them. Design the row component once and use it in
both places.

---

### 8.8 Tab 7 — Plan

**Purpose.** Show every change before any write. This tab is the safety model
of the product.

A diff, in columns. **Apple on the left. Google in the middle. The provider
on the right**, and only when a provider is chosen.

| Colour | Meaning |
|---|---|
| Green | An addition |
| Yellow | A change |
| Red | A deletion |

**The header** shows three numbers: the write count, the upload count, and
the total upload size. These three numbers tell the user the size of what is
about to happen.

**The validation list** sits at the top, above the diff. Each row names the
problem, the store, and the tab that fixes it. One click goes to that tab and
to that field.

- An **error** blocks the Apply button. Design the blocked state.
- A **warning** needs one acknowledgement, in a checkbox on the row.

**The Apply button** is the largest control on the tab. It is prominent, and
it is **not red**, because it writes a draft and a draft is reversible. Red
belongs to tab 9 alone.

**The Dry run toggle** sits in the toolbar. It is on for a new app. When it
is on, the Apply button reads **Dry run**, and the screen states that nothing
will be written.

**The states to design.** No change, which is a real and common state and
deserves a good empty screen. Changes with no error. Changes with warnings.
Changes blocked by an error. A dry run.

---

### 8.9 Tab 8 — Submit

**Purpose.** Run the writes. Show what happens.

A live step list. Each step holds a spinner, a check, or a cross. The
streaming log sits below the list, and it collapses.

The steps are grouped by system: Apple, Google, then the provider. The groups
run in that order.

**The run ends with a draft in every store. It releases nothing.** Say that
on the screen, at the end of the run.

**The failure panels.** Three cases, and each one has a fixed set of buttons:

| Case | The buttons, in this order |
|---|---|
| A store write failed | Retry from the failed step. Undo what this run created. |
| The provider sync failed | Skip the provider and finish the run. Retry the provider. Stop. |
| A release failed | Retry this store. |

**None of these is urgent, and the design must say so.** A half-applied draft
harms nobody. The developer can close the app and finish tomorrow. Put that
sentence in the panel. It is the difference between a calm screen and a
frightening one.

The tab moves to tab 9 by itself when the run ends.

**The states to design.** Ready to run. A run in progress. A run that
finished. A run that failed. A build upload, which takes minutes and needs a
live timer and a cancel button.

---

### 8.10 Tab 9 — Release

**Purpose.** The last check, then the two irreversible buttons.

**The order on the screen is the order of the work.** The checklist first.
The status second. The two buttons last, at the bottom. The checklist sits
between the draft and the review, and that placement is the point of the
whole screen.

**The checklist.** One card per system. Each card holds one row per step.
Each row holds a title, a one-line reason, a state, and a button that opens
the console page in the browser.

| State | Meaning |
|---|---|
| Done | The API confirms the value. |
| Needed | The API reports the value as missing. |
| Unknown | No API can read this step. The row holds a checkbox, and the developer marks it by hand. |
| Not applicable | The step does not apply to this app. |

A header reads `4 of 12 steps are done`. A **Copy as checklist** button copies
every open row as Markdown. A **Re-check** button runs the reads again.

The Apple rows link to a deep page in App Store Connect. Every Google row
links to the main Play Console page, and the row text names the exact page to
open. This is deliberate, and the row text carries the weight.

**The status.** One row per store, at all times. A store that a run prepared
and nobody released reads **Draft, ready to release**.

**The two release buttons.** This is the most important design problem in the
product.

- There are **two** buttons, one per store. There is **no** button that
  releases both. One button would run two irreversible calls back to back,
  and a failure between them leaves one store in review and one not.
- Both are red. Red appears nowhere else except a validation error.
- Each one opens its own confirmation sheet. The sheet names one store, the
  version, the build, and the release type. It also names the recovery and
  the limit of that recovery: Apple can cancel a submission only before the
  review starts, and Google can halt only a staged rollout.
- A button is disabled when a mandatory console step for that store is open
  and an API can detect it. The disabled state names the open step.

**Design the two buttons so that a tired developer at 2 in the morning cannot
press the wrong one.** Distance, labels with the store name, and separate
confirmation text all help. A single row of two identical red buttons does
not.

---

### 8.11 Settings

**A panel over the window, not a second window.** The app opens exactly one
window, and Settings slides over it. Three controls open the panel, and all
three do the same thing: the last row of the sidebar, the button beside the
top bar, and the standard macOS shortcut.

The panel closes with **Done** and with the Escape key. Design it at 520
points wide, with its own title and a footer that holds the Done button.

Four items. No more.

1. **Navigation.** Sidebar or Top bar.
2. **The poll interval.** The default is 5 minutes.
3. **The dry run.** The default state for a new app.
4. **The manifest path.** The location of `store.yaml`.

**Settings holds no credential.** The credentials live on tab 1 and on tab 5,
next to the choice that needs them. A developer who connects a store never
hunts for a settings panel.

---

## 9. The state vocabulary

The app uses one set of words everywhere. Use these and no synonyms.

| Word | Meaning |
|---|---|
| Not connected | No credential for this store. |
| Connected | The credential works. |
| Draft, ready to release | A run prepared this store. Nobody released it. |
| Waiting for review | The store received the submission. |
| In review | A human at the store looks at it. |
| Ready for distribution | Approved. |
| Rejected | The store refused it. The reason comes from the API. |
| Done | The API confirms the value. |
| Needed | The API reports the value as missing. |
| Unknown | No API can read this. |
| Not applicable | This step does not apply to this app. |

---

## 10. Colour

| Role | Use |
|---|---|
| Red | The two release buttons. A validation error. Nothing else, ever. |
| Yellow | A warning. A change in a diff. A pending state. |
| Green | A success. An addition in a diff. A store that matches the file. |
| The accent | The Apply button, the primary action of a tab, the selection. |
| Grey | A disabled control. A not-applicable row. |

**The trap to avoid.** A submission tool tempts a designer toward red, because
the topic feels dangerous. Resist it. If red appears on tabs 1 to 8, it loses
its meaning by the time the user reaches tab 9, and tab 9 is the one screen
where the colour must work.

**The store identity.** Apple and Google both hold strict brand rules. Use a
neutral glyph and the store name in text. Do not redraw either logo. Do not
tint a whole panel in a store brand colour.

Design light and dark together. A developer works at night, and the dark
appearance is not a secondary case.

---

## 11. Typography and density

The app holds three kinds of content, and each one needs its own treatment.

1. **The forms**, on tabs 1 to 6. Comfortable density. The user reads and
   types real sentences here.
2. **The data**, on tabs 7, 8, and 9. Compact density. A monospaced face for
   the ids, the version numbers, the file names, the YAML, and the log.
3. **The one promise**, in the onboarding and at the end of a run. Larger
   than everything else.

Use the system face. A submission tool needs credibility, not personality.

---

## 12. Motion

Motion carries information here, and it carries nothing else.

- A step that runs shows a spinner. A step that finished shows a check that
  appears at once, with no bounce.
- A build upload takes minutes. It needs a live timer, a real progress bar,
  and a cancel button. This is the longest wait in the product.
- A tab change is instant.
- A confirmation sheet uses the standard system sheet. Do not build a custom
  modal.

No decorative motion anywhere. A progress animation that continues when
nothing progresses is a lie about the state of a real store.

---

## 13. Accessibility

- Every state uses a shape or a word, never a colour alone. A green dot and a
  red dot must differ by more than the hue.
- Full keyboard navigation. The two release buttons need an explicit focus
  ring that is impossible to miss.
- Every drop target accepts a file through a button as well. A drag is not
  available to every user.
- The text scales with the system setting. The forms reflow. They do not
  clip.
- Every control carries a VoiceOver label that names the store when the store
  matters.

---

## 14. The copy rules

The interface follows the same rules as the specification.

- Use the active voice.
- Write short sentences.
- One instruction per sentence.
- Use one word for one meaning. The state vocabulary in section 9 is fixed.
- Every error names three things: what failed, which store, and what to do
  next.
- Never show a raw stack trace.

---

## 15. The states you must not forget

Design each of these. They are the states that a first draft skips, and they
are the states a real user meets.

| Screen | The state |
|---|---|
| The app switcher | No app yet. |
| Tab 1 | No store selected. |
| Tab 2 | A package that the app cannot read. |
| Tab 3 | A language with no text at all. |
| Tab 4 | A screenshot with wrong dimensions. |
| Tab 5 | The provider is None, so the lists are hidden. |
| Tab 5 | The Adapty tool is missing. |
| Tab 6 | A row with the state Unknown, which needs a manual check. |
| Tab 7 | Nothing changed. This is a success, not an empty screen. |
| Tab 7 | Apply is blocked by an error. |
| Tab 8 | A build upload that takes 8 minutes. |
| Tab 8 | The provider sync failed and the stores are fine. |
| Tab 9 | A release button disabled by an open console step. |
| Tab 9 | One store released, one store not. This is a normal state, not a failure. |

---

## 16. The deliverables

In this order. Stop and show the work after each group.

**Group 1, the shell.** The sidebar, the app switcher, the tab list, the
toolbar, the badge system, and the light and dark appearance. One tab filled
in, to prove the frame.

**Group 2, the two hard screens.** Tab 7 and tab 9. These two carry the whole
safety model. Design them before the forms, because they set the colour rules
and the button hierarchy that the forms must obey.

**Group 3, the forms.** Tabs 1 to 6, with the states from section 15.

**Group 4, the rest.** Tab 8, the onboarding, the Settings panel, the two
confirmation sheets, and the menu bar popover. The Settings panel and the two
confirmation sheets all lie over the window, so design one panel treatment
and use it three times.

**Group 5, the top bar option.** One screen, to prove that the content
survives the second navigation position.

For each screen deliver: the light appearance, the dark appearance, the
states from section 15, and one line that names the decision you made and
why.

---

## 17. Do not design these

The product does not hold them, and a mockup that shows them creates a
promise that the app breaks.

- Sales charts, analytics, downloads, revenue, or customer reviews.
- A paywall editor or a paywall preview. The app creates a paywall that holds
  the right products. The design of that paywall belongs in RevenueCat or in
  Adapty.
- A screenshot editor, a device frame generator, or an automatic resize.
- A translation feature. The developer owns the words.
- A web dashboard, a login screen, or a user account. The app runs on one
  Mac.
- A button that releases both stores at once. This one is not an omission. It
  is the central design decision of the product.

---

## 18. Open questions for you

Answer these in the work, not in a message.

1. Does the onboarding show five cards at once, or one at a time? A wide Mac
   window argues for all five.
2. How does the tab list show the boundary between the tabs that edit, the
   tab that reads, and the tabs that write? A divider, a group header, or a
   colour shift.
3. Where does the per-store preview go on tab 3 in a narrow window? A panel
   that collapses, or a segmented control that switches the view.
4. How do the two release buttons sit on tab 9 so that a tired developer
   cannot press the wrong one?
5. What does tab 7 look like when nothing changed? That state means the work
   is done, and it deserves better than an empty box.
