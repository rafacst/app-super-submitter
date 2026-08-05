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

**Done on 2026-08-05. The repository is deleted.** What follows is the record
of what went, and the procedure for bringing it back.

### What was there, and what went with it

`rafacst/super-submitter-app`, public, created 2026-08-04. No stars, no forks,
no issues, no pull requests. **8 releases**, each carrying a signed
`SuperSubmitter-*.zip`, an `appcast.xml`, and release notes, from `v1.0.0-59`
to `v1.0.0-90`. All eight are gone, along with all five Actions secrets.

The code was on GitLab before the deletion and still is. The Sparkle private
key was in the login keychain and still is.

### Bringing it back

```bash
gh repo create rafacst/super-submitter-app --public --description "Ship an iOS, macOS, and Android app to both stores from one YAML file."
```

Then every secret from section 4 and the gate from section 5, **before** the
first push. Deleting a repository needs the `delete_repo` scope, which is not
part of `repo`; `gh auth refresh -h github.com -s delete_repo` grants it.

The rest of this section is why the name and the secrets matter, and it is
worth reading before the first push rather than after it.

### Two things that decide whether this goes well

**1. The name is not free to change.** `project.yml` sets `SUFeedURL` to
`https://github.com/rafacst/super-submitter-app/releases/latest/download/appcast.xml`,
and that string is inside every bundle already shipped. Recreate under the same
owner and name and each installed copy keeps updating. Use a different name and
every one of them is orphaned for good, because the old address is baked into
software you no longer control. Today that is only your own installs. It stops
being only your own the day the product is announced.

**2. The Sparkle private key is the irreplaceable one.** A GitHub secret cannot
be read back, so the copy in the login keychain, under the service
`https://sparkle-project.org`, is the one that matters. It survived the
deletion. Export it when you need to paste it into the new secret, and delete
the file straight after:

```bash
/tmp/sparkle/bin/generate_keys -x /tmp/sparkle_private_key
```

Lose that key and no installed copy can ever update again, whatever the
repository is called.

### The five secrets, before the first push

| Secret | Where it comes from |
|---|---|
| `SPARKLE_PRIVATE_KEY` | the export above |
| `DEVELOPER_ID_CERT_P12` | Keychain Access, exported and base64 encoded |
| `DEVELOPER_ID_CERT_PASSWORD` | the password you set on that export |
| `NOTARY_APPLE_ID` | the Apple ID that notarizes |
| `NOTARY_PASSWORD` | its app-specific password |

Add the approval gate from section 5 too. Only then:

```bash
git push github main
```

### The trap

The workflow runs on **every push to `main`**, so the first push to the new
repository cuts a release immediately. A secret missing at that moment means a
failed run and a tag pointing at nothing. Add all five first. Section 2.1 of
`context.md` is the rule this sits under: GitLab is the source, and a GitHub
push ships.

### For the record

The history was checked before the deletion and held no secret. Every `.p8`,
`.p12`, `.pem`, `sk_live`, and `whsec_` pattern in it was a test fixture or a
line of prose, so nothing needed rotating and nothing needs rotating now. The
erasure was a clean start, not a containment.
