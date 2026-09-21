# transasim-mobile

A white-label eSIM app: **one Flutter codebase, three client brands**, each built as a
flavor. Nothing about a client lives in code — a brand is `brands/<slug>/brand.json`
plus a folder of assets, and `lib/flavors/main_<slug>.dart` is one line. If a client
ever needs a change under `lib/`, that is a gap in the socle, not a task for that
client; fix it so every brand gets it.

The three clients today are **sabily** (Sabily, published, French-led, seven
languages), **esimple** (eSimple, published in Austria, German-led, six languages) and
**acorn** (Odyssey Global SIM, never published, English only). They differ only in
configuration, and a test proves it: no two of them may share a brand value.

Flutter 3.47.3 / Dart 3.13, Riverpod 3, go_router, dio. On this machine Flutter is at
`/c/src/flutter/bin` and is **not** on PATH by default — add it in bash first.

## Layout, and the one structural rule

```
lib/core/       the socle: brand config, theme, i18n, storage, network, onboarding
lib/modules/    features: catalog, account, checkout, esim, wallet
lib/flavors/    one line per brand
brands/<slug>/  brand.json, README.md, assets/ (logos, pack images, intro video)
tool/           check_layers.dart, gen_place_names.dart
test/           359 tests, including goldens under test/widget/goldens/
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
flutter test                                   # 359 pass as of 2026-09-21
flutter analyze
dart run tool/check_layers.dart

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
and the output name). The backends are `https://<slug>.transasim.com/api` for all
three today. Goldens: `flutter test --update-goldens`, and look at the diff before
accepting it — a moved golden usually means a real rendering change.

Emulator on this machine (AVD `sabily_test`, adb at `/c/Android/platform-tools/`):

```bash
/c/Android/emulator/emulator.exe -avd sabily_test -memory 2048 \
  -no-boot-anim -no-audio -gpu swiftshader_indirect -no-snapshot-save
MSYS_NO_PATHCONV=1 /c/Android/platform-tools/adb.exe install -r <apk>
```

It is slow and memory-hungry enough to be killed by the host; its timings are not
evidence about real-device performance.

## Where the rest of the knowledge is

| Question | File |
|---|---|
| Why is it built this way? | `ARCHITECTURE-MOBILE.md` (French, ~100 KB, the design authority) |
| What was approved, by whom, when? | `docs/APPROVALS.md` — check before assuming something is still awaiting a decision |
| How does a brand's own configuration read? | `brands/<slug>/README.md` — sources, gaps, what to ask the client |
| Store submission, signing | `docs/STORE-SUBMISSION.md`, `docs/ANDROID-SETUP.md` |
| What the old apps did, and their bugs | `ANALYSE-EXISTANT.md` |

`ARCHITECTURE-MOBILE.md` was written before any code and carries a note at the top
listing where reality has since diverged from it. Trust this file and the code for
*what is*, that file for *why*.

## Where each brand actually stands

| | Sabily | eSimple | Acorn |
|---|---|---|---|
| Android flavor, catalogue, account screens | built | built | built |
| Verified on emulator against the live backend | yes | yes | yes |
| **Verified on a real phone** | **no** | **no** | **no** |
| Intro animation | yes | yes (20/09) | yes (20/09) |
| Store identity | `com.sabily.esim`, frozen | `com.esimple.esim`, frozen | `com.transasim.acorn`, **provisional** |
| Payments | placeholder Stripe key, checkout disabled | same | same |
| **iOS** | **does not exist** | **does not exist** | **does not exist** |

iOS has never been built for any brand, because there has never been a Mac. There are
no schemes, no configurations, no bundle wiring — only the `bundleIdentifier` values
sitting in the configs. Do not read the iOS entries in the architecture document as
finished work.

Every device check so far has been signed out: no entry in `docs/APPROVALS.md` records
a signed-in session against a real account on any brand. Checkout has never been run
(the placeholder Stripe key disables it), and no voucher has ever been redeemed — see
below for why that one is not a casual test.

## What will trip you up

- **A silent audio track in an intro video stops the animation from playing.** The
  intro is abandoned if the video has not started within 1.5 s. A muted-but-present
  AAC track makes the player build a second decoder, which costs enough on a cold
  start to miss that deadline — the animation then never appears, silently. Strip it
  before bundling: `ffmpeg -i in.mp4 -map 0:v:0 -c copy -an -write_tmcd 0 out.mp4`
  (stream copy; the video bytes do not change). Full story in
  `ARCHITECTURE-MOBILE.md` §2.4.1.
- **`--dart-define=API_BASE_URL` throws in a release build**, on purpose: a release
  must talk to the client's own backend. Use it for debug and profile only.
- **Two `flavors:` entries per brand in `pubspec.yaml`** — the `brand.json` and the
  assets folder. Miss one and every client ships every other client's files. The
  wiring test checks this, so trust the test rather than your memory.
- **The native launch window colour is duplicated** in
  `android/app/src/<slug>/res/values/colors.xml` and must equal
  `logo.introBackground ?? colors.surface`. A test enforces it. Change one, change
  both.
- **Stripe keys stay `pk_test_PLACEHOLDER_AWAITING_CLIENT`** until a client provides
  a real one; `canTakePayments` keeps checkout disabled meanwhile. Old branches and
  client websites contain live `pk_live_` keys — never copy one in.
- **Voucher redemption calls Transatel directly and provisions a real eSIM**, with no
  Stripe involvement, on every one of these backends. Never test it with a real code
  unless someone has explicitly asked for exactly that.
- Colour literals outside `app_theme.dart` fail the layer check, including in a test
  you were about to write quickly.

## This checkout vs. a fresh clone

`.gitignore` excludes `.dart_tool/`, `.flutter-plugins-dependencies` and all of
`build/`. Everything in those is reproducible: `flutter pub get` restores the first
two, and the APKs under `build/app/outputs/flutter-apk/` come back from the build
commands above. A clone is not missing anything that matters.

What is **not** in the repo and not reproducible from it: the Android signing
keystore and its passwords, the emulator AVD, the local Flutter and Android SDK
installs, and the client source material (logos, animations, onboarding documents)
that lives outside this folder. Those move by hand or not at all.

Line endings are pinned by `.gitattributes` (`* text=auto eol=lf`), so the working
tree is LF on every machine regardless of that machine's `core.autocrlf`. If
`git status` ever shows a pile of modified files whose `git diff -w` is empty, that
setting was bypassed — re-run `git add --renormalize .` rather than committing the
noise.
