plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.io.FileInputStream
import java.util.Properties

// Real release signing — see android/key.properties (gitignored, never
// committed) for the actual credentials. Falls back to the debug key only
// when that file hasn't been created yet (a fresh checkout), so the release
// build still runs locally. A Play Store upload must use the "release" config.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasKeystoreProperties = keystorePropertiesFile.exists()
if (hasKeystoreProperties) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Firebase (Phone Auth): apply the Google Services plugin only once its config
// is present, so the app still builds — on the demo auth gateway — before
// `google-services.json` has been added. Drop the file into android/app/ (or
// run `flutterfire configure`) and it switches on with no further edits.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

android {
    namespace = "com.zabnix.shield"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.zabnix.shield"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasKeystoreProperties) {
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
            // Signed with the real upload keystore when android/key.properties
            // exists. Otherwise the debug key, so `flutter run --release` still works
            // on a fresh checkout. Play Console rejects the debug key.
            signingConfig = if (hasKeystoreProperties) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
