plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // ⚠️ COMPLIANCE: change BOTH `namespace` and `applicationId` below
    // before submitting to the Play Store — Google rejects packages
    // starting with `com.example.*` (it's reserved for example code).
    // Suggested: `com.sharecab.app`. When you change it:
    //   1. Update the Google Cloud Console restriction on the Maps API key
    //      (Application restrictions → Android apps → new package).
    //   2. Recreate the AdMob app + ad units (they're bound to the
    //      package name + SHA-1 fingerprint).
    //   3. Update the MSG91 widget's allowed package list.
    //   4. Re-sign with your release keystore (debug keys must not ship).
    namespace = "com.example.sharecab"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications 17+ — its TimeZone APIs
        // are java.time.* which need backporting onto Android API levels
        // below 26. Without this the build fails with:
        //   Dependency ':flutter_local_notifications' requires core library
        //   desugaring to be enabled for :app.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.sharecab"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // Multidex needed once desugaring + a few plugins push us past 64k
        // method refs. Cheap to enable; expensive to debug if you hit the
        // ceiling without it later.
        multiDexEnabled = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Backport of java.time.* (and friends) onto pre-API-26 devices so
    // flutter_local_notifications builds. Pinned to a version known to
    // work with AGP 8.x.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
