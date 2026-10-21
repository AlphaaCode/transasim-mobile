# transasim-mobile

A white-label eSIM app: one Flutter codebase, three client brands. A brand is
`brands/<slug>/brand.json` plus its assets; `CLAUDE.md` says how the repo works,
`tool/studio/` (Studio) generates every per-brand file.

## Two flavors per brand

A store or TestFlight build never talks to a DEV server (Slice H). Each brand
builds as two separate apps:

- **`<slug>`, the store build:** the store ids, the brand's production host, and
  nothing else. It refuses to start on any other host.
- **`<slug>Dev`, the DEV build:** applicationId and bundle id + `.dev`, " DEV" in its
  name, the DEV host, and a red "TEST SERVER - not for customers" banner on every
  screen. It refuses to start on a production host, and is never uploaded.

No build takes `--dart-define=API_BASE_URL` or `STRIPE_PUBLISHABLE_KEY`: the app
refuses to start with one.

| Brand | Flavor | Android id / iOS bundle id | Backend host |
|---|---|---|---|
| Odyssey Global SIM (acorn) | `acorn` | `com.odyssey.esim` / `com.odysseysim.esim` | acorn-api.transasim.com (production) |
| | `acornDev` | `com.odyssey.esim.dev` / `com.odysseysim.esim.dev` | acorn.transasim.com (DEV) |
| eSimple (esimple) | `esimple` | `com.esimple.esim` / `com.esimple.esim` | api.esimple.at (production; its alias api.esimple.transasim.com is the same server) |
| | `esimpleDev` | `com.esimple.esim.dev` / `com.esimple.esim.dev` | esimple.transasim.com (DEV) |
| Sabily (sabily) | `sabily` | `com.sabily.esim` / `com.sabily.esim` | api.sabily.fr (production) |
| | `sabilyDev` | `com.sabily.esim.dev` / `com.sabily.esim.dev` | api.sabily.transasim.com (DEV) |

## Android

```bash
export PATH="/c/src/flutter/bin:$PATH"     # this Windows machine; the Mac: $HOME/development/flutter/bin
```

Store builds (Studio's *Build release* runs the three release lines, signed with the
brand's upload key, and files the result under `dist/<slug>/`):

```bash
# Acorn
flutter build appbundle --release --flavor acorn -t lib/flavors/main_acorn.dart
flutter build apk --release --flavor acorn -t lib/flavors/main_acorn.dart
dart run tool/studio/bin/studio.dart --verify-release acorn
flutter build apk --profile --flavor acorn -t lib/flavors/main_acorn.dart        # to try it
dart run tool/studio/bin/studio.dart --stage-apk acorn prod                       # -> app-acorn-prod-profile.apk

# eSimple
flutter build appbundle --release --flavor esimple -t lib/flavors/main_esimple.dart
flutter build apk --release --flavor esimple -t lib/flavors/main_esimple.dart
dart run tool/studio/bin/studio.dart --verify-release esimple
flutter build apk --profile --flavor esimple -t lib/flavors/main_esimple.dart
dart run tool/studio/bin/studio.dart --stage-apk esimple prod                     # -> app-esimple-prod-profile.apk

# Sabily
flutter build appbundle --release --flavor sabily -t lib/flavors/main_sabily.dart
flutter build apk --release --flavor sabily -t lib/flavors/main_sabily.dart
dart run tool/studio/bin/studio.dart --verify-release sabily
flutter build apk --profile --flavor sabily -t lib/flavors/main_sabily.dart
dart run tool/studio/bin/studio.dart --stage-apk sabily prod                      # -> app-sabily-prod-profile.apk
```

DEV builds (Studio's *Build for test (DEV)* runs the first two lines, then installs on the emulator):

```bash
# Acorn
flutter build apk --profile --flavor acornDev -t lib/flavors/main_acorn_dev.dart
dart run tool/studio/bin/studio.dart --stage-apk acorn dev                        # -> app-acorn-dev-profile.apk
flutter run --flavor acornDev -t lib/flavors/main_acorn_dev.dart                  # or straight onto a device

# Sabily
flutter build apk --profile --flavor sabilyDev -t lib/flavors/main_sabily_dev.dart
dart run tool/studio/bin/studio.dart --stage-apk sabily dev                       # -> app-sabily-dev-profile.apk
flutter run --flavor sabilyDev -t lib/flavors/main_sabily_dev.dart

flutter build apk --profile --flavor esimpleDev -t lib/flavors/main_esimple_dev.dart
dart run tool/studio/bin/studio.dart --stage-apk esimple dev                      # -> app-esimple-dev-profile.apk
flutter run --flavor esimpleDev -t lib/flavors/main_esimple_dev.dart
```

The two APKs of a brand install side by side: their ids differ.

## iOS, on the Mac

```bash
export PATH="$HOME/development/flutter/bin:$PATH"
ruby tool/ios_flavors.rb        # wires every flavor into Xcode, <slug>Dev included; idempotent
```

Store builds, for TestFlight and the App Store (Studio's *Copy prompt for the Mac*
writes the full sequence for one commit, up to and excluding "Submit for Review"):

```bash
# Acorn
flutter build ipa --release --flavor acorn -t lib/flavors/main_acorn.dart --build-name <version> --build-number <n>
dart run tool/studio/bin/studio.dart --verify-ipa acorn build/ios/ipa/*.ipa

# eSimple
flutter build ipa --release --flavor esimple -t lib/flavors/main_esimple.dart --build-name <version> --build-number <n>
dart run tool/studio/bin/studio.dart --verify-ipa esimple build/ios/ipa/*.ipa

# Sabily
flutter build ipa --release --flavor sabily -t lib/flavors/main_sabily.dart --build-name <version> --build-number <n>
dart run tool/studio/bin/studio.dart --verify-ipa sabily build/ios/ipa/*.ipa
```

Upload only an IPA whose `--verify-ipa` ends with every check `[ok]`.

DEV builds, on the simulator or a phone, never uploaded:

```bash
flutter run --flavor acornDev -t lib/flavors/main_acorn_dev.dart
flutter build ios --profile --flavor acornDev -t lib/flavors/main_acorn_dev.dart
flutter run --flavor sabilyDev -t lib/flavors/main_sabily_dev.dart
flutter build ios --profile --flavor sabilyDev -t lib/flavors/main_sabily_dev.dart
```

A DEV build's Google and Apple sign-in need their own clients and App ID, made for
the `.dev` ids (Studio, Integrations, "DEV build"). Until they exist they fail in DEV
builds; e-mail sign-in works.

## Release checklist

- [ ] **build log and About screen show the PRODUCTION host; application id / bundle id is the store id**
  - Build log: `--verify-release` (Android) or `--verify-ipa` (iOS) prints
    `[ok]  store-build-on-dev: … talks to <host>, <slug>'s PRODUCTION host` and `… names none of the DEV hosts`; once launched, logcat
    shows `[host] PRODUCTION build of <slug> on <host>`.
  - About screen: Profile, its last line, "Server: <host>".
  - Ids: the release check's `package` line (Android) and Info.plist (iOS) name the store id
    in the table above, never one ending in `.dev`.
- [ ] The flavor is `<slug>`, never `<slug>Dev`, and the command has no `--dart-define`.
- [ ] A brand with a standing production exception (studio.json `production.exception`; none today)
  needs `--acknowledge-exception` on `--verify-release` and `--verify-ipa`, and the tick in Studio.
