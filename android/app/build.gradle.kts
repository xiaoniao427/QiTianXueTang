plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "cc.septnet.qitianxuetang"
    compileSdk = 36
    ndkVersion = "28.2.13676358"

    // Produce one APK per CPU architecture instead of bundling every native
    // Flutter engine/plugin library into a single, larger universal APK.
    splits {
        abi {
            isEnable = true
            reset()
            include("armeabi-v7a", "arm64-v8a", "x86_64")
            isUniversalApk = false
        }
    }

    signingConfigs {
        create("debugFixed") {
            storeFile = file("mykey.jks")
            // 优先从环境变量读取，其次从 gradle.properties 读取，最后使用默认值
            storePassword = System.getenv("DEBUG_STORE_PASSWORD") ?: project.findProperty("DEBUG_STORE_PASSWORD") as? String ?: "android"
            keyAlias = System.getenv("DEBUG_KEY_ALIAS") ?: project.findProperty("DEBUG_KEY_ALIAS") as? String ?: "debug"
            keyPassword = System.getenv("DEBUG_KEY_PASSWORD") ?: project.findProperty("DEBUG_KEY_PASSWORD") as? String ?: "android"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "cc.septnet.qitianxuetang"
        minSdk = 24
        targetSdk = 35
        versionCode = 40601
        versionName = "4.6.1"
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("debugFixed")
        }
        release {
            signingConfig = signingConfigs.getByName("debugFixed")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // MTDataFilesProvider：为 MT 管理器注入文件提供器（仅 debug 版）
    debugImplementation("com.github.L-JINBIN:MTDataFilesProvider:v1.0.0")
}
