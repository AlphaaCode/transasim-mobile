# transasim-mobile

A white-label eSIM app: **one Flutter codebase, three client brands**, each built as a
flavor. Nothing about a client lives in code — a brand is `brands/<slug>/brand.json`
plus a folder of assets, and `lib/flavors/main_<slug>.dart` is one line. Gradle reads
each Android flavor (applicationId, label, signing file) from `brands/*/brand.json`, so
`android/app/build.gradle.kts` names no client. If a client
ever needs a change under `lib/`, that is a gap in the socle, not a task for that
client; fix it so every brand gets it.

The three clients today are **sabily** (Sabily, published, French-led, seven
languages), **esimple** (eSimple, published in Austria, German-led, six languages) and
**acorn** (Odyssey Global SIM, never published, English only). They differ only in
configuration, and a test proves it: no two of them may share a brand value.

Flutter 3.47.3 / Dart 3.13, Riverpod 3, go_router, dio. On this machine Flutter is at
`/c/src/flutter/bin` and is **not** on PATH by default — add it in bash first. On the
Mac that builds iOS it is at `~/development/flutter/bin`, also not on PATH.

## Layout, and the one structural rule

```
lib/core/       the socle: brand config, theme, i18n, storage, network, onboarding
lib/modules/    features: catalog, account, checkout, esim, wallet
lib/flavors/    one line per brand
brands/<slug>/  brand.json, README.md, assets/ (logos, pack images, intro video)
tool/           check_layers.dart, gen_brand_flavors.dart, gen_place_names.dart,
                studio/ (the brand builder: see "Studio" below)
test/           503 tests, including goldens under test/widget/goldens/
```

`dart run tool/check_layers.dart` enforces what a style guide cannot: core never
imports a module (L1), modules never import each other (L2), modules never touch
`dart:io` or dio directly (L4), and **no colour literal exists outside
`app_theme.dart`** (C1). Run it with the tests; CI fails on it.

## Commands that actually work

Before any build works, the Android SDK needs components the base install lacks:
the build compiles native C++ (`path_provider_android` and `mobile_scanner` pull
in `jni`/`jni_flutter`, a `:jni` CMake subproject), so on top of `platform-tools`
and `build-tools` it needs **NDK `28.2.13676358`** (Flutter's `flutter.ndkVersion`),
**CMake `3.22.1`**, and platforms **`android-35`** (the `:jni` module's compileSdk)
*and* **`android-36`** (the app's). A from-scratch machine without them fails at
`:jni:configureCMakeDebug` (`[CXX1300] CMake … not found`) or "Failed to find
target … android-35". Install via `sdkmanager`, but on Windows invoke its Java
class directly (`java -cp cmdline-tools/latest/lib/sdkmanager-classpath.jar
com.android.sdklib.tool.sdkmanager.SdkManagerCli "ndk;28.2.13676358" …`), never
`sdkmanager.bat`, which mis-parses the ";" in package names and crashes.

```bash
export PATH="/c/src/flutter/bin:$PATH"        # bash, this machine

flutter pub get
flutter test                                   # 503 pass as of 2026-10-04
flutter analyze
dart run tool/check_layers.dart
dart run tool/gen_brand_flavors.dart           # after adding or removing a brands/ folder
dart run tool/studio/bin/studio.dart --check   # every brand valid, every generated file in sync

# Run on a connected device/emulator (pick the flavor and its entry point)
flutter run --flavor acorn -t lib/flavors/main_acorn.dart \
  --dart-define=API_BASE_URL=https://acorn.transasim.com/api

# Build, per brand. Split first, then universal — both, every time, or a stale
# universal APK from an old commit sits next to fresh split ones.
flutter build apk --profile --split-per-abi --flavor esimple \
  -t lib/flavors/main_esimple.dart \
  --dart-define=API_BASE_URL=https://esimple.transasim.com/api
flutter build apk --profile --flavor esimple \
  -t lib/flavors/main_esimple.dart \
  --dart-define=API_BASE_URL=https://esimple.transasim.com/api
```

Swap `acorn` / `esimple` / `sabily` in all four places (flavor, entry point, URL,
and the output name).

iOS, on the Mac (Xcode 26 or later — Apple refuses older SDKs). Signing is automatic
(team `DP7F8WQCJD`, the Xcode account on that Mac). `build ipa` signs for the App
Store; the upload uses the same Xcode account, so no password or API key is involved:

```bash
export PATH="$HOME/development/flutter/bin:$PATH"   # zsh, the Mac
flutter build ipa --release --flavor sabily -t lib/flavors/main_sabily.dart \
  --build-name 2.0.0 --build-number 20
# ExportOptions.plist: method app-store-connect, destination upload, teamID DP7F8WQCJD
xcodebuild -exportArchive -archivePath build/ios/archive/Runner.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/ios/upload \
  -allowProvisioningUpdates
```

`build ipa` overwrites `build/ios/archive` and `build/ios/ipa` on every run: copy one
brand's archive aside before building the next. A new brand on iOS: add its
`ios/Flutter/<slug>.xcconfig` and `ios/Runner/Brands/Brand-<slug>.xcassets`, then run
`ruby tool/ios_flavors.rb`. The backends are `https://<slug>.transasim.com/api` for all
three today. Goldens: `flutter test --update-goldens`, and look at the diff before
accepting it — a moved golden usually means a real rendering change.

Emulator on this machine (AVD `transasim_test` — Pixel 6, Android 15 / API 35,
google_apis x86_64). The Android SDK is at `/c/src/android-sdk`, and WHPX
acceleration is available, so boot with `-gpu host`, not swiftshader:

```bash
/c/src/android-sdk/emulator/emulator.exe -avd transasim_test -gpu host \
  -no-boot-anim -no-audio -no-snapshot-save
MSYS_NO_PATHCONV=1 /c/src/android-sdk/platform-tools/adb.exe install -r <apk>
```

Cold boot is ~85s (a fresh AVD's first boot is ~150s, one-time). The daemon heap
is capped in `android/gradle.properties` (-Xmx1536m) so a concurrent build no
longer OOM-kills it. The AVD, these paths and the SDK install are machine-local —
not in the repo (see "This checkout vs. a fresh clone") — so another machine's
will differ; `C:\src\transasim_test.bat` is a one-click launcher. Its timings are
not evidence about real-device performance.

## Studio, the brand builder (`tool/studio/`)

`tool/studio/studio.bat` (or `dart run tool/studio/bin/studio.dart` from the repo root)
serves http://127.0.0.1:4777 and opens it. The Brand tab edits `brand.json`, checked by
the app's own `BrandConfig`, and shows as diffs every file it would write. Apply writes
those files and nothing else: no commit, no push, and a file git already shows as
changed is overwritten only after you confirm. `--check` validates every brand and
fails if any generated file has drifted; `test/studio/golden_master_test.dart` does the
same inside `flutter test`.

**Studio owns these files: never edit them by hand.** Edit `brands/<slug>/brand.json`
(or `studio.json`) and regenerate. They are `lib/flavors/main_<slug>.dart`, the text
files under `android/app/src/<slug>/res/`, `ios/Flutter/<slug>.xcconfig`, the JSON in
`ios/Runner/Brands/Brand-<slug>.xcassets/`, and the pubspec flavor block. Their
templates are `tool/studio/templates/**.tmpl`. `brands/<slug>/studio.json` holds what
Studio needs and the app does not: `appleTeamId`, and the `published` store ids,
which the form locks.

**Assets tab.** One drop zone per file `brand.json` names (marks, lockups, intro, card
background, pack images and country overrides). Each previews what the file becomes and
refuses a bad one with the reason. Saving writes that file only, plus the brand.json
field and, for a pack image, its row in `PACK-IMAGES-CREDITS.md`; a pack image is
refused without a source and a licence. An intro with an audio track is refused, and
Studio offers the ffmpeg strip (it says how to install ffmpeg when it is missing).

**The icon set** (`brand_mark.png`, the themed-icon monochrome layer,
`mipmap-*/ic_launcher.png`, `drawable-*/ic_notification.png`, `AppIcon-1024.png`, and
`mipmap-anydpi-v33/ic_launcher.xml`, which names the monochrome layer) is generated
from the logo mark, **only** for a new brand or when you press *Regenerate assets* for
that brand. Sabily's, eSimple's and Acorn's icons are still the hand-made ones until
someone presses it. The safe zone is a 300 px radius in the 432 px brand_mark,
because `brand_launcher_foreground.xml` insets it 28% per side
(`tool/studio/src/icons.dart` derives it; `test/studio/icon_rules_test.dart` checks it).

eSimple's launcher icon is the exception to "Studio made it": it comes from
`brands/esimple/assets/new logo.pdf` via `dart run tool/gen_esimple_icon.dart`,
which calls Studio's own `renderIcons` but writes only the four files this repo
ships (brand_mark, the xxxhdpi launcher, the iOS 1024, the Play 512) rather than
Studio's full set. Sabily's and Acorn's icons are still hand-made.

**New brand** creates everything in one previewed Apply: `brands/<slug>/` (brand.json,
studio.json, the logo), the Android `res/`, the iOS xcconfig and asset catalog, the
entry point and the pubspec block. Studio refuses a slug Gradle already uses, and any
value another brand has (`tool/studio/src/distinct.dart`, shared with the wiring test).
Two things stay outside it. The Xcode project needs `ruby tool/ios_flavors.rb` on the Mac;
until then the wiring test *skips* that brand's Xcode checks, but never a shipped
brand's. And the intro video is optional, added later from the Assets tab.

**Integrations tab and guides.** Every value that comes from a console outside the
repo (Google web, iOS and Android clients, the OAuth consent screen, the Play App
Signing SHA-1, the Play app, the Apple team, the Stripe publishable key) has a guide in
`tool/studio/guides/<id>.yaml`: the page to open, filled with this brand's ids
(`gcpProjectId`, `googleAccount` and the Play ids live in `studio.json`), the steps, the
values to copy into the console, and the rules a pasted value must pass, with accept
and reject examples that `test/studio/guides_test.dart` runs. **When a console step
costs time, add or fix its guide the same day**: it is data, not code. A pasted value
reaches brand.json or studio.json only through the tab's previewed Apply. Studio refuses
anything shaped like a secret (`sk_`, `rk_`, `whsec_`, `GOCSPX-`, PEM) in any field, and
never asks for a password: "Read from keystore" takes the upload SHA-1 from
`android/<slug>-key.properties`, passing the password to keytool through its environment.

Studio runs on the plain Dart VM, which has no `dart:ui`, and still imports
`lib/core/brand/brand_config.dart`. So that file and `lib/core/i18n/locales.dart` get
their one Flutter type each through `if (dart.library.mirrors) '../headless.dart'`
(why not `dart.library.ui`: see `lib/core/headless.dart`). Keep anything they import
Flutter-free; `test/studio/studio_test.dart` runs Studio on the plain VM to catch it.

## Where the rest of the knowledge is

| Question | File |
|---|---|
| Why is it built this way? | `ARCHITECTURE-MOBILE.md` (French, ~100 KB, the design authority) |
| What was approved, by whom, when? | `docs/APPROVALS.md` — check before assuming something is still awaiting a decision |
| How does a brand's own configuration read? | `brands/<slug>/README.md` — sources, gaps, what to ask the client |
| Store submission, signing | `docs/STORE-SUBMISSION.md`, `docs/ANDROID-SETUP.md` |
| What the old apps did, and their bugs | `ANALYSE-EXISTANT.md` |
| Studio, the local brand builder: what it will own, phase by phase | `docs/STUDIO-SPEC.md` — Phase 0 (flavors and signing from `brand.json`), 1a (server, Brand tab, text generators), 1b (Assets, icon set, New brand) and 1c (Integrations, guides) done 2026-10-04 |

`ARCHITECTURE-MOBILE.md` was written before any code and carries a note at the top
listing where reality has since diverged from it. Trust this file and the code for
*what is*, that file for *why*.

## Where each brand actually stands

| | Sabily | eSimple | Acorn |
|---|---|---|---|
| Android flavor, catalogue, account screens | built | built | built |
| Verified on emulator against the live backend | yes | yes | yes |
| **Verified on a real phone** | **yes** — Galaxy S23 Ultra, 2026-10-05 | **no** | **no** |
| Intro animation | yes | yes (20/09) | yes (20/09) |
| Store identity | `com.sabily.esim`, frozen | `com.esimple.esim`, frozen | `com.transasim.acorn`, **provisional** |
| Payments | **live** — real `pk_live_` key, real purchase 2026-10-05 | **live** — real `pk_live_` key, never exercised | disabled: no usable key |
| **Android** | 1.1.8 (21), release AAB built | 1.1.8 (21), release AAB built | not submitted |
| **iOS** | pending: build 1.1.8 from `release/1.1.8-21` on the Mac | pending: same | flavor wired, never uploaded |

iOS was first built on 2026-10-03, on a Mac. Each brand is an Xcode flavor, the
counterpart of the Android one:

- `ios/Flutter/<slug>.xcconfig` — bundle id, display name, team, Google client IDs.
  The OS reads these before any Dart runs, so they repeat `brand.json`; the wiring
  test keeps the two equal.
- `ios/Runner/Brands/Brand-<slug>.xcassets` — app icon and launch colour. The target
  excludes every `Brand-*.xcassets` and each flavor brings back only its own, so one
  client's icon never ships in another's app. The socle has no icon of its own: an
  unflavored build fails instead of shipping the wrong one.
- `Debug-/Release-/Profile-<slug>` configurations and a shared `<slug>` scheme, made
  by `ruby tool/ios_flavors.rb` (idempotent; never hand-edit the project file for this).

The App Store versions run ahead of Android's: the iOS listings were already at 1.3
(Sabily) and 1.0 (eSimple), so iOS ships as `--build-name 2.0.0` while `pubspec.yaml`
stays at Android's `1.1.7+20`. Pass the build name per platform; do not bump the
pubspec to satisfy one store.

Every device check so far has been signed out, with one exception: Sign in with Apple
on the iOS simulator against the live Sabily backend (`/v1/auth/apple` 200, then
`/account` 200, 2026-10-03). No iOS build has run on a real phone yet. Checkout has
never been run (the placeholder Stripe key disables it), and no voucher has ever been
redeemed — see below for why that one is not a casual test.

## What will trip you up

- **A silent audio track in an intro video stops the animation from playing.** The
  intro is abandoned if the video has not started within 1.5 s. A muted-but-present
  AAC track makes the player build a second decoder, which costs enough on a cold
  start to miss that deadline — the animation then never appears, silently. Strip it
  before bundling: `ffmpeg -i in.mp4 -map 0:v:0 -c copy -an -write_tmcd 0 out.mp4`
  (stream copy; the video bytes do not change). Full story in
  `ARCHITECTURE-MOBILE.md` §2.4.1.
- **`--dart-define=API_BASE_URL` throws in a release build**, on purpose — and it
  is a *runtime* crash on launch, not a build error. `BrandLoader._applyBuildOverrides`
  (`lib/core/brand/brand_loader.dart`) reads it with `const String.fromEnvironment`
  (which works fine in release — not a const-folding or tree-shaking bug), then
  deliberately `throw`s a `StateError` under `kReleaseMode`: a release must talk to
  the client's own backend and nothing else (§10.3), so a mis-built one fails loudly.
  The build completes; the app dies at startup. The fix is not to make release accept
  the define — use it for debug/profile only, and let a release read its URL from
  `brand.json`. Pointing a release at a non-prod backend is a deliberate code change,
  not a flag.
- **Two `flavors:` entries per brand in `pubspec.yaml`** — the `brand.json` and the
  assets folder. Miss one and every client ships every other client's files. They
  are generated between marker comments by `dart run tool/gen_brand_flavors.dart`;
  never type them. The wiring test fails until the block matches the `brands/`
  folders.
- **The native launch window colour is duplicated** in
  `android/app/src/<slug>/res/values/colors.xml` and the iOS `LaunchBackground`
  colorset, and must equal `logo.introBackground ?? colors.surface`. Studio generates
  both from `brand.json`, and tests enforce it; change `brand.json` and regenerate.
- **Sabily and eSimple carry live `pk_live_` publishable keys in `brand.json`, so
  payments are ENABLED on both.** `isUsableStripeKey` accepts `pk_(test|live)_`
  plus 24 or more base62 characters; both keys are live with 99-character bodies,
  so `canTakePayments` returns true and checkout charges real money. Only Acorn
  is still disabled, because it has no usable key. A publishable key is public by
  design — it ships inside the APK — but still never copy one in from a client
  website or an old branch: use the key the client gave for that brand, or you
  will be charging through someone else's account.
- **Voucher redemption calls Transatel directly and provisions a real eSIM**, with no
  Stripe involvement, on every one of these backends. Never test it with a real code
  unless someone has explicitly asked for exactly that.
- Colour literals outside `app_theme.dart` fail the layer check, including in a test
  you were about to write quickly.
- **Google sign-in on iOS needs an iOS OAuth client, not just the web one.** The iOS
  plugin ignores the `serverClientId` Dart passes unless a client ID comes with it, and
  reads `GIDClientID` / `GIDServerClientID` and the reversed-client URL scheme from
  Info.plist instead — filled from the flavor's xcconfig. Without them the button fails
  on every tap. The wiring test refuses a brand that offers Google with no iOS client.
- **Goldens are rendered on Windows.** On macOS ~22 golden tests fail by a few percent
  of pixels (font rasterisation), with no code change. Regenerate them on the Windows
  machine, not on the Mac.

## This checkout vs. a fresh clone

`.gitignore` excludes `.dart_tool/`, `.flutter-plugins-dependencies` and all of
`build/`. Everything in those is reproducible: `flutter pub get` restores the first
two, and the APKs under `build/app/outputs/flutter-apk/` come back from the build
commands above. A clone is not missing anything that matters.

What is **not** in the repo and not reproducible from it: the Android signing
keystores and their passwords (one per brand: `android/<slug>-key.properties`
pointing at `android/app/<slug>-upload-key.jks`; a brand without one is signed with
the debug key), the Apple Distribution certificate (in the Mac's
keychain; Xcode recreates it under automatic signing, given the team's account), the
emulator AVD, the local Flutter and Android SDK installs, and the client source material (logos, animations, onboarding documents)
that lives outside this folder. Those move by hand or not at all.

Line endings are pinned by `.gitattributes` (`* text=auto eol=lf`), so the working
tree is LF on every machine regardless of that machine's `core.autocrlf`. If
`git status` ever shows a pile of modified files whose `git diff -w` is empty, that
setting was bypassed — re-run `git add --renormalize .` rather than committing the
noise.
