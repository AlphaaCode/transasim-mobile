allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Plugins compile their Kotlin at whatever target they were written against —
// stripe_android uses 21 while its own Java tasks use 17, which Gradle refuses
// as inconsistent. The app is on 17, so every dependency is pinned to 17 too.
// Without this the Stripe SDK simply will not build.
subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        }
    }
    plugins.withId("com.android.library") {
        extensions.configure<com.android.build.gradle.LibraryExtension> {
            compileOptions {
                sourceCompatibility = JavaVersion.VERSION_17
                targetCompatibility = JavaVersion.VERSION_17
            }
        }
    }
}

// flutter_stripe (stripe_android) bundles a push-provisioning integration whose
// classes its OWN Kotlin source references at compile time, so the push-provisioning
// module itself cannot be excluded — doing so breaks :stripe_android:compileReleaseKotlin
// with unresolved references. That module in turn pulls the restricted
// com.google.android.gms:play-services-tapandpay (404 on every public Maven — Google's
// Push-Provisioning SDK), which only the runtime and lint classpaths resolve, never
// compile. This app uses Stripe for checkout, not Issuing / Google Pay card
// provisioning, so exclude just the unreachable tapandpay artifact across EVERY
// subproject (not only :app — :stripe_android resolves it in its own configurations,
// e.g. releaseLintChecksClasspath during lintVitalRelease). push-provisioning still
// compiles; its tapandpay-backed runtime paths are dead code we never reach.
subprojects {
    configurations.all {
        exclude(group = "com.google.android.gms", module = "play-services-tapandpay")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
