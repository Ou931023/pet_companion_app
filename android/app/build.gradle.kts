import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // CR-0006 Batch 4c-2：套用 google-services（讀取 google-services.json）。
    id("com.google.gms.google-services")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}
val releaseSigningTasks = gradle.startParameter.taskNames.joinToString(" ").lowercase()
val isReleaseSigningRequired =
    releaseSigningTasks.contains("release") || releaseSigningTasks.contains("bundle")

android {
    namespace = "com.example.pet_companion_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications 需要 core library desugaring（既有套件需求，
        // 於 4c-2 第一次完整 Android build 才浮現；與 Google 登入無關）。
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // 對齊 iOS Bundle ID（tw.edu.ncyu.im.aicompanion）。namespace 維持
        // com.example.pet_companion_app（內部程式套件，不需更動 MainActivity.kt）。
        applicationId = "tw.edu.ncyu.im.aicompanion"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // CR-0006 Batch 4c-2：Firebase Auth / Google Sign-In 需 minSdk≥23；
        // 用 maxOf 確保不低於 23，又不會把 Flutter 預設往下調。
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            val requiredKeys = listOf(
                "storeFile",
                "storePassword",
                "keyAlias",
                "keyPassword",
            )
            val missingKeys = requiredKeys.filter {
                keystoreProperties.getProperty(it).isNullOrBlank()
            }
            if (missingKeys.isNotEmpty()) {
                if (isReleaseSigningRequired) {
                    throw GradleException(
                        "Missing Android release signing config in android/key.properties: " +
                            missingKeys.joinToString(", "),
                    )
                }
                return@create
            }

            storeFile = file(keystoreProperties.getProperty("storeFile"))
            storePassword = keystoreProperties.getProperty("storePassword")
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // 支援上面 isCoreLibraryDesugaringEnabled（flutter_local_notifications 需求）。
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
