import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // Firebase Cloud Messaging (research/06 R1). Must come before the Flutter
    // plugin so the google-services task is wired into every variant.
    id("com.google.gms.google-services")
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
        // flutter_local_notifications uses java.time; desugar for API < 26.
        isCoreLibraryDesugaringEnabled = true
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

    packaging {
        resources {
            // MSAL and the WebView plugin both ship these; keep the build merging.
            excludes += setOf("META-INF/DEPENDENCIES", "META-INF/LICENSE", "META-INF/LICENSE.txt", "META-INF/NOTICE", "META-INF/NOTICE.txt")
        }
    }

    buildTypes {
        debug {
            manifestPlaceholders["msalSignatureHash"] = msalDebugSignatureHash
        }
        // Flutter's profile build type is signed with the debug key, so it
        // needs the debug hash too (flutter run --profile for measurements).
        getByName("profile") {
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

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // MainActivity calls FirebaseMessaging.register()/unregister() directly;
    // the firebase_messaging plugin keeps this off the app's compile classpath.
    // Same version the plugin resolves, so Gradle picks one.
    implementation("com.google.firebase:firebase-messaging:25.1.2")
    // R2.6 Android enrichment. Both of these are already in the APK through
    // other modules; declaring them only puts them on *this* module's compile
    // classpath, so no artifact and no size is added.
    //  * MSAL: PushTokens builds a PublicClientApplication inside the
    //    messaging service, on the configuration the vendored msal_auth plugin
    //    writes, and that plugin keeps MSAL off the app's compile classpath.
    //    Same version range it resolves, so Gradle picks one.
    //  * androidx.core: NotificationCompat, for setPublicVersion and the
    //    grouped, private notifications PushNotifier posts.
    implementation("com.microsoft.identity.client:msal:8.3.+")
    implementation("androidx.core:core:1.13.1")
}
