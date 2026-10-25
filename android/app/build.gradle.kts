import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android") // ✅ use this (not kotlin-android)
    id("dev.flutter.flutter-gradle-plugin")

    // Firebase plugin: reads android/app/google-services.json (gitignored) to
    // bind this APK to the spendsense-ota-2026 project. Required by the
    // firebase_auth and cloud_firestore plugins.
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

// Release-signing credentials: environment variables first, then android/key.properties.
// Nothing is invented here and there is no fallback to the debug key.
val releaseKeyAlias: String? = System.getenv("KEY_ALIAS") ?: keystoreProperties["keyAlias"] as String?
val releaseKeyPassword: String? = System.getenv("KEY_PASSWORD") ?: keystoreProperties["keyPassword"] as String?
val releaseStorePassword: String? = System.getenv("STORE_PASSWORD") ?: keystoreProperties["storePassword"] as String?
val releaseStoreFilePath: String? = System.getenv("KEY_PATH") ?: keystoreProperties["storeFile"] as String?
val releaseStoreFile = releaseStoreFilePath?.takeIf { it.isNotBlank() }?.let { file(it) }

// True only when a complete credential set is present AND the keystore exists.
val hasReleaseSigning: Boolean =
    !releaseKeyAlias.isNullOrBlank() &&
        !releaseKeyPassword.isNullOrBlank() &&
        !releaseStorePassword.isNullOrBlank() &&
        releaseStoreFile != null &&
        releaseStoreFile.exists()

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
            // Only populated when a complete, existing credential set is present.
            if (hasReleaseSigning) {
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
            }
        }
    }

    buildTypes {
        release {
            // Use the configured release key when complete; otherwise leave the
            // release variant unsigned. Never fall back to the debug key.
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
    }
}

// Fail a release build loudly when signing credentials are missing or
// incomplete, instead of silently producing a debug-signed artifact. Debug
// builds are unaffected because no release task enters the graph.
gradle.taskGraph.whenReady {
    val releaseTaskNames = setOf("assembleRelease", "bundleRelease", "installRelease")
    val buildingRelease = allTasks.any { task ->
        val name = task.name
        name in releaseTaskNames ||
            name.startsWith("packageRelease") ||
            name.startsWith("publishRelease")
    }
    if (buildingRelease && !hasReleaseSigning) {
        throw GradleException(
            "Release signing is not configured; refusing to build an unsigned release.\n" +
                "A production release must never be signed with the debug key.\n\n" +
                "Provide credentials in ONE of these ways, then re-run `flutter build apk --release`:\n\n" +
                "  1) android/key.properties (preferred):\n" +
                "        storeFile=/absolute/path/to/upload-keystore.jks   (or a path relative to android/app)\n" +
                "        storePassword=<store password>\n" +
                "        keyAlias=<key alias>\n" +
                "        keyPassword=<key password>\n\n" +
                "  2) Environment variables: KEY_PATH, STORE_PASSWORD, KEY_ALIAS, KEY_PASSWORD\n\n" +
                "Debug builds (flutter build apk --debug) are unaffected.",
        )
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.0.4")
}

flutter {
    source = "../.."
}