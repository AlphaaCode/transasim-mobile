# Sabily — decisions behind the configuration

The JSON carries the values. This file carries the decisions the JSON cannot
express, per ARCHITECTURE-MOBILE.md §11 and brief §7.10: a `// TODO` says
nothing, whereas a note saying *why* stops a well-meaning successor "fixing" a
validated choice.

## Identifiers — frozen, and one of them is an exception

`applicationId` and `bundleIdentifier` are both **`com.sabily.esim`**, not the
`com.transasim.<slug>` convention proposed in the brief §5.3.

**This is deliberate (ARCHITECTURE-MOBILE.md §3.2).** The Android app is already
published under `com.sabily.esim`. On Android the `applicationId` *is* the store
listing's identity: changing it creates a **new** listing and every existing
install stops receiving updates. Verified live on 10 September 2026 — the app is
on both stores.

Do not "correct" this to match the convention. The convention applies to clients
not yet published.

## Colour mapping — needs design sign-off

The Figma file carries **three different palettes** for this one client and
defines **no Figma variables** (ARCHITECTURE-MOBILE.md §5.7). The five role
tokens below are the arbitration recorded in §2.2, taken from the 10 September
frame set:

| Role      | Value     | Was called            |
|-----------|-----------|-----------------------|
| `primary` | `#003c3a` | deep green            |
| `accent`  | `#d2f5ec` | mint                  |
| `surface` | `#f9f2d3` | cream background      |
| `cta`     | `#fadb14` | yellow                |
| `ctaText` | `#003c3a` | text on the yellow    |
| `theme.premium.accent` | `#735c00` | bronze   |

Changing any of these after design review is an edit to `brand.json`, not a code
change. That is the whole point.

## Open items — needed before J4, not before J3

- [ ] **`mobile.stripePublishableKey` is a placeholder.** The real `pk_` key has
      not been supplied (brief §8.2). Payment cannot be exercised until it is.
      A key beginning `sk_` is rejected by validation, deliberately.
- [ ] **Logos are provisional.** `logo-mark.png` and `logo-full.png` were taken
      from the previous app's bundle so the socle has something real to render.
      The definitive charter — symbol, lockup, **dark-background variant** — is
      still outstanding. `logo.fullInverse` is absent, which the loader reports
      as a warning on every start.
- [ ] **No Arabic tagline.** `tagline` has `fr` and `en` only, so an
      Arabic-speaking user sees the French tagline. Visible in the J3 Arabic
      screenshot. Needs one line of copy.
- [ ] **No `howItWorks` artwork.** Sabily serves Arabic, so this needs **two
      recomposed images**, not one mirrored: a flipped composition is
      unreadable (brief §4.4). The loader warns until the RTL variant exists.
- [ ] **`legal` is minimal.** Only `companyName`, `country`, `termsUrl` and
      `privacyUrl` are set. Every other identifier renders as `—` by design:
      their absence is an anomaly better shown than hidden (§2.7). `vatRate` is
      absent and warns.
- [ ] ⚠️ **`legal.companyName` says `TRANSASIM`, but both stores list the
      publisher as `Unception`** (ARCHITECTURE-MOBILE.md §12.4). Brief §7.2
      records the same contradiction on the web side. A Sabily customer
      currently installs an app published by a name that appears nowhere in its
      legal texts. **This needs a decision, not a guess** — the value here is
      the one the web socle uses.

## Registration fields

`["email","password","firstName","lastName","phoneNum","country"]` — six of the
eleven the backend requires today. The brief §8.4 notes a request is filed to
reduce it to four. Because this list is configuration, following that change
costs an edit here rather than a store submission.

## Languages

Seven. `defaultLocale` is `fr`, and since 23/09/2026 that is **no longer what
the app opens in**: a launch takes the device's language when Sabily serves it,
and English otherwise. `fr` remains the last resort for a brand that does not
serve English — Sabily does, so it never reaches that. Nothing in `lib/`
assumes a default language.

## Google & Apple sign-in

**Recreated 2026-09-27.** The whole Google Cloud project was rebuilt from
scratch ("we just recreate all the id and keys" -- Alpha). Everything below
under project `197643311846` (`sabily-509510`) is now the RETIRED project;
do not reuse those values.

Current project: `83118739145`. `mobile.googleServerClientId` in
`brand.json` is wired to this project's **Web application** client -- the
only Google value any Dart code reads (`social_sign_in.dart`, passed as
`serverClientId`):

- [x] Web application client (now in `brand.json`):
      `83118739145-b5b4v7v8td3f737neol99dj427jclmqt.apps.googleusercontent.com`
- [ ] Google iOS client:
      `83118739145-f8r76jb0u102flevju1ok3k32jbm5u37.apps.googleusercontent.com`
      -- not read by Dart. Goes in a per-flavor `ios/Runner/Info.plist`
      (`GIDClientID` + reversed-client-ID URL scheme) once iOS packaging
      starts; none exists yet.
- [ ] Google Android clients (also not read by Dart -- Cloud Console
      registrations tied to package name + SHA-1, informational only):
      `83118739145-rhg1h4le0lddi9k6500s0po7nsfbob8v.apps.googleusercontent.com`
      and
      `83118739145-eih8dujjace89i6qp74idkfhmpmglt8d.apps.googleusercontent.com`

Open item, carried over from the retired project and NOT yet reverified
under `83118739145`: whether the OAuth consent screen is in Testing mode,
and who is on the test-user list. The old note said
console.cloud.google.com/auth/audience?project=sabily-509510 and
bensefiayazid@gmail.com -- that URL points at the dead project. Check the
equivalent page for the new one before assuming the same state carries over.

Also still unconfirmed, same as before: whether the backend's
`/v1/auth/google` validates ID tokens against this exact Web client ID as
audience. If sign-in returns a JWT from Google but the backend still
rejects it, that mismatch is the first thing to check.

### Apple

Apple needs no *app-code* config value -- no service ID, team ID, or app ID
is passed anywhere in `lib/` (`social_sign_in.dart` calls
`SignInWithApple.getAppleIDCredential()` with no arguments beyond scopes).
What it needs instead is native Xcode project configuration (Team ID in
signing & capabilities, the Sign In with Apple entitlement), which does not
exist yet because iOS packaging has not started.

On file for when it does:

- App ID: `com.sabily.esim` (already equals `applicationId`/
  `bundleIdentifier` above -- nothing to change)
- Team ID: `DP7F8WQCJD`
- Services ID: `com.sabily.esim.auth` -- this is for the **web/backend**
  Sign in with Apple flow (`webAuthenticationOptions`), which
  `social_sign_in.dart` explicitly does not wire up ("the button is not
  built on Android... it needs a service ID and a return URL nobody has set
  up"). Out of scope for this repo; belongs with whoever owns the web/backend
  project.

## Registration fields

`["email","password","firstName","lastName","phoneNum","country"]` — six of the
eleven the backend requires today. The brief §8.4 notes a request is filed to
reduce it to four. Because this list is configuration, following that change
costs an edit here rather than a store submission.

## Languages

Seven. `defaultLocale` is `fr`, and since 23/09/2026 that is **no longer what
the app opens in**: a launch takes the device's language when Sabily serves it,
and English otherwise. `fr` remains the last resort for a brand that does not
serve English — Sabily does, so it never reaches that. Nothing in `lib/`
assumes a default language.

## Google sign-in

`mobile.googleServerClientId` is set (Google Cloud project `sabily-509510`,
"Sabily"), and both Android OAuth clients are registered under package
`com.sabily.esim`:

- [x] Web application client (the value in `brand.json`):
      `197643311846-4os9jg0k5gngau7ss6iehv9skin4bsbg.apps.googleusercontent.com`
- [x] Android client, debug keystore SHA-1 (`0C:0C:CF:62:55:53:BA:E1:E9:E4:9A:E6:68:51:B5:42:17:8C:36:1E`)
- [x] Android client, Play app signing certificate SHA-1 (`48:A8:30:38:DD:A2:1B:20:91:D0:3E:19:D7:1F:7C:06:9F:F4:46:92`)

Open item: the OAuth consent screen is still in **Testing** mode (Google
Cloud caps this at 100 users and only accounts on the test-user list can
sign in — bensefiayazid@gmail.com is added). Add more testers at
console.cloud.google.com/auth/audience?project=sabily-509510, or submit for
verification before wider rollout.

Also unconfirmed: whether the backend's `/v1/auth/google` validates ID
tokens against this exact Web client ID as audience. If sign-in returns a
JWT from Google but the backend still rejects it, that mismatch is the
first thing to check with whoever owns that endpoint.

Apple needs no *app-code* config value — no service ID, team ID, or app ID is
passed anywhere in `lib/` (`social_sign_in.dart` calls
`SignInWithApple.getAppleIDCredential()` with no arguments beyond scopes). What
it needs instead is native Xcode project configuration (Team ID in signing &
capabilities, the Sign In with Apple entitlement) — which does not exist yet,
because iOS packaging for this app has not started (no per-flavor
`Info.plist`, no `ios/` signing set up).

### Supplied by Alpha, 2026-09-27 -- not yet wired anywhere

Alpha sent a Google iOS client ID, two Google Android client IDs, and an
Apple Team ID. Recorded here rather than dropped into `brand.json`, because
none of them have anywhere to go yet:

- Google iOS client ID:
  `83118739145-f8r76jb0u102flevju1ok3k32jbm5u37.apps.googleusercontent.com`
  -- belongs in a per-flavor `ios/Runner/Info.plist` (`GIDClientID` +
  reversed-client-ID URL scheme) once iOS packaging starts. Not read by any
  Dart code.
- Google Android client IDs:
  `83118739145-rhg1h4le0lddi9k6500s0po7nsfbob8v.apps.googleusercontent.com`
  and
  `83118739145-eih8dujjace89i6qp74idkfhmpmglt8d.apps.googleusercontent.com`
  -- an Android OAuth client is never read by app code at all (see above:
  `google_sign_in` only needs the **Web** `serverClientId`); these two are
  Google Cloud Console registrations tied to a package name + SHA-1
  fingerprint. Likely the debug-keystore and Play-signing-certificate clients
  the "Web application client" bullet above already accounts for by SHA-1 --
  worth confirming they're the same two, now that the actual IDs are in hand.
- Apple Team ID: `DP7F8WQCJD` -- goes in Xcode's signing & capabilities once
  the iOS target exists.

CONFIRMED by Alpha (2026-09-27) -- this is not an incremental addition, the
whole Google Cloud project was recreated ("we just recreate all the id and
keys"). So project `197643311846` (`sabily-509510`) above, and the
`googleServerClientId` value currently wired into `brand.json`, are from the
**retired** project and should be assumed dead.

**Still missing: the new project's Web application client ID.** That is the
only one of these values Dart code actually reads
(`mobile.googleServerClientId` -> `serverClientId` in `social_sign_in.dart`).
The three IDs above are iOS and Android clients; neither type can stand in
for the Web one. `brand.json` has deliberately NOT been edited yet -- the
old (dead) value is still there rather than a client ID of the wrong type,
since the wrong type fails sign-in outright rather than just going stale.
Google sign-in should be assumed broken for Sabily until the new project's
Web client ID arrives.
