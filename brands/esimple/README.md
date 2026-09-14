# eSimple: decisions behind the configuration

The second client, added as configuration only: this folder, one line in
`lib/flavors/main_esimple.dart`, one Android `productFlavor`, flavor-scoped
asset entries in `pubspec.yaml`, and `android/app/src/esimple/res/`. No code
in `lib/core` or `lib/modules` changed. `test/core/brand_wiring_test.dart`
checks that contract for every folder under `brands/`.

Values gathered 2026-09-15. Each one says where it came from.

## Sources

| Value | From |
|---|---|
| Identifiers `com.esimple.esim` (Android and iOS) | old repo branch `spc/esimple`; live on Play and the App Store ("eSimple" 1.0, 2026-08-24, seller **Unception**) |
| Colours | Alpha's bundle (`esimple colors.jpeg`), and the roles esimple.at itself declares (`--brand-primary: 73 205 210`, `--brand-accent: 59 130 246`, `--brand-surface: 255 255 255`, `--brand-cta: 47 59 79`, `--brand-cta-text: 255 255 255`) |
| `logo-full.png` | Alpha's bundle (`esimple logo.jpeg`), cropped to the badge |
| `logo-mark.png`, Android launcher and splash | the icon eSimple publishes today (`spc/esimple`, App Store icon) |
| Languages | the six esimple.at serves (`hreflang`): de, en, fr, ar, sl, sq. No Spanish |
| Taglines | esimple.at page titles in de/en/fr |
| Support email | esimple.at footer, `contact@esimple.at` |
| Partner URL | esimple.at "Devenir partenaire" (Alpha: "Portail revendeurs: oui") |
| Legal entity | esimple.at Impressum: **Eljhat Kadrii e.U.**, Hernalser Hauptstraße 135, 1170 Wien, FN 628945w (Handelsgericht Wien), host Contabo GmbH |
| Backend | `https://esimple.transasim.com/api`: valid certificate, same API shape as Sabily's, 983 packs |

## Needs a decision before release

- [ ] **Colour roles fail contrast on mobile.** The website's mapping was
      used as-is, but the app's roles are not the web's. `primary` is the app's
      text and filled-button colour: cyan `#49cdd2` on white is **1.9:1**
      (AA needs 4.5:1). `accent` is the app's soft tile tint: `#3b82f6` makes
      saturated blue tiles, with cyan text on them at 1.9:1. A mapping that
      keeps cyan as the brand colour and passes AA: `primary #2f3b4f` (navy,
      11:1 on white), `accent` a light cyan tint, `cta #49cdd2` with
      `ctaText #2f3b4f` (5.8:1). **For Yazid**; it is a five-line edit here.
- [ ] **Three logos disagree.** Alpha's bundle has "eSIMPLE" white in the
      badge; the old app and its store icon have "eSIM" in the badge beside a
      navy "PLE". The mark and launcher icon are the published "eSIM" icon, so
      the app matches what users have installed. Needed from the client: a
      square symbol in the new style, a transparent (or vector) lockup, and
      the **dark-background variant** (`logo.fullInverse` is absent and warns).
- [ ] **Legal entity: three names.** The Impressum says Eljhat Kadrii e.U.,
      the site footer says © HAUS DES HANDYS, and both stores list the seller as
      Unception. Alpha's note says "esimple". `legal.companyName` uses the
      Impressum; this needs confirming, not guessing.
- [ ] **`vatRate` and VAT number** are absent (they warn). Not guessed from
      the Austrian standard rate.
- [ ] **Default language `de`** is an inference (Austrian company, `.at`),
      not a stated fact. esimple.at itself falls back to `fr`.
- [ ] **`stripePublishableKey` is a placeholder.** esimple.at and the old
      branch both carry a `pk_live_51Tgk0…` key. It was not used: the key
      for the app has to come from the client, as for Sabily.
- [ ] **No pack photos and no intro video.** Sabily's are Sabily's; eSimple
      shows the plain pack header until it has its own.

## Found while checking, for Alpha

- ⚠️ **The published eSimple app's backend certificate has expired.**
  `spc/esimple` points at `https://api.esimple.transasim.com`, served from
  80.241.216.126 with a Let's Encrypt certificate that **expired
  2026-09-13 15:40 UTC**. esimple.at and panel.esimple.at are on the same
  certificate. The app live in the stores is very likely failing every request
  now, and the website warns visitors. The renewal on that server needs
  fixing today. (The new flavor uses `esimple.transasim.com`, which is valid
  until 2026-12-03.)
- `www.esimple.at` does not resolve.
