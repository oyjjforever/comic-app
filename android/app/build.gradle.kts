plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.comic_reader"
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
        applicationId = "com.example.comic_reader"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

// 自定义 APK 输出文件名：复制 app-release.apk 为 comic-app.apk
afterEvaluate {
    val copyTask = tasks.register("copyReleaseApk") {
        doLast {
            val buildDir = layout.buildDirectory.asFile.get()
            val apkDir = File(buildDir, "outputs/flutter-apk")
            val originalFile = File(apkDir, "app-release.apk")
            val copiedFile = File(apkDir, "comic-app.apk")
            if (originalFile.exists()) {
                originalFile.copyTo(copiedFile, overwrite = true)
                logger.lifecycle("APK copied: ${originalFile.name} -> ${copiedFile.name}")
            }
        }
    }
    tasks.findByName("assembleRelease")?.finalizedBy(copyTask)
}

flutter {
    source = "../.."
}
