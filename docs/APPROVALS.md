# Approvals

Decisions and go-aheads for this project, recorded where the next person (or
session) will find them. An approval that exists only in a chat is not an
approval anyone can act on: the Pack Details restyle was approved in
conversation, never written down, and sat idle as a result.

Each entry says what was approved, by whom, when, and its status. Add to the
top; do not rewrite history.

---

## 2026-10-03 — iOS: Sabily and eSimple built, signed and submitted (2.0.0)

- **Approved by:** Mehdi (explicit, in session), each step asked for: deploy both
  apps to the App Store; create the Google iOS clients; ship iOS as 2.0.0; accept the
  updated Apple Developer Program License Agreement; add User ID and Purchase
  History to App Privacy; release automatically on approval; submit both.
- **Scope:** the first iOS build of the project. Per-brand Xcode flavors for all
  three clients (`tool/ios_flavors.rb`, `ios/Flutter/<slug>.xcconfig`,
  `ios/Runner/Brands/Brand-<slug>.xcassets`), Sign in with Apple entitlement,
  Google iOS client wiring, wiring tests extended to iOS.
- **Decisions taken while building:**
  - Icons are the ones live on the App Store today (Sabily, eSimple), so the update
    changes nothing on users' home screens. Acorn's is its mark on its intro black.
  - The launch screen is the brand's launch colour only (`logo.introBackground ??
    colors.surface`, as on Android); Flutter's template storyboard, icon and launch
    image are removed from the socle.
  - Google: eSimple's existing iOS client (27/09) reused; Sabily got a new one,
    since Google flagged the Firebase-made client for deletion after six months
    unused.
  - App Store screenshots are simulator captures of the same screens as
    `brands/<slug>/screenshoot/`, in English, iPhone 6.9" and iPad 13".
- **Verified:** release IPAs inspected (Apple Distribution certificate, App Store
  profile, entitlements, bundle ids, only the brand's own assets inside); Sign in
  with Apple on the simulator against the live Sabily backend (200 on
  `/v1/auth/apple` and `/account`); every screen of both brands compared with the
  Android screenshots on the iPhone 17 Pro Max simulator. **Not** verified: a real
  iPhone (it never connected), Google sign-in on iOS, checkout on iOS.
- **Status:** both in App Review, 2.0.0 (20), automatic release.

## 2026-09-20 — Acorn and eSimple get their own intro animations

- **Approved by:** Yazid (explicit, in session): both files "confirmed ready
  to bundle as-is", superseding the earlier logo-hold fallback for these two.
- **Scope:** Sabily's mechanism reused unchanged — `logo.intro` in brand.json,
  the file beside the brand's other assets, `IntroGate`/`_Intro` playing it
  muted and ending on the video's own completion. No second implementation,
  no per-brand code.
- **One socle addition:** `logo.introBackground`, the colour of the
  animation's own edges. It is what the intro paints around the video and
  what the flavor's `brand_splash_background` repeats, so the OS launch
  window, the ground and the opening frame are one colour. Absent -> the
  brand's surface, which is what Sabily's cream-edged file needs; Sabily's
  config, resources and goldens are untouched. The wiring test now pins the
  launch window to this value rather than to `colors.surface`.
- **Changed from "as-is", and why:** the silent AAC track was stripped from
  both files (stream copy, `-an`; the video bitstream is byte-identical). On
  a cold start the player set up a second decoder for it and missed the
  intro's 1.5 s start deadline, so **the animation did not play at all**.
  Sabily's file has no audio track either. Also dropped the empty `tmcd`
  timecode track that ffmpeg would otherwise carry over.
- **Deliberately not done:** no re-encode, no change to fit (the video is
  centred at its own aspect ratio, as Sabily's is — not `BoxFit.cover`), no
  change to the 1.5 s deadline, no change to the prefetch hand-off (the
  catalogue loads in parallel and neither waits for the other).
- **Status:** built. Emulator, screen recordings of cold launches:
  **Acorn** black launch window -> black ground -> the α animation plays to
  its end -> Store with 202 destinations in EUR; **eSimple** the same, in
  German, ending on the eSIM mark; **Sabily** unchanged, its green mark on
  its cream ground. No colour flash in any of the three: every sampled corner
  stays the launch colour from the OS window to the app's first screen.

## 2026-09-16 — Acorn (Odyssey Global SIM), the third client, as configuration

- **Approved by:** Yazid (explicit, in session), with three answers given
  when asked: the backend is `https://acorn.transasim.com/api` (169.58.35.140,
  Acorn's **dev** server, not the documented `:9074` hosts); surface #EEF6FD
  (the site's token, not the brief's #F5F9FC); buttons follow the brief's
  two-role rule even where the site differs.
- **Scope:** `brands/acorn/` (config, logo), `lib/flavors/main_acorn.dart`,
  the Android `acorn` flavor, flavor-scoped assets. English only. Sources and
  every gap in `brands/acorn/README.md`.
- **Socle changes made for it:** a `buy` / `onBuy` role in `theme.shop` for
  the buttons that lead to paying (a pack's Buy, the detail buy bar, checkout
  Pay). It defaults to `primary`, so Sabily and eSimple render as before
  (goldens unchanged). The loader now warns when `legal.vatNumber` or
  `legal.rcs` is missing, as it already did for `vatRate`.
- **Isolation:** the wiring and two-brand tests now cover every pair of the
  three clients. The Acorn APK holds only `brands/acorn/*`.
- **Not done, on purpose:** no voucher redemption (a live Transatel
  provisioning call on this backend), no checkout (Stripe key stays a
  placeholder), no sign-in or sign-up submitted.
- **Store identity provisional:** `com.transasim.acorn` must be confirmed
  before any upload.
- **Status:** built. On the emulator against the live dev backend: catalogue
  loaded (countries/all and packs/all 200, 202 destinations, EUR); Home;
  Store; Austria's header in solid blue with white text; amber "Buy this pack"
  with navy text; My eSIMs and Profile signed out; the welcome sheet in solid
  blue; the email sign-in form with its blue Sign in button. Launch log lists
  the gaps (vatRate, vatNumber, rcs, fullInverse, payments disabled).

## 2026-09-16 — Country names shown in the interface language (Sabily)

- **Approved by:** Yazid (explicit, in session). The client-side answer to
  the backend request "country names not localized"; no backend change needed.
- **Scope, as asked:** every structured country field: the Store destination
  list, the destination header, the multi-country finder (picker, chosen
  chips, results, "missing" line), a pack's coverage list. Backend product
  names ("Best World", "One-off EU28PLUS 500MB") are shown as sent.
- **One place beyond the list, flagged:** the sign-up country picker also
  shows, orders and searches countries in the interface language. It is the
  same field kind; leaving it English beside a localized catalogue was the
  inconsistency to avoid.
- **How:** `tool/gen_place_names.dart` now writes the CLDR 48.2.0 name per
  language to `lib/core/i18n/country_names.g.dart` (core, so account can use
  it under rule L2); `countryName(code, language, fallback)` returns it or the
  backend's English. Search-only data (CLDR alternates, Wikidata capitals)
  stays in the catalogue. The text fold moved to `core/i18n/fold.dart`.
- **Found while checking, fixed:** lists sorted by raw code units put
  "États-Unis" after "Zimbabwe" and split Arabic names by alef form. Coverage
  list, finder picker and sign-up picker now order by the folded name
  (`compareCountryNames`).
- **Capitals:** confirmed search-only. A test fails if anything under `lib/`
  outside the catalogue domain reads them.
- **Status:** built. Emulator, live catalogue: **Arabic** (Store list,
  Austria header with mirrored back arrow, pack coverage, finder picker,
  chips and results: المملكة المتحدة · أستراليا) and **French** (Store list,
  Autriche header, coverage, picker ordered Égypte, Émirats…, Équateur,
  Espagne; results "Royaume-Uni · Namibie", "Manque : Namibie").

## 2026-09-15 — Destination search: every language, accents, typos (Sabily)

- **Approved by:** Yazid (explicit, in session).
- **Found first:** "Alger" already found Algeria (a plain substring of the
  English name); now pinned by a test. Two real bugs were elsewhere:
  - the fold kept only a-z and 0-9, so an **Arabic query folded to nothing
    and filtered nothing**;
  - the accent table was hand-written and partial (no ß, ł, ő, ř…).
- **Built:**
  - `tool/gen_place_names.dart` generates `place_names.g.dart` from **Unicode
    CLDR 48.2.0** (country names, en fr ar es de sl sq, alternative names
    included) and **Wikidata** (capital labels in the same languages). A Wikidata
    capital is kept only when its English label matches the curated capitals
    table: 233 kept; 7 genuine disagreements rejected (e.g. Aden for Yemen,
    Rawalpindi for Pakistan); 8 places without a confirmed capital keep the
    English one.
  - Unicode-aware fold: any script kept; Arabic vowel marks, tatweel and
    hamza/alef/ya/ta-marbuta variants folded; Latin diacritics folded, with a
    test that every generated name folds to plain letters and none to nothing.
  - Typo tolerance (optimal string alignment distance: 1 edit from 4 letters,
    2 from 9, adjacent swaps count as one), **only when nothing matches
    exactly**, so "Zambia" never lists Gambia and "Iran" never lists Iraq.
  - Store and the multi-country picker share the one search.
- **Not changed:** destinations are still displayed with the backend's English
  names. The generated CLDR data would allow localised display; that is a
  visible change and was not asked for.
- **Status:** built. Emulator (Sabily, Arabic UI, live catalogue):
  Alger, Algerie, Algerien, Argelia, Algeriaa, Alegria each find only
  Algeria; Wien, Austria; Londres, the United Kingdom; Varsovie, Poland;
  Zambia, only Zambia. Arabic queries could not be typed on the emulator
  (`adb input text` rejects non-ASCII); they are covered by
  `test/modules/destination_search_test.dart` against the real data.

## 2026-09-15 — eSimple shop register: cyan back on Store and My eSIMs

- **Approved by:** Yazid (explicit, in session), with the rule taken from
  screenshots of esimple.at: cyan for large headlines, bold prices and fills;
  navy for smaller text and every button; white badges with dark text.
- **Scope:** Store, a destination's packs, My eSIMs. Home, sign-in, Profile
  and the navigation bar are unchanged.
- **How:** an optional `theme.shop` block in `brand.json`, read through
  `ShopTokens` by those screens only. Each default is the token the widget read
  before, so a brand without the block renders as it did: Sabily's store and
  destination goldens are unchanged.
- **Interpretations taken while building:**
  - The pack detail and multi-country screens share the pack hero and chips,
    so they carry the cyan hero and active chip. Their other colours were not
    touched.
  - Inactive filter chips keep a light ground with dark text, as the site's
    filter list does; only the active chip is filled.
  - Small white-on-cyan text remains in the header (country code, `EUR` tag),
    the same pattern as the site's active chip. Flagged in the eSimple README.
- **Status:** built. Emulator, live eSimple catalogue (refreshed from the
  network, 202 destinations): Shop, Austria's header, validity and data chips
  (tapping "7 Tage" filters the list), pack cards. My eSIMs on the device:
  signed-out state only. Its cards (status pill, allowance, usage bar,
  top-up) are covered by `test/widget/shop_palette_test.dart`, pending an
  eSimple test account.

## 2026-09-15 — eSimple backend, contrast fix, logo corners

- **Approved by:** Yazid (explicit, in session).
- **Backend:** `https://esimple.transasim.com/api` confirmed as eSimple's
  `apiBaseUrl` (already set). Emulator, fresh install, signed out: catalogue
  (`countries/all` and `packs/all` both 200, 202 destinations); account
  path: `POST /account/reset-password/init` 200 and the code step shown. Not
  exercised on device: a sign-in submit (the emulator's scripted typing kept
  landing in the wrong field).
- **Contrast:** `primary #2f3b4f`, `accent #dbf5f6`, `cta #49cdd2`,
  `ctaText #2f3b4f`: 11.3:1 text, 5.9:1 on buttons (was 1.9:1).
- **Logo:** the visible white corners were the opaque App Store icon used as
  the mark; replaced by the published Android foreground (real alpha),
  trimmed so it fills the circular badge. A key-out of Alpha's JPEG left a
  fringe and was not shipped; `logo-full.png` stays opaque on a white-only
  ground until the client sends a transparent file.
- **Status:** built and verified on the emulator (screens: Home, Shop,
  Profile, sign-in, password reset).

## 2026-09-15 — eSimple, the second client, as configuration

- **Approved by:** Yazid (explicit, in session).
- **Scope:** add eSimple without changing core, modules or architecture:
  `brands/esimple/`, `lib/flavors/main_esimple.dart`, Android flavor,
  logo assets; check eSimple's backend against Sabily's; prove brand
  isolation on the two real clients; check eSimple's store readiness
  separately.
- **Decisions taken while building (flagged in `brands/esimple/README.md`):**
  - Brand assets are now **bundled per flavor** (`pubspec.yaml`
    `flavors:`). Before, every app would have carried every client's config,
    logos and video. Tests serve brand files from disk
    (`test/flutter_test_config.dart`), because `flutter test` has no flavor.
  - Colour roles copied from esimple.at's own declaration. They fail contrast
    in the app; an AA-passing mapping is proposed for Yazid.
  - The mark and launcher icon are the icon eSimple publishes today, not
    Alpha's new wordmark (no square symbol exists in the new style).
  - Default language `de`; six languages, as esimple.at serves.
- **Not done here:** the iOS scheme (no Mac; Sabily has none either).
- **Status:** built. Emulator, live eSimple backend: German by default,
  202 destinations from `esimple.transasim.com`, eSimple support, legal and
  partner links. The eSimple APK contains only `brands/esimple/*` (and
  Sabily's only its own). The isolation test fails on a planted hardcoded
  Sabily value.

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
