# Approvals

Decisions and go-aheads for this project, recorded where the next person (or
session) will find them. An approval that exists only in a chat is not an
approval anyone can act on: the Pack Details restyle was approved in
conversation, never written down, and sat idle as a result.

Each entry says what was approved, by whom, when, and its status. Add to the
top; do not rewrite history.

---

## 2026-09-14 — Catalogue prefetch at launch, with a freshness window

- **Approved by:** Yazid (explicit instruction, in session).
- **Scope:** start loading `countries/all` + `packs/all` as soon as the app
  starts, in parallel with the intro and session restore and tied to neither;
  keep the catalogue with a freshness window and refetch only when stale;
  Store uses whatever is already loaded, and shows its existing skeleton if
  the load is still running.
- **Decisions taken while building:**
  - Window **1 hour**. Checkout sends the price the card shows
    (`wireAmount`), so the window is also how long a backend price change can
    take to reach the app. Pull-to-refresh and Retry skip it.
  - A stale copy is **not** used as an offline fallback, for the same reason.
  - An empty catalogue is never cached.
  - The raw responses are kept in a file in the app cache directory, not in
    SharedPreferences (1.4 MB would load before every first frame).
- **Status:** built. Emulator, live backend: no cache: prefetch starts at
  +0.4 s, the catalogue is ready at +4.2 to +6.5 s, and Store opened
  mid-load shows the skeleton then data, **one** `packs/all` request. Cold
  start with a cache: catalogue ready from disk at +0.64 s (0.17 s after the
  prefetch starts), no request, and Store shows data on the tap.

## 2026-09-14 — Updating over the old app: signed out, cleanly (added while checking)

- **Asked for:** confirm an existing user updating gets a normal sign-in
  prompt, not a crash or a stuck loading state.
- **Found and fixed without a separate go-ahead (flagged here):**
  - The old app left `auth_token`, `user_data`, `is_logged_in`,
    `pending_email` and **`pending_password` (plaintext)** in the same
    SharedPreferences an update keeps. They are now deleted at launch. The
    old `selected_language` is carried into `app.language`.
  - A secure-storage read that throws (keychain error, keystore key lost in
    a restore) left the session provider retrying forever (the test hangs on
    the old code). It now resolves to signed out.
- **Status:** built. Emulator: the old app's exact prefs were seeded, then
  the new app was cold-started. Arabic was kept, the old keys were gone,
  there was no crash, and My eSIMs showed "Not signed in / Sign in".

## 2026-09-14 — Multi-country pack finder (new)

- **Approved by:** Yazid (explicit, in session).
- **Scope:** pick several countries; the app ranks packs that cover all of
  them (superset), fewest total countries first, cheaper on a tie; shows the
  top few with their country counts; when none covers all, says so and shows
  the packs covering the most. Client-side over the loaded catalogue. Entry
  from Store. No design source: built from existing components, for Yazid to
  review.
- **Decision taken while building:** results are ranked by distinct coverage
  (packs sharing one country list), each showing its packs, not by individual
  pack. On live data the top packs for UK + Australia + France are six sizes
  of Best World, which hid World entirely.
- **Status:** built. On the emulator against the live catalogue: UK +
  Australia + France (Best World 175 first, then 178, then World 197);
  France + Namibia (no single pack, partial matches shown); tap-through to
  pack detail.

## 2026-09-14 — Pack detail screen (new)

- **Approved by:** Yazid (explicit, in session).
- **Scope:** a new screen from the White-Label Details Template (Figma
  66:194): hero image, title, price, stat grid, content section, one "Buy
  this pack" button. Adapted to real data: no star rating, no description,
  no speed stat (none exist); Data and Validity stats kept; the content
  section is coverage (the pack's countries, expandable); the hero uses the
  existing `visuals.packImages` fallback. Tapping a pack card's body opens
  it; the card's own buy button stays a fast path to checkout.
- **Status:** built. On the emulator against the live catalogue: card body
  opens the detail (Best World 500MB, 175 countries, expand), card buy button
  goes straight to Checkout.

## 2026-09-14 — Pack header images bundled in the app (option B)

- **Approved by:** Yazid ("go with b"), over A (backend image per pack) and C
  (building the website's image URLs in the app).
- **Scope:** bundled regional photos under the existing card treatment, one
  per image region plus per-country overrides, from brand config
  (`visuals.packImages`). Chosen by the destination, not by each pack's
  coverage. CC0 only, provenance in `brands/sabily/assets/PACK-IMAGES-CREDITS.md`.
  A per-pack image from the backend, if one ever arrives, still wins.
- **Status:** built. Checked on the emulator for Saudi Arabia, Türkiye,
  France, Japan, Kenya.

## 2026-09-14 — Logo animation on every launch

- **Approved by:** Yazid (explicit, in session).
- **Scope:** the intro animation plays on every app launch, not once per
  install. The persisted "already seen" check is removed. Unchanged: tap to
  skip, the 1.5 s failsafe (not started in time, player error, animations
  disabled), muted, app loading underneath, tour waits for it.
- **Status:** built.

## 2026-09-14 — Password reset: code + new password step

- **Approved by:** Yazid (explicit, in session: "yes build it and run the
  emulator to test it").
- **Scope:** after "Envoyer le code", a screen to enter the 6-character code
  and a new password, calling `POST /account/reset-password/finish`
  (`{key, newPassword}`), with "Renvoyer un code". Wording from the live
  website (`/reinitialiser-mot-de-passe`) in every language it has. Tested on
  the emulator.
- **Status:** built. On the emulator against the live backend: code step
  after Send, wrong code refused ("Ce code n'est pas valide"), resend, Back
  to Sign In. A successful reset needs a real code (DB `reset_key`).

## 2026-09-13 — Become a Partner entry on Home and Profile

- **Approved by:** Yazid (explicit, in session).
- **Scope:** a "Become a Partner" entry on Home and on Profile, opening the
  brand's partner page in the browser. For Sabily:
  `https://sabily.fr/en/devenir-partenaire`.
- **Design source:** `Become a Partner - Sabily (Mobile)` (Figma 52:639, and
  `rebrand/mobile/new/Become a Partner - Sabily (Mobile).png`). Neither mobile
  Home (52:243) nor Profile (52:801) draws the entry, so it reuses that frame's
  value-card treatment. The application form stays on the website.
- **Status:** built.

## 2026-09-13 — Pack Details fidelity pass (63:53)

- **Approved by:** Yazid (explicit; an earlier approval was given in chat only).
- **Scope:** fidelity pass on the existing destination screen against Figma
  `Pack Details - Sabily (Mobile)` (63:53): pill back control, 24px card radius
  with the `rgba(234,227,196,0.5)` border, solid `#003c3a` Buy button with white
  text, header-image wash and darkening overlay, POPULAR badge in cta yellow
  with `#735c00` text. The duration/data filter rows on the same screen are part
  of the same layout.
- **Status:** built.

## Standing rules (approved earlier, recorded here)

- Every near-teal pulled from Figma resolves to `primary` `#003c3a`
  (ARCHITECTURE-MOBILE.md §2.2.2).
- ~~Debug builds may reach `169.58.35.140` over cleartext as a temporary
  bridge.~~ Removed 2026-09-14: the backend is served over HTTPS at
  `https://sabily.transasim.com/api`.
