# Super Submitter — Specification

A macOS app that prepares an iOS, macOS, and Android app for the App Store
and for Google Play from one manifest and one action. It mirrors the same
purchases into RevenueCat or into Adapty. It leaves every store as a draft,
and the developer releases each store for review with its own button.

- Status: draft v1
- Date: 2026-08-01
- Apple API: App Store Connect API, OpenAPI 4.4.1, `https://api.appstoreconnect.apple.com/`
- Google API: Android Publisher API v3, `https://androidpublisher.googleapis.com`
- Monetization, option A: RevenueCat Developer API v2, OpenAPI 3.0.3, `https://api.revenuecat.com/v2`
- Monetization, option B: Adapty Developer CLI, `adapty`, https://adapty.io/docs/developer-cli-reference

---

## 1. Problem

A developer who ships the same product to two stores does the same work twice.
The developer writes the description twice. The developer uploads the
screenshots twice. The developer creates the in-app purchases twice. The
developer submits twice, and then checks two dashboards for the result.

The two consoles use different words for the same thing. They use different
locale codes, different price models, and different screenshot buckets. The
developer keeps the mapping in their head. The mapping is where the mistakes
occur.

## 2. Goals

1. Keep the store metadata in one file in the repository.
2. Show the exact changes before any write occurs.
3. Apply the changes to both stores in one action.
4. Leave both stores ready to submit, and never submit for review by itself.
5. Mirror the same purchases into RevenueCat or into Adapty, for the
   developers who use one of them.
6. Report one status for every system.
7. Name every step that the APIs cannot do, and never hide it.

## 3. Non-goals

The app does not do these things in v1. Each line gives the reason.

| Not in v1 | Reason |
|---|---|
| Sales reports and finance reports | A different product. Both stores offer them, and neither one helps a submission. |
| Customers, purchases, refunds, and charts, in either provider | Run-time data. This app manages the catalog only. Section 3.1 holds the Google endpoints for a later version. |
| Paywall design and A/B tests, in either provider | A design task, not a submission task. The app creates a paywall that holds the right products. The developer styles it in the dashboard. |
| Adapty segments and audience targeting | The Adapty CLI reads segments and cannot write them. The app manages the default audience only. |
| Notarization for direct macOS distribution | A different service (`notarytool`). This app handles the **Mac App Store** only. |
| Automatic translation of the metadata | The developer owns the words. Add later if users ask. |
| Amazon Appstore, Huawei AppGallery, Microsoft Store | Two stores cover the request. Add a third only on demand. |
| A web dashboard, a server, or user accounts | The app runs on the developer machine. The stores hold the state. |
| A local database | The manifest is the desired state. The APIs are the actual state. Git is the history. |
| App Store Connect certificates, profiles, and devices | Xcode does this. Do not duplicate Xcode. |

The Managing mode covers four areas that an earlier draft of this section
excluded. The app now ships each one, so none of them is a non-goal:
the customer reviews of both stores, TestFlight and the Play internal test
distribution, the Play Developer Reporting vitals, and the Play app recovery.
Section 3.1 records the same correction row by row.

### 3.1 The deferred Google Play surface

Section 3 excludes these areas from v1. This section keeps them, because a
later version implements them. Each row names the exact endpoints, so the
work needs no second discovery pass. Milestone M8 in section 18 owns the
list.

Every row obeys the existing rules. Section 14 gives the rate limit bucket,
the retry policy, and the backoff. Section 7.2 gives the dry run: the app
builds every request and sends none. Section 11.4 gives the run log. A row
that writes an irreversible change obeys section 7.9: one button, one store,
and no chain.

| # | Area | Endpoints | What it adds | Auth | Order |
|---|---|---|---|---|---|
| — | ~~Customer reviews~~ | ~~`reviews.list`, `reviews.get`, `reviews.reply`~~ | **Implemented.** `GoogleActionsClient`, on the Reviews tab of Managing. | — | done |
| — | ~~Internal test distribution~~ | ~~`edits.testers`, `edits.tracks`, `internalappsharingartifacts`~~ | **Implemented.** `GoogleApply.googleTesters` and `GoogleActionsClient.shareInternally`. | — | done |
| 3 | The permission admin | `users.list`, `.create`, `.patch`, `.delete`; `grants.create`, `.patch`, `.delete` | Invite the service account and grant the app permission. This removes one console step from section 13. | The existing `androidpublisher` scope. The caller needs the account owner role. | 2 |
| 4 | Run-time purchase state | `purchases.products.get`, `.acknowledge`, `.consume`; `purchases.subscriptionsv2.get`, `.revoke`; `purchases.voidedpurchases.list` | Verify one purchase token. Read the refund list. | The existing `androidpublisher` scope. | 2 |
| 5 | Orders and refunds | `orders.get`, `orders.batchGet`, `orders.refund` | Read one order. Refund one order. A refund is irreversible, so section 7.9 applies to it. | The existing `androidpublisher` scope. | 3 |
| 6 | External transactions | `externaltransactions.createexternaltransaction`, `.patchexternaltransaction`, `.getexternaltransaction` | Report a transaction of an alternative billing program. | The existing `androidpublisher` scope. | 3 |
| 7 | Custom app publishing | `accounts.customApps.create` | Publish a private app to a managed Google Play organization. | A separate API. Verify the host and the scope first. | 3 |
| 8 | Play Developer Reporting | `vitals.errors.reports`, `vitals.errors.issues`, `anomalies.list`, and the six metric sets beyond the crash rate and the ANR rate | Read the release health beyond the two rates. | The second scope is already in place. See row 8a. | 3 |
| — | ~~The crash rate and the ANR rate~~ | ~~`vitals.crashrate`, `vitals.anrrate`~~ | **Implemented.** `StoreVitalsClient.googleVitals`, on the Analytics tab of Managing. It holds the `playdeveloperreporting` scope. | — | done |
| 9 | Play Games Services | The publishing endpoints for `achievements`, `leaderboards`, and `events` | Manage the game configuration. It applies to a game only. | A separate API. Verify the scope first. | 3 |
| 10 | Play Integrity | `decodeIntegrityToken` | Verify a run-time integrity verdict. This is not a submission step. | A separate host and the scope `playintegrity`. | 3 |
| 11 | System APKs | `systemapks.variants.create`, `.get`, `.list`, `.download` | Build a system image variant. | **Blocked.** Google grants this to an Android system image partner only. A normal service account answers 403. | — |
| — | ~~Generated APKs~~ | ~~`generatedapks.list`, `.download`~~ | **Implemented.** See section 7.11. | — | done |
| — | ~~Device tier configurations~~ | ~~`deviceTierConfigs.create`, `.list`~~ | **Implemented.** See section 7.4 and section 7.11. | — | done |
| — | ~~App recovery~~ | ~~`apprecovery.create`, `.deploy`, `.cancel`, `.addTargeting`, `.list`~~ | **Implemented.** `GoogleActionsClient`, on the App health tab of Managing. The create call writes a draft, and the deploy call is a separate button that confirms first. Section 7.9 holds, because the draft and the deploy never run in one chain. | — | done |

A blocked row ships no code. The app makes no call that a normal account
cannot run, and it shows no button that always fails.

Three rules hold the deferral honest.

1. The app asks for one scope only. It adds a second scope when the developer
   turns on a feature of row 8 or row 10, and never before.
2. A deferred row never blocks a release button. Section 16.6 lists the
   console steps, and none of these rows joins that list.
3. A row that reads run-time data writes nothing to `store.yaml`. The
   manifest holds the desired state, and run-time data is not a desired
   state.

### 3.2 The blocked App Store Connect surface

The App Store Connect API offers these two areas, and this app implements
neither. The reason is architectural in one case and commercial in the other,
so neither waits for a milestone. The same rule as section 3.1 applies: the
app ships no call that a normal account cannot run.

| Area | Endpoints | Why it ships no code |
|---|---|---|
| Webhooks | `webhooks`, `webhookDeliveries`, `webhookPings` | Apple delivers an event to a public HTTPS URL. This app runs on the developer machine and it owns no server, so it can register a subscription that it can never receive. Section 3 excludes a server. The status poll of section 7.10 covers the same need. |
| Alternative distribution | `alternativeDistributionPackages`, `alternativeDistributionKeys`, `marketplaceDomains`, `marketplaceSearchDetails` | Apple grants the entitlement to a registered EU marketplace operator only. A normal account answers 403 on every call. |

`nominations`, the featuring request, and `accessibilityDeclarations` were open
in an earlier draft. The app ships both now. See `AppleMarketing` and
`AppleApply`.

### 3.3 The open App Store Connect surface

A normal account can run every row below, and no code calls it yet. This list
replaces the generated coverage file that the repository used to hold.

| Area | Endpoints | What it adds |
|---|---|---|
| Offer code values | `subscriptionOfferCodeCustomCodes`, `subscriptionOfferCodeOneTimeUseCodes`, and the two `inAppPurchaseOfferCode` twins | The app creates an offer code and no redeemable code. |
| Offer code edits | `PATCH /v1/subscriptionOfferCodes/{id}`, `PATCH /v1/inAppPurchaseOfferCodes/{id}` | Deactivate an offer code. |
| Promotional images | `subscriptionImages`, `inAppPurchaseImages`, both v1 and v2 | A promotional image on a purchase or a subscription. |
| App event video | `appEventVideoClips` | The app writes an event screenshot and no video clip. |
| App Clip media | `appClipHeaderImages`, `appClipAppStoreReviewDetails`, `appClipAdvancedExperienceImages` | The header image and the App Clip review detail. |
| Media order | `PATCH /v1/appScreenshotSets/{id}/relationships/appScreenshots`, and the preview twin | Set the order of the screenshots. |
| Search keywords | The `searchKeywords` relationships of `appStoreVersionLocalizations` and `appCustomProductPageLocalizations` | A newer Apple field. The manifest holds no key for it. |
| Experiment stop | `DELETE /v2/appStoreVersionExperiments/{id}` | Stop a running experiment. |
| Featuring | `appStoreVersionPromotions` | A second featuring resource beside `nominations`. |
| TestFlight notices | `betaTesterInvitations`, `buildBetaNotifications` | Invite a tester again. Notify a group about a new build. |
| Tester removal | `DELETE /v1/betaTesters/{id}` and its four relationship deletes | The app adds a tester and removes none. |
| Game Center | The `gameCenter*` family | A game configuration, not a submission. |
| App tags | `appTags` | A newer Apple field for the listing. |

The v2 drift is a separate item. The app writes `subscriptionLocalizations` and
`subscriptionGroupLocalizations` on v1, and Apple publishes a v2 of both. The
purchase twin already moved to v2. Align the two when Apple names a sunset date.

---

## 4. Concepts

The app uses four concepts. The developer learns these four and no more.

**Manifest.** One YAML file, `store.yaml`, in the repository. It holds the
desired state of the app listing in both stores, and of the monetization
catalog. It is the only file the developer edits.

**Plan.** A read-only comparison. The app reads the actual state from every
API, compares it to the manifest, and shows a diff with one column per
system. The plan writes nothing.

**Apply.** The app performs the writes in the plan. Apply is idempotent. A
second apply on an unchanged manifest performs no writes.

**Release.** The app sends **one** store to review, when the developer clicks
that store's button. This is the only irreversible action, and the app never
performs it by itself.

The model matches `terraform plan` and `terraform apply`. Developers already
know it.

**The run has no irreversible step.** An apply ends with a draft in every
store. Nothing goes to review, nothing reaches a user, and nothing loses a
place in a review queue. Every failure inside a run is fixed by a re-run.

The monetization platform is not a fifth concept. It is one more target
inside the same plan and the same apply. Section 8 gives the details.

---

## 5. The manifest

### 5.1 Design rules

1. Write a value once. Repeat a value only when the stores truly differ.
2. A per-store override always wins over the shared value.
3. A missing value means "do not manage this field". The app never deletes a
   remote value that the manifest does not mention.
4. Rule 3 has one exception. A key set to `null` means "clear this field".

### 5.2 Example

```yaml
version: 1

apps:
  apple:
    appId: "1234567890"          # App Store Connect app id
    platforms: [IOS, MAC_OS]
    bundleId: com.example.app
  google:
    packageName: com.example.app

monetization:
  provider: revenuecat           # revenuecat | adapty | none. Default: none.
  revenuecat:                    # read only when provider is revenuecat
    projectId: proj1ab2c3d4
    appIds:                      # RevenueCat needs one app per store platform
      app_store: app1a2b3c4
      mac_app_store: app5d6e7f8
      play_store: app9g0h1i2
  adapty:                        # read only when provider is adapty
    appId: 7f3c9a10-0b2e-4d51-9a77-1c8de4b52f01   # one app covers both stores

release:
  versionName: "3.2.0"           # Apple versionString, Google release name
  build:
    ios: build/App.ipa
    macos: build/App.pkg
    android: build/app.aab
    androidApk: null             # optional. A bundle and an APK may coexist.
  apple:
    releaseType: AFTER_APPROVAL  # MANUAL | AFTER_APPROVAL | SCHEDULED
    phasedRelease: true
    phasedReleaseState: ACTIVE   # ACTIVE | PAUSED
  google:
    track: production            # the one track that the release button sends
    tracks: [internal, production]  # every track that an apply writes
    status: completed            # used at RELEASE time, not at apply time.
                                 # An apply always writes draft. See 7.4.
    userFraction: null           # required when status is inProgress
    inAppUpdatePriority: 0
    countries: []                # empty means every country
    includeRestOfWorld: false    # only meaningful with countries
    mappingFile: build/mapping.txt        # ProGuard or R8
    nativeDebugSymbols: build/symbols.zip
    expansionFileMain: null      # APK only, never a bundle
    expansionFilePatch: null
    externalApk: null            # Google Play organizations only. See 3.1.

listing:
  defaultLocale: en-US
  locales:
    en-US:
      name: "Fast Bill Split"
      subtitle: "Split any bill in seconds"
      description: |
        Split a restaurant bill with your friends. No account. No ads.
      whatsNew: "Faster scanning and a new dark theme."
      keywords: "bill,split,tip,receipt,restaurant"   # Apple only
      promotionalText: "Now with receipt scanning."    # Apple only
      supportUrl: https://example.com/support
      marketingUrl: https://example.com
      privacyPolicyUrl: https://example.com/privacy
      privacyPolicyText: "How this app handles personal data."
      privacyChoicesUrl: https://example.com/privacy/choices
      google:
        shortDescription: "Split any bill in seconds with your friends"
        video: https://youtube.com/watch?v=xxxx
        whatsNew: "Faster scanning and a new dark theme."   # 500 char limit
    pt-BR:
      name: "Divide a Conta"
      subtitle: "Divida a conta em segundos"
      description: |
        Divida a conta do restaurante com os seus amigos.
      whatsNew: "Leitura mais rapida e um tema escuro novo."
      keywords: "conta,dividir,gorjeta,recibo,restaurante"

media:
  screenshots:
    en-US:
      phone:   [assets/en/phone/*.png]
      tablet10: [assets/en/tablet/*.png]
      desktop: [assets/en/mac/*.png]
    pt-BR:
      phone:   [assets/pt/phone/*.png]
  previews:                          # Apple only. Google takes a YouTube URL.
    en-US:
      phone:   [assets/en/preview/*.mov]
  icon: assets/icon-512.png          # Google only. Apple takes the icon from the build.
  featureGraphic: assets/feature.png # Google only.

pricing:
  base:
    amount: 4.99
    currency: USD
    territory: USA
  autoConvertOtherTerritories: true

purchases:
  - id: com.example.app.pro
    kind: non_consumable
    name: "Pro Unlock"
    price: { amount: 9.99, currency: USD }
    reviewNote: "Tap Settings, then Upgrade."
    entitlements: [pro]          # ignored when provider is none
    locales:
      en-US: { name: "Pro Unlock", description: "Unlock every feature forever." }
      pt-BR: { name: "Versao Pro", description: "Desbloqueie todos os recursos." }

subscriptions:
  - groupId: main
    groupName: "Fast Bill Split Premium"
    plans:
      - id: com.example.app.premium.monthly
        duration: P1M
        basePlanId: monthly      # Google base plan id. Adapty needs it too.
        price: { amount: 2.99, currency: USD }
        entitlements: [premium]
        packageKey: monthly      # RevenueCat package key. Adapty ignores it.
        locales:
          en-US: { name: "Premium Monthly", description: "Unlimited splits." }
      - id: com.example.app.premium.yearly
        duration: P1Y
        basePlanId: annual
        price: { amount: 24.99, currency: USD }
        entitlements: [premium]
        packageKey: annual
        locales:
          en-US: { name: "Premium Yearly", description: "Unlimited splits. Two months free." }

entitlements:                    # RevenueCat entitlement. Adapty access level.
  - key: pro
    name: "Pro"
  - key: premium
    name: "Premium"

offerings:                       # RevenueCat offering. Adapty paywall plus placement.
  - key: default                 # Adapty uses this as the placement developer id.
    name: "Standard offering"
    isCurrent: true
    products: [com.example.app.premium.monthly, com.example.app.premium.yearly]

review:
  contactFirstName: Rafa
  contactLastName: C
  contactEmail: dev@example.com
  contactPhone: "+351000000000"
  demoAccountRequired: false
  notes: "No login is necessary."
  dataSafetyCSV: metadata/google-data-safety.csv  # current Play Console export
  usesNonExemptEncryption: false
  kidsAgeBand: FIVE_AND_UNDER
  attachments: [metadata/review-notes.pdf]
```

### 5.3 Schema

The app ships a JSON Schema for `store.yaml` for editor integrations. It lives
at `Sources/SubmitKit/Resources/store.schema.json`. The in-app YAML editor
validates on every keystroke by decoding the same `Codable` model that the
planner and runner use, so validation cannot drift from runtime decoding.

---

## 6. Cross-store mapping

This section is the heart of the app. Each table maps one manifest field to
both APIs and names the binding limit.

### 6.1 Text metadata

| Manifest | Apple resource + field | Apple limit | Google resource + field | Google limit | Binding limit |
|---|---|---|---|---|---|
| `name` | `appInfoLocalizations.name` | 30 | `edits.listings.title` | 30 | 30 |
| `subtitle` | `appInfoLocalizations.subtitle` | 30 | `edits.listings.shortDescription` | 80 | 30, unless `google.shortDescription` overrides |
| `description` | `appStoreVersionLocalizations.description` | 4000 | `edits.listings.fullDescription` | 4000 | 4000 |
| `whatsNew` | `appStoreVersionLocalizations.whatsNew` | 4000 | `edits.tracks.releases[].releaseNotes[].text` | 500 | 500, unless `google.whatsNew` overrides |
| `keywords` | `appStoreVersionLocalizations.keywords` | 100 | no equivalent | — | Apple only |
| `promotionalText` | `appStoreVersionLocalizations.promotionalText` | 170 | no equivalent | — | Apple only |
| `marketingUrl` | `appStoreVersionLocalizations.marketingUrl` | URL | no equivalent | — | Apple only |
| `supportUrl` | `appStoreVersionLocalizations.supportUrl` | URL | `edits.details.contactWebsite` | URL | Google is app-level, not per-locale |
| `google.video` | no equivalent | — | `edits.listings.video` | YouTube URL | Google only |
| `privacyPolicyUrl` | `appInfoLocalizations.privacyPolicyUrl` | URL | Console only | — | See section 13 |
| `privacyPolicyText` | `appInfoLocalizations.privacyPolicyText` | text | no equivalent | — | Apple only |
| `privacyChoicesUrl` | `appInfoLocalizations.privacyChoicesUrl` | URL | no equivalent | — | Apple only |

The app warns when the shared value exceeds the binding limit. The warning
names the store, the field, the limit, and the overflow count. The developer
then adds an override or shortens the text. The app never truncates text on
its own.

### 6.2 Locales

Apple and Google use different codes for the same language. The app ships a
mapping table at `Resources/locales.json`. These rows show the pattern.

| Manifest | Apple | Google |
|---|---|---|
| `en-US` | `en-US` | `en-US` |
| `en-GB` | `en-GB` | `en-GB` |
| `zh-Hans` | `zh-Hans` | `zh-CN` |
| `zh-Hant` | `zh-Hant` | `zh-TW` |
| `pt-BR` | `pt-BR` | `pt-BR` |
| `pt-PT` | `pt-PT` | `pt-PT` |
| `es-MX` | `es-MX` | `es-419` |
| `ja` | `ja` | `ja-JP` |
| `ko` | `ko` | `ko-KR` |
| `no` | `no` | `no-NO` |

A locale that only one store supports is valid. The app applies it to that
store and reports the skip for the other store.

### 6.3 Screenshots and app previews

Apple sorts the screenshots by display type. Google sorts them by device
class. The pixel dimensions decide the Apple display type, not the folder
name. The app reads the dimensions of every PNG and selects the bucket.

| Manifest class | Apple `ScreenshotDisplayType` | Google `imageType` |
|---|---|---|
| `phone` | `APP_IPHONE_67`, `APP_IPHONE_61`, `APP_IPHONE_65` … | `phoneScreenshots` |
| `tablet7` | no equivalent | `sevenInchScreenshots` |
| `tablet10` | `APP_IPAD_PRO_3GEN_129`, `APP_IPAD_PRO_3GEN_11` … | `tenInchScreenshots` |
| `desktop` | `APP_DESKTOP` | no equivalent |
| `watch` | `APP_WATCH_ULTRA`, `APP_WATCH_SERIES_10` … | `wearScreenshots` |
| `tv` | `APP_APPLE_TV` | `tvScreenshots` |
| `vision` | `APP_APPLE_VISION_PRO` | no equivalent |
| `icon` | not applicable | `icon` |
| `featureGraphic` | not applicable | `featureGraphic` |

The dimension table lives at `Resources/screenshot-sizes.json`. The app
rejects a file with unknown dimensions before it uploads anything.

Google limits each image type to 8 images per locale. Apple limits each
display type to 10 screenshots per locale. The app checks both counts in the
plan.

**App previews.** The two stores do not agree here, and the difference
surprises developers.

| Manifest | Apple | Google |
|---|---|---|
| `media.previews` | `appPreviewSets` plus `appPreviews`, one video file per display type | no equivalent. Google accepts **no video file**. |
| `listing.locales[].google.video` | no equivalent | `edits.listings.video`, one YouTube URL |

Apple takes a `.mov`, an `.m4v`, or an `.mp4` file, 15 to 30 seconds long, at
most 3 per display type per locale. The upload uses the same reservation flow
as section 7.5. Google takes a YouTube URL and nothing else. The app never
uploads a video file to Google.

### 6.4 In-app purchases

| Manifest `kind` | Apple | Google |
|---|---|---|
| `consumable` | `inAppPurchases` v2, `inAppPurchaseType: CONSUMABLE` | `monetization.onetimeproducts` |
| `non_consumable` | `inAppPurchases` v2, `inAppPurchaseType: NON_CONSUMABLE` | `monetization.onetimeproducts` |
| `non_renewing` | `inAppPurchases` v2, `inAppPurchaseType: NON_RENEWING_SUBSCRIPTION` | `monetization.onetimeproducts` — no exact equivalent, the app warns |

The app uses the newer Google `monetization.onetimeproducts` endpoints. It
does not use the legacy `inappproducts` endpoints.

### 6.5 Subscriptions

The two models differ in shape. This is the mapping that saves the most work.

| Manifest | Apple | Google |
|---|---|---|
| `subscriptions[].groupId` | `subscriptionGroups` | `monetization.subscriptions` (one product) |
| `subscriptions[].plans[]` | `subscriptions` (one per duration, inside the group) | `monetization.subscriptions.basePlans` (one per billing period) |
| `plans[].duration` | Apple subscription duration | base plan billing period, ISO 8601, for example `P1M` |
| `plans[].basePlanId` | not used | `basePlans.basePlanId` |
| `plans[].locales` | `subscriptionLocalizations` v2 | base plan `regionalConfigs` and listing text on the parent subscription |
| `plans[].offers[]` kind `free_trial` | `subscriptionIntroductoryOffers`, `offerMode: FREE_TRIAL` | `basePlans.offers` with a `freePriceOverride` phase |
| `plans[].offers[]` kind `intro_price` | `subscriptionIntroductoryOffers`, `offerMode: PAY_UP_FRONT` | `basePlans.offers` with an `absoluteDiscount` phase |
| `plans[].offers[]` kind `offer_code` | `subscriptionOfferCodes` | `basePlans.offers` with a promotion targeting |
| `offers[].eligibility` | `customerEligibilities` | `targeting`: acquisition, upgrade, or win back |
| `plans[].active` | not used | `basePlans:activate` and `:deactivate` |
| `plans[].tax`, `purchases[].tax` | not used, the console owns it | `taxAndComplianceSettings` |
| `groupId` dropped from the manifest | not used | `subscriptions:archive` |
| `subscriptions[].gracePeriodDays` | `subscriptionGracePeriods`, one per app | the base plan grace period |

One Apple subscription group maps to one Google subscription product. Each
Apple subscription inside the group maps to one Google base plan.

An offer is the one place where the two stores disagree on the id rules.
Google accepts a lowercase id with digits and dashes; Apple accepts more. The
validator applies the Google rule when the manifest selects Google, and it
stays quiet for an Apple-only manifest.

`plans[].basePlanId` defaults to a slug of the duration, for example `monthly`
or `annual`. Google needs it. Adapty needs it as `--android-base-plan-id`.
Apple ignores it. The developer writes it once, or not at all.

### 6.6 The monetization platform

The manifest holds one vocabulary. Each provider receives its own shape. The
developer picks a provider with `monetization.provider` and writes nothing
twice.

| Manifest word | RevenueCat word | Adapty word |
|---|---|---|
| entitlement | entitlement | access level |
| product | product | product |
| offering | offering plus packages | paywall plus placement |
| offering key | `Offering.lookup_key` | placement `--developer-id` |

#### 6.6.1 RevenueCat

RevenueCat has a flat catalog. It scopes a product to one app.

| Manifest | RevenueCat resource | Notes |
|---|---|---|
| `apps.apple.bundleId` | `App` with `type: app_store` | The iOS app. |
| `apps.apple.bundleId` on `MAC_OS` | `App` with `type: mac_app_store` | A separate RevenueCat app. Disabled by default in RevenueCat. |
| `apps.google.packageName` | `App` with `type: play_store` | The Android app. |
| `purchases[].id` | `Product`, `store_identifier` | One product per store app. The same id creates two products, one per platform. |
| `purchases[].kind` | `Product.type` | `consumable`, `non_consumable`, `non_renewing_subscription`. |
| `subscriptions[].plans[].id` | `Product` with `type: subscription` | Apple and Google both flatten to one product per store app. |
| `entitlements[].key` | `Entitlement.lookup_key` | |
| `*.entitlements[]` | `entitlements/{id}/actions/attach_products` | Attaches the products to the entitlement. |
| `offerings[].key` | `Offering.lookup_key` | |
| `plans[].packageKey` | `Package.lookup_key` and `position` | The `offerings[].products` order sets the position. |

One manifest product id becomes **two** RevenueCat products when the app
ships on both stores. RevenueCat scopes a product to one app. The app creates
both and attaches both to the same entitlement.

#### 6.6.2 Adapty

Adapty holds one app for both stores, and one product that carries both store
ids. This fits the manifest better than the RevenueCat shape.

| Manifest | Adapty command and flag | Notes |
|---|---|---|
| `apps.apple.bundleId` and `apps.google.packageName` | `adapty apps create --platform ios --platform android --apple-bundle-id --google-bundle-id` | **One** Adapty app covers both stores. `--platform` is immutable. |
| `entitlements[].key` | `adapty access-levels create --sdk-id` | `--sdk-id` is immutable. |
| `entitlements[].name` | `--title` | |
| `purchases[].id` and `plans[].id` | `adapty products create --ios-product-id --android-product-id` | **One** Adapty product carries both store ids. |
| `plans[].basePlanId` | `--android-base-plan-id` | Required for an Android subscription. Not needed for `--period lifetime`. |
| `plans[].duration` | `--period` | See the period table below. |
| `*.entitlements[0]` | `--access-level-id` | Adapty takes **one** access level per product. See the limit below. |
| `offerings[].name` | `adapty paywalls create --title` | |
| `offerings[].products[]` | `--product-id`, repeated, in order | |
| `offerings[].key` | `adapty placements create --developer-id` | The string the app code requests. |
| `offerings[].name` | placement `--title` | |

**The period map.** Adapty takes a fixed set of periods, not an arbitrary
duration.

| Manifest `duration` | Adapty `--period` |
|---|---|
| `P1W` | `weekly` |
| `P1M` | `monthly` |
| `P2M` | `two_months` |
| `P3M` | `trimonthly` |
| `P6M` | `semiannual` |
| `P1Y` | `annual` |
| a `purchases[]` entry, any kind | `lifetime` |

Any other duration has no Adapty period. The app reports an error and names
the plan. It never rounds a duration to a near value.

**Three Adapty limits that shape the design.**

1. A product takes **one** access level. The manifest allows a list. The app
   uses the first entry and warns about the rest. RevenueCat allows the full
   list.
2. The store product ids are **immutable** after the create. A changed id in
   the manifest needs a new Adapty product, not an update. The plan shows a
   create and an orphan, never a silent rename.
3. `adapty paywalls update` and `adapty placements update` **replace every
   field**. The app always reads the object with `--json` first, changes the
   fields it manages, and writes the whole object back. It never sends a
   partial update.

**Mac App Store.** Adapty carries one Apple bundle id per app. An app that
ships on iOS and on the Mac App Store with the **same** bundle id needs one
Adapty app. Two different bundle ids need two Adapty apps, and the manifest
then holds two `adapty.appId` values. The app reports this as a warning at
the import.

### 6.7 Prices

The two price models do not map one to one.

- Apple uses opaque price points per territory. The app reads them from
  `/v3/appPricePoints`, `/v1/inAppPurchasePricePoints`, and
  `/v1/subscriptionPricePoints`.
- Google uses an amount in micros plus a region code. Google offers
  `pricing:convertRegionPrices` to fill the other regions.

The manifest gives one base amount, one currency, and one base territory. The
app then does this:

1. For Apple, it finds the nearest price point in the base territory. It then
   creates an `appPriceSchedule` with automatic prices for the other
   territories.
2. For Google, it sets the base region price and calls
   `pricing:convertRegionPrices` for the other regions.
3. It warns when the nearest Apple price point differs from the requested
   amount by more than 5 percent.

The plan always shows the resolved amounts per store before the apply. Money
is never applied on a guess.

### 6.8 Country availability

This row is asymmetric. Read it carefully.

- Apple: writable. `POST /v2/appAvailabilities` with `territoryAvailabilities`.
- Google: mostly read-only. `edits.countryavailability` offers `GET` only.
  `Release.countryTargeting` accepts a country list, but only for an
  `inProgress` release in the production track.

The app manages the Apple territories from the manifest. It reports the
Google country list as read-only and adds a Console step. See section 13.

Neither monetization provider needs price data. Both read the prices from
the stores.

---

## 7. Workflows

### 7.1 Import (first run)

The developer starts with an app that already exists in both stores.

1. Read the Apple app: `GET /v1/apps`, then `appInfos`,
   `appInfoLocalizations`, the latest `appStoreVersions`, and
   `appStoreVersionLocalizations`.
2. Read the Google app: `edits.insert`, then `edits.listings.list`,
   `edits.details.get`, and `edits.tracks.list`. Then `edits.delete`.
3. Read the monetization catalog, when the developer supplies a provider.
   RevenueCat: `GET /projects`, `GET /projects/{id}/apps`,
   `GET /projects/{id}/products`, `GET /projects/{id}/entitlements`, and
   `GET /projects/{id}/offerings`. Adapty: `adapty apps list`,
   `adapty access-levels list`, `adapty products list`,
   `adapty paywalls list`, and `adapty placements list`, all with `--json`.
4. Merge them into one `store.yaml`. Put an identical value in the shared
   block. Put a different value in the matching store override block.
5. Match the provider products to the store products by the store product
   id. Write the entitlement keys, the package keys, and the base plan ids
   into the matching `purchases` and `subscriptions` entries.
6. Download the screenshots to `assets/`.
7. Write `store.yaml` and report every field that the import could not map.

The import never writes to a store and never writes to a provider. It
deletes the Google edit that it opened.

### 7.2 Plan

1. Read the actual state from every API, as in the import.
2. Compare each managed field to the manifest.
3. Render a diff, with one column per system. The provider gets a third
   column only when `monetization.provider` is not `none`.
4. Run every validation from section 10.
5. Show the count of writes, the count of uploads, and the total upload size.

The plan opens no Google edit. It creates no Apple resource. It creates no
provider object. Every Adapty command in the plan is a `list` or a `get`.

### 7.3 Apply — Apple

The order matters. The app performs the reversible writes first.

1. `GET /v1/apps/{id}/appStoreVersions` filtered on the platform and on the
   state `PREPARE_FOR_SUBMISSION`. Create one with
   `POST /v1/appStoreVersions` when none exists.
2. `PATCH /v1/appStoreVersions/{id}` for `versionString`, `releaseType`, and
   `earliestReleaseDate`.
3. `PATCH /v1/appInfos/{id}` for the categories.
4. `POST` or `PATCH /v1/appInfoLocalizations` for `name`, `subtitle`, and
   `privacyPolicyUrl`.
5. `POST` or `PATCH /v1/appStoreVersionLocalizations` for `description`,
   `keywords`, `promotionalText`, `whatsNew`, `supportUrl`, and
   `marketingUrl`.
6. Upload the screenshots. See section 7.5.
7. Upload the build. See section 7.6.
8. `PATCH /v1/appStoreVersions/{id}/relationships/build` to attach the build.
9. `POST` or `PATCH /v1/appStoreReviewDetails` for the contact and the notes.
10. `PATCH /v1/ageRatingDeclarations/{id}` for the age rating answers.
11. Apply the in-app purchases. See section 7.7.
12. Apply the subscription catalog: `POST` or `PATCH /v1/subscriptionGroups`,
    `/v1/subscriptionGroupLocalizations`, `/v1/subscriptions`,
    `/v1/subscriptionLocalizations`, and `/v1/subscriptionPrices`. The price
    resolves to the nearest point of
    `/v1/subscriptions/{id}/pricePoints`, the same rule as section 6.7.
13. Apply the subscription offers on top of the catalog:
    `POST /v1/subscriptionIntroductoryOffers` for a free trial and for an
    introductory price, and `POST /v1/subscriptionOfferCodes` for a code.
    Step 12 holds the ids that these need, so this step always follows it.
14. `PATCH /v1/subscriptionGracePeriods/{id}` when a group names
    `gracePeriodDays`. Apple keeps one grace period for the whole app, so the
    first group that names one wins and the validator reports a disagreement.
15. Apply the marketing block. See section 7.3.1.
16. `POST /v1/appStoreVersionPhasedReleases` when `phasedRelease` is true.
17. `POST /v2/appAvailabilities` for the territories.

### 7.3.1 The App Store marketing resources

Google offers no equivalent for any of these, so none of them appears on the
Google side and the validator says so once. Each block writes only when the
manifest holds it.

| Manifest | Call | Note |
|---|---|---|
| `marketing.customProductPages` | `appCustomProductPages`, `appCustomProductPageVersions`, `appCustomProductPageLocalizations` | Apple allows 35 pages. The promotional text limit is 170. |
| `marketing.experiments` | `/v2/appStoreVersionExperiments`, `appStoreVersionExperimentTreatments` | The app creates the experiment and **never starts it**. A running experiment changes what a real customer sees, and section 7.9 keeps that on a button. |
| `marketing.events` | `appEvents`, `appEventLocalizations` | The name limit is 30, the short description 50, the long description 120. |
| `marketing.eula` | `endUserLicenseAgreements` | The text limit is 10000. An absent block leaves the Apple standard agreement. |
| `marketing.routingCoverage` | `routingAppCoverages` | A GeoJSON file. It reserves and uploads through the same `uploadOperations` list as a screenshot, section 7.5. |
| `marketing.nomination` | `nominations` | A draft request to the editorial team. The app never submits it. |
| `marketing.accessibility` | `accessibilityDeclarations` | `VOICE_OVER` becomes the attribute `supportsVoiceOver`. The state is `DRAFT`. |
| `marketing.appClip` | `appClipDefaultExperiences`, `appClipDefaultExperienceLocalizations` | The Xcode target creates the clip. This writes what the store shows. |

### 7.4 Apply — Google

Google offers a real transaction. The app uses it.

1. `POST .../edits` to open one edit. Keep the `editId` for the whole run.
2. `PUT .../edits/{editId}/listings/{language}` for every locale.
3. `PATCH .../edits/{editId}/details` for the contact fields.
4. Upload the images. See section 7.5.
5. Upload the bundle. See section 7.6.
6. `POST .../edits/{editId}/apks` when the manifest names `build.androidApk`.
   The manifest may name a bundle and an APK, and then both reach one edit.
7. `POST .../edits/{editId}/apks/externallyHosted` when the manifest names
   `google.externalApk`. Google stores the metadata and never the bytes. A
   Google Play organization owns this call; a normal account answers 403.
8. `POST .../edits/{editId}/apks/{versionCode}/deobfuscationFiles/{type}` for
   `google.mappingFile` as `proguard` and for `google.nativeDebugSymbols` as
   `nativeCode`. Both attach to the version code that step 5 or step 6
   returned, so both follow an upload.
9. `POST .../edits/{editId}/apks/{versionCode}/expansionFiles/{type}` for
   `google.expansionFileMain` as `main` and `google.expansionFilePatch` as
   `patch`. Google attaches an expansion file to an APK and never to a
   bundle, so this reads the APK version code of step 6 alone.
10. `POST .../edits/{editId}/tracks` for every track of `google.tracks` that
    is neither a standard track nor already in the store. Google owns
    `internal`, `alpha`, `beta`, and `production`, and it creates no other.
11. `PATCH .../edits/{editId}/tracks/{track}` **for every track in
    `google.tracks`**, with the release, the version codes, the release
    notes, the user fraction, and the `countryTargeting` of
    `google.countries`. One edit reaches every track, so a build lands in
    `internal` and in `production` in one commit. The release `status` is
    always `draft` in an apply, whatever the manifest says. Section 7.9 uses
    the manifest value, and it releases the one track that `google.track`
    names.
12. `POST .../edits/{editId}:validate` to check the whole edit.
13. `POST .../edits/{editId}:commit?changesNotSentForReview=true`.

Step 13 needs an explanation, because it looks wrong. An **uncommitted Google
edit is invisible**. It exists only inside the API. The developer opens the
Play Console and sees nothing. The edit also expires after about 7 days, and
any other edit that commits first destroys it.

So the app must commit for the work to exist. The commit is **not** a
submission. Two things keep the release out of review:

- `changesNotSentForReview=true` on the commit. This holds the **store
  listing** changes. Google reviews a listing change even without a release,
  so this flag is necessary, not decorative.
- `Release.status: draft`. This holds the **bundle**. It reaches no user.

The two cover different things. The app always sends both.

The result matches the Apple side: everything is uploaded, everything is
visible in the console, and nothing is in review.

The app deletes the edit with `DELETE .../edits/{editId}` when the run fails
before step 13, or when the developer cancels. A Google edit expires after about 7 days of
inactivity. It also becomes invalid when another edit commits first. The app
detects the `editAlreadyCommitted` and `editExpired` errors and asks the
developer to re-plan.

### 7.4.1 The Google catalog, outside the edit

Google keeps the monetization endpoints outside the edit, so these calls send
no `editId` and the commit does not carry them. They run next to the two batch
updates, and each one names one product, so a failure names the product that
failed.

| Manifest | Call | Note |
|---|---|---|
| `purchases[].active` | `oneTimeProducts/{id}/purchaseOptions:batchUpdateStates` | It stops the sale and keeps the product. |
| `purchases[].offers` | `oneTimeProducts/{id}/purchaseOptions/{option}/offers:batchUpdate` | `allowMissing` covers the create and the update in one call. |
| `subscriptions[].plans[].active` | `subscriptions/{id}/basePlans/{plan}:activate` or `:deactivate` | An existing subscriber keeps the plan. |
| `subscriptions[].plans[].offers` | `subscriptions/{id}/basePlans/{plan}/offers:batchUpdate` | The free trial and the introductory price. |
| `subscriptions[].plans[].migrateExistingSubscribers` | `subscriptions/{id}/basePlans:batchMigratePrices` | **It charges a real customer.** The manifest opts in per plan and the validator warns every time. |
| a subscription that left the manifest | `subscriptions/{id}:archive` | Section 8, rule 6. The app archives; it never deletes. |
| `purchases[].tax`, `plans[].tax` | inside the two batch updates | An absent block leaves the Play Console value alone. |
| `release.google.deviceTierConfig` | `deviceTierConfigs` | Google assigns the id, so every apply creates a new configuration. The validator says so. |

### 7.5 Screenshot upload

Apple uses a three-step reservation flow.

1. `POST /v1/appScreenshotSets` with the `screenshotDisplayType` and the
   localization id. Reuse the set when it exists.
2. `POST /v1/appScreenshots` with `fileName` and `fileSize`. The response
   holds `uploadOperations`. Each operation gives a `method`, a `url`, a
   `length`, an `offset`, and the `requestHeaders`.
3. Execute every operation. Then `PATCH /v1/appScreenshots/{id}` with
   `uploaded: true` and the MD5 `sourceFileChecksum`.
4. Poll `assetDeliveryState.state` until it reads `COMPLETE`. A `FAILED`
   state carries the errors in `assetDeliveryState.errors`.

Google uses one multipart upload.

1. `POST /upload/androidpublisher/v3/applications/{packageName}/edits/{editId}/listings/{language}/{imageType}`
   with the image bytes.
2. The response holds the `sha256`. The app compares it to the local hash.

The app skips an upload when the remote checksum already matches the local
file. This makes the apply idempotent for the media.

### 7.6 Build upload

Apple now uploads the binary through the API. Transporter is not necessary.

1. `POST /v1/buildUploads` with `cfBundleShortVersionString`,
   `cfBundleVersion`, and the platform.
2. `POST /v1/buildUploadFiles` per file with `fileName`, `fileSize`,
   `assetType`, and `uti`. The `uti` reads `com.apple.ipa` for iOS and
   `com.apple.pkg` for the Mac App Store.
3. Execute the `uploadOperations` from the response. They arrive in chunks
   with an `offset` and a `length`.
4. `PATCH /v1/buildUploadFiles/{id}` with `uploaded: true` and the checksums.
5. Poll `GET /v1/buildUploads/{id}` until `state.state` leaves the in-progress
   values. Surface `state.errors` and `state.warnings` to the developer.
6. Poll `GET /v1/builds` for the processed build. Apple takes minutes to
   process a build. The app shows a live timer and a cancel button.

Google uploads the bundle in one call.

1. `POST /upload/androidpublisher/v3/applications/{packageName}/edits/{editId}/bundles`
   with the `.aab` bytes.
2. The response holds the `versionCode`. The app puts it in the track release.

### 7.7 In-app purchase apply

Apple:

1. `GET /v2/inAppPurchases` to find an existing product by `productId`.
2. `POST /v2/inAppPurchases` or `PATCH /v2/inAppPurchases/{id}`.
3. `POST` or `PATCH /v2/inAppPurchaseLocalizations` per locale.
4. `POST /v1/inAppPurchasePriceSchedules` with the resolved price point.
5. `POST /v1/inAppPurchaseAvailabilities` for the territories.
6. Upload the review screenshot with
   `POST /v1/inAppPurchaseAppStoreReviewScreenshots`, which uses the same
   reservation flow as section 7.5.

Google:

1. `POST .../oneTimeProducts:batchUpdate` with the full product list.
2. `POST .../subscriptions:batchUpdate` for the subscriptions.
3. `POST .../basePlans:batchUpdateStates` to activate the base plans.

Google offers batch endpoints. The app uses them. One call replaces twenty.

### 7.8 The monetization sync

This step runs last in the apply, after both stores hold the products. It
needs the store products to exist, so it cannot run earlier.

The step runs only when `monetization.provider` is `revenuecat` or `adapty`.

#### 7.8.1 RevenueCat

1. `GET /projects/{project_id}/apps` and check that every id in
   `monetization.revenuecat.appIds` exists. Check that the App Store app
   `bundle_id` matches `apps.apple.bundleId`. Check that the Play Store app
   `package_name` matches `apps.google.packageName`. A mismatch is an error,
   because a wrong app id writes the products to another app.
2. `GET /projects/{project_id}/products?app_id={id}` per app. Follow the
   `starting_after` cursor until the last page.
3. `POST /projects/{project_id}/products` for every missing product. The body
   holds `store_identifier`, `app_id`, `type`, and `display_name`. The app
   creates one product per store app, so a two-store product id creates two
   RevenueCat products.
4. `POST /projects/{project_id}/products/{product_id}` to update the
   `display_name` of an existing product. RevenueCat v2 uses `POST` for the
   update, not `PATCH`.
5. `GET` and `POST /projects/{project_id}/entitlements` to create the missing
   entitlements by `lookup_key`.
6. `POST /projects/{project_id}/entitlements/{id}/actions/attach_products`
   with the product ids. Call
   `.../actions/detach_products` for the products that the manifest removed.
7. `GET` and `POST /projects/{project_id}/offerings` for the offerings.
8. `GET` and `POST /projects/{project_id}/offerings/{id}/packages` for the
   packages, with the `position` from the manifest list order.
9. `POST /projects/{project_id}/packages/{id}/actions/attach_products` with
   the product ids.

**The app never calls `POST /products/{id}/create_in_store`.** That endpoint
pushes a product to the App Store only. It does not cover Google Play, and it
would make RevenueCat a second writer to Apple. Super Submitter owns the
store writes. RevenueCat receives a mirror of the result.

**The app never deletes.** It calls `actions/archive` on a product, an
entitlement, or an offering that the manifest removed. A `DELETE` on a live
catalog breaks the running app. The archive is reversible with
`actions/unarchive`.

#### 7.8.2 Adapty

Adapty ships a CLI, not a REST API. The app runs the `adapty` binary as a
subprocess and passes `--json` on every command. Section 9.3 covers the
prerequisites.

1. `adapty auth status`, then `adapty auth whoami`. A logged-out CLI is an
   error with the exact login command in the message.
2. `adapty apps get <app-id> --json` and check that the `apple-bundle-id`
   matches `apps.apple.bundleId` and that the `google-bundle-id` matches
   `apps.google.packageName`. A mismatch is an error.
3. `adapty access-levels list --app <app-id> --json`, with `--page` until the
   last page. `adapty access-levels create --sdk-id --title` for the missing
   ones. `adapty access-levels update` for a changed title.
4. `adapty products list --app <app-id> --json`. Match by
   `--ios-product-id` and `--android-product-id`.
5. `adapty products create` for the missing ones, with `--title`,
   `--access-level-id`, `--period`, `--ios-product-id`,
   `--android-product-id`, and `--android-base-plan-id`.
6. `adapty products update` for a changed `--title` or `--access-level-id`.
   The store ids are immutable, so the app never sends them here.
7. `adapty paywalls list --app <app-id> --json`, then
   `adapty paywalls create --title --product-id ...` for the missing ones.
8. `adapty placements list --app <app-id> --json`. For an existing placement,
   read it with `adapty placements get --json` first, keep every audience
   that the manifest does not manage, replace the `paywall_id` of the default
   audience, and write the whole array back with
   `adapty placements update --audiences`.
9. `adapty placements create --title --developer-id --audiences` for a
   missing placement. The default audience holds `segment_ids: []` and the
   highest `priority` value.

**Three rules for the Adapty step.**

- The app always passes `--audiences`. It never passes the deprecated
  `--paywall-id`, because that flag drops every segment-specific audience.
- The app never changes the products of a paywall that a placement already
  uses. Adapty forbids it. The plan shows a new paywall and a placement
  update instead.
- The app writes no segment. The CLI cannot write one.

`// ponytail: mirror, not a second writer. One source of truth is the store.`
`// ponytail: shell out to the adapty CLI. No second HTTP client, no second
// auth flow. Write a REST client only if Adapty ships a public REST API.`

### 7.9 Release for review

The app never runs this step as part of a run. The run ends at section 7.8,
with a draft in every store. This step waits for the developer.

Tab 9 shows **two separate buttons**, one per store. Each button releases
**one** store. The app offers no button that releases both, and it never
chains the two calls. No other tab holds a release button.

**Apple.**

1. `POST /v1/reviewSubmissions` with the app id and the platform.
2. `POST /v1/reviewSubmissionItems` with the `reviewSubmission` id and the
   `appStoreVersion` id.
3. `POST /v1/reviewSubmissionItems` again for each `inAppPurchaseVersion`, each
   `appEvent` in `READY_FOR_REVIEW`, each `appCustomProductPageVersion` in
   `PREPARE_FOR_SUBMISSION`, and each `appStoreVersionExperimentV2` in
   `PREPARE_FOR_SUBMISSION`.
4. `POST /v1/subscriptionGroupSubmissions` per group, and
   `POST /v1/subscriptionSubmissions` per subscription in `READY_TO_SUBMIT`.
   Apple keeps the subscriptions off `reviewSubmissionItems`, so each one takes
   its own submission resource and reaches the same queue.
5. `PATCH /v1/reviewSubmissions/{id}` with `submitted: true`.

Step 5 is the point of no return for Apple. Steps 1 to 4 are reversible. The
app adds the purchases and the marketing items to the **same** review
submission as the app version, so one Apple review covers them together.

An item that Apple refuses never abandons the version submission. Step 5 still
holds the whole decision, and a refused item leaves the version untouched.

**The take-back.** Each store keeps one, and each one has its own button under
the release button of that store.

- **Apple.** `GET /v1/reviewSubmissions?filter[app]=…` finds the submission in
  `READY_FOR_REVIEW` or `WAITING_FOR_REVIEW`, then
  `PATCH /v1/reviewSubmissions/{id}` with `canceled: true`. Apple refuses this
  once a reviewer opens the submission, so the button appears only while the
  status poll reports `inQueue`.
- **Google.** `PATCH .../edits/{editId}/tracks/{track}` with `status: halted`
  and every version code the track holds, then a commit. A halt stops new
  installs and it removes nothing that already landed, so the button appears
  only for a staged rollout.

Neither call restores what already reached a customer, so both confirm first.

**Google.**

1. `POST .../edits` to open a small edit.
2. `PATCH .../edits/{editId}/tracks/{track}` with the release `status` from
   the manifest, the `userFraction` when the status is `inProgress`, and
   **every** `versionCode` that the track must keep. Google treats
   `versionCodes` as the complete list, not as an addition. A missing code
   drops that build from the track. The app reads the track first and carries
   the full list back.
3. `POST .../edits/{editId}:commit`, this time **without**
   `changesNotSentForReview`.

Step 3 is the point of no return for Google.

**Why two buttons and not one.**

A single button would run two irreversible calls back to back. A failure
between them leaves one store in review and one store not, and the fix costs
a place in an Apple review queue. Two buttons put the developer between the
two calls. The developer sees the first result before the app can start the
second, so the split state cannot happen by accident.

The cost is one extra click. The benefit is that no run in this app can ever
produce a half-released version.

`// ponytail: two buttons deleted the whole two-phase commit, the recovery
// panel, and the cancel logic. The cheapest fix was to not automate the step.`

**Each button guards itself.** The confirmation sheet names one store, the
version, the build, and the release type. It also names the recovery, and the
limit of that recovery:

- Apple: `PATCH /v1/reviewSubmissions/{id}` with `canceled: true`, which works
  only before the review starts.
- Google: a new edit that sets the track release to `halted`, which works only
  for a staged rollout.

### 7.10 Status

The app shows one row per store, at all times. A store that a run prepared
but nobody released shows **Draft, ready to release**. The app polls a store
only after a release for review.

- Apple: `GET /v1/appStoreVersions/{id}` and read `appVersionState`. The
  states run `WAITING_FOR_REVIEW`, `IN_REVIEW`, `PENDING_DEVELOPER_RELEASE`,
  `READY_FOR_DISTRIBUTION`, `REJECTED`, and `METADATA_REJECTED`.
- Google: `GET .../edits` is not usable after a commit. The app reads
  `GET /androidpublisher/v3/{parent=applications/*/tracks/*}/releases` and
  reports the release status and the user fraction.

The poll interval is 5 minutes. The app posts a macOS notification on every
state change. The app does **not** use the App Store Connect webhooks, and
section 3.2 gives the reason: Apple delivers an event to a public HTTPS URL,
and this app owns no server. Polling needs none.

### 7.11 The reads that change nothing

These answer a question about what a store built. None of them belongs in the
plan, because the plan compares a desired state to an actual state and none of
these is a desired state. A diff row for one of them could never close.

| Read | Call | Answers |
|---|---|---|
| The generated APKs | `generatedapks.list`, `generatedapks.download` | What Google actually built from the uploaded bundle. |
| The device tier configurations | `deviceTierConfigs.list` | Which configurations Google already holds. |
| The build bundles | `/v1/builds/{id}/buildBundles`, `/v1/buildBundles/{id}/buildBundleFileSizes` | What is inside a processed build: the app, every extension, the download size, and the encryption flag. |
| The build icons | `/v1/builds/{id}/icons` | Which icons Apple extracted from the build. |
| The territories | `/v1/territories` | Every territory id, so a code in the availability block or the licence agreement can be checked. |

---

## 8. The monetization platform, in short

A developer who uses RevenueCat or Adapty keeps a third catalog in sync by
hand today. That is the third copy of the same product ids. This app removes
it.

The rules are the same for both providers, and they never change:

1. The provider is optional. `provider: none`, or no `monetization` block,
   means no provider calls at all.
2. The app supports **one** provider per manifest. RevenueCat and Adapty
   solve the same problem. A developer who runs both has a different
   question, and this app does not answer it.
3. The provider is a mirror. The stores are the source of truth.
4. The provider runs inside the apply, never inside a release for review.
5. A provider failure never blocks a store draft. The failure panel offers
   **Skip the provider and finish the run** as the first button.
6. The app archives, or it deactivates. The app does not delete.

`// ponytail: one provider per manifest. Add a multi-provider mode only when a
// real user runs both at once.`

### 8.1 Which provider fits the manifest better

Adapty fits better, and the reason is structural. One Adapty app covers both
stores, and one Adapty product carries the iOS id and the Android id
together. That is the same shape as the manifest.

RevenueCat scopes an app and a product to one store. One manifest product id
becomes two RevenueCat products. The app handles this, but it doubles the
object count and it doubles the drift surface.

The spec supports both. It does not recommend one. The developer already has
an account somewhere, and that decides it.

## 9. Authentication

### 9.1 Apple

The developer creates an App Store Connect API key in the Users and Access
page. The key gives three items: the `.p8` private key file, the key id, and
the issuer id.

The app builds a JWT for every request window.

- Algorithm: `ES256`.
- Header: `alg`, `kid` (the key id), and `typ: JWT`.
- Payload: `iss` (the issuer id), `iat`, `exp`, and `aud: appstoreconnect-v1`.
- A team-scoped key also needs the `scope` claim.
- Apple rejects a token with a lifetime over 20 minutes. The app uses 15
  minutes and refreshes at 12 minutes.

The app signs with CryptoKit `P256.Signing`. It adds no crypto dependency.

### 9.2 Google

The developer creates a service account in the Google Cloud console, grants
it the Android Publisher role, and invites the service account email in the
Play Console. The console step is mandatory. The API cannot do it.

The app performs the OAuth 2.0 JWT bearer flow.

- Scope: `https://www.googleapis.com/auth/androidpublisher`.
- Assertion: `RS256`, signed with the private key from the service account
  JSON.
- Exchange the assertion at `https://oauth2.googleapis.com/token`.
- The access token lasts 1 hour. The app refreshes at 50 minutes.

### 9.3 RevenueCat

RevenueCat uses the simplest scheme of the four. The developer creates a
secret v2 API key in the RevenueCat dashboard, under Project settings, then
API keys.

- Header: `Authorization: Bearer <api_key>`.
- The key needs these scopes: `project_configuration:apps:read`,
  `project_configuration:products:read_write`,
  `project_configuration:entitlements:read_write`,
  `project_configuration:offerings:read_write`, and
  `project_configuration:packages:read_write`.
- The key does not expire. The app refreshes nothing.
- A key belongs to one RevenueCat project. The app stores one key per
  project.

The app asks for the read-write scopes only. It never asks for the customer
scopes, because it never reads a customer.

### 9.4 Adapty

Adapty holds no secret that this app can store. The `adapty` CLI owns its own
credentials. This removes a whole class of work, and it adds one
prerequisite.

- The developer installs the CLI and runs `adapty auth login` once. The
  command opens a browser and uses a device flow.
- The app runs `adapty auth status` before every run. This command makes no
  server call, so it is cheap.
- The app runs `adapty auth whoami` once per run, to confirm the token with
  the server.
- The app never reads, writes, copies, or logs the Adapty credentials. It
  never runs `adapty auth logout` or `adapty auth revoke`, because those
  affect the whole machine and not this app.

The Settings screen shows one of three states for Adapty: **The CLI is
missing**, with the install command; **Not logged in**, with
`adapty auth login`; or **Logged in as <user>**. The app never runs the login
command by itself. A login opens a browser and it belongs to the developer.

### 9.5 Secret storage

The Apple, Google, and RevenueCat secrets live in the macOS Keychain, as a
generic password item with the access group of the app. The Adapty CLI holds
its own credentials, and the app never touches them. The app never writes a
secret to `store.yaml`. The app never writes a secret to a log. The manifest
holds ids only.

### 9.4a What the app never sends

The app reads the purchases that Google voided, and it issues no refund. A
refund moves real money to a customer, and that decision belongs to a person in
the Play Console. The same rule keeps the app away from orders, from external
transactions, and from every call that changes who may access a developer
account.

The App Store Connect key and the Play service account are credentials of the
developer account, not of one app. One of each covers every app in the team, so
the app asks for the `.p8` file and the service-account JSON once and every
linked app reads that copy. The RevenueCat key and the reviewer demo account
describe one app, and each app holds its own.

The **demo account** for the Apple reviewer follows the same rule. The user
name and the password live in the Keychain. The manifest holds
`review.demoAccountRequired` only. A manifest sits in a repository, and a
review password is a real credential of a real service.

The Keychain items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. The
secrets do not sync to iCloud.

---

## 10. Validation

Every rule runs during the plan, before any write. A rule has a severity of
error or warning. An error blocks the apply. A warning needs one
acknowledgement.

### 10.1 Text

- A field exceeds the binding limit from section 6.1. Error.
- The Apple `keywords` string exceeds 100 characters. Error.
- The Google release note exceeds 500 characters and no override exists.
  Error.
- The default locale has no entry in the manifest. Error.
- A locale exists in the manifest but the store does not support it. Warning.
- The `description` holds a URL that returns 404. Warning.

### 10.2 Media

- A screenshot has dimensions that match no known bucket. Error.
- A screenshot has a file type that the store does not accept. Error.
- A locale has screenshots for one store and none for the other. Warning.
- A phone screenshot count exceeds 10 for Apple or 8 for Google. Error.
- The Google `icon` is not 512 by 512 PNG. Error.
- The Google `featureGraphic` is not 1024 by 500. Error.
- An app preview has a duration under 15 seconds or over 30 seconds. Error.
- An app preview count exceeds 3 per display type per locale. Error.
- The manifest holds an app preview and the Google locale holds no `video`
  URL. Warning. Google shows no video without the URL.

### 10.3 Build

- The manifest names a build file that does not exist. Error.
- The `.ipa` `CFBundleVersion` is not greater than the highest build already
  in App Store Connect. Error.
- The `.aab` `versionCode` is not greater than the highest version code in
  the target track. Error.
- The `.ipa` bundle id does not match `apps.apple.bundleId`. Error.
- The `.aab` package name does not match `apps.google.packageName`. Error.
- The `versionName` in the manifest does not match the build. Warning.

### 10.4 Money

- The resolved Apple price point differs from the request by more than 5
  percent. Warning, with both amounts shown.
- A subscription plan has a duration that Apple does not offer. Error.
- A product id exists in one store and not in the other. Warning.

### 10.5 The monetization platform

These rules run only when `monetization.provider` is not `none`.

Both providers:

- A product names an entitlement key that the `entitlements` block does not
  declare. Error.
- An offering names a product id that no purchase and no plan declares.
  Error.
- The manifest holds no offering. Warning. The app code then has nothing to
  request.
- A provider object exists that the manifest does not name. Warning, with the
  archive or the deactivation shown in the plan.
- The manifest sets `provider` to a value that is not `revenuecat`, `adapty`,
  or `none`. Error.

RevenueCat only:

- A RevenueCat app id in the manifest does not exist in the project. Error.
- The RevenueCat App Store app `bundle_id` does not match
  `apps.apple.bundleId`. Error. A wrong app id writes to another app.
- The RevenueCat Play Store app `package_name` does not match
  `apps.google.packageName`. Error.
- The manifest holds no offering with `isCurrent: true`. Warning.
- The manifest ships on two stores but a product exists in only one
  RevenueCat app. Warning.
- The API key lacks a needed scope. Error, with the missing scope named.

Adapty only:

- The `adapty` binary is not on the `PATH`. Error, with the install command.
- `adapty auth status` reports a logged-out CLI. Error, with
  `adapty auth login` in the message.
- The Adapty app id does not exist. Error.
- The Adapty `apple-bundle-id` or `google-bundle-id` does not match the
  manifest. Error.
- A plan `duration` has no Adapty period. Error, with the plan named and the
  supported periods listed. The app never rounds a duration.
- An Android subscription plan has no `basePlanId`. Error.
- A product names more than one entitlement. Warning. Adapty takes the first
  one and the app says which one it used.
- A product id in the manifest differs from the id on the matching Adapty
  product. Error. The store ids are immutable, so the plan shows a create and
  an orphan, never a rename.
- A paywall that a placement already uses needs a different product list.
  Error, with the new-paywall path named. Adapty forbids the change.

### 10.6 State

- The Apple version state is not `PREPARE_FOR_SUBMISSION` and the plan holds
  metadata writes. Error, with the current state named.
- An Apple review submission is already open for the app. Error, with a link
  to cancel it.
- Another Google edit committed while this run was open. The app detects
   `editAlreadyCommitted` or `editExpired`, discards its own edit, and asks
   for a re-plan. Nothing is lost, because the app committed nothing.
- A Google draft release already exists in the target track with a different
  version code. Warning, with both codes named. An apply replaces it.

---

## 11. Failure handling

**A run holds no irreversible step.** This is the whole design, and it comes
from one decision: the app prepares, and the developer releases. Sections 7.3
to 7.8 write to both stores, and every one of those writes ends in a draft.
Nothing reaches a user. Nothing enters a review queue.

So the app needs no two-phase commit, no rollback engine, and no split-state
recovery. A failed run is fixed by a re-run, because an apply is idempotent.

### 11.1 When an apply fails

The app stops at the failed step. It shows the completed steps and the failed
step, with the HTTP status and the API error `detail`.

It offers two buttons: **Retry from the failed step** and **Undo what this
run created**.

The undo deletes the Google edit when the run failed **before** step 8 of
section 7.4, and it archives the provider objects that this run created.

The undo has two limits, and the panel states both:

- After the Google commit, the undo cannot remove the Google draft. The edit
  no longer exists, and the draft release sits in the Play Console. The fix
  is another apply with a corrected manifest, not an undo. The draft harms
  nobody in the meantime.
- The undo does not remove the uploaded Apple screenshots, because Apple
  keeps them in the version. A second apply reuses them by checksum.

Neither button is urgent. A half-applied draft harms nobody. The developer
can close the app and finish tomorrow.

### 11.2 When the monetization sync fails

The apply continues. A provider failure is a catalog problem, not a release
problem. The panel offers three buttons, in this order:

1. **Skip the provider and finish the run.** The default. The app adds a row
   to the "Finish in the console" screen.
2. **Retry the provider sync.**
3. **Stop the run.**

The app never holds a store draft for a mirror.

### 11.3 When a release for review fails

One store, one button, one failure. The other store is untouched, because the
app never chained the two.

The panel names the store, the error, and one button: **Retry this store**.
There is nothing to roll back and no second store to reason about.

### 11.4 The run log

Every run appends to `.super-submitter/runs/<timestamp>.jsonl`. One line per
API call: the timestamp, the method, the path, the status, the duration, and
the request id. The app redacts the tokens. This file is the first thing to
read when a run fails.

---

## 12. Architecture

### 12.1 Modules

```
SubmitKit/                  Swift package, no UI, fully testable
  Manifest/                 YAML parsing, schema validation, the merge rules
  Apple/                    the App Store Connect client
  Google/                   the Android Publisher client
  RevenueCat/               the Developer API v2 client, one provider option
  Adapty/                   a wrapper over the `adapty` CLI, one provider option
  Mapping/                  the tables from section 6
  Planner/                  the state diff and the plan model
  Runner/                   the apply engine, the retries, the run log
  Assets/                   the image dimension reader and the checksums
  Package/                  the `.ipa`, `.pkg`, and `.aab` reader for the pre-fill

SuperSubmitter/             the macOS app target, SwiftUI, thin
```

The app target holds views and no logic. Every rule from section 6 and
section 10 lives in `SubmitKit` and has a unit test.

`project.yml` is the reproducible XcodeGen source for the checked-in native
`SuperSubmitter.xcodeproj`. That application target produces a conventional
`SuperSubmitter.app`, compiles the asset catalog into `AppIcon.icns`, enables
the hardened runtime, and uses the deliberately non-sandboxed entitlement set
required by this developer tool. The same project owns native SubmitKit and UI
test bundles and is the signing, archive, and notarization entry point.

### 12.2 Technology

| Choice | Reason |
|---|---|
| Swift 6, SwiftUI, macOS 14 or later | The target is a Mac app. The Keychain, the notifications, and the file access are native. |
| `URLSession` only | No HTTP dependency. Three APIs need a client, not a framework. |
| `Codable` structs, hand-written | See section 12.3. |
| Yams for the YAML | The only dependency. YAML has no stdlib parser. |
| CryptoKit for `ES256` and `RS256` | Native. No crypto dependency. |
| `Process` for the Adapty CLI | Adapty ships a CLI, not a public REST API. A subprocess with `--json` costs less code than an HTTP client, an OAuth flow, and a token store. |
| `unzip` and `pkgutil` to read a build | Every Mac ships both. An `.ipa` and an `.aab` are zip files, and a `.pkg` opens with `pkgutil --expand-full`. No zip library, and no Xcode on the machine that submits. |
| A hand-written protobuf reader for the `.aab` manifest | The `AndroidManifest.xml` inside an `.aab` is an aapt2 protobuf message. `aapt2 dump` reads an `.apk` and **refuses an `.aab`**, and `bundletool` is a Java program that a Mac does not ship. Six fields off the wire cost about 100 lines and they remove the Android SDK from the list of prerequisites. Add SwiftProtobuf only when this needs the resource table too. |
| No database | The stores hold the state. The manifest holds the intent. Git holds the history. |

The `Adapty/` module takes the command runner as a parameter. The real runner
calls `Process`. The test runner returns a fixture and records the argument
list. This is the whole test seam, and it needs no network.

### 12.3 A note on code generation

The Apple OpenAPI file holds 966 paths and 1393 schemas, and it weighs 6.9 MB.
A full generator run produces a very large module for a client that touches
about 40 resource types.

The app hand-writes the ~40 `Codable` types that it uses. It keeps the
OpenAPI file in the repository and adds a test that checks the hand-written
types against the spec on every Apple API version bump.

`// ponytail: hand-written models over full codegen. Switch to
swift-openapi-generator when the touched surface passes ~150 types.`

---

## 13. Steps that the APIs cannot do

This section is a feature, not a disclaimer. The app shows this list as a
checklist in the UI, with a link to the correct console. It marks each item
done when an API confirms the value.

| Step | Apple | Google | Monetization |
|---|---|---|---|
| Content rating questionnaire | API writable: `PATCH /v1/ageRatingDeclarations/{id}` | Console only. The IARC questionnaire has no API. | not applicable |
| Privacy labels and data safety | Console only. The privacy nutrition labels have no API. | API writable: `POST /v3/applications/{packageName}/dataSafety` | not applicable |
| Country availability | API writable: `POST /v2/appAvailabilities` | Console only, except the staged rollout country targeting. | not applicable |
| The first app record | Console only. The API cannot create an app record. | Console only. | Writable by both: `POST /projects/{id}/apps` and `adapty apps create`. This app does not use either. See section 20, question 6. |
| App category | API writable: `PATCH /v1/appInfos/{id}` | Console only. The Android Publisher API writes no category. | not applicable |
| App access for the reviewer, the demo account | API writable: `POST` or `PATCH /v1/appStoreReviewDetails` | Console only. The App access page has no API. | not applicable |
| Export compliance | API writable: `PATCH /v1/builds/{id}` with `usesNonExemptEncryption` | Console only, inside the data safety form. | not applicable |
| Tax and banking | Console only. | Console only. | Dashboard only. |
| The service account invitation | not applicable | Console only. | not applicable |
| App signing key upload | not applicable | Console only. | not applicable |
| Store credential upload | not applicable | not applicable | Dashboard only, in both providers. RevenueCat `PlayStoreAppCreate` takes the package name and no credential. The Adapty CLI takes no credential at all. |
| Push a product to the store | this app does it | this app does it | RevenueCat `create_in_store` covers Apple only. Adapty offers no such command. This app does not use either. See section 7.8. |
| Paywall design and A/B tests | not applicable | not applicable | Dashboard only, by choice. See section 3. |
| Adapty segments | not applicable | not applicable | Dashboard only. The CLI reads segments and cannot write them. |

The app disables the release button of a store when a mandatory console step
for that store is not done and an API can detect it. The app warns when it cannot detect it. Section 16 gives the
screen that shows the remaining steps as links.

---

## 14. Rate limits, retries, and concurrency

- App Store Connect returns an `X-Rate-Limit` header on every response, in
  the form `user-hour-lim:3600;user-hour-rem:3599;`. The app reads the
  remaining count and slows down under 10 percent.
- The Android Publisher API applies a per-project quota. The app reads the
  `429` responses and the `Retry-After` header.
- The RevenueCat API applies a limit per domain. The Project Configuration
  domain, which holds every catalog endpoint that this app uses, allows 60
  requests per minute. Every response carries
  `RevenueCat-Rate-Limit-Current-Usage` and
  `RevenueCat-Rate-Limit-Current-Limit`. The app reads both.
- The Adapty CLI documents no rate limit. The app runs the `adapty` commands
  in sequence, never in parallel, and it uses `--page-size 100` on every list
  command. The catalog is small, so this costs a few seconds.
- The app never retries an Adapty command by itself. A CLI exit code of
  non-zero stops the step and shows the `stderr` output as written. A retry
  of a create can produce a duplicate, and the CLI offers no idempotency
  key.
- One token bucket per system. The three buckets are independent.
- Retry policy: retry on `429`, `500`, `502`, `503`, and `504`. Use an
  exponential backoff with full jitter, a base of 1 second, and a cap of 60
  seconds. Retry at most 5 times. Never retry a `4xx` other than `429`.
- Never retry a `POST` that creates a resource without an idempotency check.
  The app re-reads by the natural key first, for example the `productId` or
  the `locale`.
- Concurrency: at most 4 concurrent uploads per store. The uploads dominate
  the wall clock. The metadata writes run in sequence, because the order
  matters.

---

## 15. Errors

Apple returns a JSON:API error body with `errors[]`. Each error holds `code`,
`status`, `title`, `detail`, and often a `source.pointer`. The pointer names
the exact field. The app maps the pointer back to the manifest line and shows
the error next to that line in the editor.

Google returns a Google API error body with `error.code`, `error.message`,
and `error.details[]`. The app shows the message and links to the resource
docs.

The app never shows a raw stack trace. Every user-facing error names three
things: what failed, which store, and what to do next.

---

## 16. User interface

One window. Ten tabs, in the order of the work. One Settings window.

### 16.1 The shell

The window holds three parts.

- **The app switcher.** It sits at the top of the sidebar. It lists the
  linked apps and it holds a **New app** row. Each row shows the icon, the
  name, the Apple state, and the Google state. A green row means that both
  stores match the manifest.
- **The tab list.** It sits below the switcher.
- **The content area.** It fills the rest of the window.

**The position of the tabs.** Settings holds one picker, **Navigation:
Sidebar or Top bar**. The sidebar is the default. The top bar shows the same
ten tabs as a segmented control and moves the app switcher into the toolbar.
The two positions render the same views. Nothing else changes.

`// ponytail: one preference, two containers, one set of views. No second
// navigation model.`

**The tabs are a form over `store.yaml`.** Every field writes the manifest,
and the manifest stays the source of truth. Section 5 does not change. Each
tab holds a **YAML** toggle in its toolbar that shows the raw block behind
that tab, and both sides edit the same file.

**The tabs are not a wizard.** The developer opens any tab at any time. A tab
that lacks a prerequisite shows one line that names the missing item and one
button that opens the tab which holds it. A tab with an error shows a red
badge in the sidebar. A tab with a warning shows a yellow badge. Tab 7
collects every badge in one list.

**The locale switcher.** Tab 3 and tab 4 hold a locale picker in the toolbar.
It lists every locale in the manifest and holds an **Add a locale** row. The
badge on the picker shows the locales that hold an error.

The menu bar shows a status item during a run and after a release. It shows
the current state of both stores in one glance.

### 16.2 The onboarding

The onboarding opens on the first run, and from the Help menu afterwards. It
shows five cards, one per step of the work, and one **Start** button.

| Card | Text |
|---|---|
| 1 | Choose your stores. Connect each one. |
| 2 | Pick your build, or pick an app to update. |
| 3 | Write the details once. We read what the build already knows. |
| 4 | Add the screenshots and the videos. We check every size. |
| 5 | Set the price and the purchases. We mirror them to RevenueCat or to Adapty. |

A last line reads: **We prepare a draft. You press release.** This is the one
promise of the product, and the onboarding states it before the first
credential.

The onboarding writes nothing. One click skips it.

### 16.3 The tabs

| # | Tab | Question it answers | Manifest block |
|---|---|---|---|
| 1 | Stores | Where does this app go, and who am I? | `apps`, `monetization` ids |
| 2 | Build | What do I submit? | `release.build`, `release.versionName` |
| 3 | Details | What does the listing say? | `listing` |
| 4 | Media | What does the listing show? | `media` |
| 5 | Money | What does it cost, and what can I buy? | `pricing`, `purchases`, `subscriptions`, `entitlements`, `offerings` |
| 6 | Marketing | How does the App Store sell it? | `marketing` |
| 7 | Review info | What does the reviewer need? | `review` |
| 8 | Plan | What changes, exactly? | none. It reads. |
| 9 | Submit | Do it. | none. It writes. |
| 10 | Release | Is it ready, and shall I send it? | none. It releases. |

Tabs 1 to 7 edit the manifest. Tab 8 reads. Tab 9 writes the drafts. Tab 10
holds the only irreversible buttons in the app.

Tab 6 is the one tab that reaches a single store. Every field on it writes to
the App Store, and Google Play has no equivalent for any of it, so the tab
says that once in its header rather than in every section.

#### Tab 1 — Stores

The developer selects App Store, Google Play, or both. A selected store shows
a credential card below it.

| Store | The card asks for | Help |
|---|---|---|
| App Store | The `.p8` key file, the key id, the issuer id | Section 9.1 |
| Google Play | The service account JSON file | Section 9.2 |

Each card holds a **Where do I get this?** disclosure. It opens an inline
guide with the numbered steps, and one button that opens the correct console
page. The Apple guide names the Users and Access page, and it warns that
Apple shows the `.p8` file **once**. The Google guide names the two places,
the Cloud console for the service account and the Play Console for the
invitation, and it states that the invitation is mandatory and that no API
performs it.

Each card holds a **Test connection** button. A pass shows the team name or
the developer account name. A failure names the cause and the fix.

The card drops the file on the Keychain and keeps no copy. Section 9.5 holds
the rules.

#### Tab 2 — Build

The tab holds two paths. Both end in the same state.

1. **Submit a build.** The developer drops an `.ipa`, a `.pkg`, or an `.aab`.
   One row per platform.
2. **Update an app that exists.** A picker lists every app on the connected
   accounts. It calls `GET /v1/apps` and
   `GET /androidpublisher/v3/applications`. The developer picks one app per
   store, and the app then runs the import from section 7.1.

The app reads every dropped package and shows what it found. The next table
holds the pre-fill source for tab 3.

| Read from | Apple `.ipa` and `.pkg` | Google `.aab` |
|---|---|---|
| Bundle id or package name | `CFBundleIdentifier` | the manifest `package` |
| Version name | `CFBundleShortVersionString` | `versionName` |
| Build number | `CFBundleVersion` | `versionCode` |
| App name | `CFBundleDisplayName`, then `CFBundleName` | the application label, when it is a literal. A `@string/…` reference stays empty. See the limit below. |
| Locales | `CFBundleLocalizations` | the `values-*` resource folders. The unqualified `values/` folder names no language. |
| Minimum OS | `MinimumOSVersion`, or `LSMinimumSystemVersion` for the `.pkg` | `minSdkVersion` |
| Device class | `UIDeviceFamily` | none. An Android manifest declares no device class. |
| Encryption answer | `ITSAppUsesNonExemptEncryption` | not applicable |
| Privacy hints | the `NS*UsageDescription` keys | the `uses-permission` names |

**Two limits, and the app states both on the screen.**

1. An Android `android:label` that reads `@string/app_name` needs the resource
   table, and the resource table is a second protobuf schema. The app leaves
   the name empty and the developer types it. One field, two seconds.
2. The app reads no icon from a build. Apple takes the icon from the build by
   itself, and the Google icon is a separate 512 by 512 file in `media.icon`.
   No manifest field holds it, so no pre-fill needs it.

The tab warns at once when the bundle id does not match the selected app,
when the build number is not greater than the highest build in the store, or
when the version name differs between the two packages. Section 10.3 holds
the rules.

#### Tab 3 — Details

The tab holds one form per locale, and it starts with the values from tab 2.
Every field that the package supplied shows a small **from the build** label,
and the developer overwrites it freely.

Each field shows a character counter against the binding limit from section
6.1. The counter turns red over the limit. A field that the two stores limit
differently shows a **Different for Google** button, which adds the override
instead of a truncation. The app never truncates text.

A per-store preview panel shows the exact text that each store will receive.

The tab marks the Apple-only fields and the Google-only fields with the store
icon. A developer who selected one store never sees the fields of the other.

#### Tab 4 — Media

A grid per locale and per device class. The developer drops the files.

The app reads the dimensions of every file **on the drop**, before any
upload. It then does one of three things.

1. The file matches a bucket. It shows the bucket name, for example
   `iPhone 6.7 inch`, and the target store icons.
2. The file matches no bucket. The tile turns red. The message names the
   dimensions of the file and the nearest accepted size. The app offers no
   automatic resize, because a stretched screenshot fails a review.
3. The file type is wrong. The tile turns red and names the accepted types.

The grid shows the count against the limit, for example `7 of 10`. It blocks
the drop past the limit.

A video row sits below the screenshots. It states the rule from section 6.3
in one line: Apple takes a file, and Google takes a YouTube URL. The Google
row is a URL field, never a drop target.

#### Tab 5 — Money

The tab opens on the base price. The provider choice moved to Settings, and
the reason is the frequency: a developer picks RevenueCat or Adapty once per
machine, and then edits the catalog on every app. Two jobs, two screens.

The tab still holds the whole catalog: the price, the availability, the
purchases, the subscriptions, and the entitlements and offerings of the
provider. Those belong to the manifest and they change per app.

The Adapty panel shows the three states from section 9.4: **The CLI is
missing**, with the install command; **Not logged in**, with
`adapty auth login`; or **Logged in as <user>**. The app never runs the login
command by itself.

Each panel holds an **I have no account yet** link that opens the sign-up
page, `https://app.revenuecat.com/signup` or `https://app.adapty.io`.

**The rest of the tab.**

- **The price.** One base amount, one currency, one base territory. The
  panel shows the resolved Apple price point next to the request, and it
  warns over a 5 percent difference. Section 6.7 holds the rule.
- **Availability.** The Apple territory list is editable. The Google country
  list is read-only, and the row links to the Play Console. Section 6.8
  states the reason.
- **In-app purchases.** One row per product, with the kind, the price, and
  the localized names.
- **Subscriptions.** One group per row, and one plan per line inside it. The
  plan line holds the duration, the base plan id, and the price.
- **Entitlements and offerings.** Two small lists. The app hides both when
  the provider is None, because nothing reads them.

The tab shows the provider vocabulary of the selected provider only. Section
6.6 holds the word map, and the developer never learns two vocabularies.

#### Tab 6 — Review info

This tab holds everything that the reviewer needs and nothing that the
customer sees. It is the tab that a developer forgets, so the app shows the
open rows first.

- **The review contact.** The first name, the last name, the email, and the
  phone. Apple writes it to `appStoreReviewDetails`. Google has no
  equivalent.
- **The demo account.** A required toggle, a user name, and a password. The
  password goes to the **Keychain**, never to `store.yaml`. The manifest
  holds `demoAccountRequired` only. Section 9.5 holds the rule.
- **The review notes.** One text field per store.
- **The age rating.** The Apple questionnaire, as a form. The app writes it
  with `PATCH /v1/ageRatingDeclarations/{id}`. The Google IARC questionnaire
  is Console only, and the row links to it.
- **The categories.** The Apple primary and secondary category, from the API.
  The Google category is Console only.
- **The privacy policy URL.** One per locale for Apple. Console only for
  Google.
- **The privacy answers.** The Apple nutrition labels are Console only. The
  Google data safety form is API writable. The app pre-fills the Google form
  from the permission list and the privacy manifest that tab 2 read, and it
  shows every answer before it writes one.
- **Export compliance.** The answer from `ITSAppUsesNonExemptEncryption`,
  when the build carries it.

Every Console-only row shows the same four states as section 16.6 and the
same link. This tab and tab 9 read one list.

#### Tab 7 — Plan

A two-column diff. Apple on the left and Google on the right. The provider
gets a third column when it is not None. Green for an addition, yellow for a
change, red for a deletion.

The header shows the write count, the upload count, and the total upload
size. The validation errors sit at the top. Each error names the tab that
fixes it, and one click goes there.

An error blocks the **Apply** button. A warning needs one acknowledgement.

The toolbar holds the **Dry run** toggle. It is on for a new app, and section
17 states why.

This tab is the safety model of the product. Section 19 names the Apple
sandbox as the top risk, and this tab is the mitigation. The app never skips
it. Without the plan, the app writes to a live listing on a guess.

#### Tab 8 — Submit

A live step list with a spinner, a check, or a cross per step. The streaming
log sits below it.

The run ends with a draft in every store. It releases nothing. The failure
panels from section 11 open here.

The tab moves to tab 9 by itself when the run ends.

#### Tab 9 — Release

This tab holds the "Finish in the console" checklist from section 16.6, the
two release buttons, and the live status from section 7.10.

The order on the screen is the order of the work: the checklist first, then
the buttons. The checklist sits between the draft and the review, and that
placement is the point.

Each store shows one row at all times. A store that a run prepared and nobody
released reads **Draft, ready to release**. The app polls a store only after
a release.

The two buttons are red. Each one releases **one** store, and each one guards
itself with its own confirmation sheet. Section 7.9 holds the reason for two
buttons and the text of each sheet.

### 16.4 What the tabs replaced

The earlier draft held six windows: Apps, Manifest, Plan, Run, Finish in the
console, and Settings. The Apps window became the app switcher in the
sidebar. The Manifest window became tabs 1 to 6, because every tab now edits
its own block of the same file. The Plan, Run, and Finish windows became tabs
7, 8, and 9. The Settings window became a panel over the window.

**The app now opens exactly one window.**

`// ponytail: no window management, no document model. One window, one
// selection, one file on disk.`

### 16.5 Settings

Settings opens as a **panel over the window**. It is not a second window, and
the app holds no Settings scene.

Three controls open it, and all three do the same thing: the last row of the
sidebar, the button beside the top bar, and the standard macOS shortcut. The
panel closes with **Done** and with the Escape key.

It holds five things and no more.

1. **Navigation.** Sidebar or Top bar. Section 16.1.
2. **The poll interval.** The default is 5 minutes. Section 7.10.
3. **The dry run.** The default state for a new app. Section 17.
4. **The manifest path.** The location of `store.yaml`.
5. **The monetization provider.** None, RevenueCat, or Adapty, with the
   credential panel of the choice.

| Provider | The panel asks for | Help |
|---|---|---|
| RevenueCat | A secret v2 API key, and the project | Section 9.3, with the scope list |
| Adapty | Nothing. It shows the CLI state. | Section 9.4 |

The two **store** credentials stay on tab 1, next to the connection that needs
them. A developer who connects a store never hunts for a settings panel. The
provider key sits here instead, because the provider itself is a per-machine
choice. Every key of both kinds lives in the Keychain and never in
`store.yaml`.

`// ponytail: a panel over the window, not a second window. One window to
// manage, one place the shortcut can lead, and no state to keep in sync
// between two scenes.`

### 16.6 The Finish in the console screen

A run ends with a draft in every store. Several mandatory steps live only in
the two consoles, and section 13 lists them. A developer who releases without
them waits for a rejection to learn it. This checklist removes that wait. It
sits on tab 9, above the two release buttons, so the checklist sits between
the draft and the review.

**When it opens.** Tab 9 opens by itself when a run ends. It also opens from
the tab list, from the app switcher, and from the menu bar item. It blocks
nothing. The developer opens another tab at any time.

**What it shows.** One card per system. Each card holds one row per step.
Each row holds a title, a one-line reason, a state, and a button that opens
the console page in the default browser.

Each row carries one of four states:

| State | Meaning | Source |
|---|---|---|
| Done | The API confirms the value. | A read call. |
| Needed | The API reports the value as missing. | A read call. |
| Unknown | No API can read this step. | Section 13. |
| Not applicable | The step does not apply to this app. | The manifest. |

A row with the state Unknown holds a checkbox. The developer marks it done by
hand. The app stores the mark in `.super-submitter/console-state.json`, keyed
by the app and the version. The app clears every hand-made mark when the
version string changes, because a new version needs the check again.

**The rows.**

| System | Row | Link |
|---|---|---|
| Apple | App privacy (nutrition labels) | `https://appstoreconnect.apple.com/apps/{appId}/distribution/privacy` |
| Apple | App information and categories | `https://appstoreconnect.apple.com/apps/{appId}/distribution/info` |
| Apple | Pricing and availability | `https://appstoreconnect.apple.com/apps/{appId}/distribution/pricing` |
| Apple | The submitted version | `https://appstoreconnect.apple.com/apps/{appId}/distribution/ios/version/inflight` |
| Apple | Agreements, tax, and banking | `https://appstoreconnect.apple.com/business` |
| Google | Content rating (IARC) | `https://play.google.com/console` |
| Google | Data safety | `https://play.google.com/console` |
| Google | Country availability | `https://play.google.com/console` |
| Google | The release in the track | `https://play.google.com/console` |
| Google | App signing | `https://play.google.com/console` |
| Google | App category | `https://play.google.com/console` |
| Google | App access, the reviewer credentials | `https://play.google.com/console` |
| RevenueCat | The store credential upload | `https://app.revenuecat.com` |
| RevenueCat | The offering, to confirm the packages | `https://app.revenuecat.com` |
| Adapty | The store credential upload | `https://app.adapty.io` |
| Adapty | The paywall, to style it and to confirm the products | `https://app.adapty.io` |

The app shows the provider rows of the selected provider only.

The Apple links use the numeric app id that the API already returns. They
need no extra setup.

Every Google row opens the main Play Console dashboard. Play Console URLs
need two internal numeric ids that no Android Publisher endpoint returns, and
the app does not guess a URL. The row text names the exact page to open, so
the developer finds it in two clicks. This costs two clicks and it removes a
setup step, a stored id, and a class of broken links.

**A header** shows one line, for example `4 of 12 steps are done`. A **Copy as
checklist** button copies every open row as Markdown, for a ticket or for a
message to a colleague.

**A re-check button** runs the read calls again and updates the states. The
checklist never writes to a store.

Tab 6 shows the same rows for the steps that it owns, with the same states
and the same links. The two tabs read one list, so a row is never done in one
place and open in the other.

`// ponytail: one dashboard link over a parsed-id deep link. Add the deep
// link if two clicks per row becomes a real complaint.`

---

## 17. Testing

- Unit tests for every mapping table and every validation rule. These run
  with no network.
- HTTP record and replay. The app records the real responses once into
  fixtures, then replays them in CI. The fixture recorder redacts the tokens.
- A dry-run mode that logs every request and sends none. This is the default
  for a new app until the developer turns it off.
- Google testing is **no longer free**, and the draft-first design is the
  reason. An apply commits the edit, so it writes a real draft release. The
  tests therefore use a throwaway app and the `internal` track, never
  `production`. A test that only exercises the write path stops after
  `:validate` and deletes the edit, which still costs nothing.
- RevenueCat testing is safe. The tests use a throwaway RevenueCat project
  and archive every object at the end. RevenueCat also offers a test store
  app type, which needs no store credential.
- Adapty testing uses a throwaway Adapty app. The `Adapty/` module takes the
  command runner as a parameter, so the unit tests inject a fake runner and
  assert on the exact argument list. This needs no network and no CLI.
- Apple testing is not safe. App Store Connect has no sandbox. The tests use
  a throwaway app record on a test team. This is a real risk. The mitigation
  is the dry-run default and the plan step.
- One end-to-end test per milestone, run by hand against the throwaway app.

---

## 18. Milestones

| # | Scope | Proves |
|---|---|---|
| M0 | The tab shell, the app switcher, the onboarding, tab 1. | The navigation and the credential flow. It writes nothing. |
| M1 | Auth for both stores. Import. Read-only. | Both clients work. The manifest round-trips. |
| M2 | Plan and apply for the text metadata and the screenshots. | The diff engine and the upload flows. |
| M3 | The package reader and the tab 3 pre-fill. Build upload and attach, for `.ipa`, `.pkg`, and `.aab`. | The chunked upload, the processing poll, and the pre-fill. |
| M4 | In-app purchases and subscriptions. | The hardest mapping in section 6. |
| M5 | The monetization sync, for RevenueCat and for Adapty. | Two catalog mappings over one manifest vocabulary. It builds on M4. |
| M6 | Tab 6, tab 9, the two release buttons, the status polling, the notifications, the "Finish in the console" checklist. | The whole product. |
| M7 | A CLI target over the same `SubmitKit` package, for CI. | Reuse, not a rewrite. |
| M8 | The deferred Google Play surface of section 3.1, in the order that its last column gives. | The client already carries the auth, the retry, and the dry run. Each row adds calls, not architecture. |

M0 to M6 make a shippable product. M5 is optional for a first release, because
the manifest works with `provider: none`. M7 costs little, because
the logic already lives in a package with no UI.

---

## 19. Risks

| Risk | Impact | Mitigation |
|---|---|---|
| Apple has no sandbox. A bug writes to a real listing. | High | The dry-run default. The plan step. Never write without an explicit apply. |
| The Apple API version changes and a field moves. | Medium | The spec file is in the repository. A test compares the hand-written types to it. |
| A Google edit expires or another edit commits first. | Low | The app opens and commits one edit inside a single apply, so the window is minutes, not days. It detects `editExpired` and `editAlreadyCommitted`, discards its own edit, and asks for a re-plan. It committed nothing, so nothing is lost. |
| The price point mapping resolves an unexpected amount. | High | Show both amounts in the plan. Warn over 5 percent. Never apply money on a guess. |
| A partial release leaves one store in review and one not. | Removed | A run releases nothing. Two separate buttons put the developer between the two irreversible calls, so the app can never chain them. |
| The console-only steps make the tool look incomplete. | Low | Section 13 is a visible checklist and section 16.6 is a tab, not a footnote. |
| An apply writes a visible Google draft that a colleague did not expect. | Low | This is the cost of the draft-first design, because an uncommitted edit is invisible. The plan names every Google write before the apply, and a draft release serves no user. |
| The provider catalog and the store catalog drift apart. | Medium | The plan reads the provider every time. A drift shows as a diff row, the same as a store drift. |
| A wrong provider app id writes the products to another app. | High | The bundle id and the package name check, in section 7.8.1 step 1 and in section 7.8.2 step 2. It runs before any write. |
| An Apple Console URL pattern changes and the links break. | Low | A CI test checks every Apple link pattern. The Google rows use the dashboard root, which does not change. |
| The developer expects the provider to push the products to the stores. | Low | Section 7.8 states the direction. The stores are the source. The provider is the mirror. |
| The Adapty CLI changes a flag or an output shape. | Medium | The CLI is a subprocess with a version check. The app runs `adapty --help` once per session and warns on an unknown flag. Pin the tested CLI version in the README. |
| An Adapty product id is immutable and the developer renames one. | Medium | The validation in section 10.5 turns the rename into a visible create plus an orphan. The plan never hides it. |

---

## 20. Open questions

1. Does the developer want the manifest in the app repository or in a
   separate repository? The spec assumes the app repository.
2. Should the app manage the TestFlight and the Play internal test tracks in
   v1? The spec says no. A later milestone can add it.
3. Should the app write the screenshots back to `assets/` on import, or link
   the remote URLs? The spec says download, because a build must work
   offline.
4. Which team model does the Apple key use, an individual key or a
   team-scoped key? The spec supports both, but the scope claim differs.
5. Should the app style the paywalls? Both providers offer a paywall object,
   and RevenueCat offers a publish action. The spec says no. The app creates
   a paywall that holds the right products. The design belongs in the
   dashboard.
6. Should the app create a missing provider app? The spec says no in v1. The
   developer links an existing app. An automatic create needs the store
   credentials, and those belong in the provider dashboard.
7. Should a manifest support both providers at once, for a migration from one
   to the other? The spec says no. Ask a user who is doing the migration
   before you build it.
8. **May a save lose the comments and the block scalars in `store.yaml`?**
   The tabs write the whole file through the YAML encoder. The values
   survive, and a test proves it. The shape does not. A `# comment` is gone
   after the first save, and a `|` block returns as a quoted scalar. The file
   sits in a repository, and the spec calls it the only file the developer
   edits. Three answers are open:
   - Accept it. The app owns the file, and git shows the diff.
   - Write only the keys that changed, with a text-level edit that leaves the
     rest of the file untouched. This costs a YAML editor that Yams does not
     offer.
   - Keep the tabs read-only for the blocks that hold long text.

   The spec assumes the first answer until a user complains.
