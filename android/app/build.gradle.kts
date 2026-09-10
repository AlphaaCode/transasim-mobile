plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.transasim.transasim_mobile"
    compileSdk = flutter.compileSdkVersion
    // No plugin in this project ships native code, so no NDK is required.
    // Left unset deliberately: declaring it makes AGP demand a ~2 GB download
    // and, with the current cmdline-tools, auto-install through the deprecated
    // sdkmanager.bat wrapper, which mis-parses the ";" in package names and
    // crashes. Restore `ndkVersion = flutter.ndkVersion` the day a plugin
    // genuinely needs it.

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        // AGP 9 disables resValue by default. The per-flavor app label depends
        // on it, so it is turned on explicitly rather than the label being
        // hardcoded back into the manifest.
        resValues = true
    }

    // One product flavor per client. ARCHITECTURE-MOBILE.md §9.1.
    //
    // The applicationId lives HERE, never in the manifest, and the app label is
    // a per-flavor resource rather than a hardcoded string — the old app had
    // android:label="Sabily eSim" written into AndroidManifest.xml, which is one
    // of the things that made a client a branch instead of a configuration.
    flavorDimensions += "client"
    productFlavors {
        create("sabily") {
            dimension = "client"
            // FROZEN. Already published under this id; changing it creates a new
            // store listing and orphans every existing install. See §3.2 — this
            // is a documented exception to the com.transasim.<slug> convention,
            // not an oversight.
            applicationId = "com.sabily.esim"
            resValue("string", "app_name", "Sabily")
        }
    }

    defaultConfig {
        applicationId = "com.transasim.transasim_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
