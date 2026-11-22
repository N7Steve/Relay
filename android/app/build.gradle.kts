plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("org.jetbrains.kotlin.plugin.serialization")
}

android {
    namespace = "app.relay.android"
    compileSdk = 36
    defaultConfig {
        applicationId = "app.relay.android"
        minSdk = 26
        targetSdk = 36
        // bin/release-local.py assigns the code from the commit count of main.
        versionCode = providers.environmentVariable("RELAY_ANDROID_VERSION_CODE").orElse("1").get().toInt().also {
            require(it in 1..2_100_000_000) { "Invalid Android version code" }
        }
        versionName = providers.environmentVariable("RELAY_ANDROID_VERSION_NAME").orElse("0.1.0-dev").get()
    }
    signingConfigs {
        // Local release environment only. Never fall back to the debug key for a release.
        if (providers.environmentVariable("RELAY_ANDROID_KEYSTORE").isPresent) {
            create("release") {
                storeFile = file(providers.environmentVariable("RELAY_ANDROID_KEYSTORE").get())
                storePassword = providers.environmentVariable("RELAY_ANDROID_STORE_PASSWORD").get()
                keyAlias = providers.environmentVariable("RELAY_ANDROID_KEY_ALIAS").get()
                keyPassword = providers.environmentVariable("RELAY_ANDROID_KEY_PASSWORD").get()
            }
        }
    }
    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            signingConfig = signingConfigs.findByName("release")
        }
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    testOptions { unitTests.isReturnDefaultValues = true }
}
kotlin { jvmToolchain(17) }

dependencies {
    implementation(platform("androidx.compose:compose-bom:2025.10.01"))
    implementation("androidx.activity:activity-compose:1.11.0")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui-tooling-preview")
    debugImplementation("androidx.compose.ui:ui-tooling")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.9.4")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.9.4")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.9.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    testImplementation("junit:junit:4.13.2")
    testImplementation("com.squareup.okhttp3:mockwebserver:4.12.0")
    testImplementation("com.squareup.okhttp3:okhttp-tls:4.12.0")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
}
