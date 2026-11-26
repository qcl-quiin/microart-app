import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Khoá ký bản release: đọc từ android/key.properties (file này KHÔNG đưa lên git, xem android/.gitignore).
// Chưa có file đó thì bản release tạm ký bằng khoá debug: chạy thử được, nhưng KHÔNG dùng để phát hành.
val keystoreProperties = Properties()
val externalSigningRoot = providers.environmentVariable("MICROACT_ANDROID_SIGNING_ROOT").orNull
val signingRoot = externalSigningRoot?.let { rootProject.file(it) } ?: rootProject.projectDir
val keystorePropertiesFile = signingRoot.resolve("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
check(externalSigningRoot == null || hasReleaseKey) {
    "key.properties was not found in MICROACT_ANDROID_SIGNING_ROOT"
}
if (hasReleaseKey) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.microart.microart"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.microart.microart"
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
        manifestPlaceholders["microactLabel"] = "MicroAct"
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let {
                    signingRoot.resolve("app").resolve(it)
                }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".firebase_debug"
            manifestPlaceholders["microactLabel"] = "MicroAct Debug"
        }
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
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
