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
| Colours | Alpha's bundle (`esimple colors.jpeg`: `#49CDD2`, `#2F3B4F`, `#3B82F6`), mapped to the app's roles for contrast (below) |
| `logo-full.png` | Alpha's bundle (`esimple logo.jpeg`), cropped to the badge |
| `logo-mark.png`, Android launcher and splash | the icon eSimple publishes today: `spc/esimple`'s Android adaptive-icon foreground, which has real transparency, trimmed to its edge |
| Languages | the six esimple.at serves (`hreflang`): de, en, fr, ar, sl, sq. No Spanish |
| Taglines | esimple.at page titles in de/en/fr |
| Support email | esimple.at footer, `contact@esimple.at` |
| Partner URL | esimple.at "Devenir partenaire" (Alpha: "Portail revendeurs: oui") |
| Legal entity | esimple.at Impressum: **Eljhat Kadrii e.U.**, Hernalser Hauptstraße 135, 1170 Wien, FN 628945w (Handelsgericht Wien), host Contabo GmbH |
| Backend | `https://esimple.transasim.com/api`: valid certificate, same API shape as Sabily's, 983 packs |

## Colour roles: why they differ from the website's

esimple.at declares `primary #49cdd2`, `accent #3b82f6`, `cta #2f3b4f`. In
the app, `primary` is the text and filled-button colour and `accent` a soft
tile tint, so that mapping put cyan text on white at **1.9:1** and cyan on
blue tiles. Applied 2026-09-15 (approved, and Alpha had seen the problem by
eye):

| Role | Value | Contrast |
|---|---|---|
| `primary` | `#2f3b4f` navy | 11.3:1 on white, both ways |
| `accent` | `#dbf5f6` light cyan tint (20% of `#49cdd2`) | navy on it 9.9:1 |
| `surface` | `#ffffff` | — |
| `cta` / `ctaText` | `#49cdd2` / `#2f3b4f` | 5.9:1 |

Cyan stays the colour of every call to action; navy carries the text.

### The shop's register (`theme.shop`): Store, destination, My eSIMs

Those screens take the cyan-heavy look back, following what esimple.at itself
does (homepage, destinations, footer; checked 2026-09-15):

| esimple.at | In the app | Token |
|---|---|---|
| Large display headlines and bold prices in cyan | "Finden Sie Ihre eSIM", "Verfügbare Pakete", "Meine eSIMs", prices, a plan's allowance | `display` |
| Filter labels and region names in dark navy | pack and destination names, specs, labels | `primary` (unchanged) |
| The only cyan fill is the active filter chip, white text on it | active chip; also the destination header and pack hero gradients, the usage bar | `fill`, `fillEnd`, `onFill` |
| Every button solid navy, white text | "Dieses Paket kaufen", "Aufladen", retry | `primary`, `cta`/`ctaText` |
| Badges white with dark text | price per GB, eSIM status; a pack's price tag white with the price in cyan | `badge`/`onBadge`, `priceBadge`/`onPriceBadge` |

Home (including its cyan "Gutschein scannen" CTA), sign-in, Profile and the
navigation bar keep the roles above. Sabily writes no `shop` block and renders
exactly as before (its goldens did not move).

Small text that is still white on cyan, as the site does it on its active chip,
and so still low-contrast: the header's country-code line and its `EUR` tag.
Flagged, not changed.

## Needs a decision before release

- [ ] **Three logos disagree.** Alpha's bundle has "eSIMPLE" white in the
      badge; the old app and its store icon have "eSIM" in the badge beside a
      navy "PLE". The mark and launcher icon are the published "eSIM" icon, so
      the app matches what users have installed. Needed from the client: a
      square symbol in the new style, a transparent (or vector) lockup, and
      the **dark-background variant** (`logo.fullInverse` is absent and warns).
- [ ] **`logo-full.png` is still the opaque JPEG crop, deliberately.** A
      key-out of the white was tried: the background is not one colour
      (236-254, JPEG noise), and the result, even with the edge un-blended,
      kept a light fringe along the badge on dark grounds. It was not shipped.
      Nothing in the app draws `logo.full` today, and the only ground a brand
      logo sits on is `surface #ffffff`, where the white cannot read as a
      rectangle. A stopgap, not a fix: the real fix is a transparent source file
      from the client. The white corners that WERE visible (the mark on the Home
      gradient) came from the opaque App Store icon, and are gone: the mark now
      uses the published Android foreground, which has real alpha.
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
- [ ] **No pack photos.** Sabily's are Sabily's; eSimple shows the plain
      pack header until it has its own.

## The intro animation

`logo.intro` plays once at launch, the mechanism Sabily has had since
2026-09-14: bundled with the brand's other assets, centred at its own aspect
ratio, muted, skipped if it cannot start within 1.5 s, and ended by the
video's own completion — never a timer.

- **Source:** `esimple bundel/logo for phone.mp4`, 2.10 MB, H.264 1080x1920, 24 fps, 4.000 s.
- **The silent AAC track was removed** (stream copy, `-an`; the video
  bitstream is byte-for-byte the file Alpha sent). It was true silence, but
  the player still set up a second decoder for it, which cost enough on a
  cold start to miss the 1.5 s deadline: the animation did not play at all
  until it was stripped. Sabily's file has no audio track either.
- **`logo.introBackground` is `#000000`**, the colour of the animation's own
  four corners, and `android/app/src/esimple/res/values/colors.xml` repeats it
  so the OS launch window, the ground around the video and its opening frame
  are all the same black. The iOS launch screen needs the same when there is
  a Mac.

## Google & Apple sign-in

**Recreated 2026-09-27.** The whole Google Cloud project was rebuilt from
scratch ("we just recreate all the id and keys" -- Alpha). Project
`292877676224` (the one `googleServerClientId` used to point at) is now
RETIRED; do not reuse that value.

Current project: `1029607422562`. `mobile.googleServerClientId` in
`brand.json` is wired to this project's **Web application** client -- the
only Google value any Dart code reads (`social_sign_in.dart`, passed as
`serverClientId`):

- [x] Web application client (now in `brand.json`):
      `1029607422562-dnv5kd97665ls15och6nss7kdi62q1md.apps.googleusercontent.com`
- [ ] Google iOS client:
      `1029607422562-bh3kj59gp468knt6k1fme0pgjo66ua1e.apps.googleusercontent.com`
      -- not read by Dart. Goes in a per-flavor `ios/Runner/Info.plist`
      (`GIDClientID` + reversed-client-ID URL scheme) once iOS packaging
      starts; none exists yet.
- [ ] Google Android client (also not read by Dart -- a Cloud Console
      registration tied to package name + SHA-1, informational only):
      `1029607422562-mcsntaef7emhloglsuluu67654oht7ur.apps.googleusercontent.com`

Filled in 2026-09-27, now that eSimple's upload key was reset (below):

- [x] Android client, debug keystore SHA-1 (shared machine-wide debug key,
      same one Sabily's README already lists):
      `0C:0C:CF:62:55:53:BA:E1:E9:E4:9A:E6:68:51:B5:42:17:8C:36:1E`
- [x] Android client, Play app signing certificate SHA-1 (from Play Console's
      "App signing key" panel, Alpha, 2026-09-27):
      `4B:60:D6:1C:B0:EB:F7:A0:A2:6C:75:26:47:E5:D4:BD:56:99:8A:1A`
      -- **registered against the `1029607422562` Android OAuth client
      in Google Cloud Console, Alpha, 2026-09-27.** Google sign-in on a
      real Play-installed build should now resolve correctly; if it still
      shows as a silent cancel, `UNREGISTERED_ON_API_CONSOLE` in logcat is
      the first thing to check (same failure mode documented elsewhere in
      this file).

Still open, same as Sabily's: OAuth consent screen state (Testing mode,
test-user list) for project `1029607422562` is unconfirmed.

## Upload key reset -- 2026-09-27

eSimple's upload key was reset in Play Console. The new keystore had
already been generated ahead of time and parked at
`android/esimple-key.properties.pending` (gitignored, not wired into the
build on purpose -- see the comment in `android/app/build.gradle.kts`) so
that resetting it in Play Console wouldn't touch a build that was still
signing with something else in the meantime.

Verified today: Play Console's "Upload key certificate" panel now shows
SHA-1 `C1:25:44:D4:97:81:4E:24:27:9C:22:3B:D6:CE:F4:A4:D2:65:17:6B` and
SHA-256 `63:D0:16:8F:82:9B:CA:2D:2B:0B:05:1C:DB:D1:2E:44:20:45:09:AF:BA:2C:F6:3C:DB:92:4B:9B:52:66:3F:8B`
-- matched byte-for-byte against the pending keystore with `keytool -list -v`
before touching anything. So the reset has gone through and Play now
expects uploads signed by that keystore.

**Activated**: `android/esimple-key.properties.pending` renamed to
`android/esimple-key.properties`. `flutter build appbundle --release
--flavor esimple` now signs with the real upload key instead of falling
back to debug.

### Apple

Apple needs no *app-code* config value: `SignInWithApple.getAppleIDCredential()`
is called with no service ID / team ID / app ID anywhere in `lib/`. What
Apple sign-in actually needs is native Xcode signing configuration, which
does not exist -- eSimple has no iOS target yet either.

On file for when it does:

- App ID: `com.esimple.esim` (already equals `applicationId` above --
  nothing to change)
- Team ID: `DP7F8WQCJD` (same Apple Developer team as Sabily's)
- Services ID: `at.esimple.auth` -- for the **web/backend** Sign in with
  Apple flow, which this app does not wire up (iOS-only, native credential
  flow, no service ID involved). Out of scope for this repo.

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
