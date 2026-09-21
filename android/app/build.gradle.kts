import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Real upload signing for release, read from android/key.properties (gitignored,
// alongside the .jks keystore). When it is absent — a fresh clone, or CI without the
// secret — the release buildType falls back to the debug key so `flutter run --release`
// and profile builds still work.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) FileInputStream(keystorePropertiesFile).use { load(it) }
}

android {
    namespace = "com.transasim.transasim_mobile"
    compileSdk = flutter.compileSdkVersion
    // `ndkVersion` is intentionally not set in THIS app module: declaring it
    // makes AGP auto-install the NDK through the deprecated sdkmanager.bat
    // wrapper, which mis-parses the ";" in package names and crashes.
    //
    // But the build DOES require an NDK + CMake — this module just doesn't pull
    // them in itself. path_provider_android and mobile_scanner depend on
    // jni / jni_flutter, which compile native C++ in a ":jni" CMake subproject
    // built against android-35. Those plugins request flutter.ndkVersion
    // themselves, so the NDK + CMake must be installed out of band; a
    // from-scratch machine fails at ":jni:configureCMakeDebug" without them.
    // See CLAUDE.md's toolchain setup: NDK 28.2.13676358, CMake 3.22.1,
    // platforms android-35 (alongside the app's android-36).

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
        create("esimple") {
            dimension = "client"
            // FROZEN, for the same reason: eSimple is published on both stores
            // under this id (ARCHITECTURE-MOBILE.md §3.4).
            applicationId = "com.esimple.esim"
            resValue("string", "app_name", "eSimple")
        }
        create("acorn") {
            dimension = "client"
            // PROVISIONAL, not frozen: never published. The convention (the
            // transasim prefix or the client's own domain) must be decided and
            // written into ARCHITECTURE-MOBILE.md §3.1 BEFORE the first upload
            // to any store track — after that it can never change (§3.3).
            applicationId = "com.transasim.acorn"
            resValue("string", "app_name", "Odyssey Global SIM")
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

    signingConfigs {
        // Sabily's upload key. Only created when key.properties is present, so a
        // keyless checkout still configures cleanly.
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Sabily's real upload key when key.properties is present; the debug key
            // otherwise, so a keyless clone/CI still builds a release.
            //
            // WARNING: this applies to EVERY flavor's release variant, and
            // key.properties currently holds only Sabily's upload key. Do NOT ship an
            // acorn/esimple release from a machine that has this key.properties until
            // each brand's own key is wired in per-flavor (eSimple's key is still an
            // open question).
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
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
