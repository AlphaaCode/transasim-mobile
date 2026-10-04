# SPC Studio — spec for the white-label app builder

Status: design, written 2026-10-04 by Claude (architect). To be built by Claude Code in this repo.
Audience: Claude Code. Read `CLAUDE.md` first; this file does not repeat it.

## 1. Goal

One local tool where Alpha drops a client's logo, colours and IDs into a form, and gets back a
tested Android APK + AAB (and, on the Mac, an iOS archive) with no hand-editing of the repo.
When something fails, one click produces a compact report he pastes to Claude; nothing else
needs explaining.

Principles (these decide every trade-off below):

1. **Deterministic code does the work, Claude only handles exceptions.** Every step we did by hand
   for Sabily/eSimple/Acorn (flavor wiring, icons, signing checks, SHA-1s, store checklists) becomes
   a function, a validator or a checklist item. Tokens are spent only on new failures.
2. **Every incident becomes a rule.** A failure that cost us time is turned into a log signature
   (§8) or a checklist item (§9) the same day. The tool gets smarter, Claude does not re-diagnose.
3. **Generators are idempotent and previewable.** Running twice changes nothing; every write is shown
   as a diff first.
4. **The tool never publishes.** It produces artifacts and verifies them. Uploading to Play / App
   Store, "Submit for review", rollout, and any credential entry stay with Alpha.
5. **No secrets in git, none in logs.**

Non-goals: editing app screens/layout (that is the socle in `lib/`, shared by all brands); replacing
the Play/App Store consoles; building a cloud service. It is a local tool for one operator.

## 2. What a brand is today (the touch-point map)

A new brand currently touches all of these. Studio must own every row; if a row cannot be generated,
that is a gap in the socle to fix in Phase 0, not a manual step.

| # | Where | What | Source of truth in Studio |
|---|---|---|---|
| 1 | `brands/<slug>/brand.json` | identity, colours, locales, legal, `mobile.*` (ids, URLs, Stripe `pk_`, Google server client id, registration fields, popular destinations) | the form |
| 2 | `brands/<slug>/assets/` | `logo-mark.png`, `logo-full.png`, (`fullInverse`), `logo-intro.mp4`, card background, `pack-<region>.jpg` x8 | drop zones |
| 3 | `pubspec.yaml` | **two** `flavors:` entries per brand (json + assets folder); forgetting one leaks another client's files | generated block between markers — done in Phase 0: `tool/gen_brand_flavors.dart` |
| 4 | `lib/flavors/main_<slug>.dart` | one line `bootstrap('<slug>')` | generated |
| 5 | `android/app/build.gradle.kts` | `productFlavor` with `applicationId`, `app_name` | done in Phase 0: Gradle loops over `brands/*/brand.json`, no hand-written blocks |
| 6 | `android/app/src/<slug>/res/` | `drawable/brand_mark.png` (432 px max), `mipmap-*` launcher set, `values/colors.xml` launch colour (= `logo.introBackground ?? colors.surface`, a test enforces it), `values-v31` splash | generated from the logo |
| 7 | signing | per-brand upload keystore + `android/<slug>-key.properties`; each brand already signed with its own key (or debug) before Phase 0 | `brandKeys`, keyed by the `brands/*` list since Phase 0; Studio adds generate/import (Phase 4) |
| 8 | `ios/Flutter/<slug>.xcconfig` | bundle id, display name, team `DP7F8WQCJD`, Google iOS client id + reversed scheme + server client id | generated |
| 9 | `ios/Runner/Brands/Brand-<slug>.xcassets` | iOS icon (1024, no alpha), launch colour | generated |
| 10 | Xcode project | configurations + scheme per brand | `ruby tool/ios_flavors.rb` (Mac only, idempotent) |
| 11 | `test/core/brand_wiring_test.dart` | proves 1-10 agree and that no two brands share a value | run as the validation gate |
| 12 | Google Cloud (per brand project) | web client, Android client (package + **two** SHA-1), iOS client | checklist §9 + fields in the form |
| 13 | Play Console / App Store Connect | listing, privacy, data safety, target audience, signing | checklist §9 |
| 14 | Backend | API base URL live, auth endpoints, Stripe, test account | checklist §9 + auto probes |

## 3. Architecture

**A local web app.** `dart run tool/studio/bin/studio.dart` (wrapper `studio.bat` / `studio.command`)
starts a server on `127.0.0.1:4777` and opens the browser. Reasons: drag-and-drop and live logs are
trivial in a browser; nothing to package or sign; Claude Code can build and change it quickly; the
same code runs on the Windows PC (Android) and the Mac (iOS), switching panels by `Platform`.

Why **Dart** for the server (default; Node is the fallback): Dart is already installed with Flutter
on every build machine, no `npm install`, and Studio can import the app's own `BrandConfig` parser
(`lib/core/brand`) so the form validates with exactly the rules the app enforces at startup. One
source of truth, no schema drift. UI is plain HTML/CSS/JS in `tool/studio/web/`, no build step,
no CDN (works offline).

```
tool/studio/
  bin/studio.dart            server entry, opens browser
  lib/core/                  brand model + validation (reuses lib/core/brand), versions, paths
  lib/gen/                   generators: pure fns -> FileChange{path, before, after}
  lib/assets/                image + video pipeline
  lib/run/                   job runner (spawn, stream, cancel), emulator, adb, gradle, flutter, xcode
  lib/doctor/                environment checks and one-click installs
  lib/report/                log store, signature catalogue, fix bundle
  lib/checklist/             checklist engine + probes
  checklists/template.yaml   the checklist every brand starts from (editable by Claude Code)
  signatures/*.yaml          known-failure catalogue
  web/                       UI
  test/                      generator tests, golden-master test (§12)
```

State on disk:
- `brands/<slug>/brand.json` and assets: app configuration, committed.
- `brands/<slug>/studio.json`: Studio-only data, committed, no secrets: checklist state with
  evidence notes, live store versions, SHA-1/SHA-256 fingerprints, build history, store URLs.
- `.studio/` (gitignored): logs, temp, dist cache.
- Secrets: keystore passwords are asked once and kept in the OS credential store (Windows Credential
  Manager / macOS Keychain), never in a file, never in logs (redaction filter on all process output
  for every known secret value and for `sk_*`, `storePassword=`, `keyPassword=`).
- `dist/<slug>/<versionName>+<versionCode>/`: build outputs + `release.json`.

One job at a time (a Gradle build and an emulator together already wedged the 16 GB laptop). The
runner queues, streams, cancels, and stops the Gradle daemon between brands.

## 4. UI

Left rail: brand list + "New brand". Top tabs for the selected brand:

`Brand` | `Assets` | `Integrations` | `Checklist` | `Build` | `Logs` | `Doctor` (global)

- **Brand** — form for everything in `brand.json` (identity, tagline per locale, five colour roles
  + premium, locales + default, currency, support, legal URLs, registration fields, popular
  destinations). Live preview of Home / Store / Checkout in a phone frame (light/dark, LTR/RTL).
  Contrast check on `cta`/`ctaText` and `primary`/`surface` (warn under WCAG AA).
- **Assets** — drop zones: logo mark, full logo, inverse logo, intro video, card background,
  eight pack images, store screenshots. Each shows what it will become (see §5) and rejects bad files
  with the reason.
- **Integrations** — package/bundle id (with "FROZEN once published" lock), deep-link scheme,
  universal-link hosts, API base URL, remote config URL, Stripe publishable key, Google Cloud
  project id + Google account hint, Google web client id, Google iOS client id (reversed scheme
  derived automatically), Apple team id, upload-key status (generate / import / show SHA-1), Play App
  Signing SHA-1. Each external value has a **Get it** button (see 4a).
- **Checklist** — §9.
- **Build** — three large buttons in order, each unlocked by the previous one (§6), and the version
  fields.
- **Logs** — live stream, history per step, "Copy for Claude" (§8).
- **Doctor** — §7.

Visual style: one dark, dense, readable page; status chips (green/amber/red); no wizard modals.

### 4a. Guided fields (click a field, land on the right console page)

Every field that comes from outside the repo (Google client ids, SHA-1s, Stripe key, Apple team id,
Play/App Store ids) has a **"Get it" button** next to it. Clicking it:

1. Opens the exact console page in a new tab, already scoped to this brand (project id, package id,
   app id filled into the URL), using the brand's saved Google account hint (`authuser=<email>`;
   Sabily's and eSimple's Cloud projects are different accounts/projects).
2. Opens a **guide card** docked beside the field with the numbered steps for that field, every value
   the console will ask for shown with a copy button (package name, bundle id, SHA-1, app name), and
   screenshots/arrows optional later.
3. Shows a **paste box** that validates the format as you paste, tells you what is wrong ("this is the
   Android client, not the web one"), and on success writes the field, ticks the checklist item and
   stores the evidence. When you return to the Studio tab, if the clipboard holds something shaped like
   the expected value, a one-click "Use pasted value" appears (clipboard read needs your click).
4. Derives dependent values automatically (iOS client id -> reversed URL scheme -> `Info.plist`
   fields) and flags mismatches with what the backend expects.

Guides are **data, not code**: `tool/studio/guides/<id>.yaml` with `field`, `urlTemplate`, `steps`,
`copyValues`, `validate` (regex + message), `derive`, `checklistItem`. Claude Code adds a guide the
same day a new console step costs us time. When a console changes its UI, we edit one YAML file.

Seed guides (URL templates use `{gcpProject}`, `{authuser}`, `{package}`, `{bundleId}`, `{playAppId}`,
`{devId}`; the brand's Integrations tab stores `gcpProjectId` and `googleAccount`):

| Field | Opens | Steps shown | Validates |
|---|---|---|---|
| Google **web** client id (`googleServerClientId`) | `https://console.cloud.google.com/apis/credentials?project={gcpProject}&authuser={authuser}` | Create credentials -> OAuth client ID -> type **Web application** -> name "<Brand> web" -> create -> copy Client ID. Backend must use this same id as audience. | `^\d+-[a-z0-9]+\.apps\.googleusercontent\.com$`, must differ from the iOS/Android ids |
| Google **Android** client | same page, create client of type **Android** | package `{package}`; SHA-1 #1 = upload key (button "show from keystore"); create a **second** Android client for SHA-1 #2 = Play App Signing (copied from Play Console, see next row). Nothing to paste back; Studio records "created" with the two SHA-1s | SHA-1 format `^([0-9A-F]{2}:){19}[0-9A-F]{2}$` |
| **Play App Signing SHA-1** | `https://play.google.com/console/u/0/developers/{devId}/app/{playAppId}/keymanagement` | copy "SHA-1 certificate fingerprint" under App signing key certificate (not the upload key) | SHA-1 format; must differ from the upload key's SHA-1 |
| Google **iOS** client id | credentials page, create client type **iOS** | bundle id `{bundleId}`, (team id `DP7F8WQCJD` optional), create, copy Client ID | format as above; reversed scheme derived |
| OAuth consent screen | `https://console.cloud.google.com/apis/credentials/consent?project={gcpProject}` | check "Published" (not Testing), support email, authorized domains | manual tick + note |
| Stripe publishable key | `https://dashboard.stripe.com/apikeys` | copy **Publishable** key only; never the secret | starts `pk_live_` or `pk_test_`, never `sk_`; not equal to another brand's key |
| Apple team id / Sign in with Apple | `https://developer.apple.com/account` and `.../identifiers/list` | bundle id registered, capability ticked | 10 characters, `[A-Z0-9]` |
| Play app id | Play Console app list | copy numeric id from URL | digits only |

The same mechanism backs the checklist (§9): every `assisted` item is a guide.

## 5. Asset pipeline (rules learned the hard way)

| Input | Output / rule | Why |
|---|---|---|
| logo mark PNG | `brand_mark.png` **<= 432 px**, `ic_launcher` xxxhdpi **192 px**, full mipmap set, adaptive icon (foreground + background colour), monochrome layer, iOS AppIcon 1024 **without alpha**, notification icon | Sabily shipped 1473 px icons; Google's account picker crashed with "Canvas: trying to draw too large bitmap" |
| logo full / inverse | stored as is, max width check; warn if inverse missing | loader warns on every start without it |
| intro MP4 | strip audio (`ffmpeg -i in -map 0:v:0 -c copy -an -write_tmcd 0 out`), reject if it cannot start fast (duration/size sanity), keep dimensions | a silent AAC track makes the intro miss its 1.5 s deadline and never play |
| pack images | one per region + per-country overrides, JPEG, bounded size, licence note required (CC0 etc.) | `visuals.packImages`, provenance file |
| colours | writes `colors.xml` launch colour and iOS launch colour from the same value | native launch window must equal `introBackground ?? surface` |
| screenshots | validate store sizes (Play phone, iPhone 6.9", iPad 13") | store rejections |

Everything generated is shown in a preview grid before it is written.

## 6. Build flow (the three buttons)

**State machine per brand**: `Draft -> Valid -> Tested -> Released`. A later edit to brand data or
a new commit sets `Tested` back to `Valid` (the test applies to a git hash + brand hash).

1. **Validate** (auto on every change, also a button)
   `flutter pub get`, `flutter analyze`, `dart run tool/check_layers.dart`, the wiring test, the
   brand tests, and the checklist items marked `gate: test`. Fast path: only wiring + brand tests.
2. **Test on emulator**
   - find the Android SDK (differs per machine: `C:\Android`, `C:\src\android-sdk`; never assume the
     default), create the AVD if missing (Pixel 6, API 35 google_apis x86_64, 2 GB, `-gpu host`),
     boot with `-no-snapshot-save`, wait for `sys.boot_completed`;
   - build a debug or profile APK for the flavor (`API_BASE_URL` override allowed here only if the
     user ticks "use dev backend"; default is the brand's own URL), `adb install -r`, launch;
   - stream filtered `adb logcat` (app pid, `E/` and `flutter` tags) into Logs;
   - Alpha tests by hand. **When he closes the emulator window the process exits and Studio
     unlocks step 3**, recording `{gitHash, brandHash, time}`; a "Pass / Fail + note" prompt appears.
     "Skip test" exists but is recorded as skipped.
3. **Generate release**
   - preconditions: `Tested` for this hash (or skipped), checklist items `gate: release` green,
     upload key present, version strictly above the live version entered in `studio.json`;
   - `flutter build appbundle --release --flavor <slug> -t lib/flavors/main_<slug>.dart`, then
     `flutter build apk --release ...` (no `--split-per-abi` for the universal; if split is wanted,
     remember Flutter adds 1000/2000/4000 to the versionCode). **Never pass `API_BASE_URL` to a
     release** (the app throws on launch by design).
   - sequential, never two brands at once; stop the Gradle daemon after;
   - **verify the artifact itself**, not the intent: `applicationId`, `versionName/Code`,
     `targetSdkVersion == 36` (Play deadline passed 31 Aug 2026), signing certificate SHA-1/SHA-256
     equals the stored upload-key fingerprint (not the debug key), only this brand's assets inside
     (no cross-brand leakage), icon sizes, size within expectation;
   - copy to `dist/<slug>/<version>/` with `release.json` (hashes, fingerprints, commands, tool
     versions, git hash) and open the folder.

Release timing facts to encode: cold release build 19-20 min (`lintVitalRelease`), warm ~7.5 min;
R8 needs `-Xmx4g` (already committed); `play-services-tapandpay` exclusion lives in root
`android/build.gradle.kts` (do not "clean it up").

**iOS (Mac mode)** is the same three buttons with different commands: `ruby tool/ios_flavors.rb`
(idempotent), simulator test via `xcrun simctl`, then `flutter build ipa --release --flavor <slug>
-t lib/flavors/main_<slug>.dart --build-name <iosVersion> --build-number <n>` and
`xcodebuild -exportArchive ... -allowProvisioningUpdates` with the app-store-connect/upload export
options. iOS and Android versions are separate fields (iOS ran ahead: 2.0.0 (20) vs Android 1.1.7+20);
`build ipa` overwrites `build/ios/archive`, so Studio copies each brand's archive aside before the
next. The Apple ID, 2FA, Mac password and "Submit for Review" stay manual; Studio stops at
"uploaded, processing".

Windows produces the iOS *files* (xcconfig, xcassets) and commits them; the Mac pulls and builds.

## 7. Doctor (global tab)

Checks with a green/red result and, where safe, a one-click fix:
Flutter version (and that its default target SDK is 36), Dart, JDK 21, Android SDK root,
`platform-tools` on PATH (adb), platforms `android-35` **and** `android-36`, build-tools,
NDK `28.2.13676358`, CMake `3.22.1`, licences accepted, `gradle.properties` heap values,
ffmpeg, git state (clean tree, `.gitattributes` honoured: LF), free disk >= 20 GB, free RAM
warning for builds, AVD present, `key.properties` per brand, Xcode >= 26 and CocoaPods on the Mac.
Installs on Windows call the sdkmanager **Java class** directly
(`java -cp cmdline-tools/latest/lib/sdkmanager-classpath.jar com.android.sdklib.tool.sdkmanager.SdkManagerCli ...`),
never `sdkmanager.bat` (it mis-parses the `;` in package names).

## 8. Logs and the Fix Bundle (the token saver)

Every job writes `.studio/logs/<time>-<slug>-<step>.log` and streams it to the UI. On failure:

1. **Classify.** Run the log through `signatures/*.yaml`. Each entry: `id`, regex, plain-language
   cause, `autofix` (optional command or setting) and `doc` link. Seed catalogue from our history:
   - `[CXX1300] CMake ... not found` / `Failed to find target ... android-35` -> install NDK, CMake, platforms 35+36
   - `jni_flutter` / `:jni:configureCMakeDebug`
   - `Could not find com.google.android.gms:play-services-tapandpay` (release only, via lintVitalRelease)
   - `Gradle build daemon has been stopped ... GC is thrashing` / R8 OOM -> raise heap, build one flavor at a time
   - release app dies at start with `StateError ... API_BASE_URL` -> remove the define
   - `Could not prepare isolate` / `Could not create root isolate` -> wrong `-t` entry (use `lib/flavors/main_<slug>.dart`)
   - Stripe sheet never opens -> `MainActivity` must extend `FlutterFragmentActivity`
   - `Canvas: trying to draw too large bitmap` (com.google.android.gms.ui) -> oversized brand icon
   - signed with debug key (cert fingerprint != upload key) / missing `android/key.properties`
   - `targetSdkVersion` below 36 in the built artifact
   - `sdkmanager.bat` crash on `;`
   - `adb` not recognised -> locate SDK root
   - intro video never plays -> audio track present
   - golden tests fail on macOS only -> regenerate on Windows; CRLF in working tree -> `core.autocrlf false`, re-checkout
   - iOS: signing fails until the Apple Developer Program licence agreement is accepted
   - Play: uploads refused until the new upload key's activation time
2. **Autofix if safe** (install a missing SDK package, stop the daemon, regenerate an asset), re-run
   once, log what was tried.
3. **Fix Bundle** — button "Copy for Claude". Markdown, capped at ~8k characters:
   brand slug + version, step + exact command + exit code + duration, matched signature ids and the
   autofix attempted, the first error block and the last 150 lines, tool versions (Flutter, Dart,
   JDK, Gradle, NDK, Xcode), OS, git hash + dirty files, `brand.json` with secrets redacted, the
   failing checklist items, and the path of the full log. Alpha pastes this; Claude (or Claude Code)
   gets everything in one message. Optional later: a button that launches Claude Code with the bundle
   as its prompt.

## 9. Backend and launch checklist

Template in `checklists/template.yaml`, copied per brand into `studio.json`. Item fields:
`id`, `title`, `group`, `kind` (`auto` | `assisted` | `manual`), `gate` (`test` | `release` |
`submit` | `none`), `severity` (`block` | `warn`), `how` (numbered steps, with deep links filled from
the brand's ids), `probe` (for auto), `evidence` (note/URL/screenshot path), `doneAt`.

- `auto`: Studio verifies (HTTP probe, cert expiry, JSON shape, URL returns real content).
- `assisted`: Studio opens the right console page, Alpha pastes the value (client id, SHA-1); Studio
  validates the format and stores it.
- `manual`: Alpha ticks it and adds a note. The Build tab shows "N blocking items open" and which.

Seed items (from what actually went wrong):

**Backend**
- API base URL answers over HTTPS and the certificate has > 14 days left (eSimple's expired 2026-09-13). *auto, block*
- `GET /packs/all` returns packs, time to first byte logged. *auto, block*
- Test account can log in; App Review / store reviewer account exists **on this brand's backend**. *assisted, block (submit)*
- Registration accepts the brand's field set; null-phone collision known (warn). *auto, warn*
- `POST /v1/auth/google` and `/v1/auth/apple` exist (a bad token must give 4xx, not 404). *auto, block if brand offers social sign-in*
- Backend's Google audience equals the app's `googleServerClientId` (the web client). *assisted, block*
- Google-vs-password account linking behaviour known (`error.emailexists`). *manual, warn*
- Stripe: publishable key starts `pk_`, belongs to the brand (never copied from another brand), and is the **same Stripe account** as the backend secret key; a test purchase completes **through provisioning** (`/v1/subscriptions/card` returns 2xx), not just the payment. *assisted, block (release)*
- Backend prod config sanity: the live secret key is valid (a corrupted `sk_live` caused a 401). *manual*
- Voucher redemption provisions a real eSIM: do not test with real codes. *info*
- `app-config` route: 404 is acceptable (warn).

**Legal / web**
- Privacy URL returns 200 **with content** (sabily.fr/privacy was blank; `/en/confidentialite` works). *auto, block*
- Terms URL same. Account-deletion page exists publicly (not login-gated). *auto, block (submit)*
- Publisher name vs `legal.companyName` decision recorded. *manual, warn*

**Google Cloud (the brand's own project)**
- OAuth consent screen published. *manual*
- Web client id recorded. *assisted*
- Android client for package + **upload-key SHA-1** and a second one for the **Play App Signing SHA-1**
  (apps installed from Play use the Play key; missing it broke Sabily's Google sign-in). *assisted, block (release)*
- iOS client id recorded (reversed scheme derived). *assisted, block if iOS*

**Google Play**
- App created with the final package id (frozen). Play App Signing enrolled; upload key registered. *manual*
- Target audience: **"Restrict users that Google has determined to be minors" is a deliberate choice**
  — when ticked, minors cannot find or download the app and it can look missing in search for some
  accounts (Sabily, 2026-10). Studio asks and records the decision. *manual, block*
- Content rating, Data safety (export/import CSV between brands), privacy URL, deletion URL. *manual, block*
- Store listing complete (512 icon, 1024x500 feature graphic, screenshots, 7 locales). *manual*
- Target API 36 verified in the built artifact (auto at §6). *auto*
- After publishing: public listing URL returns 200 and appears when searching name and package id
  (indexing can lag days). *auto, warn*

**App Store Connect**
- Bundle id registered with Sign in with Apple capability; agreements (incl. the updated licence) accepted. *manual, block*
- App Privacy answers match `PrivacyInfo.xcprivacy`; screenshots iPhone 6.9" and iPad 13". *manual*
- Review account; export compliance (`ITSAppUsesNonExemptEncryption`); What's New text. *manual*
- Build processing finished before "Submit". *assisted*

Studio deep-links each item to the console page for that brand's ids.

**Feedback loop:** when a launch hits a new problem, the fix is two edits — a signature (§8) or a
checklist item (here). Claude Code is told to do this as part of closing any incident.

## 10. Safety rails

- Dry-run diff for every generator; write only after "Apply". Refuses to run on a dirty tree unless
  the dirty files are listed and accepted.
- Never commits or pushes on its own; "Commit brand changes" is an explicit button that stages only
  the files the generators own.
- Frozen ids: once `studio.json` says a package id is published, the field is read-only.
- A Stripe key from one brand cannot be pasted into another (cross-brand value check, as the wiring
  test already requires distinct values).
- No store upload, no Submit for Review, no rollout, no credential entry. Ever.
- Keystores: generate in the tool (keytool) or import; show SHA-1/SHA-256 once; **warn loudly to back
  the keystore up** (losing an upload key means a Play reset request and a multi-day wait).

## 11. Phases for Claude Code (commit per phase, tests green before the next)

0. **Socle refactor so a brand is data only.** Gradle `productFlavors` and signing built by looping
   over `brands/*/brand.json`; per-brand `key.properties` selection; pubspec flavor entries generated
   between marker comments; keep the wiring test as the contract. *Exit: adding a throwaway brand folder
   builds with zero hand edits in `android/`.* **Done 2026-10-04 (4517c2f).** The drill needed the
   flavor's `res/` folder copied in by hand; generating it is Phase 1.
1. **Core + Brand form + Assets + Guided fields.** Server, UI shell, form bound to `BrandConfig`
   validation, asset pipeline, generators with diff preview, the guide-card mechanism (§4a) with the
   Google, Play and Stripe seed guides, golden-master test (§12). *Exit: regenerate sabily and
   esimple, zero unintended diff; clicking "Get it" on the Google web client id opens the right
   project page and a pasted id is validated and saved.*
   Split in three. **1a done 2026-10-04:** server, UI shell, Brand form, text generators with diff
   preview, golden master over all three brands; 1b = asset pipeline + "New brand", 1c = guided
   fields. Deviations from §3: code in `tool/studio/src/` (a folder named `lib` trips the
   `avoid_relative_lib_imports` lint), tests in `test/studio/` (so plain `flutter test` runs them),
   templates in `tool/studio/templates/`. `mobile.googleIosClientId` joined brand.json (it ships, in
   Info.plist); `appleTeamId` and the `published` ids live in `brands/<slug>/studio.json`.
   **1b done 2026-10-04:** Assets tab, the icon pipeline (`image`, pure Dart, dev
   dependency), New brand. Exit drill passed: "demo" created from the UI alone, `flutter test`
   green (its Xcode-project checks skipped until the Mac step), its profile APK held only its own
   assets and icons, and it ran on the emulator. Existing brands' PNGs are regenerated only on
   request. New brands get a themed-icon layer through a `mipmap-anydpi-v33` adaptive icon,
   so the v26 one shipped brands use is unchanged.
2. **Runner + Logs + Fix Bundle + Doctor.** Job queue, streaming, redaction, signature catalogue,
   environment checks. *Exit: forced failures (missing NDK, bad icon) produce the right signature and bundle.*
3. **Emulator test loop.** AVD management, install/launch, logcat, window-close unlock, test record.
4. **Release.** Key management, AAB + APK, artifact verification, `dist/`, `release.json`.
5. **Checklist engine + probes + template.** All seed items, gating wired into Build.
6. **Mac mode.** iOS generators already in Phase 1; here: simulator test, `build ipa`, export/upload
   command, archive handling, panel shown only on macOS.
7. **Polish.** Phone-frame preview, history, optional "launch Claude Code with this bundle".

Each phase ends with: tests, `flutter analyze`, `dart run tool/check_layers.dart`, and a short
entry in `CLAUDE.md` (how to start Studio, what it owns).

## 12. Acceptance tests

- **Golden master:** feeding `brands/sabily` and `brands/esimple` through every generator reproduces
  the committed files (icons byte-compared after normalisation, text files exact). This proves the
  tool can replace our hand work without regressions.
- **Throwaway brand "demo":** created entirely from the UI with a sample logo, builds, runs on the
  emulator, produces a verified AAB with a test key.
- **Wiring test** passes for every generated brand; Studio refuses to enable Build otherwise.
- **Failure drills:** remove NDK, enlarge the logo, drop the key file, add `API_BASE_URL` to a release
  — each yields its signature and a Fix Bundle under the size cap with no secrets inside.
- **Redaction test:** feed logs containing a fake keystore password and `sk_live_...`; none survives.

## 13. Decisions already taken (change only with reason)

- Local web app, Dart server in `tool/studio/`, reusing the app's `BrandConfig`; no cloud.
- `brand.json` stays the single source of app values; Studio adds `studio.json` for its own data.
- One job at a time; Windows builds Android, Mac builds iOS, the same Studio on both.
- Release never gets `API_BASE_URL`; test builds may.
- The tool stops before every store action.

## 14. Open questions for Alpha (defaults in brackets)

1. Should Studio also run on the Mac for iOS, or only generate iOS files on Windows? [both]
2. Acorn (never published): treat as the first end-to-end real use of Studio? [yes]
3. Play upload automation (API) later? [no; manual upload, revisit after Phase 5]

## 15. Kickoff prompt for Claude Code

> Work in this repo (`transasim-mobile`): Studio lives in `tool/studio/`, not in a new project, because it
> reuses `lib/core/brand` and edits `brands/`, `android/` and `ios/` in place.
> Read `CLAUDE.md` and `docs/STUDIO-SPEC.md` (including §4a guided fields). Do Phase 0 only. Plan first: list the exact files you
> will change and how the wiring test will prove nothing regressed for sabily, esimple and acorn.
> Wait for my approval of the plan, then implement, run `flutter test`, `flutter analyze` and
> `dart run tool/check_layers.dart`, and commit. Do not start Phase 1 until I say so.
