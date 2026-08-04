# Releasing

Every push to `main` builds a signed, notarized release and publishes it to
GitHub. The app then finds it on its own, because Sparkle polls the appcast
that the same release carries.

The workflow waits for your approval before it builds. Nothing ships until you
press the button.

This page is the one-time setup. Do it once, in order.

## What the pieces are

| Piece | Where it lives |
| --- | --- |
| The workflow | [.github/workflows/release.yml](.github/workflows/release.yml) |
| The updater | [Updater.swift](Sources/SuperSubmitter/Updater.swift) |
| The feed URL and the public key | The `info:` block in [project.yml](project.yml) |
| The version | `MARKETING_VERSION` in [project.yml](project.yml) |

The download URL is `https://github.com/OWNER/REPO/releases/latest/download/appcast.xml`.
GitHub keeps that path pointing at the newest release, so the URL never
changes and the app never needs a server.

## 1. Make the GitHub repository

The repository must be **public**. Sparkle downloads the appcast and the zip
without credentials, and a private repository refuses both.

Create an empty repository named `super-submitter-app` under your account. Then
add it next to GitLab, which stays the place you push day to day:

```bash
git remote add github https://github.com/rafacst/super-submitter-app.git
```

If you name the repository something else, change `SUFeedURL` in `project.yml`
to match.

## 2. Make the Sparkle key pair

Sparkle signs every update with an EdDSA key. The app carries the public half
and refuses any download that the private half did not sign.

Download the Sparkle tools, then run the generator:

```bash
curl -fsSL -o /tmp/sparkle.tar.xz https://github.com/sparkle-project/Sparkle/releases/download/2.9.5/Sparkle-2.9.5.tar.xz && mkdir -p /tmp/sparkle && tar -xJf /tmp/sparkle.tar.xz -C /tmp/sparkle && /tmp/sparkle/bin/generate_keys
```

It writes the private key into your login keychain and prints the public key.
Copy the public key into `project.yml`, in place of
`REPLACE_WITH_SPARKLE_PUBLIC_KEY`. The public key is safe to commit.

Now export the private key for the workflow:

```bash
/tmp/sparkle/bin/generate_keys -x /tmp/sparkle_private_key
```

Keep that file only long enough to paste it into a GitHub secret in step 4,
then delete it. Losing this key means no existing install can ever update
again, so back up the keychain item.

## 3. Export the signing certificate

Open Keychain Access, find **Developer ID Application: R CASTRO SILVA
CONSULTORIA EM TECNOLOGIA LTDA**, right-click it, and choose Export. Save it as
`certificate.p12` and give it a password.

Turn it into one line of text for the secret:

```bash
base64 -i certificate.p12 | pbcopy
```

## 4. Add the secrets

Go to Settings, then Secrets and variables, then Actions. Add five secrets:

| Name | Value |
| --- | --- |
| `DEVELOPER_ID_CERT_P12` | The base64 text from step 3 |
| `DEVELOPER_ID_CERT_PASSWORD` | The password you gave the `.p12` |
| `SPARKLE_PRIVATE_KEY` | The contents of `/tmp/sparkle_private_key` |
| `NOTARY_APPLE_ID` | The Apple ID of your developer account |
| `NOTARY_PASSWORD` | An app-specific password, not your Apple ID password |

Make the app-specific password at [appleid.apple.com](https://appleid.apple.com),
under Sign-In and Security, then App-Specific Passwords.

Delete `certificate.p12` and `/tmp/sparkle_private_key` once the secrets hold
them.

## 5. Add the approval gate

Go to Settings, then Environments, and create an environment named `release`.
Turn on **Required reviewers** and add yourself.

Without this the workflow still runs, but it ships every push with no pause.

## 6. Push

```bash
git push github main
```

The workflow starts and stops at the approval. Approve it, and about fifteen
minutes later the release is on the Releases page.

## What happens on every push after that

1. The workflow reads `MARKETING_VERSION` from `project.yml` and counts the
   commits. Version `1.0.0` at commit 143 becomes the tag `v1.0.0-143`, and the
   app carries build number 143.
2. It builds, signs with your Developer ID, notarizes with Apple, and staples
   the ticket into the app.
3. It writes the release notes from the commit subjects since the last tag.
4. It signs the appcast with the Sparkle key.
5. It publishes the zip and `appcast.xml` as one GitHub release.

Sparkle compares build numbers, so the commit count is what decides that an
update exists. To change the version users see, edit `MARKETING_VERSION` in
`project.yml` and push.

## Things that break, and why

**"SUPublicEDKey is still the placeholder."** Step 2 is not done.

**The build fails on `macos-26`.** GitHub retired the runner label. Change
`runs-on` in the workflow to the current macOS label.

**Notarization fails on an entitlement.** `SuperSubmitter.entitlements` is an
empty dictionary today. Adding an entitlement can need a provisioning profile,
which this workflow does not install.

**Notarization fails on an ad-hoc signature.** Sparkle ships four helpers
inside its framework, and Xcode signs only the framework around them. The
"Sign the Sparkle helpers" step signs them from the inside out. If a Sparkle
upgrade adds a fifth helper, add it to that list.

**Users see no update.** Open `https://github.com/OWNER/REPO/releases/latest/download/appcast.xml`
in a browser. If it does not load, the repository is private or the release
failed. If it loads but shows the old version, the run did not finish.

**The Sparkle tools and the framework drift apart.** `SPARKLE_TOOLS_VERSION` in
the workflow and `from: 2.9.0` in `project.yml` move on their own. Keep the
tools version at or above the resolved framework version.
