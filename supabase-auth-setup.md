# Supabase sign-in setup

The app ships three provider buttons: Apple, GitHub, and GitLab. The client
half is done and tested. This file is the half that only you can do,
because each step needs a login and a secret that must never reach this
repository.

Today all three answer `Unsupported provider: provider is not enabled`. The
buttons stay in the sheet and report that message until you finish the steps
below, one provider at a time. Email and password already work.

## 0. The one setting every provider needs

Supabase refuses a redirect it does not know, so do this first or every
provider fails at the last step.

1. Open the Supabase dashboard, project `cvrvyxcjddtpsyfxieuf`.
2. Go to **Authentication → URL Configuration → Redirect URLs**.
3. Add `supersubmitter://auth-callback`.

That is the scheme the app registers in `project.yml` under
`CFBundleURLTypes`, and the one `OAuthSession.callback` opens with.

The confirmation email uses the same address. Set **Site URL** to
`supersubmitter://auth-callback` as well, because that is where Supabase sends
a signup link when nothing else asks for a different one. The app catches it in
`onOpenURL`, hands it to `SupabaseAuth.adopt(callback:)`, and the developer is
signed in without typing the password again. Supabase puts the token pair in
the fragment, so anything that drops a fragment breaks the link.

The callback URL you paste into each provider below is always the same:

```
https://cvrvyxcjddtpsyfxieuf.supabase.co/auth/v1/callback
```

The provider talks to Supabase, and Supabase talks to the app. No provider
ever sees `supersubmitter://`.

## 1. GitHub

The shortest one. Start here to prove the flow end to end.

1. GitHub → **Settings → Developer settings → OAuth Apps → New OAuth App**.
2. Application name: `Super Submitter`. Homepage URL: your product page.
3. Authorization callback URL: the Supabase callback above.
4. Register, then **Generate a new client secret**.
5. Supabase dashboard → **Authentication → Sign In / Providers → GitHub**.
   Turn it on, paste the Client ID and the Client Secret, and save.

## 2. GitLab

1. GitLab → **Preferences → Applications → Add new application**.
2. Redirect URI: the Supabase callback above.
3. Scopes: tick `read_user` and `openid`. Nothing else.
4. Save, and copy the Application ID and the Secret.
5. Supabase → **Sign In / Providers → GitLab**. Turn it on, paste both, save.

Self-hosted GitLab needs its base URL in the Supabase provider panel as well.

## 3. Apple

The longest one, and it needs a paid Apple Developer account. You already
have one, because the app is Developer ID signed.

Sign in with Apple on the **web** is what this flow uses, even though the app
is a Mac app, because Supabase performs the exchange.

1. Apple Developer → **Certificates, Identifiers & Profiles → Identifiers**.
2. Your App ID `com.rafacst.supersubmitter`: enable **Sign In with Apple**.
3. Make a new **Services ID**, for example
   `com.rafacst.supersubmitter.signin`. This becomes the Client ID.
4. Configure that Services ID:
   - Domains: `cvrvyxcjddtpsyfxieuf.supabase.co`
   - Return URL: the Supabase callback above.
5. **Keys → new key**, enable Sign In with Apple, download the `.p8` once.
   Apple gives it to you a single time.
6. Note the Key ID and your Team ID.
7. Make the client secret. Supabase does **not** take the `.p8`. Apple's
   client secret is a JWT signed with it, so build one on your own machine:

   ```bash
   swift tools/apple-client-secret.swift --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 --key-id XXXXXXXXXX --team-id 88BXH8KNVZ --services-id com.rafacst.supersubmitter.signin
   ```

8. Supabase → **Sign In / Providers → Apple**. Turn it on. Put the Services ID
   in **Client IDs** and the token from step 7 in **Secret Key (for OAuth)**.

**This secret expires after six months.** Apple allows no longer. When it
lapses every Apple sign-in fails, and nothing else does, so it looks like a
provider outage. The script prints the expiry date. Put it in a calendar, and
keep the `.p8`, because the next secret needs it.

The `.p8` is a private key. It belongs in your password manager and nowhere
in this repository. `.gitignore` refuses `*.p8` and `*.p12` as a backstop.

## 4. Check it

Run the app, open **Settings → Account → Sign in or create account**, and
press a provider button. A browser window opens, you approve, and the sheet
closes with your address in the Account tab.

To check a provider without the app:

```bash
curl -s -o /dev/null -w "%{http_code}\n" "https://cvrvyxcjddtpsyfxieuf.supabase.co/auth/v1/authorize?provider=github&redirect_to=supersubmitter%3A%2F%2Fauth-callback&code_challenge=E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM&code_challenge_method=s256"
```

`302` means the provider is live. `400` means it is still switched off.

## What the app does with the answer

`SupabaseAuth.authorization(with:redirectTo:)` builds the authorize URL and a
PKCE verifier. `OAuthSession` opens it in `ASWebAuthenticationSession`, so the
password is typed into the provider's own page and this app never sees one.
`completeOAuth(callback:verifier:)` trades the code for a session, and the
session lands in the Keychain beside the one the email form makes. Everything
after that is identical for both doors.

Identity linking is on, so a developer who signs in with GitHub today and
with GitLab tomorrow lands on one account, as long as both providers hand
Supabase the same verified address.

**Apple is the one that can break that.** A user who picks **Hide My Email**
gives Apple's private relay address, something like
`a1b2c3@privaterelay.appleid.com`. It matches nothing, so that sign-in makes
a second account with its own entitlement, and a developer who paid through
their GitHub account finds no paid access behind the Apple button.

There is no client fix for this: the app never sees which address Apple will
send until the session comes back. Two ways out, and both are yours to pick.

1. Leave it, and answer the support mail with **Restore access** after they
   sign in with the door they bought through. Cheapest, and rare enough at
   this scale.
2. Turn on **manual linking** in Supabase and add a "Link another sign-in" row
   to the Account tab, so a signed-in developer attaches Apple deliberately.
   That is real work in `AppStateAccess.swift` and it is not built, because
   nobody has hit the problem yet.

The entitlement hangs off the account, so whichever you pick, decide before
the first Apple sign-in reaches a paying customer.

---

## 6. The custom domain, `auth.rafacst.me`

**Not done, and not scheduled.** Read this section before you start it.

Supabase serves auth from `cvrvyxcjddtpsyfxieuf.supabase.co`. A custom domain
puts your own name in front of it. The project domain keeps working, so both
answer once this is done.

### What it costs, and the three ways to get it

| Way | Cost per month | What you own |
|---|---|---|
| Hosted add-on | 10 USD, **and** a paid plan. 35 USD from Free. | Nothing. Supabase runs it. |
| Reverse proxy in front of hosted | Free | It does not work. See below. |
| Self-host on Railway | Roughly 7 to 14 USD, on the Hobby plan already paid for | The database, **and the backups** |

Railway is the cheapest of the three and it is not close. Its rates are 10 USD
per GB of RAM per month, 20 USD per vCPU per month, and 0.15 USD per GB of
volume. Four small services idle at roughly 7 to 14 USD, and the Hobby plan
already includes 5 USD of that.

**Use four services, not twelve.** Railway's own Supabase template deploys the
whole stack and costs 20 to 40 USD per month. This project uses Postgres,
GoTrue for auth, PostgREST for `/rest/v1`, and Kong to put both behind one
name. It uses no Realtime, no Storage, no edge functions, no analytics, and no
pooler. Deploying those is paying rent on nothing.

**A reverse proxy does not solve this on hosted Supabase.** A proxy on
`auth.rafacst.me` can carry the API calls the app makes, but it cannot change
the `redirect_uri` that Supabase Auth hands to GitHub, GitLab, or Apple. That
value comes from the project's own external URL, and hosted Supabase pins it to
the project name unless the add-on is on. So the provider consent screen still
says `supabase.co`, which is the one place a customer actually reads it. The
proxy buys a hop and a failure point and almost nothing else.

**Self-hosting does solve it**, because `API_EXTERNAL_URL` and
`GOTRUE_SITE_URL` become yours. Railway also carries the parts of self-hosting
that usually hurt: it provisions the machine, patches the host, and restarts a
dead container.

It does not carry the one that matters here.

### Backups: not yet, and that is what makes now the moment

**Railway Hobby takes no database backups.** Its 72 hour retention is of
deployment images, which rolls back code and not data. Lose the Postgres volume
and every account and every row of `entitlement_grants` goes with it.

Today there is nothing in there. The product is live, unannounced, and has no
users, so there is no data to lose and nobody to lock out. `context.md`
section 1 records that.

This is what makes the decision easy, and it points the other way from the
usual advice. Moving now is a fresh deployment: stand the stack up, point the
config at it, sign in once. Moving after the first customer is a data
migration, a session cutover, and an outage on the system that gates paid
access.

So the backup job is a **launch blocker, not a today blocker**. Before the
product is announced anywhere, a scheduled `pg_dump` to R2 and a restore you
have actually performed have to exist. An untested dump does not count.

### What the move still costs

Two of the usual costs are free right now, and stop being free the day someone
signs up.

- ~~The user ids have to survive~~. `entitlement_grants.user_id` points at
  `auth.users(id)`, and a migration that mints new ids would disconnect every
  paying customer. **No users, so nothing to preserve.**
- ~~Everyone signs in once more~~. The signing keys change at the cutover.
  **Nobody is signed in.** `acceptedIssuers()` in the Worker already reads a
  list rather than one string, so this stays cheap later too.

These still apply:

- **GoTrue must be told to sign with ES256.** Set `JWT_KEYS` and `JWT_JWKS`, or
  it falls back to the legacy shared secret and serves an empty JWKS. The
  Worker refuses that loudly on purpose, so auth would stop dead.
- **The providers move.** GitHub, GitLab, and Apple all need the new callback,
  and Apple needs a fresh client secret. Same work on either path.
- **SMTP moves too.** Confirmation mail goes through Proton today, and
  self-hosted GoTrue needs those credentials again. Email confirmation must
  stay on.
- **The schema moves.** `migrations/` is the whole of it, and it applies to a
  fresh Postgres unchanged.
- **Do not expose Studio.** It is full access to the database and the auth
  configuration, with no authentication in front of it by default.

### The decision, 2026-08-05

**Stay on hosted Supabase. Nothing moves for now.** The project keeps
`cvrvyxcjddtpsyfxieuf.supabase.co`, and `auth.rafacst.me` does not exist.

The analysis above stands and the recommendation was the other way, so the
reason to revisit is written down rather than rediscovered: while the product
has no users, this move is a fresh deployment. After the first customer it is a
data migration, a session cutover, and an outage on the system that gates paid
access. The cost of waiting is real and it only goes up.

Two rules for the day it happens. Do not deploy the twelve service template,
only the four this project uses. And write the backup job before the product is
announced, not before the move.

### The steps, when the day comes

**Wrangler cannot do the DNS half.** Wrangler manages Workers and ships no
`dns` command. The records go through the Cloudflare DNS API, and
`super-submitter-worker/scripts/supabase-domain-dns.sh` calls it.

### What it costs and what it needs

Custom domains are a **paid add-on on a paid Supabase plan**, per domain. The
Supabase CLI is not installed on this Mac. Install it and log in first.

### The order matters

The `iss` claim of every token changes the moment the domain activates. The
Worker checks that claim. Do these in order or every signed-in developer is
signed out, and a paying one loses access until they sign in again.

**1. Teach the Worker both issuers, and deploy it. Do this first.**

In `wrangler.toml`, under both `[env.test.vars]` and `[env.live.vars]`, leave
`SUPABASE_ISSUER` alone and add the new one as the alternate:

```toml
SUPABASE_ISSUER_ALTERNATES = "https://auth.rafacst.me/auth/v1"
```

Deploy both. The Worker now accepts a token from either name. Nothing has
changed yet for anybody, which is the point: this step is free to take early
and it is the one that removes the outage.

**2. Register the domain and read back the TXT value.**

```bash
supabase domains create --project-ref cvrvyxcjddtpsyfxieuf --custom-hostname auth.rafacst.me
```

**3. Write the two DNS records.**

```bash
export CF_API_TOKEN=...        # Zone:DNS:Edit on rafacst.me
cd super-submitter-worker
./scripts/supabase-domain-dns.sh '<the _acme-challenge value from step 2>'
```

Both records stay **DNS only**. A proxied record puts Cloudflare in front of
the hostname, and Supabase then cannot answer the ACME challenge or serve its
own certificate. The script sets `proxied: false` for exactly this reason.

**4. Move every OAuth provider to the new callback before you activate.**

Each provider still points at
`https://cvrvyxcjddtpsyfxieuf.supabase.co/auth/v1/callback`. Change each one to:

```
https://auth.rafacst.me/auth/v1/callback
```

- **GitHub** → the OAuth app's Authorization callback URL.
- **GitLab** → the application's Redirect URI.
- **Apple** → the Services ID. Both the **Domains** field, which becomes
  `auth.rafacst.me`, and the **Return URL**. Apple is the one that also needs
  a **new client secret**, because the JWT is bound to the Services ID. Run
  `tools/apple-client-secret.swift` again afterwards and paste the result into
  Supabase.

Supabase's own note says to do this before activation, or the providers break
at the moment of the switch.

**5. Verify and activate.**

```bash
supabase domains reverify --project-ref cvrvyxcjddtpsyfxieuf
supabase domains activate --project-ref cvrvyxcjddtpsyfxieuf
```

The certificate can take up to 30 minutes.

**6. Move the primary name over.**

Only now, and only after a sign-in on the new name works:

- `project.yml`: `SUPABASE_URL` becomes `https://auth.rafacst.me`.
- `wrangler.toml`, both environments: `SUPABASE_URL` and `SUPABASE_ISSUER`
  become the new name. Move the **old** issuer into
  `SUPABASE_ISSUER_ALTERNATES`, so the tokens already in the wild keep working.
- `.github/workflows/release.yml`, wherever `SUPABASE_URL` is set.

Deploy the Worker, then ship a client build.

**7. Drop the alternate, later.**

A Supabase access token lasts an hour and a refresh token far longer, so leave
`SUPABASE_ISSUER_ALTERNATES` in place for at least a week. Empty it once
nothing signs in on the old name.

### Rolling it back

`supabase domains delete --project-ref cvrvyxcjddtpsyfxieuf` gives up the
custom domain, and the project name keeps working throughout. Keep the
alternate issuer configured until you are sure, because it is what makes the
switch reversible in both directions.
