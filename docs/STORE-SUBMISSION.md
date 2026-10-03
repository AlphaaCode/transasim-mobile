# Store submission: shipping the rebuild as an update

Sabily first; **eSimple** in its own section at the end.

## iOS update — submitted 2026-10-03

Both apps are in App Review as **2.0.0 (20)**, set to release automatically on
approval (all users at once). Built on a Mac with Xcode 26.6 and Flutter 3.47.3,
signed **Apple Distribution: Unception (DP7F8WQCJD)** with each app's App Store
profile; the shipped entitlements carry Sign in with Apple. Signing first failed
until the updated Apple Developer Program License Agreement was accepted
(2026-10-03).

- **Version:** the App Store listings were at 1.3 (Sabily) and 1.0 (eSimple), above
  `pubspec.yaml`'s `1.1.7`, so iOS ships `--build-name 2.0.0`; Android keeps 1.1.7.
- **Sign-in:** Google *and* Apple are offered on iOS (Guideline 4.8 satisfied). Each
  brand has an iOS OAuth client in its Google project; Sabily's is new
  (2026-10-03), because Google had scheduled the Firebase-made one for deletion.
  Apple sign-in verified against the live Sabily backend on the simulator.
- **Store listing:** iPhone 6.9" and iPad 13" screenshots replaced with the rebuild
  (taken on the simulator, same screens as `brands/<slug>/screenshoot/`). What's New
  in French (Sabily) and English (eSimple). App Privacy now also declares User ID
  and Purchase History (app functionality, linked, no tracking), matching
  `PrivacyInfo.xcprivacy`.
- **App Review account:** `bensefiayazid@gmail.com` on both listings; it has to
  exist on both backends.
- **eSimple drops iOS 13–14** (live app 13.0, rebuild 15.0), as noted below. Nothing resolved for
one client is assumed for the other: separate store listings, separate upload
keys, and store access confirmed per app, even though both list the same
seller (Unception).

## Sabily

Checked 2026-09-14. Each item says what was verified, and how. Items marked
**console** can only be answered from Play Console or App Store Connect.

## Blockers

| # | Item | State | Owner |
|---|---|---|---|
| 1 | **iOS bundle id.** The iOS project is still the template: `com.transasim.transasimMobile`, display name "Transasim Mobile", no per-brand scheme. The live app is `com.sabily.esim`. Uploaded as is, it would be a new app, not an update. Needs the §9.1 iOS scheme + configuration for `sabily`, done in Xcode on a Mac. | ✅ done 2026-10-03: `sabily` flavor, `com.sabily.esim`, "Sabily" | Mac + Xcode |
| 2 | **Version numbers** (see below). `pubspec.yaml` says `1.0.0+1`: both stores would refuse it. | iOS ✅: highest uploaded build was 11 (1.0.9); shipped as 2.0.0 (20) | Alpha |
| 3 | **Android upload key.** `release` is signed with the debug key. The upload has to be signed with the key Play expects for `com.sabily.esim` (the old repo's CI took it from secrets). | ❌ open, **console** | Alpha |
| 4 | **Xcode 26 / iOS 26 SDK.** Required for every upload since 2026-04-28. The old CI pinned `XCODE_VERSION: '15.0'`, which would now be refused. This repo has no iOS CI yet: whatever Mac builds it must run Xcode 26 or later. | ✅ Xcode 26.6 / iOS 26.5 SDK | Mac + Xcode |

## Version numbers

Each must be **strictly higher** than what is live. The old repo cannot give
the exact numbers: fastlane `increment_build_number` bumped iOS builds at
upload time, and the live iOS version (1.3) does not appear in any branch.

| | Live (public listing) | Highest in the old repo | Needed from the console |
|---|---|---|---|
| Android `versionCode` | not public | `17` (`versionName 1.1.6`, hardcoded in `build.gradle`) | the highest `versionCode` ever uploaded, **on any track** |
| iOS `CFBundleShortVersionString` | **1.3** (App Store lookup, released 2026-08-13) | 1.1.0 (`dev/ios`) | confirm 1.3 is the highest |
| iOS `CFBundleVersion` | not public | 8 (pubspec; overridden at upload) | the highest build number uploaded |

Once the numbers are known, one line in `pubspec.yaml` covers both
platforms, e.g. `version: 2.0.0+<N>`, where N is above both the Android
`versionCode` and the iOS build. Upload an **AAB** to Play: `--split-per-abi`
APKs add 1000/2000/4000 to the `versionCode`.

## Checked and fine

- **Sign in with Apple (Guideline 4.8).** Not a risk today: the rebuild
  offers **no** third-party sign-in. The old app's Google and Apple buttons
  were deliberately not rebuilt: the deployed backend has no
  `google-auth` / `apple-auth` endpoints (`auth_screens.dart` header). **It
  becomes a rejection the day Google sign-in ships without Apple beside it.**
  Consequence for the update: if any account was ever created through those
  buttons (the endpoints they call do not exist on the deployed backend, so
  possibly none), it has no password here and can only get in through
  "Forgot password". Worth a line in the release notes.
- **Existing users updating.** Their session is not carried over. They land
  signed out, in the language they had, and My eSIMs asks them to sign in.
  The old app's plaintext token and password are deleted. Verified on the
  emulator with the old app's exact SharedPreferences seeded, and by tests.
- **Android `applicationId`** is `com.sabily.esim` (the `sabily` flavor).
- **iOS minimum version** 15.0, the same as the live app: nobody loses
  updates.
- **`NSCameraUsageDescription`** was **missing**; now added. Without it, iOS
  kills the app the moment the voucher scanner opens, and App Store Connect
  flags the binary. English only for now: localising it needs
  `InfoPlist.strings`, added in Xcode (with item 1).
- **`PrivacyInfo.xcprivacy`** was **missing**; now added to Runner and
  registered in the Xcode project. No tracking. Data collected, linked to
  the account, for app functionality: name, email, phone, address, date of
  birth, user id, purchase history. Required-reason API: UserDefaults
  (CA92.1). **Not yet compiled**: the project file was edited on Windows, so
  the first Xcode build (item 1) confirms it. Keep it in step with the App
  Privacy answers in App Store Connect.

## Not a blocker, worth doing with the submission

- **Store screenshots.** Both listings still show the old app's design.
  Replace them with the rebuild's screens in the same submission.

---

## eSimple

Checked 2026-09-15. Published on both stores as **`com.esimple.esim`**
(App Store "eSimple" 1.0, released 2026-08-24, seller **Unception**; the Play
listing is live). So this is an **update**, with the same four blockers
checked separately:

| # | Item | State | Owner |
|---|---|---|---|
| 1 | **iOS bundle id / scheme.** No iOS scheme exists for any client yet (Sabily's item 1). eSimple needs its own: `com.esimple.esim`, display name "eSimple". | ✅ done 2026-10-03 | Mac + Xcode |
| 2 | **Version numbers.** Old branch `spc/esimple`: Android `versionCode 19` / `1.1.8`. App Store: **1.0**. Build numbers are not public. The new app must exceed both, per store. | iOS ✅: highest uploaded build was 12 (1.0.0); shipped as 2.0.0 (20) | Alpha |
| 3 | **Upload keys.** `spc/esimple` signed with its own `key.properties` keystore, which is in no repository. Whether it is the same key as Sabily's is unknown. Both listings name **Unception** as seller, but access to eSimple's listing has to be confirmed on its own. | ❌ open, **console** | Alpha |
| 4 | **Xcode 26 / iOS 26 SDK.** Same requirement as Sabily. | ✅ Xcode 26.6 | Mac + Xcode |

Also specific to eSimple:

- **iOS minimum.** The live app supports **iOS 13.0**; the rebuild requires
  15.0. Updating raises the floor: users on iOS 13 and 14 keep the old app
  and stop receiving updates. A decision, not a blocker.
- **The live app's backend certificate has expired** (2026-09-13;
  `api.esimple.transasim.com`, also esimple.at). Today's store app is very
  likely failing. That is a fix on the server, independent of this release.
- **The old app's local data** uses the same keys as Sabily's old app, so the
  launch cleanup (token and plaintext password deleted, language kept) applies
  unchanged.
- **Store listing:** English only on the App Store; the rebuild serves six
  languages.
- **One `pubspec.yaml` version serves both flavors.** Either pick one number
  above both clients' highest (Android: Sabily 17, eSimple 19, pending the
  consoles), or pass `--build-name` / `--build-number` per flavor at build
  time.
