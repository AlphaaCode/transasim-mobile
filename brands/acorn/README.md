# Acorn Enterprises (Odyssey Global SIM): decisions behind the configuration

The third client, added the same way as eSimple: this folder, one line in
`lib/flavors/main_acorn.dart`, one Android `productFlavor`, flavor-scoped
asset entries in `pubspec.yaml`, and `android/app/src/acorn/res/`.
`test/core/brand_wiring_test.dart` checks that contract for every folder
under `brands/`; `test/widget/two_brands_test.dart` checks that no two of the
three clients show each other's values.

Values gathered 2026-09-16. Each one says where it came from.

## Sources

| Value | From |
|---|---|
| Name, legal entity, form, address, support email | `acorn-config.docx` and the onboarding PDF (2026-08-21) |
| Backend `https://acorn.transasim.com/api` | Alpha: the TRANSASIM host (169.58.35.140), **Acorn's dev server**. The documented `80.241.216.126:9074` (prod) and `213.136.70.254:9074` (dev) time out from outside and would be plain HTTP |
| Colours | the tokens acorn.transasim.com declares: `--brand-primary 35 76 222` (#234CDE), `--brand-surface 238 246 253` (#EEF6FD), `--brand-cta 255 178 30` (#FFB21E), `--brand-cta-text 11 46 107` (#0B2E6B) |
| `accent` #D3E8F8 | a 20% tint of the site's `--brand-accent` #238ADE: the app's accent is a soft tile ground, not a fill (same move as eSimple) |
| Logo | `acorn logo.pdf`, the embedded 640×453 image: one flat blue mark (#0093DD) on white, made transparent by computing each pixel's coverage and filling it with that one blue (no key-out halo) |
| Terms / privacy | acorn.transasim.com `/v2/en/cgu` and `/v2/en/confidentialite` (odysseysim.com does not point at the platform yet) |
| Languages | English only, as the client asked |
| Currency EUR | the backend prices every pack in EUR, not GBP |

## Buttons: two roles, as asked

- **Commerce** (a pack's "Buy", the detail buy bar, checkout "Pay", Home's
  "Scan your voucher", top-up): amber #FFB21E with #0B2E6B text, via `cta`
  and `theme.shop.buy` / `onBuy`.
- **Functional form buttons** (Sign in and the other form buttons): blue
  #234CDE with white text, via `primary`.

The `buy` role was added to `theme.shop` for this; it defaults to `primary`,
so Sabily and eSimple are unchanged (their goldens did not move).

Note, for Alpha: on acorn.transasim.com itself, "Buy an eSIM" uses the BLUE
button class and "Log in" is a grey text link. The app follows the brief's
two-role rule, not that page.

## Gaps, listed rather than blank

The loader warns on each start until these arrive:

- [ ] `legal.vatNumber`: not provided.
- [ ] `legal.rcs` (business registry): not provided. A UK sole proprietorship
      may have none; if so, that is worth writing down.
- [ ] `legal.vatRate`: not provided.
- [ ] `logo.fullInverse` and a wordmark: only the blue mark exists locally;
      the Drive "Logo File" and "Icon File" were not in the folder.
- [ ] `stripePublishableKey`: placeholder until production, by design.

## For Alpha

- ⚠️ **Support and OTP email is `acornbusinesssolutions@aol.co.uk`.** Mail
  sent as an AOL address from a server AOL does not authorise is likely to
  fail AOL's DMARC/SPF checks, and to land in spam or be rejected. Nobody has
  checked this yet. A real registration or password-reset send should be
  tested early, to a mailbox someone can read.
- **Invoice prefix "Acorn Enterprises"** has no place in the app config: the
  app renders no invoices. It belongs to the backend or portal.
- **Onboarding scope says Android App, iOS App and Voucher Activation: No.**
  The app is being built anyway, and it shows voucher entry on Home, as every
  client does. If voucher activation is truly out for Acorn, that needs a
  feature flag, which does not exist today.
- **Voucher redemption is a live Transatel provisioning call** on this
  backend, payment placeholder or not. Not tested with a real code.
- **Store identity is provisional**: `com.transasim.acorn`, never published.
  The convention (transasim prefix vs the client's own domain) must be decided
  and written into ARCHITECTURE-MOBILE.md §3.1 before the first upload to any
  store track; after that it can never change.
- **"Odyssey Global SIM" is long**: Home's header shows it cut off as
  "Welcome to Odyssey Global S…" on a 1080-px-wide phone, and launcher labels
  have less room still. A short name is the client's call.
- **iOS scheme**: pending a Mac, as for the other two clients.
