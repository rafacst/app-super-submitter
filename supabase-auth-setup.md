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
7. Supabase → **Sign In / Providers → Apple**. Turn it on. Client ID is the
   Services ID from step 3. Then paste the Team ID, the Key ID, and the
   contents of the `.p8`. Supabase builds the client secret from those.

The `.p8` is a private key. It belongs in your password manager and nowhere
in this repository.

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
