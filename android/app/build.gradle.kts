import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseKeyProperties = Properties()
val releaseKeyPropertiesFile = rootProject.file("key.properties")
if (releaseKeyPropertiesFile.exists()) {
    releaseKeyProperties.load(releaseKeyPropertiesFile.inputStream())
}

fun releaseSigningPropertiesConfigured(): Boolean {
    return releaseKeyPropertiesFile.exists() &&
        listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all {
            !releaseKeyProperties.getProperty(it).isNullOrBlank()
        }
}

android {
    namespace = "com.humanifest.phonopticon"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.humanifest.phonopticon"
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
        release {
            if (releaseSigningPropertiesConfigured()) {
                signingConfigs.create("release") {
                    storeFile = file(releaseKeyProperties.getProperty("storeFile"))
                    storePassword = releaseKeyProperties.getProperty("storePassword")
                    keyAlias = releaseKeyProperties.getProperty("keyAlias")
                    keyPassword = releaseKeyProperties.getProperty("keyPassword")
                }
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

tasks.matching {
    it.name == "assembleRelease" ||
        it.name == "bundleRelease" ||
        it.name.startsWith("assembleRelease") ||
        it.name.startsWith("bundleRelease")
}.configureEach {
    doFirst {
        if (!releaseSigningPropertiesConfigured()) {
            throw GradleException(
                "Release signing is not configured. Create android/key.properties with an authorized keystore outside source control."
            )
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
