import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// Play Store release signing — real upload key, not the debug certificate.
// key.properties/upload-keystore.jks are gitignored; back them up somewhere
// safe outside the repo (losing this key means never being able to publish
// an update to this app again — Play Store has no recovery process for it).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.scholarshiphive.scholarshiphive"
    // Play Store requires targetSdk 35 right now and 36 from Aug 31, 2026 —
    // targeting 36 directly here so this doesn't need redoing in a few weeks.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.scholarshiphive.scholarshiphive"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // geofence_foreground_service requires 29+ (Android 10) — the vast
        // majority of phones in real use are well past this by now.
        minSdk = 29
        // Play Store requires targeting a recent SDK (35 now, 36 from
        // Aug 31, 2026 — no grace period for a first-time upload) on every
        // release track, including Internal Testing. The sideloaded-only
        // build on the master branch stays pinned at targetSdk=30 to keep
        // opting out of Android 12+'s foreground-service-background-start
        // restriction and Android 13+'s exact-alarm restriction — this
        // branch instead relies on the background-service redesign (FCM/
        // WorkManager-driven short-lived checks instead of an all-day
        // foreground service) to stay reliable under the real restrictions
        // that come with targeting 36. See background-work redesign notes
        // in office_geofence_service.dart / attendance_foreground_service.dart.
        targetSdk = 36

        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Real upload key for Play Store — see key.properties (gitignored).
            // Falls back to the debug config if key.properties is missing
            // (e.g. a fresh checkout of this branch before it's been set up),
            // so `flutter run --release` still works without it.
            signingConfig = if (keystorePropertiesFile.exists()) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
