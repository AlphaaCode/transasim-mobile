# Android build environment

What a machine (or CI runner) actually needs to build this project, established
by doing it from nothing on 11 September 2026. ARCHITECTURE-MOBILE.md §9.

## Versions

| Component | Version | Why this one |
|---|---|---|
| Flutter | 3.47.3 (stable) | Dart 3.13.3 |
| JDK | Microsoft OpenJDK **21** | Gradle 8.x + AGP 9. Also what the backend JAR needs. |
| Android platform | **36** (compileSdk/targetSdk) and **35** | 36 from `flutter.compileSdkVersion`; 35 is required by the transitive `jni` plugin. |
| Build tools | 36.0.0 | |
| NDK | **28.2.13676358** | Not optional — see below. |
| CMake | **3.22.1** | The `jni` plugin compiles native code. |

## Install

```bash
# JDK
winget install --id Microsoft.OpenJDK.21 --exact --silent \
  --accept-package-agreements --accept-source-agreements

# Flutter — not in winget; take the stable archive and unzip it
#   https://storage.googleapis.com/flutter_infra_release/releases/releases_windows.json
#   -> current_release.stable -> that release's `archive`

# Android SDK command-line tools -> C:\Android\cmdline-tools\latest\
#   https://dl.google.com/android/repository/commandlinetools-win-16111833_latest.zip

android sdk install --sdk=C:/Android platform-tools
android sdk install --sdk=C:/Android "platforms;android-36"
android sdk install --sdk=C:/Android "platforms;android-35"
android sdk install --sdk=C:/Android "build-tools;36.0.0"
android sdk install --sdk=C:/Android "ndk;28.2.13676358"
android sdk install --sdk=C:/Android "cmake;3.22.1"

flutter config --android-sdk C:/Android
flutter config --jdk-dir "C:/Program Files/Microsoft/jdk-21.0.12.101-hotspot"
```

## Build and run

```bash
flutter build apk --debug --flavor sabily -t lib/flavors/main_sabily.dart
```

**Both flags are required.** There is no default flavor and no `lib/main.dart` —
a white-label socle should not have a nameless build. Omitting `--flavor` fails,
which is the intended behaviour.

## Three traps, all hit while setting this up

### 1. `sdkmanager.bat` mis-parses `;` and crashes

The wrapper shipped with cmdline-tools 16111833 splits package names on the
semicolon, so `platforms;android-36` arrives as two arguments. It then exits
with NTSTATUS `0xC0000409` (stack buffer overrun).

Use the `android.exe` binary rather than the `.bat` wrappers. Same for
`avdmanager.bat`; if it must be used, invoke the class directly:

```bash
java -Dcom.android.sdkmanager.toolsdir="C:/Android/cmdline-tools/latest" \
     -cp "C:/Android/cmdline-tools/latest/lib/*" \
     com.android.sdklib.tool.AvdManagerCli create avd \
     -n sabily_test -k "system-images;android-36;google_apis;x86_64" -d pixel_6
```

### 2. SDK auto-download hides the real error

`android/gradle.properties` sets `android.builder.sdkDownload=false`.

With auto-download on, AGP reacts to any missing package by invoking the broken
wrapper above, and the build fails with a stack trace about the wrapper instead
of naming what is missing. With it off, the message is
`Failed to find target with hash string 'android-35'` — which is actionable.

It is also the right setting for CI regardless: a build that fetches its own
toolchain is not reproducible.

### 3. The NDK is not optional, even though this app has no native code of its own

Flutter's Gradle plugin sets `ndkVersion` on the AGP extension itself
(`FlutterExtension.kt`), so removing the line from `android/app/build.gradle.kts`
changes nothing. And the transitive `jni` plugin really does compile C++, so the
NDK and CMake are genuinely needed. Budget ~2.2 GB on disk for the NDK alone.

## Emulator

```bash
android sdk install --sdk=C:/Android emulator
android sdk install --sdk=C:/Android "system-images;android-36;google_apis;x86_64"

emulator -avd sabily_test -no-snapshot -no-audio -no-boot-anim \
         -gpu swiftshader_indirect
```

Software rendering boots in roughly 3–4 minutes on this machine. Wait for
`adb shell getprop sys.boot_completed` to return `1` before installing.

⚠️ **Launch with `am start`, not `monkey`.** `adb shell monkey -p <pkg> -c
android.intent.category.LAUNCHER 1` injects one pseudo-random UI event along
with the launch, which lands on whatever is under it. That produced a
convincing false bug report here — the app appeared to open in the wrong
language because the injected tap hit a language chip.

```bash
adb install -r build/app/outputs/flutter-apk/app-sabily-debug.apk
adb shell am start -n com.sabily.esim/com.transasim.transasim_mobile.MainActivity
adb exec-out screencap -p > shot.png
```

Note the component: the `applicationId` is `com.sabily.esim` (the frozen,
already-published identity, §3.2) while the activity's package is the Dart
package's namespace. That mismatch is expected.
