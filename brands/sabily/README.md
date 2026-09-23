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

Apple needs no config value, but it is iOS-only and iOS does not exist yet.
