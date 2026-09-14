# Approvals

Decisions and go-aheads for this project, recorded where the next person (or
session) will find them. An approval that exists only in a chat is not an
approval anyone can act on: the Pack Details restyle was approved in
conversation, never written down, and sat idle as a result.

Each entry says what was approved, by whom, when, and its status. Add to the
top; do not rewrite history.

---

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
