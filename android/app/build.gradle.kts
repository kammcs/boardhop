import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// MSAL redirect URI signature hash (msauth://com.kammcs.boardhop/<hash>).
// Per-machine for debug builds, so it lives in the gitignored android/secret.properties.
val secretProperties = Properties()
val secretPropertiesFile = rootProject.file("secret.properties")
if (secretPropertiesFile.exists()) {
    secretProperties.load(FileInputStream(secretPropertiesFile))
}
val msalDebugSignatureHash = secretProperties.getProperty("MSAL_DEBUG_SIGNATURE_HASH", "MISSING_SEE_secret.properties.example")
val msalReleaseSignatureHash = secretProperties.getProperty("MSAL_RELEASE_SIGNATURE_HASH", msalDebugSignatureHash)

android {
    namespace = "com.kammcs.boardhop"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.kammcs.boardhop"
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
        debug {
            manifestPlaceholders["msalSignatureHash"] = msalDebugSignatureHash
        }
        release {
            manifestPlaceholders["msalSignatureHash"] = msalReleaseSignatureHash
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
