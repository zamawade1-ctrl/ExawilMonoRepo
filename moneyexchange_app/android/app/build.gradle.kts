import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing config. Loaded from android/key.properties (gitignored) so the
// keystore + passwords never enter source control. This is the SAME signing identity
// every previously distributed build used, so a new release installs as an UPDATE over
// existing installs with no uninstall and no data loss. Keep android/app/xawil-release-key.jks
// and key.properties safe and backed up — losing them means future updates can't be signed
// with a matching key. If the file is absent (e.g. a fresh clone / CI), the build falls back
// to the debug signing config so it still compiles.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.moneyexchange.moneyexchange_app"
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
        applicationId = "com.moneyexchange.moneyexchange_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                // Sign with ALL of v1 (JAR), v2 and v3 schemes. minSdk 24 makes AGP drop
                // v1 by default, leaving a v2-ONLY signature — and a v2 signature covers the
                // whole archive, so ANY corruption/truncation in transit (e.g. a >50 MB APK
                // clipped by Supabase Storage's 50 MB object limit) makes Android's package
                // installer reject the sideloaded APK with "App not installed as package
                // appears to be invalid". Some Samsung sideload paths also refuse v2-only
                // APKs outright. Enabling v1+v2+v3 makes the APK verify under whatever scheme
                // the installing device prefers and is the standard cure for that error.
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            // Sign release builds with the persistent release keystore (android/key.properties)
            // so they update existing installs without an uninstall. Falls back to the debug
            // key only when the keystore is unavailable (fresh clone / CI without the secret).
            signingConfig = if (hasReleaseKeystore) {
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

dependencies {
    testImplementation("junit:junit:4.13.2")
}
