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
test/           990 tests, including goldens under test/widget/goldens/
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
target … android-35". Install them without `sdkmanager.bat`. Up to cmdline-tools 19, that
.bat mis-parses the ";" in package names and crashes, so call its Java class
(`java -cp cmdline-tools/latest/lib/sdkmanager-classpath.jar
com.android.sdklib.tool.sdkmanager.SdkManagerCli "ndk;28.2.13676358" …`). **cmdline-tools
23 has no such class**: the .bat now wraps the Android CLI, so call
`cmdline-tools/latest/bin/android --sdk=<root> sdk install ndk/28.2.13676358 …`
(packages with "/"). Studio's Doctor detects which one is there and installs from a
button.

```bash
export PATH="/c/src/flutter/bin:$PATH"        # bash, this machine

flutter pub get
flutter test                                   # 1000 pass, 3 skipped, as of 2026-10-21
flutter analyze
dart run tool/check_layers.dart
dart run tool/gen_brand_flavors.dart           # after adding or removing a brands/ folder
dart run tool/studio/bin/studio.dart --check   # every brand valid, every generated file in sync

# Run on a connected device/emulator. Two flavors per brand (Slice H): <slug>
# is the store build, on its production host; <slug>Dev the DEV build, on its
# DEV host, ids + ".dev" and a red banner. No --dart-define, ever: the app
# refuses to start with one.
flutter run --flavor acornDev -t lib/flavors/main_acorn_dev.dart
flutter run --flavor acorn -t lib/flavors/main_acorn.dart

# Build, per brand. Split first, then universal — both, every time, or a stale
# universal APK from an old commit sits next to fresh split ones.
flutter build apk --profile --split-per-abi --flavor esimple -t lib/flavors/main_esimple.dart
flutter build apk --profile --flavor esimple -t lib/flavors/main_esimple.dart
```

Swap `acorn` / `esimple` / `sabily` in all three places (flavor, entry point, and
the output name); `README.md` lists every brand's commands, both flavors, and the
release checklist. eSimple has no `esimpleDev` until its server merge (below).

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
`ruby tool/ios_flavors.rb` (it wires `<slug>Dev` too, when Studio generated its
xcconfig). The backends, each brand's `mobile.apiBaseUrl` (production) and
`mobile.devApiBaseUrl` (DEV):
- Acorn: `https://acorn-api.transasim.com/api`; DEV `https://acorn.transasim.com/api`, on
  169.58.35.140, the box `docs/STUDIO-SPEC.md` §16 calls dev.
- eSimple: `https://api.esimple.at/api` (alias `api.esimple.transasim.com`, the same server);
  DEV `https://esimple.transasim.com/api`. Until 2026-10-21 its store builds used the DEV
  server as a recorded exception; `studio --pin-production … --end-exception` ended it.
- Sabily: `https://api.sabily.fr/api`, on its own prod box; DEV `https://api.sabily.transasim.com/api`.

## A store build never talks to a DEV server (Slice H, 2026-10-21)

In October 2026 eSimple's store app was built against its DEV host: two months of its
customers and payments went into the DEV database and never reached the shop's admin.
- **Two flavors per brand.** `<slug>`: the store ids, the production host. `<slug>Dev`:
  applicationId and bundle id + `.dev`, name + " DEV", the DEV host, a red "TEST SERVER -
  not for customers" banner on every screen. Each ships its own generated bundle,
  `brands/<slug>/flavor/<flavor>.json`; brand.json itself never ships (it names the DEV
  host). A brand has a DEV flavor only while `mobile.devApiBaseUrl` names a host other
  than production's.
- **Fail closed.** Each brand's entry points compile in its production hosts (from
  studio.json). A store build on any other host, or a DEV build on a production one, shows
  why and does not start (`[host] refusing to start:` in logcat); the store build logs
  `[host] PRODUCTION build of <slug> on <host>`, and the Profile screen shows the host.
- **The pin.** studio.json `production` holds the production URL, its aliases, a temporary
  `exception` and a log. Only Go prod's Apply writes `mobile.apiBaseUrl`, from the pin; only
  `studio --pin-production <slug> <url> --reason "…"` moves the pin (`--exception <url>`,
  `--end-exception`). New brand and the intake write `mobile.devApiBaseUrl` only.
- **Stripe.** The store flavor takes only `pk_live_` (or payments off), the DEV flavor only
  `pk_test_`, from `mobile.devStripePublishableKey`. A key of the wrong mode, built in or from
  the remote config, is dropped with a warning.
- **The release gates read the artifact.** `--verify-release` and `--verify-ipa` check the
  bundle inside the AAB, APK and IPA (production host, store ids, no dev bundle) and scan every
  byte for the DEV hosts. A DEV APK is `app-<slug>-dev-profile.apk`, the store one
  `app-<slug>-prod-profile.apk` (`studio --stage-apk`); neither ever reaches dist/.
- **Production exceptions.** studio.json `production.exception` lets a brand's store builds
  use another host, temporarily and with a reason. Every release shows it in red and needs it
  acknowledged (`--acknowledge-exception`), and the brand has no DEV flavor while the DEV host
  is its production. None stands today: eSimple's ended when it moved to api.esimple.at.
- **The `.dev` ids need their own** Google sign-in clients and Apple App ID (Integrations, "DEV
  build"). Until they exist Google and Apple sign-in fail in DEV builds; e-mail works.

Goldens: `flutter test --update-goldens`, and look at the diff before
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
(or `studio.json`) and regenerate (`studio --regenerate` writes them all, as Apply would).
They are `lib/flavors/main_<slug>.dart` and `main_<slug>_dev.dart`, the flavor bundles
`brands/<slug>/flavor/<slug>.json` and `<slug>Dev.json`, the text files under
`android/app/src/<slug>/res/`, `ios/Flutter/<slug>.xcconfig` and `<slug>Dev.xcconfig`, the
JSON in `ios/Runner/Brands/Brand-<slug>.xcassets/`, and the pubspec flavor block. Their
templates are `tool/studio/templates/**.tmpl`. `brands/<slug>/studio.json` holds what
Studio needs and the app does not: `appleTeamId`, the `published` store ids, which the
form locks, and the `production` pin, which locks `mobile.apiBaseUrl`.

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
that brand. Sabily's and eSimple's icons are still the hand-made ones until
someone presses it. The safe zone is a 300 px radius in the 432 px brand_mark,
because `brand_launcher_foreground.xml` insets it 28% per side
(`tool/studio/src/icons.dart` derives it; `test/studio/icon_rules_test.dart` checks it).

eSimple's launcher icon is the exception to "Studio made it": it comes from
`brands/esimple/assets/new logo.pdf` via `dart run tool/gen_esimple_icon.dart`,
which calls Studio's own `renderIcons` but writes only the four files this repo
ships (brand_mark, the xxxhdpi launcher, the iOS 1024, the Play 512) rather than
Studio's full set. Sabily's icons are still hand-made; Acorn's were regenerated from its mark on 2026-10-16.

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
reaches brand.json or studio.json only through the tab's previewed Apply. Each guide's
`createUrl` lists the pages where its value is *created*, best first: the label and
**Get it** open the first one whose ids are known (else the list page), and "This one
worked" records the winner per brand in `studio.json` `guideLinks`. Consoles move pages,
which is why it is a list. A missing project id or Google account is typed inside the card,
and the tab opens with a **Missing data** list of everything the brand still lacks.
Verified in Chrome by Alpha, 2026-10-11: `…/auth/clients/create?project=83118739145` lands
on "Create OAuth client ID", and the console accepts a project *number*, rewriting the
address to the project ID (Sabily's 83118739145 is `sabily`). So `gcpProjectId` may hold
either; the card says so and stores the ID if you paste it or the console address. The
older `/apis/credentials/oauthclient` stays second. Studio refuses
anything shaped like a secret (`sk_`, `rk_`, `whsec_`, `GOCSPX-`, PEM) in any field, and
never asks for a password: "Read from keystore" takes the upload SHA-1 from
`android/<slug>-key.properties`, passing the password to keytool through its environment.

**Build, Logs, Doctor and the incident list** (Slice B, 2026-10-11).
- **Build** starts *Validate (fast)*: the wiring and brand tests, the layer check and
  `studio --check`. *Validate (full)* adds `pub get`, `analyze` and the whole suite.
- **The runner** runs one job at a time. Each line is redacted (`tool/studio/src/redact.dart`)
  before it is shown, streamed or written to `.studio/logs/<time>-<slug>-<job>.log`.
  `.studio/` is gitignored; `machine.json` there holds this machine's SDK root, AVD and
  emulator GPU mode. **Cancel** kills the whole process tree. A request names a job from
  `tool/studio/src/jobs.dart` and never carries a command.
- **Logs** shows the live stream with search, Pause and an error count. A failed job lists
  the incidents it matched, each with its cause, its fix and, where safe, a fix button.
  **Show the Fix Bundle** then **Copy for Claude** gives at most 8,000 characters of
  redacted context; the page shows the text before you copy it.
- **Doctor** reads the machine fresh every time it opens: the toolchain, the SDK root (from
  `android/local.properties`, then `ANDROID_HOME`, then `ANDROID_SDK_ROOT`; never
  assumed), packages, licences, the AVD, the GPU mode (`angle_indirect` on Windows), the
  heap, git and line endings, upload keys, disk and memory. It installs nothing unless
  you press its button, and never accepts a licence.
- **`tool/studio/incidents/<id>.yaml` is the one incident list.** The log signatures, the
  release checklist (`kind: checklist`, `gate:`) and the case store all read it.
  **Every incident becomes a file there the same day**, with match and miss examples that
  `test/studio/incidents_test.dart` runs. Mark a message you have not seen in a real log
  `evidence: unverified`. A line the app itself prints names its `source`, so rewording it
  fails a test instead of silently breaking the match.

**Client intake** (Slice I, 2026-10-12). New brand and the Brand tab take the onboarding portal's
`spc-intake-<slug>.json` (the Drive folder, its zip, or the JSON and its logo), read strictly by
`tool/studio/src/intake.dart`: 256 KB cap, contract v1 only, the whole file refused on any
secret-shaped value. Every value goes through a previewed Apply and keeps its source ("client
intake <id>"); blanks are listed as "ask the client". `support.email` is never filled from a contact.
A legal URL is written only when it is an https page: a Drive or Docs link, or an uploaded PDF, is
listed as "host this as a public page" instead, `legal.accountDeletionUrl` included.
The mapping is `docs/STUDIO-SPEC.md` §17. The test fixture is fake; never commit a real intake.
The whole intake panel is the drop target, and the page refuses any drop elsewhere, so Chrome never
opens a dropped file. `dart run tool/studio/checks/intake_drop_check.dart`, with Studio running,
drags real files in headless Chrome (DevTools' `Input.dispatchDragEvent`) and checks the drops.

**Cases and Solve** (Slice D1, 2026-10-14). `tool/studio/src/cases.dart`: a case is a fix that
worked (incident, redacted symptom, cause, diff, tests), stored only by a previewed Apply as
`.studio/cases/<id>.yaml` (private) and `tool/studio/cases/<id>.yaml` (committed, secret-free; a case
holding a secret-shaped value or a path outside the repo is refused whole). A failed job's **Solve**
shows, in order, its known fix (a button), the nearest cases, then the Fix Bundle, which lists what was
tried. No agent, no replay, no exporter: `docs/STUDIO-SPEC.md` §18 says why.

**Test record** (Slice C1/C2, 2026-10-13). A release needs a recorded result for this commit and
this brand: Build's "Tested on device/emulator" takes Pass, Fail or Skip (Skip counts) and writes
`brands/<slug>/studio.json` `tests` through a previewed Apply (`tool/studio/src/testrecord.dart`).
Any new commit that touches code, or a brand edit, resets it; commit studio.json after recording.

**Release** (Slice E, 2026-10-12). Build's *Build release* runs `release-android`: the AAB
and the APK, signed with the brand's upload key, then `studio --verify-release <slug>` checks the
artifacts (package, version, targetSdk, certificate SHA-1, only this brand's assets, icon sizes)
and files them under `dist/<slug>/<version>/` with `release.json`. It is refused while the tree
has uncommitted changes, without the key file, or when the release check below says no. It never uploads: Play and App Store
uploads stay a human's step. *Copy prompt for the Mac* writes the iOS commands for this commit,
stopping before "Submit for Review".

**Store** (slice S, 2026-10-17, `docs/PLATFORM-PLAN.md` §9). The Store tab writes Play's 512 icon (the
launcher's own render) and the 1024×500 feature graphic into `dist/<slug>/store/`. The graphic's lockup and
ground are measured, not assumed: the surface then the primary colour, with `logo.full` then
`logo.fullInverse`, until one pair reaches 3:1 (Sabily's `logo.full` is white); a lockup without
transparency sits on its own background (eSimple's white box). *Start capture mode* sets the emulator
to 1080×1920 with demo mode's clean status bar, *Capture screen* saves `phone/phone-NN.png` without alpha,
*End capture mode* undoes both, all `adb -e`. `checkShot` holds each screenshot to Play's rules
(320 to 3840 px, at most 2:1, no alpha, 8 MB). Nothing is uploaded. *Build for the store* comes first: a
profile APK of the store flavor, on its production host as a release is, then the same launch steps as
*Launch the store build again*. Build for test builds the DEV flavor instead.
First run live on 2026-10-17 (Acorn's five screenshots). On Android 16, demo mode's Wi-Fi needs
`fully true`, or it draws a satellite icon in its place. `tool/studio/store/play-data-safety.csv` is Play's Data safety
export (Acorn's answers, 2026-10-18) with `{accountDeletionUrl}` and `{dataDeletionUrl}` in place of its URLs:
the starting point for a new brand's "Import from CSV".

**The backend phase** (`docs/STUDIO-SPEC.md` §16). The Backend tab was built in G1 and G2,
2026-10-11. **Go prod uses option B:** PROD gets a hostname of its own, and Go prod's previewed
Apply points `brand.json`'s `apiBaseUrl` at it. **The release check** (`releaseRefusal` in
`backend.dart`) runs before every release build. It refuses a gated brand that has not passed
Go prod, still points at DEV, or has no `legal.accountDeletionUrl`. The
schema ledger lists every SQL run by hand on DEV; Go prod waits until each is applied on
PROD.
- **Studio and the servers.** Studio checks each brand's DEV, then PROD, backend in three
  ways:
  - probes from this PC (DNS, TLS, `/v1/packs/all`, the social endpoints);
  - a read-only checker (`tool/studio/backend/`) that Alpha runs on the server and whose JSON
    he pastes in;
  - ticks.

  Studio never connects to a server and never holds a server password, key or token.
- **Claude Code cannot reach any server either: do not try.**
- **Where it lives.**
  - `tool/studio/servers.yaml` is the registry.
  - `tool/studio/src/backend.dart` holds the report, the items, the gate and the commands;
    `probes.dart` holds the probes.
  - Accepted reports go to `.studio/reports/` (gitignored). A pasted report is refused
    whole, and never stored, when it is:
    - from the wrong box;
    - older than 24 h;
    - of an unknown schema;
    - carrying anything `redact.dart` would mask.
  - Go phase 2 records the DEV jar and the backend commit in `studio.json`, and unlocks
    Build's "Build for test (DEV)": a profile APK of the dev flavor, whose bundle carries
    `mobile.devApiBaseUrl` (and, with payments, `mobile.devStripePublishableKey`, a `pk_test_` key).
  - Build's **Launch on emulator** does the rest in one job:
    - stops the Gradle daemon;
    - starts the AVD Doctor recorded in `.studio/machine.json` (`-gpu angle_indirect` on
      Windows), unless one already runs;
    - waits for `sys.boot_completed`;
    - turns airplane mode off (the `sabily_test` AVD had it on) and Wi-Fi on (off after a cold boot,
      2026-10-17);
    - installs the DEV APK and opens the app.

    The emulator is a detached step: no pipes, so the job never waits for its window to
    close, and Cancel leaves it running. **Stop Gradle** is its own button next to it.
  - Change the checker in `tool/studio/backend/` only together with `reportFields` in
    `backend.dart`: a test keeps them equal.
  - A report must be the brand's own backend's (WRONG BACKEND otherwise): Acorn and Sabily
    share a box, so the hostname alone cannot tell their reports apart.
  - Report schema version 2 (checker 1.1.0) hashes `timestamp(6)` as `timestamp`. Hibernate
    writes the default precision out and Liquibase leaves it implicit; the column is the same.
    After any change to the hashes, re-run Sabily's report and press "Use as schema reference"
    again: an older reference reads as outdated.
- **Sabily and eSimple are legacy** (`studio.json` `backendGate: "legacy"`): their backend
  items are information only and never block anything, including G2's release check. Never ask
  for their payments or vouchers: Studio reads both from the app. Acorn and new brands are
  gated.
- **The backend items** are entries in the one incident list, with `env`, `when` and
  `severity`. Gate `test` guards "Go phase 2", which unlocks DEV test builds; gate `release`
  guards "Go prod".
- **Server facts from the 2026-10-11 dev-box inventory:**
  - **Postgres is on port 6478.** `psql` without `-p 6478` can reach a stray listener.
  - **Restart Sabily's backend on that box with `systemctl restart sabily`.** Its
    `bin/startup.sh` starts a second JVM ("Port 9060 was already in use").
  - **acorn-backend and esimple-backend restart with `bin/shutdown.sh && bin/startup.sh`,**
    and do not survive a reboot.

**Checking Studio's UI** (the recipe that worked, 2026-10-04 to 10-11). With Claude in
Chrome connected, `javascript_tool` on `http://127.0.0.1:4777/#<slug>` is enough. Its
screenshots time out whenever the Chrome window is in the background: the page reports
`visibilityState: hidden` and paints nothing, but still answers scripts. Without it:
- Stop Studio by the PID listening on port 4777. Stopping the shell task leaves its `dartvm`
  holding the port, and the next start fails while the stale server answers requests.
- Headless Chrome: `chrome.exe --headless=new --remote-debugging-port=9334
  --remote-allow-origins=* --user-data-dir=<absolute scratch dir> about:blank`. Without
  `--remote-allow-origins` the DevTools WebSocket hangs. With a *relative*
  `--user-data-dir`, Chrome started from Dart never opens the port. Poll the port rather
  than sleeping. Open the page with
  `PUT /json/new?http://127.0.0.1:4777/#<slug>` and drive it with `Runtime.evaluate` from a
  small Dart script, with a timeout on every call.
- **Keep each run to a few steps on a fresh page.** The renderer freezes, idle at 0% CPU
  and not a loop in Studio, after a screenshot or a burst of re-renders. It then never
  answers again. Take the screenshot last. To check what an event changed, read the state
  in the same `Runtime.evaluate` that dispatches it.
- Stub `window.open` to record URLs. Drop a file with a `DragEvent('drop')` carrying a
  `DataTransfer` built in the page, not `DOM.setFileInputFiles`. Clipboard reads are
  denied headless even after `Browser.grantPermissions`, so stub
  `navigator.clipboard.readText` to test Studio's own logic.
- Kill only your Chrome, matching its `--user-data-dir` in the process command line.

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
| Studio, the local brand builder: what it will own, phase by phase | `docs/STUDIO-SPEC.md` — Phase 0 (flavors and signing from `brand.json`), 1a (server, Brand tab, text generators), 1b (Assets, icon set, New brand) and 1c (Integrations, guides) done 2026-10-04; Phase 2 (runner, logs, incidents, Doctor, Fix Bundle) done 2026-10-11; §16 the backend phase (servers, the checker, Go phase 2, Go prod, the release check): G1 and G2 done 2026-10-11; Slice E (release) and §17 the client intake (Slice I) done 2026-10-12 |
| What has gone wrong before, and its fix | `tool/studio/incidents/*.yaml`, the one incident list |
| Where Studio is going: the console on a VPS, SSH provisioning, brand websites, onboarding v2, the WinCode iOS lane | `docs/PLATFORM-PLAN.md` (design, 2026-10-16). Built: slice U, Studio's light/dark theme and per-page guidelines (`test/studio/theme_test.dart` holds both themes to WCAG AA), and slice S's graphics and screenshots (the Store tab) |

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
| Store identity | `com.sabily.esim`, frozen | `com.esimple.esim`, frozen | `com.odyssey.esim`, frozen (on Play since 2026-10-16) |
| Payments | **live** — real `pk_live_` key, real purchase 2026-10-05 | **live** — real `pk_live_` key, never exercised | **live** — `pk_live_` key given by Alpha 2026-10-16, never exercised |
| **Android** | 1.1.8 (21), release AAB built | 1.1.8 (21), release AAB built | 1.1.9 (22), uploaded to Play 2026-10-16 |
| **iOS** | pending: build 1.1.8 from `release/1.1.8-21` on the Mac | pending: same | flavor wired, never uploaded |
| Store build's host | api.sabily.fr | api.esimple.at | acorn-api.transasim.com |
| DEV build (`<slug>Dev`) | on api.sabily.transasim.com; Xcode wiring waits for the Mac | on esimple.transasim.com; Xcode wiring waits for the Mac; `.dev` sign-in clients and App ID not made yet | on acorn.transasim.com; Xcode wiring waits for the Mac; `.dev` sign-in clients and App ID not made yet |

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

- **eSimple has two production-like backends.**
  - The new app's `brand.json` points at esimple.transasim.com. That is esimple-backend on
    169.58.35.140, with a live Stripe key and its own `esimple_prod` database. This setup was
    approved 2026-09-15 (`docs/APPROVALS.md`).
  - The old store app and esimple.at use 80.241.216.126, which has another database, also
    named `esimple_prod`. An account in one database is not in the other, unless something
    syncs them; the dev box showed no such job.
  - **Decided 2026-10-11: 169.58.35.140 is eSimple's app production** (`docs/STUDIO-SPEC.md`
    §14.4). `servers.yaml` marks it `prodFor: [esimple]`.
  - So Studio never treats that backend as a DEV one. **Never propose a test key there:**
    every eSimple build since 2026-09-15 pays through its live key.
- **A socle resource in a qualified folder beats every flavor's own.** Android merges
  `main/` and the flavor, then picks the most specific qualifier, whichever set it came
  from. Flutter's template `main/res/drawable-v21/launch_background.xml` hid every brand's
  launch window on Android 5–11, and `main/res/values-night/styles.xml` hid every brand's
  Android 12+ splash in dark mode (black window, though the app pins light mode). Both were
  deleted on 2026-10-11, so published 1.1.8 still has the bug until the next release. The
  wiring test now refuses any such file. Deleting them left Gradle's incremental resource merge
  stale in every existing build/ folder: the flavor's own launch_background then went missing
  ("resource drawable/launch_background ... not found"). Delete
  build/app/intermediates/merged_res and incremental/*/merge*Resources once (incident
  stale-merged-resources); flutter clean also deletes the APKs and AABs.
- **A silent audio track in an intro video stops the animation from playing.** The
  intro is abandoned if the video has not started within 1.5 s. A muted-but-present
  AAC track makes the player build a second decoder, which costs enough on a cold
  start to miss that deadline — the animation then never appears, silently. Strip it
  before bundling: `ffmpeg -i in.mp4 -map 0:v:0 -c copy -an -write_tmcd 0 out.mp4`
  (stream copy; the video bytes do not change). Full story in
  `ARCHITECTURE-MOBILE.md` §2.4.1.
- **`--dart-define=API_BASE_URL` (or `STRIPE_PUBLISHABLE_KEY`) stops the app at
  launch, in every build mode**, on purpose — a *runtime* refusal, not a build error.
  `BrandLoader.refuseDefines` (`lib/core/brand/brand_loader.dart`) still reads both with
  `const String.fromEnvironment` and throws if either was passed: no build overrides the
  backend or the key any more (Slice H), and a define nothing reads is worse than none.
  The build completes; the app shows why and stops. For the DEV server, build the dev
  flavor (`--flavor <slug>Dev -t lib/flavors/main_<slug>_dev.dart`). Pointing a store build
  at another backend is a pin move (`studio --pin-production`) and a Go prod, not a flag.
- **The `flavors:` entries in `pubspec.yaml`**: per brand its store bundle, its DEV
  bundle when it has one, and the assets folder for both flavors. Miss one and every
  client ships every other client's files. They are generated between marker comments
  by `dart run tool/gen_brand_flavors.dart`; never type them. The wiring test fails until
  the block matches the `brands/` folders, and refuses one that ships `brand.json`.
- **The native launch window colour is duplicated** in
  `android/app/src/<slug>/res/values/colors.xml` and the iOS `LaunchBackground`
  colorset, and must equal `logo.introBackground ?? colors.surface`. Studio generates
  both from `brand.json`, and tests enforce it; change `brand.json` and regenerate.
- **Sabily and eSimple carry live `pk_live_` publishable keys in `brand.json`, so
  payments are ENABLED on both.** `isUsableStripeKey` accepts `pk_(test|live)_`
  plus 24 or more base62 characters; both keys are live with 99-character bodies,
  so `canTakePayments` returns true and checkout charges real money. Acorn joined
  them on 2026-10-16 (the key Alpha gave for it). A publishable key is public by
  design — it ships inside the APK — but still never copy one in from a client
  website or an old branch: use the key the client gave for that brand, or you
  will be charging through someone else's account.
- **Voucher redemption calls Transatel directly and provisions a real eSIM**, with no
  Stripe involvement, on every one of these backends. Never test it with a real code
  unless someone has explicitly asked for exactly that.
- Colour literals outside `app_theme.dart` fail the layer check, including in a test
  you were about to write quickly.
- **Status-bar icons are the app's job.** The app root sets dark ones over the light app; a
  screen whose top is dark wraps it in `AnnotatedRegion(value: statusBarOver(colour))`
  (`app_theme.dart`), as the destination header does. Without it the icons vanish into the
  colour (Acorn's blue, 2026-10-17). Flutter keeps the last style it applied, which is why the
  root sets a default.
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
