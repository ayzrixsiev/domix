import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key, kept out of the repository.
//
// android/key.properties is gitignored (along with *.jks and *.keystore) because whoever holds this
// file and the keystore it points at can publish an update to Domix under our name. It is created by
// hand on the release machine - see the "release build" section of CLAUDE.md - and the build falls
// back to debug signing when it is absent so that `flutter run` keeps working for everyone else.
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}
val hasUploadKey = keystoreProperties.getProperty("storeFile") != null

android {
    namespace = "app.domix"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // These stay at 17 - they say what bytecode *we* emit, and nothing needs more.
    //
    // What did change with Yandex MapKit is the JDK that has to *run* the build: the plugin ships
    // class files at version 65 (Java 21), and a javac from JDK 17 cannot read them at all. The
    // failure names neither Java nor the JDK -
    //
    //   bad class file: .../YandexMapsPlugin.class
    //   class file has wrong version 65.0, should be 61.0
    //
    // - so it is worth recognising: 65 is Java 21, 61 is Java 17. Build with JDK 21 or newer
    // (`flutter config --jdk-dir`, or JAVA_HOME).
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // The identity of the app on Google Play, permanent from the first upload onwards: it is the
        // primary key of the listing, so it cannot be changed later without publishing a different
        // app and losing every install and review. It was "com.example.frontend", which Play rejects
        // outright - com.example.* is reserved for samples - and which would have named a real
        // business's app after a tutorial placeholder.
        applicationId = "app.domix"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // 26 (Android 8.0 Oreo) is Yandex MapKit's floor, not ours - the build fails outright
        // below it. It replaces flutter.minSdkVersion, which was 24, so the move to MapKit costs us
        // Android 7.x. That is a fraction of a percent of devices in use and none of them can run a
        // modern map anyway; the reason it is written down is that raising a minSdk is invisible
        // until an install fails on somebody's phone with no explanation.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // only declared when key.properties is present, so a checkout without the key still builds
        if (hasUploadKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Play refuses an artifact signed with the debug key - that key is generated locally,
            // shared by every Android SDK install and has a known password, so it proves nothing
            // about who built the app.
            //
            // Falling back to debug signing when the key is missing is deliberate: it keeps
            // `flutter run --release` working on a machine that has no upload key, and a debug-signed
            // build simply cannot be uploaded, so the fallback cannot be shipped by accident.
            signingConfig = if (hasUploadKey) {
                signingConfigs.getByName("release")
            } else {
                logger.warn("WARNING: android/key.properties not found - signing the release build " +
                    "with the debug key. This build CANNOT be uploaded to Google Play.")
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

dependencies {
    // required by Yandex MapKit: its location layer is built on Google Play services, and the
    // plugin does not pull this in itself. without it the app compiles and then fails at runtime the
    // moment the map asks where the user is.
    implementation("com.google.android.gms:play-services-location:21.3.0")
}
