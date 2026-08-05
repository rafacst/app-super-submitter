# The licensing service contract

The macOS client is implemented. This file is what the service must provide for
it to work. `stripe-spec.md` holds the product rules, the Stripe setup, the
webhook handling, and the server data model. This file holds only the wire
contract the shipped client already speaks.

The client is in `Sources/SubmitKit/Access/`. `HTTPLicensingClient` is the type
that makes these calls.

## Configuration the client build carries

| Setting | Where | Value |
|---|---|---|
| `SSLicensingBaseURL` | Info.plist, from the `LICENSING_BASE_URL` build setting | The HTTPS licensing service base |
| `SSEntitlementPublicKeys` | Info.plist, from `ENTITLEMENT_PUBLIC_KEYS` | `keyId=base64,keyId=base64` |
| `SSSupabaseURL` | Info.plist, from `SUPABASE_URL` | The Supabase project URL |
| `SSSupabasePublishableKey` | Info.plist, from `SUPABASE_PUBLISHABLE_KEY` | The public app key, never a service role key |

`.github/workflows/release.yml` passes both from repository secrets. A build
with neither refuses every store write in Release and allows them in Debug with
a line on standard error. The environment variables of the same names override
the Info.plist, so a Debug build can point at a local service.

No `sk_`, `rk_`, `pk_`, or `whsec_` value belongs in the app bundle. Hosted
Stripe Checkout needs no publishable key in the client.

## Authentication

Every route except `GET /v1/billing/plans` takes `Authorization: Bearer <token>`.
The token is a Supabase Auth access token. The service verifies it against the
project JWKS, and the verified `sub` is the account. There is no separate
Super Submitter account system.

The app signs in through Supabase Auth, keeps the refreshable session in the
Keychain, and passes short-lived access tokens to `AccessController`.

## The entitlement document

`GET /v1/entitlements/me` and `POST /v1/billing/restore` both return:

```json
{
  "payload": "<base64url of the entitlement JSON>",
  "signature": "<base64url of the Ed25519 signature>",
  "keyId": "entitlement-2026-01"
}
```

**The signature covers the ASCII bytes of the `payload` string itself**, not a
re-encoding of the decoded JSON. Sign `Buffer.from(payload, "ascii")`. Two JSON
encoders disagree about key order and about how many digits a timestamp carries,
and a signature that depends on either one breaks the day a library is upgraded.

base64url, no padding, on both fields.

The decoded payload:

```json
{
  "version": 1,
  "subject": "usr_opaque",
  "email": "developer@example.com",
  "status": "active",
  "plan": "annual",
  "capabilities": ["store_write", "store_upload", "store_release"],
  "issuedAt": "2026-08-04T12:00:00Z",
  "refreshAfter": "2026-08-05T00:00:00Z",
  "expiresAt": "2026-08-11T12:00:00Z"
}
```

Optional: `currentPeriodEnd`, `cancelAtPeriodEnd`. Timestamps are ISO 8601,
with or without fractional seconds.

| Field | Values |
|---|---|
| `status` | `free`, `active`, `grace`, `expired`, `revoked` |
| `plan` | `free`, `monthly`, `annual`, `lifetime`, `complimentary` |
| `capabilities` | any of `store_write`, `store_upload`, `store_release` |

Rules the client enforces and the service must respect:

- A free, expired, or revoked account gets a **signed document with an empty
  `capabilities` array**, never a `404`. An unsigned answer is treated as a
  service failure and the client keeps its previous document.
- All paid and complimentary grants carry all three capabilities.
- `expiresAt` is the hard offline limit. The client keeps working offline until
  it, then refuses every store write. Use about 7 days for a subscription and
  about 30 days for a lifetime grant, so a refund can still be enforced.
- `refreshAfter` is when the client asks again. Anything shorter than
  `expiresAt` is fine.
- A document issued more than 5 minutes in the future is refused.
- `subject` must stay stable for an account. A change is treated as a replayed
  document.

## Routes

### `GET /v1/billing/plans`

Unauthenticated. Amounts are in the smallest currency unit.

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

The client displays these and decides nothing about price. Only `id` travels
back, and the server maps it to an allow-listed Stripe Price. A modified client
must not be able to buy an arbitrary Price.

### `GET /v1/entitlements/me`

Reconciles when stale, then returns the signed document.

### `POST /v1/billing/promotion-code/validate`

Request `{"plan": "lifetime", "code": "LAUNCH100"}`. Response:

```json
{"valid": true, "plan": "lifetime", "subtotal": 44990, "discount": 44990,
 "total": 0, "currency": "USD", "message": null}
```

Display-safe facts only. No coupon object, no redemption count. Rate limit by
account and IP: this route is a code-enumeration surface.

### `POST /v1/billing/checkout`

Request `{"plan": "annual", "promotionCode": "LAUNCH100", "idempotencyKey": "<uuid>"}`.
`promotionCode` is absent when the field was empty. Response:

```json
{"sessionId": "cs_test_...", "url": "https://checkout.stripe.com/...",
 "expiresAt": "2026-08-04T13:00:00Z"}
```

Create a Stripe-hosted Checkout Session: `subscription` mode for monthly and
annual, `payment` mode for lifetime, quantity 1, the account's Customer
attached, the promotion code resolved server side. The same idempotency key
must return the same unexpired session, because the client reuses one key per
plan until a checkout completes.

### `POST /v1/billing/restore`

Reconciles the authenticated account against Stripe and returns the effective
signed document. Do not search Stripe by an unverified email.

### `POST /v1/billing/portal`

Returns `{"url": "https://billing.stripe.com/..."}` for a short-lived Customer
Portal session. Never accept a Customer ID from the client.

### `POST /v1/stripe/webhook`

Not called by the app. `stripe-spec.md` section 9 is the authority.

## Errors

Any non-2xx must carry:

```json
{"code": "already_subscribed", "message": "You already have an active subscription."}
```

The client shows `message` as written, so it must already be safe and must
contain no em dash. Three codes get special handling; every other code is shown
with its message.

| Code | Client behaviour |
|---|---|
| `authentication_required` | Treated as signed out, free access |
| `entitlement_expired` | Returns to free access |
| `entitlement_refresh_required` | Refuses the write, offers a retry |

## What the client never does

- Unlock from a success URL, a deep link, or a query parameter. Access changes
  only after a verified signed document says so.
- Send an email address, a promotion code, a token, or any Stripe ID to
  analytics.
- Write billing state into `store.yaml`.
- Hold a Stripe secret. Every privileged Stripe call is yours.

## Before you turn the gates on

`stripe-spec.md` section 18 states it, and it is the one that costs money if
ignored: do not ship a Release build with `LICENSING_BASE_URL` set until the
service, the webhook reconciliation, and the restore path all work. A client
gate in front of a service that is not live locks out people who have paid.
