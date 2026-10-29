import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android") // ✅ use this (not kotlin-android)
    id("dev.flutter.flutter-gradle-plugin")

    // Required by the firebase_auth plugin. Reads android/app/google-services.json,
    // which is gitignored and supplied by tool/write_google_services.dart.
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.example.spendsense"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.example.spendsense"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    
    signingConfigs {
        create("release") {
            keyAlias = System.getenv("KEY_ALIAS") ?: keystoreProperties["keyAlias"] as String?
            keyPassword = System.getenv("KEY_PASSWORD") ?: keystoreProperties["keyPassword"] as String?
            val storeFilePath = System.getenv("KEY_PATH") ?: keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
            } else {
                storeFile = file("upload-keystore.jks")
            }
            storePassword = System.getenv("STORE_PASSWORD") ?: keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            if (System.getenv("KEY_ALIAS") != null || System.getenv("KEY_PATH") != null || keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                signingConfig = signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")

    // FileProvider, used by MainActivity to hand a verified OTA APK to the
    // system installer. Declared explicitly rather than relying on it arriving
    // transitively from a Flutter plugin.
    implementation("androidx.core:core-ktx:1.13.1")
}

// Kotlin 2.x removed `android { kotlinOptions { ... } }`; the compiler options
// DSL replaces it and the build fails to even compile the script otherwise.
// Declared outside `android { }` on purpose.
kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}