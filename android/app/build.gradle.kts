import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.heizungstrainer.heizungstrainer"
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
        applicationId = "com.heizungstrainer.heizungstrainer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Upload key for Google Play (Play re-signs with the app signing key).
    // android/key.properties is gitignored; the keystore lives in
    // ~/.config/heizungstrainer/.
    val keystoreProperties = Properties()
    val keystoreFile = rootProject.file("key.properties")
    if (keystoreFile.exists()) keystoreFile.inputStream().use { keystoreProperties.load(it) }

    signingConfigs {
        if (keystoreFile.exists()) {
            create("upload") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    flavorDimensions += "store"
    productFlavors {
        // Website APK: keeps the debug key so existing installs keep updating.
        create("direct") {
            dimension = "store"
            signingConfig = signingConfigs.getByName("debug")
        }
        // Google Play bundle: Pro via Play Billing, signed with the upload key.
        create("play") {
            dimension = "store"
            signingConfig = signingConfigs.findByName("upload")
        }
    }
}

flutter {
    source = "../.."
}
