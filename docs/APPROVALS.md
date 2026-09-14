# Approvals

Decisions and go-aheads for this project, recorded where the next person (or
session) will find them. An approval that exists only in a chat is not an
approval anyone can act on: the Pack Details restyle was approved in
conversation, never written down, and sat idle as a result.

Each entry says what was approved, by whom, when, and its status. Add to the
top; do not rewrite history.

---

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
