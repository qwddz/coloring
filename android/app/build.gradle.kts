import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing: key.properties lives outside the project folder and is
// found through COLORING_KEY_PROPERTIES (see CLAUDE.md). Without the variable,
// release builds use the debug key, which Google Play rejects on upload.
val keyPropertiesPath: String? = System.getenv("COLORING_KEY_PROPERTIES")
val keyProperties = Properties()
if (keyPropertiesPath != null) {
    val keyFile = file(keyPropertiesPath)
    require(keyFile.exists()) {
        "COLORING_KEY_PROPERTIES points to a missing file: $keyPropertiesPath"
    }
    keyFile.inputStream().use { keyProperties.load(it) }
    for (key in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        require(!keyProperties.getProperty(key).isNullOrBlank()) {
            "$keyPropertiesPath has no $key"
        }
    }
} else if (gradle.startParameter.taskNames.any { it.contains("Release") }) {
    logger.warn("COLORING_KEY_PROPERTIES is not set: signing the release build with the DEBUG key. Google Play will reject it.")
}

android {
    namespace = "app.animosaic.coloring"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "app.animosaic.coloring"
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

    signingConfigs {
        if (keyPropertiesPath != null) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
            // The Flutter Gradle plugin already turns these on for release and
            // adds its own and the plugins' consumer ProGuard rules; stated here
            // so the release setup is visible in one place.
            isMinifyEnabled = true
            isShrinkResources = true
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
