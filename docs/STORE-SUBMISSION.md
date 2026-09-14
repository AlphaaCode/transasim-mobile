# Store submission: shipping the rebuild as an update to Sabily

Checked 2026-09-14. Each item says what was verified, and how. Items marked
**console** can only be answered from Play Console or App Store Connect.

## Blockers

| # | Item | State | Owner |
|---|---|---|---|
| 1 | **iOS bundle id.** The iOS project is still the template: `com.transasim.transasimMobile`, display name "Transasim Mobile", no per-brand scheme. The live app is `com.sabily.esim`. Uploaded as is, it would be a new app, not an update. Needs the §9.1 iOS scheme + configuration for `sabily`, done in Xcode on a Mac. | ❌ open | Mac + Xcode |
| 2 | **Version numbers** (see below). `pubspec.yaml` says `1.0.0+1`: both stores would refuse it. | ❌ open, **console** | Alpha |
| 3 | **Android upload key.** `release` is signed with the debug key. The upload has to be signed with the key Play expects for `com.sabily.esim` (the old repo's CI took it from secrets). | ❌ open, **console** | Alpha |
| 4 | **Xcode 26 / iOS 26 SDK.** Required for every upload since 2026-04-28. The old CI pinned `XCODE_VERSION: '15.0'`, which would now be refused. This repo has no iOS CI yet: whatever Mac builds it must run Xcode 26 or later. | ❌ open | Mac + Xcode |

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
