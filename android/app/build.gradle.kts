import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") version "4.4.2"
}

// Load key.properties at the top level (outside android block) to avoid scope issues
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(keystorePropertiesFile.inputStream())
    }
}

android {
    namespace = "com.surya.fiscora"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    defaultConfig {
        applicationId = "com.surya.fiscora"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // Debug signing is only a fallback; the task-graph check below refuses to
            // actually build a release with it unless explicitly allowed.
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
    }
}

dependencies {
    // Import the Firebase BoM
    implementation(platform("com.google.firebase:firebase-bom:34.15.0"))

    // When using the BoM, don't specify versions in Firebase dependencies
    // https://firebase.google.com/docs/android/setup#available-libraries
}

flutter {
    source = "../.."
}

// A debug-signed release APK can't upgrade a properly signed install, so never
// produce one silently. Local/PR builds opt in with ALLOW_DEBUG_SIGNING=true.
gradle.taskGraph.whenReady {
    val buildsRelease = allTasks.any {
        (it.name.startsWith("assemble") || it.name.startsWith("bundle")) && it.name.endsWith("Release")
    }
    if (buildsRelease && !keystorePropertiesFile.exists() && System.getenv("ALLOW_DEBUG_SIGNING") != "true") {
        throw GradleException(
            "android/key.properties is missing. Set ALLOW_DEBUG_SIGNING=true for a debug-signed local release build."
        )
    }
}
