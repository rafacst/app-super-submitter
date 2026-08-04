# Super Submitter Stripe access specification

Status: draft implementation specification  
Audience: engineers implementing the macOS client and its licensing service  
Scope: direct-download, notarized macOS distribution only

## 1. Purpose

Super Submitter remains useful without payment. A free user can configure an
app, edit its store data through the structured interface, inspect builds, read
the connected stores, and preview a plan. Payment or a valid promotion-code
checkout unlocks two capabilities:

1. viewing or editing raw YAML through Super Submitter; and
2. writing, uploading, submitting, or releasing anything to Apple App Store
   Connect or Google Play.

This document defines the client, server, Stripe, security, and user-interface
work needed to enforce those rules.

## 2. Product rules

### 2.1 Plans

Prices must be created in Stripe as fixed Prices. Amounts are expressed in the
smallest currency unit when sent to Stripe.

| Plan | Stripe mode | Amount | Access term | Suggested lookup key |
|---|---|---:|---|---|
| Monthly | `subscription` | USD 4.99 (`499`) | While the subscription is entitled | `super_submitter_monthly_usd` |
| Annual | `subscription` | USD 49.90 (`4990`) | While the subscription is entitled | `super_submitter_annual_usd` |
| Lifetime | `payment` | USD 449.90 (`44990`) | Perpetual, subject to the refund and abuse rules below | `super_submitter_lifetime_usd` |

The amount, currency, recurrence, Stripe Price ID, and lookup key are server
configuration. The client may display values returned by the server, but must
not decide what to charge from hard-coded amounts.

There is no trial in version 1. Adding a trial later is a pricing change, not an
implicit consequence of the free tier.

### 2.2 Free access

A free user may:

- create, import, open, and switch between app manifests;
- select Apple, Google, or both stores;
- add and test store credentials;
- retrieve existing apps and their available listing data;
- edit every supported field through the structured tabs;
- add and validate local assets;
- build, archive, inspect, and retain artifacts locally;
- perform read-only store diagnostics;
- read the stores, generate a plan, and run a dry-run that makes no remote
  writes; and
- use all local checklists and validation.

A free user may not:

- open the raw-YAML panel;
- reveal, copy, export, or edit raw YAML through Super Submitter;
- start a non-dry apply against Apple or Google;
- upload an `.ipa`, `.pkg`, `.aab`, or `.apk` to a store;
- commit a Google Play edit that changes store state;
- create, update, delete, submit, or release App Store Connect or Google Play
  resources; or
- invoke a release, phased-rollout, halt, cancel-submission, or approved-build
  release action.

Structured editing still persists the manifest to `store.yaml`; the app needs
that file as its data model. This requirement is an application-UI restriction,
not file encryption or DRM. Super Submitter must not show free users the raw
contents or provide a reveal/export shortcut. A user who independently opens a
file on disk is outside this product boundary.

### 2.3 Paid access

Monthly, annual, lifetime, and fully complimentary promotion-code orders unlock
the same features. There is no higher tier in version 1.

An active user may access raw YAML and perform store writes, uploads, applies,
submissions, and releases, subject to all existing confirmations and store
validation. Payment never bypasses a safety confirmation or validation error.

### 2.4 Promotion codes

The pricing screen must always include a field labeled **Promotion code** and
an **Apply** action. Codes are Stripe Promotion Codes, not secrets embedded in
the app.

- A user selects Monthly, Annual, or Lifetime, then enters a code.
- The code is applied to the Checkout Session for that selected Price.
- A partially discounted order still requires successful payment.
- A 100% code creates a no-cost order. Access begins only after Stripe confirms
  completion; entering or locally validating a code is never enough.
- Promotion restrictions configured in Stripe remain authoritative, including
  eligible product, eligible customer, expiry, maximum redemptions, minimum
  amount, and first-purchase restrictions.
- For complimentary lifetime access, create a 100% coupon restricted to the
  lifetime Product and issue customer-facing promotion codes from it.
- For complimentary subscription access, the coupon duration must explicitly
  define whether the discount applies once, for a fixed duration, or forever.
  The entitlement follows the resulting subscription, not the label of the
  code.

The server resolves and applies the promotion code. It must not return Stripe
coupon or Promotion Code object details that the client does not need.

## 3. Required architecture

### 3.1 Components

```text
Super Submitter.app
  |-- HTTPS: authentication, plans, checkout, entitlement, portal
  |       |
  |       v
  |   Licensing service ---- database
  |       |
  |       |-- Stripe secret-key API calls
  |       `-- verified Stripe webhooks
  |
  `-- Apple/Google APIs, only after a local entitlement gate succeeds
```

The licensing service is mandatory. A publishable Stripe key cannot create
trusted entitlements, read protected Stripe objects, verify webhooks, or keep a
Stripe secret key safe. The app must never contain a Stripe secret key or
webhook signing secret.

The service can be implemented on any reliable HTTPS platform with a durable
database and secret storage. The choice of provider is outside this spec.

### 3.2 Stripe Checkout

Use Stripe-hosted Checkout in the user's default browser. Do not collect card
numbers in the macOS app and do not add a native card form.

Hosted Checkout minimizes PCI scope and does not require a Stripe client SDK.
The configured publishable key is therefore reserved for a future Stripe.js or
embedded-checkout client and may not be exercised by version 1. All privileged
Stripe API calls originate from the licensing service.

### 3.3 Trust boundary

The following are authoritative:

- Stripe for payment, invoice, refund, dispute, and subscription state;
- the licensing database for the mapping between a Super Submitter account and
  its Stripe Customer and entitlement; and
- a server-signed entitlement document for short-lived client authorization.

The following are not authoritative:

- the selected plan or price displayed by the client;
- a Checkout success URL or app deep link;
- an email returned only by the browser;
- a cached boolean in `UserDefaults`;
- a locally typed promotion code;
- client metadata without a matching authenticated account; or
- analytics events.

The macOS app is distributed to machines controlled by its users, so perfect
local DRM is impossible. The goal is sound product enforcement in the official
binary, not protection against a deliberately patched binary or a user calling
Apple and Google APIs with their own credentials outside Super Submitter.

## 4. Configuration

### 4.1 Client configuration

The provided live publishable key is:

```text
pk_live_51U09CT3vRdmMCUuqefp3wDiD3F3diOXMxSiJa6DN8fljQVMMeaICYR1fGnv3Vk4ft3zdi1UekNvfiEZrsU5X4JRU00Tso43TYm
```

Publishable keys are intended for client use, but this value must still be
injected through the Release build configuration rather than scattered through
Swift source. Debug and test builds use a separate `pk_test_...` value.

Required client settings:

| Setting | Example purpose |
|---|---|
| `LICENSING_BASE_URL` | Base HTTPS URL for the licensing service |
| `STRIPE_PUBLISHABLE_KEY` | Test or live publishable key for the build |
| `ENTITLEMENT_PUBLIC_KEY` | Ed25519 public key used to verify cached grants |
| `BILLING_RETURN_SCHEME` | `supersubmitter://billing/complete` |

No `sk_...`, `rk_...`, or `whsec_...` value may appear in the app bundle,
repository, logs, crash reports, or analytics.

### 4.2 Server configuration

Required secrets and settings:

- Stripe restricted or secret API key;
- Stripe webhook endpoint signing secret;
- monthly, annual, and lifetime Price IDs;
- expected Product IDs and lookup keys;
- entitlement-document signing private key;
- session/authentication signing keys;
- database connection secret;
- public return and cancellation URLs; and
- current Stripe API version, pinned and upgraded deliberately.

Use separate Stripe sandboxes/test mode and production/live mode. Never allow a
Debug client to request a live Checkout Session.

### 4.3 Stripe Dashboard setup

1. Create one product named **Super Submitter** or three clearly named products.
   If one product is used, attach all three Prices to it.
2. Create the three immutable USD Prices from section 2.1.
3. Record the live and test Price IDs in server configuration.
4. Configure company branding, support contact, privacy policy, and terms.
5. Configure the Customer Portal for payment-method updates, invoice history,
   cancellation, and monthly/annual switching if switching is desired.
6. Disable quantity changes; Super Submitter is not seat based in version 1.
7. Decide tax registrations and enable Stripe Tax before setting
   `automatic_tax.enabled = true` in production.
8. Create coupons and customer-facing Promotion Codes in Stripe. Restrict
   complimentary lifetime codes to the lifetime Product.
9. Register separate test and live webhook endpoints and subscribe only to the
   events listed in section 9.

Prices are immutable for entitlement mapping. To change an amount, create a new
Price, update server configuration, and keep the old Price mapping so existing
subscriptions continue to resolve correctly.

## 5. Account and device identity

### 5.1 Account requirement

A free user does not need an account. Sign-in is required when the user selects
**Upgrade**, **Use a promotion code**, **Restore access**, or **Manage billing**.

Use verified email magic links for version 1. The service creates one internal
user ID per verified account. Stripe Customer email is useful contact data, but
email text alone is not authentication.

### 5.2 Sign-in flow

1. The user enters an email address in Super Submitter.
2. `POST /v1/auth/magic-link` sends a short-lived, one-use link.
3. The browser verifies the token with the licensing service.
4. The service redirects to the registered app URL scheme with a one-use
   exchange code, never a long-lived bearer token.
5. The app sends the code and its generated device ID to
   `POST /v1/auth/exchange`.
6. The service returns access and refresh tokens plus the current signed
   entitlement document.
7. The app stores tokens and device ID in macOS Keychain.

The exchange code expires after five minutes and is invalid after one use. The
deep link is not proof of payment; it only finishes authentication.

### 5.3 Restore access

**Restore access** signs in and calls `POST /v1/billing/restore`. The server
finds the Stripe Customer mapped to the authenticated internal user, reconciles
its current subscriptions and successful lifetime orders, updates the
entitlement, and returns a fresh signed document.

Do not search Stripe globally by an unverified email address. If an older
checkout created an orphan customer, recovery is a support/admin workflow with
an audit trail.

## 6. Pricing and checkout experience

### 6.1 Entry points

The upgrade sheet opens from:

- the Settings **Plan & billing** section;
- the locked YAML control;
- Apply or Submit while free;
- an upload confirmation while free;
- either Release action while free; and
- **Restore access**.

Opening the sheet does not discard current form, plan, build, or manifest state.

### 6.2 Pricing sheet

Show four cards or rows:

- **Free — $0**: structured editing, validation, local builds, and store reads;
- **Monthly — $4.99/month**;
- **Annual — $49.90/year**; and
- **Lifetime — $449.90 once**.

The selected paid plan is visually unambiguous. Below the paid options show:

- **Promotion code** text field;
- **Apply** button;
- validation progress and an inline result;
- **Continue to secure checkout** primary button;
- **Restore access**; and
- links to Terms, Privacy, and refund policy.

Do not claim a discount until the server has validated it for the selected
Price. If the user changes plan, clear or revalidate the code.

### 6.3 Checkout request

The authenticated client calls `POST /v1/billing/checkout` with:

```json
{
  "plan": "annual",
  "promotionCode": "LAUNCH100",
  "idempotencyKey": "client-generated-uuid"
}
```

The server:

1. verifies the account and rate limits;
2. maps `plan` to an allow-listed Price ID and mode;
3. creates or reuses the account's Stripe Customer and supplies that Customer
   to Checkout;
4. resolves an active, eligible Promotion Code when one was supplied;
5. creates a hosted Checkout Session with quantity `1`;
6. uses `subscription` mode for monthly/annual and `payment` mode for lifetime;
7. sets `customer` and an opaque `client_reference_id` containing no personal
   information;
8. puts the internal user ID and plan key in server-controlled metadata;
9. applies the Promotion Code ID through the Checkout Session discount;
10. enables automatic tax only if section 4.3 has been completed;
11. sets success and cancellation URLs owned by the licensing service; and
12. returns only the Checkout Session ID, short-lived hosted URL, and expiry.

Server plan mapping prevents a modified client from buying a cheap arbitrary
Price and receiving Super Submitter access.

### 6.4 Browser handoff and completion

1. The app opens the returned HTTPS Checkout URL with `NSWorkspace`.
2. The user completes or cancels checkout in the browser.
3. The success page says that payment is being confirmed and offers **Return to
   Super Submitter**.
4. The return link contains a Checkout Session reference but no entitlement or
   secret.
5. On return, the app polls `GET /v1/entitlements/me` with bounded backoff for
   up to 60 seconds.
6. The UI unlocks only after the service returns a verified active entitlement.
7. If webhook delivery is delayed, show **Payment received; still confirming**
   with **Check again** and **Contact support**, not a second purchase button.

Never unlock from `success_url`, a deep-link query parameter, or the client
fetching Checkout directly with the publishable key.

### 6.5 Existing paid customer

If an active subscriber attempts another subscription purchase, the server
returns `409 already_subscribed` and a Customer Portal URL. Lifetime users are
not offered another purchase. If an active monthly/annual user chooses lifetime,
the service may permit it only after presenting a clear cancellation policy;
version 1 should instead direct the user to support to avoid duplicate billing.

## 7. Entitlement model

### 7.1 Capabilities

The client consumes capabilities, not plan-name checks:

```text
raw_yaml
store_write
store_upload
store_release
```

All paid and valid complimentary entitlements grant all four capabilities.
Free grants none. Keeping separate capabilities makes gates explicit and allows
future product changes without spreading plan comparisons across the app.

### 7.2 Entitlement record

An entitlement contains at least:

| Field | Meaning |
|---|---|
| `user_id` | Internal verified account |
| `status` | `active`, `grace`, `expired`, `revoked`, or `free` |
| `plan` | `monthly`, `annual`, `lifetime`, `complimentary`, or `free` |
| `source` | Subscription, lifetime payment, or Promotion Code order |
| `stripe_customer_id` | Server-side relationship |
| `stripe_subscription_id` | Present for a recurring plan |
| `stripe_checkout_session_id` | Purchase audit link |
| `stripe_price_id` | Exact Price purchased |
| `promotion_code_id` | Optional server-side audit link |
| `current_period_end` | Recurring access boundary |
| `cancel_at_period_end` | User has canceled but retains current access |
| `grace_until` | Optional temporary recovery period |
| `created_at`, `updated_at` | Audit timestamps |
| `revocation_reason` | Refund, dispute, admin, fraud, or replacement |

Stripe IDs never belong in `store.yaml`.

### 7.3 Effective-access precedence

The highest valid grant wins:

1. active lifetime;
2. active subscription;
3. temporary grace;
4. free.

An expired subscription must not override a lifetime purchase. A refunded
lifetime order must not remove access if another valid subscription exists.

### 7.4 Subscription transitions

| Stripe condition | Effective status | App behavior |
|---|---|---|
| `trialing` if trials are added later | Active until trial end | Paid capabilities |
| `active` with paid invoice | Active | Paid capabilities |
| cancellation scheduled at period end | Active through period end | Paid capabilities plus renewal warning |
| `past_due` | Grace, for up to 7 days | Paid capabilities plus payment warning |
| `unpaid`, `paused`, or ended | Expired | Free capabilities |
| subscription deleted after period end | Expired | Free capabilities |

The server must derive state from the latest Stripe objects, not assume webhook
delivery order.

### 7.5 Lifetime transitions

Lifetime becomes active only when the Checkout Session is complete and its
PaymentIntent is successfully paid, or when Stripe reports a completed no-cost
order. An asynchronous payment method remains pending until its success event.

Default policy:

- a full refund revokes that lifetime grant;
- a partial refund does not automatically revoke it and creates an admin-review
  flag;
- a lost dispute revokes it;
- a won or withdrawn dispute restores it after reconciliation; and
- an administrator may revoke or restore with a reason and audit record.

The published refund policy must match this behavior before launch.

## 8. Signed client authorization and offline behavior

### 8.1 Entitlement document

`GET /v1/entitlements/me` returns a server-signed document resembling:

```json
{
  "version": 1,
  "subject": "usr_opaque",
  "device": "dev_opaque",
  "status": "active",
  "plan": "annual",
  "capabilities": ["raw_yaml", "store_write", "store_upload", "store_release"],
  "issuedAt": "2026-08-02T12:00:00Z",
  "refreshAfter": "2026-08-03T00:00:00Z",
  "expiresAt": "2026-08-09T12:00:00Z",
  "keyId": "entitlement-2026-01"
}
```

Sign the canonical payload with Ed25519. The app bundle contains only the
verification public key. Store the document and auth tokens in Keychain, not
`UserDefaults` or the manifest.

### 8.2 Refresh policy

- Refresh on app launch, account sign-in, checkout return, wake from sleep,
  before opening YAML, and immediately before every remote write/upload/release.
- Refresh in the background after `refreshAfter` while the app is running.
- A failed refresh may use an unexpired signed document.
- Give previously verified monthly/annual users at most seven days of offline
  grace, bounded by the signed `expiresAt` value.
- Lifetime grants may use a 30-day signed cache, then require a refresh. This
  permits refund and dispute enforcement without making ordinary offline use
  brittle.
- A device that has never obtained a valid grant is free while offline.
- Clock rollback, signature failure, subject mismatch, device mismatch, or an
  unsupported document version invalidates the cached grant.

The app must never begin a store mutation if entitlement refresh is required
and neither the service nor a valid cached document is available. It may keep
local editing and read-only work available.

## 9. Webhooks and reconciliation

### 9.1 Required events

Handle at least:

- `checkout.session.completed`;
- `checkout.session.async_payment_succeeded`;
- `checkout.session.async_payment_failed`;
- `customer.subscription.created`;
- `customer.subscription.updated`;
- `customer.subscription.deleted`;
- `customer.subscription.paused`;
- `customer.subscription.resumed`;
- `invoice.paid`;
- `invoice.payment_failed`;
- `charge.refunded`;
- `charge.dispute.created`;
- `charge.dispute.closed`; and
- `customer.updated` when billing contact data is mirrored.

Do not grant subscription access solely from
`customer.subscription.created`; the first invoice can still require action or
be incomplete. Reconcile the subscription and latest invoice/payment state.

### 9.2 Webhook processing

For every webhook:

1. read the untouched raw request body;
2. verify `Stripe-Signature` with the endpoint's signing secret;
3. reject invalid signatures before parsing business data;
4. insert the Stripe Event ID into an idempotency table with a unique index;
5. return success for an event already processed;
6. enqueue or execute a reconciliation for the affected Customer;
7. retrieve current Stripe objects when needed so out-of-order events converge
   to current truth;
8. update entitlement records in one database transaction;
9. record a sanitized audit entry; and
10. return `2xx` quickly enough to avoid unnecessary retries.

Webhook payloads can be retried and delivered out of order. A handler that only
applies incremental transitions is insufficient.

### 9.3 Scheduled reconciliation

Run a daily reconciliation for active and grace entitlements and provide an
admin-triggered reconciliation by user, Customer ID, Subscription ID, or
Checkout Session ID. This repairs missed webhooks and supports purchase restore.

## 10. Licensing-service API

All responses use JSON over HTTPS. Authenticated routes require a short-lived
bearer access token. Refresh tokens are rotating and device bound. Error
responses contain a stable machine code and safe display message.

### `GET /v1/billing/plans`

Returns server-authoritative display data and availability for Free, Monthly,
Annual, and Lifetime. It does not expose secret Stripe configuration.

Example response:

```json
{
  "currency": "USD",
  "plans": [
    {"id": "monthly", "amount": 499, "interval": "month", "available": true},
    {"id": "annual", "amount": 4990, "interval": "year", "available": true},
    {"id": "lifetime", "amount": 44990, "interval": null, "available": true}
  ]
}
```

### `POST /v1/auth/magic-link`

Accepts a normalized email and sends a one-use link. Always return a neutral
success response so the endpoint does not disclose whether an account exists.

### `POST /v1/auth/exchange`

Exchanges a one-use browser code and device identifier for auth tokens and the
current entitlement document.

### `POST /v1/auth/refresh`

Rotates the refresh token and returns a new access token and current signed
entitlement.

### `POST /v1/billing/promotion-code/validate`

Request:

```json
{"plan": "lifetime", "code": "LAUNCH100"}
```

Returns only display-safe facts such as validity, selected plan, resulting
subtotal/discount/total, currency, and a validation token lasting at most five
minutes. Checkout resolves eligibility again; this preview cannot reserve a
redemption or grant access.

Normalize surrounding whitespace but preserve the semantics Stripe uses for
the code. Rate limit failures by account, device, and IP to prevent code
enumeration.

### `POST /v1/billing/checkout`

Creates the allow-listed hosted Checkout Session described in section 6.3.
Require an idempotency key and bind it to user plus plan. Repeating the same
request returns the same unexpired session.

### `GET /v1/billing/checkout/{sessionId}`

Returns a sanitized state: `open`, `complete_pending`, `entitled`, `failed`, or
`expired`. The session must belong to the authenticated user.

### `GET /v1/entitlements/me`

Reconciles when stale and returns the signed effective entitlement. For a free
or expired user it returns a signed free document rather than an ambiguous
`404`.

### `POST /v1/billing/restore`

Performs the authenticated reconciliation described in section 5.3 and returns
the effective signed entitlement.

### `POST /v1/billing/portal`

Creates a short-lived Stripe Customer Portal session for the authenticated
user's mapped Customer. Return the URL; the app opens it in the browser. Never
accept an arbitrary Customer ID from the client.

### `POST /v1/stripe/webhook`

Unauthenticated by app tokens, authenticated only by verified Stripe webhook
signature. Apply section 9 exactly.

## 11. Server data model

The database technology is implementation-defined. Equivalent tables must
preserve these constraints.

### `users`

- opaque primary key;
- normalized verified email with a unique index;
- status and timestamps.

### `devices`

- opaque device ID;
- user ID;
- token generation/revocation state;
- last seen and timestamps.

### `stripe_customers`

- user ID with a unique index;
- Stripe Customer ID with a unique index;
- live/test environment marker;
- timestamps.

Never mix test and live objects in one entitlement chain.

### `entitlement_grants`

One row per subscription, lifetime purchase, or administrative grant. Include
the fields from section 7.2 and unique indexes on non-null Stripe Subscription,
PaymentIntent, and Checkout Session IDs.

### `webhook_events`

- Stripe Event ID unique index;
- event type, livemode flag, received/processed timestamps;
- processing result and sanitized error;
- retry count.

Do not retain full payment payloads longer than necessary.

### `checkout_attempts`

- internal user and idempotency key unique pair;
- selected plan, Stripe Session ID, optional Promotion Code ID;
- state, expiry, and timestamps.

### `audit_events`

Record grants, revocations, restores, admin actions, and reconciliation results.
Exclude secrets, card data, raw store credentials, and full webhook bodies.

## 12. macOS implementation boundaries

### 12.1 New SubmitKit types

Add platform-neutral types to `SubmitKit`, with no SwiftUI dependency:

- `AccessCapability`;
- `AccessPlan`;
- `EntitlementStatus`;
- `SignedEntitlementDocument`;
- `EntitlementVerifier`;
- `LicensingClient` protocol and HTTP implementation;
- Keychain-backed credential/document storage abstraction; and
- typed billing and licensing errors.

Keep Stripe object decoding on the server. The macOS client needs licensing
responses, not the full Stripe API model.

### 12.2 AppState

`AppState` owns observable billing presentation state and delegates policy to a
single access controller. Suggested state:

```text
account: signedOut | signingIn | signedIn(email)
entitlement: loading | free | active(plan) | grace(plan, until) | unavailable
upgradeSheet: closed | open(trigger)
billingOperation: idle | validatingCode | openingCheckout | confirming | failed
```

Do not add repeated `isPaid` booleans to views. All checks call one centralized
API such as `access.can(.rawYAML)` or `try await access.authorize(.storeUpload)`.

When a grant expires or is revoked while YAML is visible, close the panel,
clear its in-memory raw text, and return to the structured editor. Never discard
the parsed manifest.

### 12.3 Raw YAML gates

The header control in `Sources/SuperSubmitter/Shell/RootView.swift` must remain
visible but display a lock and paid label for free users. Selecting it opens the
upgrade sheet and must not call `loadYAML`, populate `yamlText`, or show
`YAMLEditor`.

Also gate every non-visual entry to raw YAML, including menu commands, keyboard
shortcuts, accessibility actions, context menus, reveal/export actions, and
state restoration. A view-only gate is insufficient.

### 12.4 Apply gates

In the Plan and Submit flows:

- free users may read stores and generate plans;
- dry run remains available;
- switching `dryRun` off opens the upgrade sheet or explains the lock;
- `AppState.canApply` must require `.storeWrite` whenever `dryRun == false`;
- `AppState.startRun` must authorize again before creating a non-dry `Runner`;
  and
- the lowest practical mutation boundary in `SubmitKit.Runner` must reject a
  non-dry execution without a current authorization context.

The last check prevents an alternate UI entry or stale screen state from
starting writes.

### 12.5 Build-upload gates

Local project selection, preflight, build, archive, artifact inspection, and
conflict reads remain free. Gate only the remote upload transition.

In `BuildFlowRun.startUpload`, perform a fresh `.storeUpload` authorization
before changing the run to `uploading` and again before the first remote upload
call if the build/confirmation process took long enough to cross
`refreshAfter`. If authorization fails, retain the artifact and return the run
to `needsUploadConfirmation` with an upgrade or reconnect action.

Both Apple `xcodebuild -exportArchive` upload and Google
`UploadService.uploadGoogleBundle` paths require the same centralized gate.

### 12.6 Release gates

Gate all `ReleaseClient` mutation entry points behind `.storeRelease`, including:

- Apple review submission;
- Apple submission cancellation;
- release of an approved Apple version;
- Google track release commit; and
- Google staged-rollout halt.

Check once when the user opens the release confirmation and again immediately
before the irreversible network call. If access changed, dismiss or disable the
confirmation and preserve store state.

### 12.7 Provider writes

RevenueCat and Adapty are not app stores. Under the stated product rule, their
read and write features remain free. If a single run contains both provider
writes and Apple/Google writes, a free user may run only a provider-only plan;
the UI must not silently execute a partial mixed plan. Version 1 may simplify
this by keeping the complete mixed Apply locked while clearly explaining why.

### 12.8 Analytics

Allowed events include upgrade-sheet shown, plan selected, checkout opened,
checkout confirmed, entitlement restored, and gate encountered. Do not send:

- email address;
- promotion-code text;
- auth or entitlement tokens;
- Stripe Customer, Session, PaymentIntent, or Subscription IDs;
- store credentials;
- YAML contents; or
- exact local file paths.

Payment and entitlement correctness must never depend on PostHog delivery.

## 13. User-interface states and messages

Use direct messages that say what remains available.

| Situation | Required behavior |
|---|---|
| Free user selects YAML | Keep raw YAML hidden; open pricing sheet; say “Raw YAML is included with paid access. You can keep editing every field here for free.” |
| Free user selects Apply | Preserve plan; open pricing sheet; say “Store writes require paid access. Read-only planning and dry runs remain free.” |
| Free user reaches upload | Preserve artifact; open pricing sheet; say “Your build is ready. Upgrade or apply a promotion code to upload it.” |
| Free user selects Release | Preserve draft; open pricing sheet; say “Releasing to review requires paid access.” |
| Invalid code | Inline “This code is invalid, expired, or not available for the selected plan.” |
| Valid partial code | Show original price, discount, resulting total, currency, and checkout action |
| Valid 100% code | Show `$0` and “Complete checkout to activate access”; never unlock immediately |
| Checkout canceled | Return to pricing without an error or lost work |
| Confirmation delayed | Show pending state and Check again; prevent duplicate checkout |
| Subscription past due | Keep access during grace; banner links to Manage billing |
| Entitlement expired | Return to free access without closing the app or losing local edits |
| Service unavailable with valid cache | Continue until signed expiry and show a non-blocking status |
| Service unavailable without valid cache | Keep free/local/read-only work; block mutations with Retry |

The UI must not call a user “unlicensed” or imply their local project is locked.

## 14. Customer Portal and plan changes

Settings must include **Plan & billing** with:

- signed-in email;
- current plan and status;
- renewal or expiration date when applicable;
- cancellation-at-period-end notice;
- **Manage billing**;
- **Restore access**;
- **Sign out**; and
- support link.

The service creates a new short-lived Customer Portal session for each
**Manage billing** action. Configure the portal so customers can update payment
methods, see invoices, cancel subscriptions, and switch monthly/annual plans.
Do not permit quantity changes.

If plan switching is enabled, define proration behavior in Stripe and state it
in the UI before launch. Lifetime is not a subscription and must not appear as
a normal portal switch target.

Signing out removes local auth tokens and signed entitlement documents, closes
raw YAML, and immediately returns the app to free access. It does not delete
local app projects, manifests, assets, builds, or store credentials.

## 15. Errors, recovery, and support

Use stable error codes such as:

| Code | Meaning | Client response |
|---|---|---|
| `authentication_required` | No valid account token | Open sign-in |
| `promotion_code_invalid` | Invalid/ineligible/expired code | Inline field error |
| `plan_unavailable` | Server has disabled the Price | Refresh plans |
| `already_subscribed` | Duplicate recurring purchase attempt | Open portal |
| `checkout_pending` | Stripe has not finalized payment | Poll/check again |
| `entitlement_refresh_required` | Cached grant cannot authorize mutation | Refresh before action |
| `entitlement_expired` | No paid access remains | Return to free tier |
| `billing_service_unavailable` | Temporary service failure | Use valid cache or retry |
| `environment_mismatch` | Test/live client-server mismatch | Fail closed and report build issue |

Every pending or failed checkout support screen should offer a copyable support
reference generated by the licensing service. It must not expose secrets or
full Stripe IDs.

## 16. Security and privacy requirements

- All licensing traffic uses HTTPS with normal platform trust validation.
- Store auth tokens, refresh tokens, device IDs, and signed entitlement caches
  in Keychain with appropriate accessibility for an unlocked user session.
- Rotate refresh tokens; revoke a device on suspicious reuse.
- Require recent authorization for account-sensitive server actions.
- Rate limit sign-in, code validation, checkout creation, restore, and portal
  session creation.
- Validate every plan, Price, mode, return URL, and customer association on the
  server.
- Use Stripe idempotency keys for Checkout creation in addition to local
  database uniqueness.
- Verify webhook signatures against the raw body.
- Pin the Stripe API version server-side.
- Redact Stripe IDs and billing data from routine logs and analytics.
- Do not store card numbers, CVC, payment-method payloads, or raw Stripe secret
  responses in the client.
- Do not place billing state, email, or Stripe IDs in `store.yaml` or project
  repositories.
- Document collected account and billing data in the privacy policy and provide
  account/support deletion handling.
- Ensure Terms, Privacy, refund, contact, and tax disclosures are visible before
  checkout.

## 17. Testing requirements

### 17.1 Unit tests

Test in `SubmitKitTests`:

- signature verification, altered payload, wrong key, expiry, future issue
  time, device mismatch, and clock rollback;
- capability resolution for free, monthly, annual, lifetime, grace, expired,
  revoked, and overlapping grants;
- raw-YAML, write, upload, and release gates;
- fail-closed behavior at mutation boundaries;
- Keychain abstraction with an in-memory test store; and
- error decoding without leakage of server details.

### 17.2 Server tests

- allow-listed plan-to-Price mapping and amount assertions;
- monthly/annual `subscription` mode and lifetime `payment` mode;
- valid, invalid, expired, restricted, exhausted, partial, and 100% Promotion
  Codes;
- first-time-customer and product restrictions;
- idempotent checkout creation;
- forged customer, session, plan, return URL, and metadata rejection;
- signature verification against the raw body;
- duplicate and out-of-order webhooks;
- incomplete first invoice, renewal, failed renewal, recovery, cancellation,
  pause, resume, refund, and dispute;
- restore and overlapping lifetime/subscription precedence; and
- separation of test and live objects.

### 17.3 Integration tests

Use Stripe sandboxes/test mode and Stripe CLI webhook forwarding. Never run
automated tests against live Prices.

Use Stripe Test Clocks to cover:

- initial monthly and annual purchase;
- successful renewal;
- failed payment into grace;
- payment recovery during grace;
- cancellation at period end; and
- expiration after the final entitled period.

Complete both paid and no-cost Checkout Sessions and confirm that the app waits
for server entitlement rather than trusting browser return.

### 17.4 UI tests

- free users retain every allowed workflow;
- locked YAML never loads raw text;
- locked Apply, upload, and Release preserve work and open the correct sheet;
- promotion field is keyboard and VoiceOver accessible;
- plan changes revalidate the code;
- checkout cancellation preserves app state;
- delayed confirmation cannot create an accidental duplicate session;
- paid access unlocks each capability;
- expiration while YAML is open closes and clears the raw panel; and
- signing out removes access without deleting projects.

### 17.5 Live-mode smoke test

Before launch, use one controlled live Promotion Code or low-risk internal
purchase, verify the live webhook endpoint and portal, then refund/revoke it in
accordance with policy. Do not use the customer-facing production codes for
routine QA.

## 18. Rollout plan

1. Create test Products, Prices, coupons, and Promotion Codes.
2. Implement the licensing service, database, auth, signed documents, webhooks,
   reconciliation, and operational alerts.
3. Add the client types and access controller.
4. Add Settings billing UI and the centralized pricing sheet.
5. Gate raw YAML at state and UI boundaries.
6. Gate apply, upload, and release at both AppState and SubmitKit/service
   mutation boundaries.
7. Add Customer Portal and restore flows.
8. Complete test-mode automated and manual scenarios.
9. Publish Terms, Privacy, refund, and support pages.
10. Configure live Stripe Products, Prices, Promotion Codes, portal, tax, and
    webhook endpoint.
11. Inject live client/server settings into the notarized Release build.
12. Run the controlled live smoke test.
13. Roll out first to a small direct-download cohort with entitlement and
    webhook monitoring, then expand.

Do not enable client gates before the production licensing service, restore
path, and webhook reconciliation are operational. Otherwise legitimate users
can pay and remain locked out.

## 19. Operational monitoring

Alert on:

- webhook signature failures above a low threshold;
- webhook processing failures or queue age;
- reconciliation mismatches;
- Checkout completed without entitlement after five minutes;
- repeated entitlement-signing failures;
- test/live environment mismatches;
- unusual Promotion Code validation or redemption volume; and
- an increase in paid users receiving authorization failures.

Provide an internal support view or command that can safely inspect a user,
mapped Stripe Customer, effective grants, recent webhook outcomes, and device
tokens. Administrative grant/revoke operations require an actor, reason, and
immutable audit entry.

## 20. Acceptance criteria

The integration is complete only when all of the following are true:

- Stripe holds the three correctly configured USD Prices: $4.99 monthly,
  $49.90 annual, and $449.90 lifetime.
- The supplied live publishable key is build-configured, and no Stripe secret or
  webhook secret exists in the client or repository.
- A user can use the structured app, local build tools, validation, store reads,
  planning, and dry run without an account or payment.
- A free user cannot obtain raw YAML through any app UI or restored state.
- A free user cannot cause any Apple or Google write, upload, submission, or
  release from any entry point.
- The pricing UI always exposes a Promotion Code field.
- Invalid and restricted codes fail safely; partial codes charge the correct
  remainder; 100% codes require a completed no-cost Checkout Session.
- Paid monthly, annual, lifetime, and complimentary users receive the same four
  capabilities.
- Client access changes only after a verified server entitlement, never solely
  after a browser redirect.
- Subscription renewal, failure, grace, cancellation, refund, dispute, restore,
  duplicate webhook, and out-of-order webhook scenarios converge correctly.
- Existing confirmations and submission-safety rules remain intact after
  unlocking.
- Billing management and purchase restore work on a second device after verified
  sign-in.
- The app behaves predictably offline according to signed expiry rules.
- Unit, server, integration, and UI tests cover every gate and state transition.
- Test and live Stripe environments cannot be mixed.
- Production monitoring and an audited support/reconciliation path are in
  place.

## 21. Explicitly out of scope

- Mac App Store distribution or StoreKit in-app purchase;
- iOS, Android, or web versions of Super Submitter;
- native collection of card data;
- seat-based/team billing;
- metered usage;
- cryptocurrency payment;
- a custom promotion-code administration UI; use Stripe Dashboard initially;
- encrypted DRM for `store.yaml` files on disk;
- styling or changing the user's own app-store monetization; and
- bypassing existing apply/release confirmations for paid users.

## 22. Implementation references

- [Stripe API keys and secret-key safety](https://docs.stripe.com/keys-best-practices)
- [Create a Checkout Session](https://docs.stripe.com/api/checkout/sessions/create)
- [Checkout discounts and Promotion Codes](https://docs.stripe.com/payments/checkout/discounts)
- [No-cost Checkout orders](https://docs.stripe.com/payments/checkout/no-cost-orders)
- [Subscription webhooks](https://docs.stripe.com/billing/subscriptions/webhooks)
- [Webhook signature verification](https://docs.stripe.com/webhooks)
- [Customer Portal integration](https://docs.stripe.com/customer-management/integrate-customer-portal)
- [Stripe Tax with Checkout](https://docs.stripe.com/tax/checkout)
- [Stripe Test Clocks](https://docs.stripe.com/api/test_clocks)
