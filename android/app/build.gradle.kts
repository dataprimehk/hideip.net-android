import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing config. key.properties lives outside version control and
// points at the upload keystore stored outside the repo. Release tasks fail
// closed when any part is absent; debug signing must never reach a store APK.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}
val releaseRequested = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}
val signingKeys = listOf("keyAlias", "keyPassword", "storeFile", "storePassword")
val missingSigningKeys = signingKeys.filter {
    (keystoreProperties[it] as String?)?.isBlank() != false
}
val releaseStoreFile = (keystoreProperties["storeFile"] as String?)?.let(::file)
val releaseSigningReady = keystorePropertiesFile.exists() &&
    missingSigningKeys.isEmpty() &&
    releaseStoreFile?.isFile == true
if (releaseRequested && !releaseSigningReady) {
    val detail = when {
        !keystorePropertiesFile.exists() -> "android/key.properties is missing"
        missingSigningKeys.isNotEmpty() ->
            "missing properties: ${missingSigningKeys.joinToString()}"
        else -> "the configured storeFile does not exist"
    }
    throw GradleException("Release signing is not configured: $detail")
}

val libboxAar = file("libs/libbox.aar")
val nativeBuildRequested = gradle.startParameter.taskNames.any {
    listOf("assemble", "bundle", "compile", "merge", "package").any(it::contains)
}
if (nativeBuildRequested && !libboxAar.isFile) {
    throw GradleException(
        "Missing locally verified libbox AAR. Run scripts/build-libbox.sh --android first.",
    )
}

android {
    namespace = "net.hideip.vpn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "net.hideip.vpn"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = maxOf(21, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (releaseSigningReady) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = releaseStoreFile
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            // Ship only the ABIs real phones use. The sing-box core is a Go
            // binary that costs ~60 MB per architecture, and x86_64 serves
            // emulators alone. These libraries arrive prebuilt from the libbox
            // AAR and Flutter, so they are dropped at packaging time rather
            // than through ndk.abiFilters, which only covers locally compiled
            // sources. Debug builds keep every ABI so the emulator stays usable.
            packaging {
                jniLibs {
                    excludes += "lib/x86_64/**"
                    excludes += "lib/x86/**"
                }
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // GPLv3 sing-box core built by scripts/build-libbox.sh from pinned source.
    implementation(files(libboxAar))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
}

flutter {
    source = "../.."
}
