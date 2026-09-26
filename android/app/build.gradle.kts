import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Upload signing, ONE KEY PER BRAND.
//
// This was a single shared `release` signingConfig applied to every flavor, with
// only Sabily's key on disk — so `flutter build apk --release --flavor esimple`
// signed eSimple with Sabily's own upload certificate, the one Play Console has
// registered against com.sabily.esim. A brand's signing identity is not shared
// state, and the build must not be able to reach another client's key by
// default. Each flavor now resolves its own properties file or signs with
// nothing (and falls back to debug); there is no path from one brand to
// another's certificate.
//
// The file names, all gitignored:
//   sabily  -> android/key.properties           (historical name, left alone)
//   esimple -> android/esimple-key.properties
//   acorn   -> android/acorn-key.properties
//
// A brand whose file is absent gets the debug key, which is what a fresh clone,
// CI without the secret, and a brand whose key has not gone live yet all need.
// eSimple's generated keystore is parked at esimple-key.properties.PENDING
// until its Play Console upload-key reset is approved: drop the suffix and the
// build picks it up, no code change.
fun brandSigning(flavor: String): Properties? {
    val name = if (flavor == "sabily") "key.properties" else "$flavor-key.properties"
    val file = rootProject.file(name)
    if (!file.exists()) return null
    return Properties().apply { FileInputStream(file).use { load(it) } }
}

val brandKeys: Map<String, Properties> =
    listOf("sabily", "esimple", "acorn").mapNotNull { flavor ->
        brandSigning(flavor)?.let { flavor to it }
    }.toMap()

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
        // Named for the brand, never "release": a config called `release` is one
        // every flavor will happily pick up, which is the bug this replaces.
        brandKeys.forEach { (flavor, props) ->
            create(flavor) {
                keyAlias = props["keyAlias"] as String
                keyPassword = props["keyPassword"] as String
                storeFile = file(props["storeFile"] as String)
                storePassword = props["storePassword"] as String
            }
        }
    }

    // Deliberately NOT set on buildTypes.release: a signing config there applies
    // to every flavor, which is exactly how one brand reached another's key.
    // Each flavor names its own below, or names none and gets the debug key.
    productFlavors.configureEach {
        signingConfig = brandKeys[name]?.let { signingConfigs.getByName(name) }
            ?: signingConfigs.getByName("debug")
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
