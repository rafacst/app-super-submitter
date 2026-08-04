# Prompt: build the Super Submitter licensing service

Copy everything under the line into a fresh agent session. The agent needs
access to the Cloudflare account that holds the `rafacst.me` zone, and a
terminal with `wrangler`.

---

You are building a licensing service on Cloudflare Workers. It sells access to
**Super Submitter**, a direct-download macOS app, through Stripe. The macOS
client is already written, shipped, and unchangeable from your side. Your job is
to serve the contract it already speaks, exactly.

Read this whole brief before you write anything. The contract in section 4 is
not a suggestion. A client that cannot verify your entitlement document refuses
every store write for a paying customer.

The values you do not have to ask for:

| Name | Value |
|---|---|
| Supabase project URL | `https://cvrvyxcjddtpsyfxieuf.supabase.co` |
| Supabase JWKS | `https://cvrvyxcjddtpsyfxieuf.supabase.co/auth/v1/.well-known/jwks.json` |
| Expected JWT issuer | `https://cvrvyxcjddtpsyfxieuf.supabase.co/auth/v1` |
| Support email | `support@rafacst.me` |
| Live host | `super-submitter.rafacst.me` |
| Test host | `super-submitter-test.rafacst.me` |

The Supabase publishable key `sb_publishable_sI-T324LV-ymezJ0j9uecA_XZ2Dyep3`
belongs to the macOS client, not to this Worker. Do not put it in the Worker
configuration. The Worker needs the service role key only, and the owner sets
that as a secret.

## 1. What the product sells

Super Submitter prepares an iOS, macOS, and Android app for the App Store and
Google Play from one YAML file. It is free to configure, validate, build
locally, read both stores, plan, and dry run. Paid access adds three things:

- writing a non-dry apply to App Store Connect or Google Play,
- uploading a build to a store, and
- releasing to review, cancelling a submission, releasing an approved version,
  committing a Google track, and halting a rollout.

Three plans, all USD, all fixed Prices:

| Plan | Stripe mode | Amount (minor units) | Lookup key |
|---|---|---:|---|
| Monthly | `subscription` | 499 | `super_submitter_monthly_usd` |
| Annual | `subscription` | 4990 | `super_submitter_annual_usd` |
| Lifetime | `payment` | 44990 | `super_submitter_lifetime_usd` |

There is no trial. There is no higher tier. All paid and complimentary grants
carry the same three capabilities.

## 2. Architecture

```
Super Submitter.app
  |  Authorization: Bearer <Supabase access token>
  v
Cloudflare Worker  super-submitter.rafacst.me       (Stripe live mode)
                   super-submitter-test.rafacst.me  (Stripe test mode)
  |-- Supabase Postgres      licensing tables, via the REST API
  |-- Supabase Auth JWKS     token verification
  `-- Stripe REST API        secret key, and verified webhooks
```

Identity comes from **Supabase Auth**. The user signs up with an email address
in the macOS app, and Stripe attributes the payment to that same address. The
Worker never invents its own account system and never trusts an email that
arrives in a request body.

### Free tier, and what it forbids

Everything must run inside the Cloudflare free plan. This is a hard constraint.

- **Workers free**: 100,000 requests per day, 10 ms CPU per invocation. Signing
  an Ed25519 document and verifying a JWT both fit easily. Network waiting is
  not CPU, so Stripe and Supabase round trips are fine.
- **No Queues.** Webhook work happens inside the request. Return `200` quickly,
  then finish reconciliation in `ctx.waitUntil(...)`.
- **Cron Triggers are available.** Use one daily trigger for reconciliation.
- **Do not add Durable Objects, Queues, KV write loops, or any paid add-on.**
  Supabase Postgres is your only durable store.
- Two Workers, one per environment, each on its own custom domain in the
  `rafacst.me` zone.

### Libraries

Prefer plain `fetch` against the Stripe REST API over the Stripe Node SDK. It
keeps the bundle small and avoids Node compatibility flags. If you do use the
SDK, you must use `Stripe.createFetchHttpClient()` and
`constructEventAsync(...)`; the synchronous `constructEvent` uses Node crypto
and fails in a Worker.

For Supabase, call the PostgREST endpoint with `fetch` and the service role key.
Do not pull in `supabase-js` for six table operations.

## 3. Configuration

### Secrets, set by the account owner with `wrangler secret put`

Never print these, never commit them, never log them. Tell the owner the exact
commands to run and let them run them.

| Secret | Both environments |
|---|---|
| `SUPABASE_SERVICE_ROLE_KEY` | Same project, both Workers |
| `STRIPE_SECRET_KEY` | `sk_test_` / `rk_test_` for test, `sk_live_` / `rk_live_` for live |
| `STRIPE_WEBHOOK_SECRET` | `whsec_`, one per registered endpoint |
| `ENTITLEMENT_SIGNING_KEY` | You generate this; see section 4.2 |

### Plain variables in `wrangler.toml`

| Variable | Value |
|---|---|
| `SUPABASE_URL` | `https://cvrvyxcjddtpsyfxieuf.supabase.co` |
| `SUPPORT_EMAIL` | `support@rafacst.me` |
| `ENTITLEMENT_KEY_ID` | `entitlement-2026-01` |
| `STRIPE_MODE` | `test` or `live`, one per environment |
| `PRICE_MONTHLY`, `PRICE_ANNUAL`, `PRICE_LIFETIME` | You create these; see section 8 |

`STRIPE_MODE` exists so the Worker can refuse a mismatch. If a request would
mix a test Customer with a live Price, fail with `environment_mismatch` rather
than creating the object.

Pin the Stripe API version in every request header. Choose the current version,
write it in `wrangler.toml`, and upgrade it deliberately.

## 4. The contract the macOS client already speaks

This section is the authority. The client is compiled and will not adapt.

### 4.1 Authentication

Every route except `GET /v1/billing/plans` requires
`Authorization: Bearer <token>`, where the token is a Supabase Auth access
token.

Verify it against the project JWKS at

```
https://cvrvyxcjddtpsyfxieuf.supabase.co/auth/v1/.well-known/jwks.json
```

Cache the JWKS in memory for the isolate's lifetime and refetch on an unknown
`kid`. Check the signature, `exp`, and that `iss` is
`https://cvrvyxcjddtpsyfxieuf.supabase.co/auth/v1`. The verified `sub` is the
account. The verified `email` is contact data.

Fetch that JWKS URL as your first action, before you write any code. It tells
you whether the project uses asymmetric keys.

If that project still uses the legacy shared HS256 secret instead of asymmetric
keys, say so and ask the owner to set a `SUPABASE_JWT_SECRET` secret. Do not
guess and do not skip verification.

A missing, expired, or invalid token is
`401 {"code":"authentication_required","message":"..."}`.

### 4.2 The entitlement document

Two routes return a signed document. Get this format exactly right.

```json
{
  "payload": "<base64url of the entitlement JSON, no padding>",
  "signature": "<base64url of the Ed25519 signature, no padding>",
  "keyId": "entitlement-2026-01"
}
```

**The signature covers the ASCII bytes of the `payload` string itself.** Do not
decode it, do not re-encode the JSON, do not canonicalise. Sign
`new TextEncoder().encode(payloadString)`. Two JSON encoders disagree about key
order and timestamp precision, and a signature that depends on either one breaks
the day a library is upgraded.

The decoded payload:

```json
{
  "version": 1,
  "subject": "<the Supabase auth user id>",
  "email": "developer@example.com",
  "status": "active",
  "plan": "annual",
  "capabilities": ["store_write", "store_upload", "store_release"],
  "issuedAt": "2026-08-04T12:00:00.000Z",
  "refreshAfter": "2026-08-05T00:00:00.000Z",
  "expiresAt": "2026-08-11T12:00:00.000Z"
}
```

Optional: `currentPeriodEnd`, `cancelAtPeriodEnd`. Timestamps are ISO 8601, with
or without fractional seconds; `toISOString()` is correct.

| Field | Allowed values |
|---|---|
| `status` | `free`, `active`, `grace`, `expired`, `revoked` |
| `plan` | `free`, `monthly`, `annual`, `lifetime`, `complimentary` |
| `capabilities` | any of `store_write`, `store_upload`, `store_release` |

Rules the client enforces. Break one and paying customers get locked out:

- A free, expired, or revoked account receives a **signed document with an empty
  `capabilities` array**, never a `404` and never an unsigned body. The client
  treats an unsigned answer as a service failure and keeps its old document.
- Every paid or complimentary grant carries all three capabilities. There is no
  partial grant.
- `expiresAt` is the hard offline limit. Use **7 days** for a subscription and
  **30 days** for a lifetime grant. Longer weakens refund enforcement; shorter
  makes ordinary offline work brittle.
- `refreshAfter` is when the client asks again. Use **12 hours**.
- A document issued more than 5 minutes ahead of the client's clock is refused.
  Do not backdate or postdate `issuedAt`.
- `subject` must stay stable for an account forever. A change reads as a
  replayed document.

#### Generating the signing key

Generate an Ed25519 key pair with WebCrypto or `openssl`. Store the private key
as a secret. **Export the public key in `raw` form: exactly 32 bytes, then
base64.** The client parses it with
`Curve25519.Signing.PublicKey(rawRepresentation:)`. An SPKI export is 44 bytes
and will fail. Verify the length before you hand it over.

Give the owner the public key in this exact shape, because it becomes a GitHub
Actions secret named `ENTITLEMENT_PUBLIC_KEYS` in the macOS app repository:

```
entitlement-2026-01=<base64 of the 32 raw bytes>
```

The format is a comma separated list, so a future rotation ships as a second
entry and documents signed by the retired key still verify until they expire.

### 4.3 Routes

All JSON over HTTPS. Any non-2xx must carry
`{"code": "...", "message": "..."}`. The client shows `message` verbatim, so it
must already be safe to read, must name what still works, and **must contain no
em dash**.

Three codes get special client handling. Every other code is shown with its
message.

| Code | Client behaviour |
|---|---|
| `authentication_required` | Treated as signed out, free access |
| `entitlement_expired` | Returns to free access |
| `entitlement_refresh_required` | Refuses the write, offers a retry |

Other codes the client expects to see: `promotion_code_invalid`,
`plan_unavailable`, `already_subscribed`, `checkout_pending`,
`billing_service_unavailable`, `environment_mismatch`.

#### `GET /v1/billing/plans`

Unauthenticated. Amounts in minor units.

```json
{
  "currency": "USD",
  "plans": [
    {"id": "monthly",  "amount": 499,   "interval": "month", "available": true},
    {"id": "annual",   "amount": 4990,  "interval": "year",  "available": true},
    {"id": "lifetime", "amount": 44990, "interval": null,    "available": true}
  ]
}
```

Only `id` travels back from the client. The server maps it to an allow-listed
Price. A modified client must never be able to buy an arbitrary Price.

#### `GET /v1/entitlements/me`

Reconcile if the stored entitlement is stale, then return the signed document.

#### `POST /v1/billing/promotion-code/validate`

Request `{"plan": "lifetime", "code": "LAUNCH100"}`. Response:

```json
{"valid": true, "plan": "lifetime", "subtotal": 44990, "discount": 44990,
 "total": 0, "currency": "USD", "message": null}
```

Display-safe facts only. Never return the Stripe coupon object, the redemption
count, or the customer restrictions. Trim surrounding whitespace and preserve
everything else about the code. Rate limit hard by account and by IP: this is a
code enumeration surface.

An invalid code is a `200` with `"valid": false`, or a `400` with
`promotion_code_invalid`. Either is handled; pick one and be consistent.

#### `POST /v1/billing/checkout`

Request:
`{"plan": "annual", "promotionCode": "LAUNCH100", "idempotencyKey": "<uuid>"}`.
`promotionCode` is absent when the field was empty.

Response:

```json
{"sessionId": "cs_...", "url": "https://checkout.stripe.com/...",
 "expiresAt": "2026-08-04T13:00:00.000Z"}
```

The server must:

1. verify the account and apply a rate limit;
2. map `plan` to the allow-listed Price ID and mode;
3. create or reuse the account's Stripe Customer, and pass it to Checkout;
4. resolve the Promotion Code server side when one was supplied;
5. create a hosted Checkout Session, quantity 1;
6. use `subscription` mode for monthly and annual, `payment` mode for lifetime;
7. set `client_reference_id` to an opaque value that carries no personal data;
8. put the Supabase user id and the plan key in Checkout metadata;
9. set success and cancel URLs owned by this Worker;
10. use a Stripe idempotency key derived from the account plus the client key;
11. return only the session id, the hosted URL, and the expiry.

The client reuses one idempotency key per plan until a checkout completes, so
repeating the request must return the same unexpired session and never a second
one.

If the account already holds an active subscription and asks for another,
return `409 already_subscribed` with a Customer Portal URL in the message. A
lifetime holder is offered nothing further; direct them to support.

#### `POST /v1/billing/restore`

Reconcile the authenticated account against Stripe and return the effective
signed document. Look up the Customer through your own stored mapping. **Never
search Stripe globally by an unverified email.** An orphaned customer is a
support workflow with an audit record, not a lookup.

#### `POST /v1/billing/portal`

Return `{"url": "https://billing.stripe.com/..."}` for a short-lived Customer
Portal session for this account's mapped Customer. Never accept a Customer ID
from the client.

#### `POST /v1/stripe/webhook`

Section 6.

#### The browser pages

The Worker also serves, as plain HTML with no external assets:

- `GET /checkout/success` says that payment is being confirmed and that the
  user should return to Super Submitter. It grants nothing and shows no token.
  The macOS app polls the service when its window becomes active; there is no
  deep link and no URL scheme.
- `GET /checkout/cancel` says nothing was charged and to return to the app.

Legal pages are deliberately out of scope for now. Note in your handover that
Stripe Checkout still needs a support contact and a privacy policy URL set in
the Dashboard branding settings before live mode is used.

## 5. Supabase schema

Create these tables with SQL migrations you commit to the repository. Enable row
level security on every one and grant no anon access. The Worker uses the
service role key, so RLS keeps a leaked publishable key harmless.

### `stripe_customers`
- `user_id` uuid, unique, references the auth user
- `stripe_customer_id` text, unique
- `livemode` boolean
- timestamps

Never mix a test object and a live object in one entitlement chain. Enforce it
with a unique index on `(user_id, livemode)`.

### `entitlement_grants`
One row per subscription, per lifetime purchase, and per administrative grant.

- `user_id`, `status`, `plan`, `source`
- `stripe_customer_id`, `stripe_subscription_id`, `stripe_payment_intent_id`,
  `stripe_checkout_session_id`, `stripe_price_id`, `promotion_code_id`
- `current_period_end`, `cancel_at_period_end`, `grace_until`
- `revocation_reason`, timestamps

Unique index on each non-null Stripe subscription, payment intent, and checkout
session id.

### `webhook_events`
- `stripe_event_id` text, **unique index**
- `type`, `livemode`, `received_at`, `processed_at`
- `result`, `sanitized_error`, `retry_count`

### `checkout_attempts`
- unique pair of `(user_id, idempotency_key)`
- `plan`, `stripe_session_id`, `promotion_code_id`, `state`, `expires_at`

### `audit_events`
Grants, revocations, restores, administrative actions, and reconciliation
results. No secrets, no card data, no full webhook bodies.

## 6. Webhooks

Register one endpoint per environment. Subscribe to exactly these:

`checkout.session.completed`, `checkout.session.async_payment_succeeded`,
`checkout.session.async_payment_failed`, `customer.subscription.created`,
`customer.subscription.updated`, `customer.subscription.deleted`,
`customer.subscription.paused`, `customer.subscription.resumed`,
`invoice.paid`, `invoice.payment_failed`, `charge.refunded`,
`charge.dispute.created`, `charge.dispute.closed`, `customer.updated`.

For every delivery:

1. read the **untouched raw request body**, before any parsing;
2. verify `Stripe-Signature` against that raw body with the endpoint secret;
3. reject an invalid signature before you read any business field;
4. insert the Stripe Event ID into `webhook_events` with its unique index;
5. return success immediately for an event already recorded;
6. reconcile the affected Customer from **current Stripe objects**, not from the
   delta in the payload;
7. write the entitlement change in one transaction;
8. record a sanitized audit entry;
9. return `2xx` fast, and use `ctx.waitUntil` for the rest.

Deliveries retry and arrive out of order. A handler that applies incremental
transitions is wrong and will corrupt state. Always converge on current truth.

Do **not** grant subscription access from `customer.subscription.created` alone.
The first invoice can still be incomplete or require action. Read the
subscription and its latest invoice together.

## 7. Entitlement rules

### Precedence, highest valid grant wins

1. active lifetime
2. active subscription
3. temporary grace
4. free

An expired subscription must never override a lifetime purchase. A refunded
lifetime order must never remove access while a valid subscription exists.

### Subscription state

| Stripe condition | Effective status |
|---|---|
| `active` with a paid invoice | `active` |
| cancellation scheduled at period end | `active` through the period end, `cancelAtPeriodEnd` true |
| `past_due` | `grace`, for up to 7 days, then `expired` |
| `unpaid`, `paused`, or ended | `expired` |
| deleted after the period end | `expired` |

### Lifetime state

Active only when the Checkout Session is complete **and** its PaymentIntent is
paid, or when Stripe reports a completed no-cost order. An asynchronous payment
method stays pending until its success event.

- a full refund revokes the grant
- a partial refund does not revoke it, and raises an admin review flag
- a lost dispute revokes it
- a won or withdrawn dispute restores it after reconciliation

### Scheduled reconciliation

One daily Cron Trigger reconciles every `active` and `grace` entitlement. Add an
admin-triggered reconciliation by user, Customer ID, Subscription ID, or
Checkout Session ID, behind a separate admin secret. This repairs missed
webhooks and is what makes restore reliable.

## 8. Stripe Dashboard work you perform

Do this in **test mode first**, through the API, and record every ID:

1. Create one product named **Super Submitter**.
2. Create the three immutable USD Prices from section 1, with the lookup keys
   given there.
3. Write the Price IDs into the test `wrangler.toml`.
4. Register the test webhook endpoint at
   `https://super-submitter-test.rafacst.me/v1/stripe/webhook`, subscribed to
   the events in section 6. Give the owner the `wrangler secret put` command for
   the resulting `whsec_`.
5. Configure the Customer Portal: payment method updates, invoice history,
   cancellation, and monthly to annual switching. **Disable quantity changes.**
   Lifetime is not a subscription and must not appear as a portal switch target.
6. Leave `automatic_tax` **off** until the owner has registered for tax and
   enabled Stripe Tax. Say so in the handover.
7. Create one 100 percent coupon restricted to the lifetime product, and one
   customer-facing Promotion Code from it, for complimentary access.

Then repeat every step in live mode, against
`https://super-submitter.rafacst.me/v1/stripe/webhook`. Prices are immutable for
entitlement mapping: to change an amount later, create a new Price, update the
configuration, and keep the old mapping so existing subscriptions still resolve.

## 9. Security requirements

- Verify webhook signatures against the raw body, before parsing.
- Pin the Stripe API version.
- Validate every plan, Price, mode, return URL, and customer association on the
  server. Trust nothing in a request body except the verified JWT.
- Use Stripe idempotency keys on Checkout creation, in addition to the database
  uniqueness constraint.
- Rate limit sign-in adjacent routes, code validation, checkout creation,
  restore, and portal creation.
- Redact Stripe IDs and billing data from routine logs.
- Store no card number, no CVC, and no payment method payload.
- Every error message you return is shown to a user. It must contain no Stripe
  ID, no internal detail, and no em dash.

## 10. Tests

Write them, and make them pass before you hand over.

- Plan to Price mapping, with the amounts asserted.
- `subscription` mode for monthly and annual, `payment` mode for lifetime.
- Promotion codes: valid, invalid, expired, restricted, exhausted, partial, and
  100 percent.
- Idempotent checkout creation: the same key returns the same session.
- Rejection of a forged customer, session, plan, return URL, and metadata.
- Signature verification against the raw body, including a tampered body.
- Duplicate and out-of-order webhook deliveries converging on the same state.
- Incomplete first invoice, renewal, failed renewal, recovery during grace,
  cancellation, pause, resume, refund, and dispute.
- Restore, and overlapping lifetime and subscription precedence.
- Test and live objects never mixing.
- **A round trip of the entitlement document**: sign one, then verify the
  signature against the raw 32-byte public key, and assert the payload decodes.

Use Stripe test mode and `stripe listen` for webhook forwarding. Use Stripe Test
Clocks for the initial purchase, a successful renewal, a failed payment into
grace, recovery during grace, cancellation at period end, and expiry after the
final entitled period. Never run an automated test against a live Price.

## 11. Deployment

- Two Workers in one repository, one `wrangler.toml` with two environments.
- Custom domains: `super-submitter.rafacst.me` and
  `super-submitter-test.rafacst.me`, both in the `rafacst.me` zone.
- The owner runs every `wrangler secret put`. You write the exact commands, you
  do not ask for the values, and you never print one.
- Commit the SQL migrations, the `wrangler.toml`, and a `README.md` that lists
  every secret, every variable, and how to roll the signing key.

## 12. Hand back to me

When you are done, report these, and nothing sensitive:

1. The two deployed URLs, and a `curl` of `GET /v1/billing/plans` on each.
2. The **entitlement public key**, in the exact form
   `entitlement-2026-01=<base64 of 32 raw bytes>`, with the byte length stated.
   It becomes the `ENTITLEMENT_PUBLIC_KEYS` GitHub Actions secret in the macOS
   app repository, alongside `LICENSING_BASE_URL`.
3. The test and live Price IDs.
4. What is still switched off: Stripe Tax, the legal pages, and anything else.
5. The result of a real test-mode purchase run end to end, including the webhook
   that granted the entitlement and the document that
   `GET /v1/entitlements/me` then returned.

## 13. One thing that must not go wrong

Do not tell the owner to point a Release build of the macOS app at the live URL
until the service, the webhook reconciliation, and the restore path all work
against real Stripe events. The client gate is already live in the app. A gate
in front of a service that is not ready locks out people who have paid, and they
have no way to fix it themselves.
