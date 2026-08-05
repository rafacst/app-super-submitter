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

A local build counts the commits too, in the "Stamp the build number from git"
script phase. Both sides use `git rev-list --count HEAD`, so a build you make
on your own Mac carries the same number the release would, and "Check for
updates" answers "up to date" instead of offering you the version you already
have. A checkout with no git history keeps `CURRENT_PROJECT_VERSION` instead.

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

---

## Starting the GitHub repository again from scratch

Planned, not done. Read the whole section before you run anything.

### What is on the repository today

`rafacst/super-submitter-app`, public, created 2026-08-04. No stars, no forks,
no issues, no pull requests. **8 releases**, each carrying a signed
`SuperSubmitter-*.zip`, an `appcast.xml`, and release notes.

### Three things to know first

**1. The history holds no secret.** Every `.p8`, `.p12`, and `.pem` pattern in
the history is a test fixture or a line of prose. No key was ever committed. So
if the reason for erasing is a leak, there is no leak. Erase it because you want
a clean start, not because you have to.

**2. The Sparkle private key is safe.** It lives in the login keychain under
the service `https://sparkle-project.org`, and a GitHub secret cannot be read
back, so the keychain is the only copy that matters. Export it before you touch
anything:

```bash
/tmp/sparkle/bin/generate_keys -x /tmp/sparkle_private_key
```

Lose that key and no installed copy can ever update again, whatever you do to
the repository.

**3. The feed URL is baked into every shipped build.** `project.yml` sets
`SUFeedURL` to
`https://github.com/rafacst/super-submitter-app/releases/latest/download/appcast.xml`.
**Keep the same owner and repository name** and every installed copy keeps
updating. Change the name and each one is orphaned for good, because the name
is inside the bundle they already have. Today only your own installs are
affected, and that stops being true the day the product is announced.

### Two ways to do it

**The cheap one, and it does what was asked.** One commit, no history, and the
releases, the secrets, and the approval gate all stay:

```bash
git checkout --orphan fresh && git add -A && git commit -m "chore: start the public history again" && git branch -M fresh main && git push github main --force
```

Nothing else needs re-creating. The eight old releases stay reachable, which is
either what you want or the reason to use the other way.

**The full one, if the releases must go too.** This destroys the eight releases
and all five secrets. `gh` is not installed on this Mac, so either install it or
use the web interface.

```bash
brew install gh && gh auth login --scopes delete_repo
```

```bash
gh repo delete rafacst/super-submitter-app --yes
```

```bash
gh repo create rafacst/super-submitter-app --public --description "Ship an iOS, macOS, and Android app to both stores from one YAML file."
```

Then re-add every secret from section 4 and the gate from section 5 **before**
the first push. `SPARKLE_PRIVATE_KEY` comes from the export above; the rest are
in your password manager:

| Secret | Where it comes from |
|---|---|
| `SPARKLE_PRIVATE_KEY` | the export above |
| `DEVELOPER_ID_CERT_P12` | Keychain Access, exported and base64 encoded |
| `DEVELOPER_ID_CERT_PASSWORD` | the password you set on that export |
| `NOTARY_APPLE_ID` | the Apple ID that notarizes |
| `NOTARY_PASSWORD` | its app-specific password |

Only then:

```bash
git push github main --force
```

### The trap

The workflow runs on **every push to `main`**, so the first push to the new
repository cuts a release immediately. Secrets missing at that moment means a
failed run and a tag pointing at nothing. Add all five first. Section 2.1 of
`context.md` is the rule this sits under: GitLab is the source, and a GitHub
push ships.
