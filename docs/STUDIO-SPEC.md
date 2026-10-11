# SPC Studio — spec for the white-label app builder

Status: design, written 2026-10-04 by Claude (architect). To be built by Claude Code in this repo.
§16 (the backend phase) added 2026-10-11.
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
| 14 | Backend | API base URL live, auth endpoints, Stripe, test account; the server, its config, database and web tier | §16: `servers.yaml`, `studio.json` `backend`, probes, the checker's report, the items of §9 |

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

`Brand` | `Assets` | `Integrations` | `Backend` | `Checklist` | `Build` | `Logs` | `Doctor` (global)

Setup is the first four tabs: a brand is set up when its data, assets, console values and DEV
backend are in, which is what "Go phase 2" (§16.10) checks.

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
- **Backend** — §16: the DEV and PROD backend fields, the checker and its pasted report, the
  backend and server items with their status, **Go phase 2** and **Go prod**.
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

Doctor checks this machine only. Servers are §16: Studio never connects to one.

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
   - **Backend (§16, added 2026-10-11).** These are seen in a backend log, in certbot's or
     bash's output, or in the app's logcat. Studio sees the last of these from Slice C, and
     the others once Alpha pastes them (G2):
     - `SUBSCRIBER_STATUS_NOT_ELIGIBLE` -> a bad SIM in `esim_inventory`: back the table up,
       then change that one row (transatel-bad-sim);
     - `Invalid API Key provided` -> the backend's Stripe secret key is corrupted or revoked
       (stripe-key-invalid);
     - `client_secret provided does not match any associated PaymentIntent` -> the app's
       publishable key and the backend's secret key belong to different Stripe accounts
       (stripe-account-mismatch; *unverified* wording);
     - `TaskUtils$LoggingErrorHandler` with a foreign-key violation at 01:00 -> JHipster's
       `removeNotActivatedUsers` hits users a subscriber or agency still references. Benign;
       the backend dev owns it (nightly-user-cleanup-fk);
     - certbot `Type: unauthorized` / `DNS problem` -> the A record does not point at the box
       yet. Do not retry: Let's Encrypt rate-limits (certbot-dns; *unverified* wording);
     - bash `event not found` -> a `!` inside double quotes was expanded, so the command ran
       with a corrupted password. Generate passwords with `openssl rand -hex` (bash-bang-password).

   **One fact, one entry.** Where a backend failure is the failure of a §16 item, the item's
   entry carries its cause, its fix and, when the fact also shows in a log, its `match`. So
   there is no separate signature for it:
   - `Anonymous subscriber not found` is be-anon;
   - `must be owner of table` and `permission denied for schema public` are
     ddl-auto-cannot-alter;
   - `Port <n> was already in use` (startup.sh run on a systemd backend) is be-layout;
   - nginx's `conflicting server name` is be-nginx;
   - `CERTIFICATE_VERIFY_FAILED` is be-tls, which takes over backend-tls-expired.

   Other names used on 4 Oct are the same kind of alias:
   - wrong-box is be-box;
   - jwt-template-default is be-jwt;
   - shared-secret is be-unshared;
   - management-public is be-mgmt-private;
   - template-placeholder-left and yaml-hash-placeholder are be-config;
   - psql-wrong-port is be-db;
   - conf-world-readable and restart-wrong-method are be-layout;
   - pg-exposed is srv-pg-private;
   - prod-secrets-on-dev-box is srv-no-prod-secrets;
   - pg-schema-create-denied is ddl-auto-cannot-alter;
   - stripe-test-live-mix is be-stripe-test plus bp-live-stripe;
   - bp-restart is be-layout re-evaluated on PROD.
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

**Where the items live (as built, 2026-10-11).** There is no `checklists/template.yaml`. An
item is an entry in the one list, `tool/studio/incidents/<id>.yaml` (§8):
- `kind: check` when Studio evaluates it (this section's `auto`);
- `kind: checklist` when a person ticks it (`manual`).
`assisted` items are the guides of §4a, and their ticks are 1c's `studio.json` `checklist.<id>`;
manual ticks use the same map, as `{note, evidence, at}`.

**Env-aware items (the backend phase, §16).** Four optional fields:
- `env`: `dev`, `prod`, `both` or `server`. A `both` item gates its own `gate` on DEV and is
  evaluated again on PROD, where it gates `release`. A `server` item is evaluated once per server.
- `when`: the conditions under which the item applies (`payments`, `vouchers`, `google`, `ios`,
  `provisions`, `clientDomains`). Otherwise it reads *n/a*.
- `severity`: `block` (the default) or `warn`, or one per env, e.g. `{dev: warn, prod: block}`.
- `acceptedRisk`: a reason. The item then reads *accepted* and never blocks, but stays on show.

A check may also carry `match` when the same fact shows in a log. It then needs `match` and
`miss` examples, like a signature. Each entry with an `env` has an evaluator in
`tool/studio/src/`, keyed by its id. The evaluators' order is the runbook's order (§16.11).

**Statuses:** pass, fail, warn, n/a, accepted, unknown (no fresh report or probe) and stale (a
report older than 24 h). A gate is open while any applicable `block` item is anything but
pass, n/a or accepted, so **unknown blocks**.

**The gate engine did not exist before slice G1.** Only the `gate` field and 1c's ticks did;
nothing evaluated an item or blocked a step. G1 builds the minimum:
- evaluate one brand on one env;
- list the open blockers for each gate;
- wire gate `test` to Go phase 2.
G2 wires gate `release` to Go prod and to the release build. Phase 5 extends the engine to the
other groups below.

Seed items (from what actually went wrong):

**Backend.** These are now the items of §16.7, which replace the backend bullets that stood
here:
- HTTPS and the certificate (eSimple's expired 2026-09-13) are be-tls.
- `/v1/packs/all` is be-packs.
- The social endpoints and the Google audience are be-social-google and be-social-apple.
- The Stripe keys, the same account, and the purchase through provisioning are
  be-stripe-test, bp-live-stripe, be-dev-purchase and bp-first-purchase.
- A corrupted `sk_live` (the 401) is bp-live-stripe and stripe-key-invalid.
- The store reviewer account on this brand's backend is reviewer-account (gate submit).
- Vouchers provision a real eSIM: never test them with real codes (be-dev-purchase says so).
- The `app-config` route: "404 is acceptable" predates the 24 Sep release that added an
  AppConfig entity. It is *unverified*; be-app-config re-probes it and records the status.

Two backend items stay here, outside §16:
- Registration accepts the brand's field set; null-phone collision known. *auto, warn*
- Google-vs-password account linking behaviour known (`error.emailexists`). *manual, warn*

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
- No connection to a server: no SSH, no deploy, no restart. Studio never holds a server
  password, key or token (§16.2).
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
   **1c done 2026-10-04:** guide engine (`tool/studio/guides/*.yaml`, read with `yaml`, already
   in the lockfile), the 8 seed guides of §4a, the Integrations tab.
   - **Guide schema:** `id`, `title`, `field` (`brand:<path>` | `studio:<key>`), `kind` (paste |
     confirm), `urlTemplate`, `steps`, `copyValues`, `validate` (match / refuse / differsFrom /
     uniqueAcrossBrands, each with its message), `derive`, `requires`, `normalize`,
     `checklistItem`, `examples`.
   - **Confirm guides** (consent screen, Android clients) record `studio.json` `checklist.<item>`,
     with the values they were confirmed for, so a key change marks them stale. Phase 5's
     checklist reads it.
2. **Runner + Logs + Fix Bundle + Doctor.** Job queue, streaming, redaction, signature catalogue,
   environment checks. *Exit: forced failures (missing NDK, bad icon) produce the right signature and bundle.*
   **Done 2026-10-11 (Slice B).**
   - **One incident list.** The "signature catalogue" is `tool/studio/incidents/<id>.yaml`, 24
     seeds. It is the single list that §8's signatures, Phase 5's checklist (`kind: checklist`,
     `gate`) and D1's cases share. Each file carries `match` regexes with `match` and `miss`
     examples, which are its tests. `autofix` names a job and is never a command. It is a
     button, not an automatic re-run, so nothing installs unasked.
   - **Jobs.** Validate (fast and full), stopping the Gradle daemon, and installing SDK
     packages. Cancel kills the process tree.
   - **Drills.** Missing NDK, an oversized logo, a missing key file, `API_BASE_URL` in a
     release, and the Stripe activity each yield their incident and a redacted bundle under
     8,000 characters (`test/studio/fix_bundle_test.dart`).
   - **The SDK installer.** cmdline-tools 23 removed sdkmanager's Java class, so Doctor uses
     `android sdk install` there.
   - **Deferred to Phase 4,** where Studio first runs Gradle: stopping the daemon between two
     brands' builds.
   - **App fixes found on the way.** The socle's `drawable-v21` and `values-night` launch
     resources hid every flavor's launch window, so both were deleted and a guard was added.
     The intro now logs `[intro] abandoned`.
3. **Emulator test loop.** AVD management, install/launch, logcat, window-close unlock, test record.
4. **Release.** Key management, AAB + APK, artifact verification, `dist/`, `release.json`.
5. **Checklist engine + probes + template.** All seed items, gating wired into Build.
6. **Mac mode.** iOS generators already in Phase 1; here: simulator test, `build ipa`, export/upload
   command, archive handling, panel shown only on macOS.
7. **Polish.** Phone-frame preview, history, optional "launch Claude Code with this bundle".

**The backend phase, slices G1 and G2 (§16), added 2026-10-11.**
- **G1:** `servers.yaml`; the Backend tab's DEV fields and validation; the probes; the checker v1
  with report ingest (schema, WRONG BOX, secret refusal, 24 h expiry); every DEV, `both` and
  server item; the minimum gate engine; Go phase 2; the DEV build defines; the Fix Bundle's
  Backend section.
  **Done 2026-10-11.**
  - **The checker** (v1) is in `tool/studio/backend/`. Its parsers run in a `--selftest` that
    `flutter test` calls.
  - **The items** are 34 entries in the one list; `backend-tls-expired` became `be-tls`.
  - **The code:** `tool/studio/src/backend.dart` holds the registry, report ingest,
    evaluators, gate, plans and commands; `probes.dart` holds the probes.
  - **The page:** the Backend tab, and Build's "Build for test (DEV)".
  - **Acorn** was entered through the tab, and **Sabily's DEV backend** too (for the schema
    reference).
  - **The live probe of Acorn passed:** DNS, TLS 58 days, `/management` 403, 983 packs.
  - **The report path was checked with a fixture,** since only Alpha can run the checker: a
    v1 report derived from the real 2026-10-11 run read exactly as §16.12 predicts.
  - **The gate is held only by be-schema-drift,** until Sabily's real report sets the
    reference.
- **G2:** the PROD fields and items; the schema ledger; Go prod and the release assertion;
  the backend signatures (§8); pasting a log to classify it; the runbook page generated from
  the items.

**The remaining slices run in this order: G1, G2, E, C, D1, D2, F.**
- G1 and G2 go first because Acorn's backend is what blocks Acorn now, and because E's
  release build needs G2's release assertion before it builds any brand: eSimple's
  `brand.json` points at the dev box today (§16.12).
- G1 builds the part of Phase 5's engine that its gates need. Phase 5 extends it to the
  other §9 groups.
- E (Phase 4 plus Phase 6's Mac prompt), C (Phase 3) and D are unchanged.

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
- **Backend (G1, G2):** Acorn on DEV (acorn.transasim.com, 169.58.35.140:9074, db `acorn_prod`;
  payments and vouchers off in its Phase 1).
  - be-anon and be-stripe-test read n/a. Every other item is driven by the probes and a
    pasted v1 report.
  - A report from the wrong box, one older than 24 h, one with an unknown `schema_version`,
    one missing a field, and one carrying anything secret-shaped are each refused, and
    nothing is stored.
  - Go prod shows exactly the `brand.json` diff, and a release build pointing at DEV is
    refused.

## 13. Decisions already taken (change only with reason)

- Local web app, Dart server in `tool/studio/`, reusing the app's `BrandConfig`; no cloud.
- `brand.json` stays the single source of app values; Studio adds `studio.json` for its own data.
- One job at a time; Windows builds Android, Mac builds iOS, the same Studio on both.
- Release never gets `API_BASE_URL`; test builds may.
- The tool stops before every store action.
- Studio never connects to a server. The backend is checked by probes from the PC, by a
  read-only report Alpha runs and pastes, and by ticks (§16).

## 14. Open questions for Alpha (defaults in brackets)

1. Should Studio also run on the Mac for iOS, or only generate iOS files on Windows? [both]
2. Acorn (never published): treat as the first end-to-end real use of Studio? [yes]
3. Play upload automation (API) later? [no; manual upload, revisit after Phase 5]
4. **eSimple's mobile backend.** **Decided 2026-10-11: 169.58.35.140 is eSimple's app
   production**, because the app pays through it.
   - **What the box holds:** the app's `brand.json` points at esimple.transasim.com, served by
     esimple-backend there, with a live Stripe key and 70 payments.
   - **In `servers.yaml`:** the dev box carries `prodFor: [esimple]`.
   - **What Studio does with that:** it offers that box only as eSimple's PROD, never as its
     DEV, and never proposes a test key for that backend.
   - **The other backend:** the old store app and esimple.at keep using 80.241.216.126, a
     different database also named `esimple_prod`.
5. **Sign in with Apple on DEV.** Acorn has an iOS flavor, so its app offers Apple sign-in,
   and acorn-backend has no Apple client ids. Should be-social-apple block Go phase 2 or
   only Go prod? [only Go prod: it warns on DEV] **Accepted 2026-10-11.**
6. **The three narrower columns.** Matching the reference schema fails Acorn and eSimple on
   three columns: `app_config.config_key`, `app_config.updated_by` and
   `subscriber.auth_provider`. deploy.sh's SQL gave them explicit lengths, while Sabily's
   ddl-auto used 255. Widen them, or let a column difference be accepted like a CHECK?
   [widen them through the ledger: the spec says columns must match] **Accepted 2026-10-11.**

## 15. Kickoff prompt for Claude Code

> Work in this repo (`transasim-mobile`): Studio lives in `tool/studio/`, not in a new project, because it
> reuses `lib/core/brand` and edits `brands/`, `android/` and `ios/` in place.
> Read `CLAUDE.md` and `docs/STUDIO-SPEC.md` (including §4a guided fields). Do Phase 0 only. Plan first: list the exact files you
> will change and how the wiring test will prove nothing regressed for sabily, esimple and acorn.
> Wait for my approval of the plan, then implement, run `flutter test`, `flutter analyze` and
> `dart run tool/check_layers.dart`, and commit. Do not start Phase 1 until I say so.

## 16. Backend phase

Added 2026-10-11 and built in slices G1 and G2 (§11). The facts come from two sources:
- Alpha's 4 Oct operations log;
- the read-only inventory of the dev box run on 2026-10-11 (`spc-check/REPORT.md`, outside
  the repo).

Anything neither source showed is marked *unverified*.

### 16.1 The flow

```
Setup: Brand, Assets, Integrations, Backend (DEV)   Studio collects and verifies the DEV backend
Go phase 2       (gate test green on DEV)           unlocks DEV test builds
Build for test   (profile APK + DEV defines)        Alpha tests against DEV
Go prod          (gate release green on PROD)       brand.json switches to PROD (previewed Apply)
Generate release (§6)                                refused unless brand.json points at PROD
```

Required items block. The items are §9's, entries in `tool/studio/incidents/`, and the gates
are §9's gates. This phase adds no second list.

### 16.2 What Studio never does

- **Connect to a server.** No SSH, SCP, SQL or deploy, and no password, key or token is ever
  held. Alpha logs in himself.
- **Reach a server through Claude Code.** Claude Code on the PC cannot reach any server and
  does not try. Running commands over key-based SSH is out of scope.
- **Store a secret.** `studio.json`, reports, logs and the Fix Bundle hold only key classes
  (`sk_test_`), booleans, counts, names and hashes. `redact.dart` runs over every paste.
- **Change a server.** It prints commands; Alpha runs them.

### 16.3 Servers: `tool/studio/servers.yaml`

The file is committed and holds no secrets. Its fields:
- `id`;
- `role`: dev, prod or retired;
- `prodFor`: brands whose production backend the box runs, whatever its role. Studio offers
  that box only as their PROD, never as their DEV, and never proposes a test key there;
- `host`;
- `expectedHostname`, the name in the shell prompt. A report from any other host is refused
  as WRONG BOX;
- `sshPort` and `sshUser`;
- `pgPort`;
- `scripts`: existing automation on that box, as `{name: {path, use}}`. It stays empty until a
  server report describes them;
- `notes`.

| id | role | host | expectedHostname | login | pgPort | holds |
|---|---|---|---|---|---|---|
| dev | dev, `prodFor: [esimple]` | 169.58.35.140 | vmi3448057 | root, port 22 (no `hostadmin` user) | 6478, confirmed 2026-10-11 | Debian 13, PostgreSQL 17. `sabily` (9060, systemd, db `sabily`), `esimple-backend` (9073, scripts, db `esimple_prod`: **eSimple's app production**, §14.4), `acorn-backend` (9074, scripts, db `acorn_prod`) |
| prod-esimple | prod | 80.241.216.126 | vmi3247176 | hostadmin, port 52145 | 6478 *unverified* | eSimple's web and old store app (its db is also named `esimple_prod`), Castrum, an old Acorn copy. **The default prod for a new brand.** |
| prod-sabily | prod | 109.199.126.149 | vmi2943380 | *unverified* | *unverified* | api.sabily.fr; log `/var/log/sabily/sabily.log` *unverified* (on dev, `logging.file.name` is never written) |
| retired | retired | 213.136.70.254 | vmi3234013 | | | never offered |

Postgres listens on 6478 on these boxes. `psql` on its default port can reach a different,
stray listener. So `pgPort` is per server, and the report confirms it (`pg_ports_listening`).

### 16.4 A brand's backend: `studio.json` `backend`

```json
"backend": {
  "features": {"payments": false, "vouchers": false},
  "clientDomains": ["odysseysim.com"],
  "migrationPath": "SQL files applied by deploy.sh",
  "schemaAccepted": {"agency.agency_status_check": "<reason>"},
  "dev": {"server": "dev", "name": "acorn-backend", "domain": "acorn.transasim.com",
          "apiBaseUrl": "https://acorn.transasim.com/api", "port": 9074,
          "dir": "/apps/acorn-backend", "db": "acorn_prod", "jar": "acorn-backend.jar",
          "restartMethod": "scripts", "shellUser": "root", "stripePublishableKeyTest": null},
  "prod": {"server": "prod-esimple", "...": "the same fields, without the test key"},
  "activeEnv": "dev",
  "phase2": {"at": "<time>", "jarSha256": "<16 hex>", "backendCommit": "54dd318"},
  "prodAt": null,
  "schemaLedger": [{"id": "payment-method-check", "what": "<the SQL, as a description>",
                    "devAt": "<time>", "prodAt": null}]
}
```

**Features.**
- `payments` and `vouchers` are **declared** here.
  - `brand.json` has no such flags: `BrandFeatures` holds only what the app reads, and every
    brand's home screen offers vouchers.
  - If `payments` is declared but `brand.json`'s key cannot take payments, Go prod asks for
    the `pk_live_` key, and the reverse warns.
- `google` and `ios` are **derived** and shown read-only.
  - `google` is set when `brand.json` has `mobile.googleServerClientId`.
  - `ios` is set when the brand has an iOS flavor, since the iOS app always offers Sign in
    with Apple.
- `provisions` is true for every brand today. Add a flag the day one does not provision.
- `partner` is dropped, because no item reads it.

**Manual ticks** use the existing `checklist.<id>` map (Phase 1c), as `{note, evidence, at}`.

**Every field:**
- is validated as typed: a host name; an `https://` URL on that domain; a port; `/apps/<name>`;
  a database identifier; `pk_test_` and nothing else for the test key;
- is distinct where it must be: port, dir and db per server, the domain, and the test key per
  brand;
- is refused if it is shaped like a secret;
- is written only through the previewed Apply, under the write lock.

### 16.5 How an item is checked

**Probe:** Studio's own call from this PC to the brand's public endpoints, run on "Check" with
an 8 s timeout each.
- DNS: the A record of `domain` equals the server's `host`.
- TLS: the certificate is valid and has more than 14 days left.
- `GET <apiBaseUrl>/v1/packs/all` answers 200 with packs (a `{content: [...]}` page); its time
  to first byte is recorded.
- `POST <apiBaseUrl>/v1/auth/google` and `/v1/auth/apple` with a junk token answer 4xx, not
  404. Each runs only when `google` or `ios` is set.
- `https://<domain>/management/health` must **not** answer 200: nginx denies it with 403 by
  design. Plain `http://` must never answer 200.
  - Health is not probed publicly. The report's local
    `http://127.0.0.1:<port>/management/health` is the authority.
  - `/api/management/health` answers 401: never probe it.
- `GET <apiBaseUrl>/app-config`: the status is recorded, nothing more. On Acorn's DEV it
  answered **401** on 2026-10-11, so the route exists and wants a login.

**Report:** the checker's JSON, pasted in (16.6).

**Manual:** Alpha ticks the item, with a note and the evidence.

### 16.6 The checker and its report

**The scripts.** `tool/studio/backend/` holds `spc-backend-check.sh`, `ymlmap.py` and
`sharecheck.py`, adopted from Alpha's run on 2026-10-11.
- **Install.** Studio shows each file's SHA-256 and a paste snippet that writes the three files
  to `~/spc-check/` and prints `sha256sum`, so Alpha can compare.
- **Read-only.** It uses `ps`, `ss`, `curl`, `getent`, `nginx -T`, `certbot certificates`,
  `journalctl`, and SELECT and catalog queries.
- **Output.** It prints ONE JSON object of booleans, counts, enums, names and hashes. A config
  value appears only for an allowlisted key.
- **Guard.** It withholds its whole output when a secret marker (`sk_`, `pk_`, `eyJ`, `BEGIN`,
  `password`) appears anywhere in it. That guard stays.

**Version 1 adds these fields to the 2026-10-11 output:**
- `schema_version` (1), `generated_at` (UTC), `script_version`, `jar_sha256_16`;
- `conf_dir_mode`, `conf_world_readable`;
- `management_public_status`, and `management_public_exposed`: true if `/management` answers
  200 over HTTPS, or answers 200 over plain HTTP (a redirect is not followed);
- `pg_listen_all`, `ufw_pg_open_to_world`, `pg_ports_listening`;
- `anonymous_subscriber_user_valid`: the subscriber's `user_id` points at an existing user;
- `url_host_resolves_to_this_box`, for the Stripe success and cancel URLs and the mail base
  URL;
- `config_values`: those hosts, plus `mail_from_domain`, `spc_name` and `log_file`. Only a domain is
  printed, never an address. be-config and be-mail need them;
- `template_placeholder_left`, as key names:
  - "my-server-url-to-change";
  - another brand's value, such as info@sabily.fr on a non-Sabily brand;
  - a `key: #` line, which YAML reads as null;
- `unit_enabled`, `layout_missing`, `scripts_executable`, `logging_keys_ok`,
  `sftp_path_in_dir`, `db_role_exists`;
- `authorities`, the role names;
- `nginx_management_denied`;
- `google_client_listed`, given `--google-client <the app's web client id>` (the id is public
  and ships in the app);
- `gcp_credentials_shared_with`, and the SFTP password added to `secret_shared_with`;
- `schema`: a hash of each table's columns (name, type, null) and of each CHECK's definition,
  for be-schema-drift. Names would trip the `password` guard (`jhi_user.password_hash`), so
  the script prints hashes;
- `server`: `ufw_open_ports`, `pg_hba_external_rules`, `http_only_backend_vhosts`,
  `world_readable_dumps`, `stray_live_stripe_files` (files holding a live key outside a running
  backend's own config, a count), `certbot_timer_active`, `ufw_active`,
  `backups_scheduled`;
- `stripe_account_ok` and `stripe_charges_enabled`, given `--stripe-account`. That calls
  `GET api.stripe.com/v1/account` with the configured key and prints neither the key nor the
  answer.

**Two script changes:**
- The box's public IP comes from `--public-ip` (Studio passes the server's `host`), or else
  from `ip route get`. The script no longer calls api.ipify.org.
- `ymlmap.py` masks credentials in a URL (`://user:pass@`) for allowlisted keys as well.

**Ingest** (`POST /api/backend/<slug>/report`, with the env):
1. It is one JSON object, and `schema_version` is known (1). Otherwise: "unknown
   schema_version".
2. Every field is present with its type, no field is unknown, and every string is short
   (200 characters at most).
3. `hostname` equals the env's server's `expectedHostname`. Otherwise the whole report is
   refused as **WRONG BOX**.
4. `generated_at` is at most 24 h old, and no more than 5 min ahead.
5. `redact.dart` must leave the text unchanged.
   - If it would mask anything (`sk_`, `rk_`, `whsec_`, a JWT, PEM, an e-mail address or a
     known password), the report is refused and nothing is stored.
   - The error names the shape and never the text.

An accepted report is written to `.studio/reports/<slug>/<env>-<generated_at>.json`
(gitignored). Once it is 24 h old, it no longer satisfies a gate, and its items read
*stale*.

### 16.7 The items

§9 defines the statuses, `env`, `when` and `severity`. Every item blocks unless it says warn.
Evaluated on DEV, a `both` item gates `test` (Go phase 2). Evaluated on PROD, against the
PROD report and probes, it gates `release` (Go prod).

**On every backend, DEV and PROD** (`env: both`)

| id | from | passes when | applies when |
|---|---|---|---|
| be-box | report | `hostname` is the server's `expectedHostname` (otherwise the report is refused) | |
| be-port | report, studio.json | the port listens, and the config's `server.port` equals the recorded port, which is unique among the brands on that server | |
| be-layout | report | `/apps/<name>/{bin,conf,lib,logs,temp}` exist; the jar is `<name>.jar`, run from there; APP_NAME is the same in startup.sh and shutdown.sh; the scripts are executable; conf is not world-readable; the recorded `restartMethod` equals the report's | |
| be-survives-reboot | report | an enabled systemd unit. warn on DEV | |
| be-db | report | Postgres listens on the server's `pgPort`; the datasource URL names this database on that port; the role exists (`db_role_exists`) | |
| be-schema-drift | report, reference | 16.8 | |
| ddl-auto-cannot-alter | report | warn only: with `ddl-auto: update` and a role that owns no table, schema changes are SQL, recorded in the ledger | |
| be-seed | report | `jhi_authority` holds 4 roles, including ROLE_ADMIN, ROLE_USER and ROLE_SUBSCRIBER; country, currency, area, pack, price and allowance are non-empty; so is esim_inventory, when `provisions`. network, operator, subscription_config and display_config may be empty (0 rows in all three working databases) | |
| be-anon | report | a subscriber `anonymous@anonymous.com` whose `user_id` is an existing user (not necessarily one called "anonymous") | vouchers |
| be-config | report | no template value is left; the mail base URL and the Stripe success and cancel hosts resolve to this server or are a declared client domain; spc-name is the brand's name; the log path names this brand and no other; the SFTP local path is inside this backend's directory; the `com.tamarisoft.sabily` logging keys are untouched | |
| be-mail | report | the from-address's domain is the brand's (its support e-mail's or one of its domains), never another brand's | |
| be-jwt | report | not the template default (prefix `ZjljZjQ1`); not shared on the box | |
| be-unshared | report | Stripe, the Transatel login, SFTP, the database, reCAPTCHA and the GCP credentials file are not shared with another backend, unless a reason is recorded. warn on DEV | |
| mail-shared-account | report | accepted risk: one Ionos account sends for every brand | |
| be-start | report | the port listens; local `/management/health` answers 200 UP; the jar runs from this dir | |
| be-transatel | report | the log shows "APIs Transatel … (8/8)" within 48 h, with the brand's own login | provisions |
| be-dns | probe | the A record is the server's `host` | |
| be-nginx | report | `nginx -t` passes; `server_name` is present, with no "conflicting server name"; `/api/` proxies to the port; `/management/` is denied | |
| be-tls | probe | valid, with more than 14 days left (takes over backend-tls-expired) | |
| be-mgmt-private | probe, report | the public `/management` never answers 200, and never answers over plain HTTP | |
| be-packs | probe | `/v1/packs/all` answers 200 with packs; its time to first byte is recorded | |
| be-social-google | probe, report | a junk token gets 4xx, not 404; the backend lists the app's web client id | google |
| be-social-apple | probe, report | a junk token gets 4xx, not 404; the Apple client ids are set. warn on DEV | ios |
| be-app-config | probe | warn only: the status is recorded (the "404 is acceptable" verdict is *unverified* since AppConfig) | |

**DEV only**

| id | from | passes when | applies when |
|---|---|---|---|
| be-stripe-test | report, studio.json | the backend's key is `sk_test_`; the account probe shows `acct_` and `charges_enabled`; the DEV `pk_test_` key is recorded | payments |
| transatel-production-on-dev | report | accepted risk: DEV also provisions through api.transatel.com, since no sandbox is known | provisions |
| be-dev-purchase | manual | gate release: a test purchase completes through provisioning (`POST /v1/subscriptions/card` answers 2xx), with evidence; never with a real voucher code | payments |

**PROD only** (gate release unless stated)

| id | from | passes when | applies when |
|---|---|---|---|
| bp-same-jar | report | `jar_sha256_16` equals the one recorded at Go phase 2 | |
| bp-live-stripe | report, manual | the key is `sk_live_`; the account probe passes, with `charges_enabled`. A manual tick confirms the `pk_live_` key Go prod writes is from the same Stripe account | payments |
| bp-nopending | report | no `PENDING_` placeholder is left | |
| bp-fresh | manual | the JWT secret, the database password and the admin password were generated new for PROD | |
| bp-testdata | manual | the test accounts and the default admin password are gone | |
| bp-ledger | studio.json, report | every ledger entry is applied on PROD, and the PROD schema matches the reference except for accepted differences | |
| bp-backup | manual, report | a fresh `pg_dump` exists before any PROD database change, and srv-backups passes | |
| bp-rotated | manual | every credential ever pasted into a chat or a terminal log has been rotated. Four from 4 Oct are still unconfirmed, and their names are not in the repo | |
| bp-domain | probe | the client's domain resolves to the PROD host and is on the same certificate | clientDomains |
| release-points-at-dev | studio.json | 16.9. It also runs before every release build | |
| bp-first-purchase | manual | gate submit: one real purchase through provisioning on PROD, then refunded | payments |
| reviewer-account | manual | gate submit: the store reviewer account exists on the PROD backend (§9) | |

**Once per server** (`env: server`): warn on a dev box, block on a prod box. Each is
evaluated from the freshest report of any backend on that server, and shown on every brand
there.

| id | passes when |
|---|---|
| srv-ports | ufw allows only ssh, 80 and 443 from anywhere |
| srv-pg-private | Postgres cannot be reached from outside: it is not both listening on `*` and open in ufw, and pg_hba has no rule for an outside address |
| srv-no-http-backend | no plain-HTTP vhost proxies a backend |
| srv-world-readable | no dump, SQL file or tarball is world-readable |
| srv-no-prod-secrets | no live Stripe key sits outside a running backend's own config (a stray copy), on any box |
| srv-certbot | `certbot.timer` is active |
| srv-backups | a scheduled job dumps the databases |

### 16.8 Schema

**How the backends change their schema.**
- All three backends run `ddl-auto: update`, with Liquibase disabled on the command line.
- acorn_prod's and esimple_prod's tables belong to `postgres`, so ddl-auto cannot alter them.
  Their schema changes are SQL files that deploy.sh applies.
- The `databasechangelog` copy step is moot.

**The reference** is Sabily's dev database. "Use as schema reference" stores the `schema`
hashes of an accepted Sabily DEV report in `tool/studio/backend/reference-schema.json`,
through a previewed Apply. The file holds hashes only.

**be-schema-drift passes when:**
- every table and column equals the reference;
- each CHECK difference is listed, then either accepted with a reason (`schemaAccepted`) or
  fixed;
- the migration path is recorded.

Foreign-key, primary-key, unique-key and index names differ only by convention (Liquibase
against Hibernate), so they are not compared.

**The schema ledger** (G2):
- `schemaLedger` records every SQL statement run by hand on DEV since the template, e.g.
  `payment_method_check` allowing CARD, CASH, TRANSFER and BALANCE.
- Each entry is ticked "applied on prod".
- bp-ledger blocks Go prod until every entry is, and the PROD report's `schema` confirms it.

**Today (2026-10-11),** acorn_prod and esimple_prod differ from sabily in three ways:
- three columns: `app_config.config_key` is 50 against 255, `app_config.updated_by` 100
  against 255, and `subscriber.auth_provider` 20 against 255;
- acorn_prod lacks the 12 CHECKs that sabily has, and esimple_prod lacks 11 of them (it has
  `payment_method_check`).

### 16.9 DEV and PROD builds

The code already enforces the split: a release reads `mobile.apiBaseUrl` and
`mobile.stripePublishableKey` from `brand.json` only, and throws on launch if either is
overridden (`brand_loader.dart`).

**Build for test (DEV)** is unlocked by Go phase 2.
- It is a profile, universal APK.
- It passes `--dart-define=API_BASE_URL=<backend.dev.apiBaseUrl>`.
- With payments, it also passes `--dart-define=STRIPE_PUBLISHABLE_KEY=<the DEV pk_test_ key>`,
  and refuses anything that is not `pk_test_`.

**The release assertion** (release-points-at-dev) runs before every release build, and Studio
refuses the build unless:
- `brand.json` `mobile.apiBaseUrl` equals `backend.prod.apiBaseUrl`;
- with payments, the key starts with `pk_live_`;
- without payments, the key is not a usable `pk_test_` key.

### 16.10 Go phase 2 and Go prod

**Go phase 2** is enabled when gate `test` is green on DEV.
- Its previewed Apply writes `backend.phase2`: the time, the DEV report's `jar_sha256_16`, and
  the backend commit Alpha types (54dd318 today).
- A later DEV report showing another jar says "re-test".

**Go prod** is enabled when gate `release` is green, which needs:
- every `both` item, on the PROD report and probes;
- every PROD item;
- be-dev-purchase;
- the PROD jar equal to the one recorded at Go phase 2 (bp-same-jar).

Then Go prod:
- shows the exact `brand.json` diff: `mobile.apiBaseUrl`, plus `mobile.stripePublishableKey`
  when payments needs the `pk_live_` key;
- applies it through the previewed Apply, under the write lock;
- sets `activeEnv: prod` and `prodAt`;
- never commits or pushes.

### 16.11 The commands Studio prints

Per brand and env, filled from `servers.yaml` and `studio.json`, and golden-tested:
- the ssh line;
- the checker's run;
- the restart, by the report's method:
  - systemd: `systemctl restart <name>`;
  - scripts: `bin/shutdown.sh && bin/startup.sh`.

  Never `startup.sh` on a systemd backend: it starts a second JVM on the same port;
- `check` and `status` of the box's own scripts (install.sh, deploy.sh), once `servers.yaml`
  describes them; until then, "script unknown".

No replacement for those scripts is designed now.

**The runbook page** (G2) is generated from the same entries, in the evaluators' order, with
these commands. The written runbook therefore cannot drift from the checklist.

### 16.12 What the dev box shows today (2026-10-11)

The run produced v0 reports, so some items have no field yet. What they show:

**eSimple (decided, §14.4)**
- The app's `brand.json` points at esimple.transasim.com, which resolves to **this box**.
- esimple-backend there runs a `sk_live_` key, and its database holds 70 payments.
- It is eSimple's app production. So it is evaluated as eSimple's PROD (G2), where a live key
  is right, and never as a DEV backend.

**Per item**
- **be-jwt** fails, and blocks, for Sabily DEV: its JWT secret starts with the template
  default.
- **be-unshared**:
  - the mail password is shared by all three backends, an accepted risk
    (mail-shared-account);
  - acorn's and esimple's GCP credentials file is the same file, which warns.
- **transatel-production-on-dev** is an accepted risk: all three call api.transatel.com.
- **be-survives-reboot** warns for acorn-backend and esimple-backend, which have no systemd
  unit.
- **be-config** fails for esimple: its mail base URL is still the template placeholder, its
  mail sender is Sabily's address, and its SFTP path is outside its own directory.
- **be-mail** fails for esimple.
- **be-layout** fails for esimple: its conf directory is world-writable.
- **be-schema-drift**: see 16.8.
- **Server items, all warnings on a dev box:**
  - Postgres 6478 is reachable through ufw from anywhere. It is not open to the internet:
    pg_hba admits only 127.0.0.1 (and ::1) and one external address;
  - a plain-HTTP vhost proxies a whole backend, `/management` included;
  - an acorn dump and the tarballs are world-readable;
  - three stray copies of live Stripe keys sit in files;
  - no backup is scheduled.
- **srv-certbot** passes.

**Logs.** The 01:00 errors on all three backends are JHipster's `removeNotActivatedUsers`
hitting foreign keys. They are benign (nightly-user-cleanup-fk), and the backend developer
owns them.

**Acorn (payments and vouchers off)** is expected to read:
- **pass:** be-box, be-port, be-layout, be-db, be-seed, be-start, be-transatel (8/8), be-dns,
  be-nginx, be-tls (58 days), be-mgmt-private (403), be-packs, be-jwt and be-mail;
- **n/a:** be-anon, be-stripe-test, be-dev-purchase and be-social-google (Acorn has no Google
  client);
- **accepted:** mail-shared-account and transatel-production-on-dev;
- **warn:** be-survives-reboot, be-unshared (the GCP file), ddl-auto-cannot-alter and the
  server items;
- **fail until fixed or decided:**
  - be-schema-drift: the reference and the CHECK acceptances, plus §14.6;
  - be-config: odysseysim.com, until it is declared in `clientDomains` (done in G1: it passes);
  - be-social-apple, which only warns on DEV.
