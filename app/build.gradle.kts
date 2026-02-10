import java.util.Properties

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    id("kotlin-kapt")
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.kotlin.compose)
}

android {
    namespace = "com.porarri.yamabikochat"
    compileSdk = 35
    // Explicitly select a non-corrupted Build Tools revision
    buildToolsVersion = "35.0.1"

    fun String.escapeForKotlinString(): String =
        replace("\\", "\\\\").replace("\"", "\\\"")

    val localProperties = Properties().apply {
        val file = rootProject.file("local.properties")
        if (file.isFile) {
            file.inputStream().use { load(it) }
        }
    }

    fun signingProperty(name: String): String? =
        (project.findProperty(name) as String?)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
            ?: localProperties.getProperty(name)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
            ?: System.getenv(name)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }

    val geminiOauthClientId = (project.findProperty("GEMINI_OAUTH_CLIENT_ID") as String?)
        ?.trim()
        .orEmpty()
    val geminiOauthClientSecret = (project.findProperty("GEMINI_OAUTH_CLIENT_SECRET") as String?)
        ?.trim()
        .orEmpty()

    defaultConfig {
        applicationId = "com.porarri.yamabikochat"
        minSdk = 24
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
        buildConfigField("boolean", "DIAGNOSTIC", "false")
        buildConfigField("String", "GEMINI_OAUTH_CLIENT_ID", "\"${geminiOauthClientId.escapeForKotlinString()}\"")
        buildConfigField("String", "GEMINI_OAUTH_CLIENT_SECRET", "\"${geminiOauthClientSecret.escapeForKotlinString()}\"")

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }


    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }

    val releaseKeyAlias = signingProperty("RELEASE_KEY_ALIAS")
    val releaseKeyPassword = signingProperty("RELEASE_KEY_PASSWORD")
    val releaseStoreFilePath = signingProperty("RELEASE_STORE_FILE")
    val releaseStorePassword = signingProperty("RELEASE_STORE_PASSWORD")
    val hasReleaseSigning =
        !releaseKeyAlias.isNullOrBlank() &&
            !releaseKeyPassword.isNullOrBlank() &&
            !releaseStoreFilePath.isNullOrBlank() &&
            !releaseStorePassword.isNullOrBlank()

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storeFile = rootProject.file(releaseStoreFilePath!!)
                storePassword = releaseStorePassword
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            isDebuggable = false
            signingConfig =
                if (hasReleaseSigning) signingConfigs.getByName("release") else signingConfigs.getByName("debug")
        }
        create("diagnostic") {
            isMinifyEnabled = true
            isShrinkResources = true
            // Keep non-debuggable so R8 optimizations/obfuscation stay enabled (same as release)
            isDebuggable = false
            applicationIdSuffix = ".diagnostic"
            versionNameSuffix = "-diagnostic"
            resValue("string", "app_name", "YamabikoChat (Diagnostic)")
            signingConfig = signingConfigs.getByName("debug")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-diagnostic.pro"
            )
            matchingFallbacks += listOf("release")
            buildConfigField("boolean", "DIAGNOSTIC", "true")
        }
        debug {
            isMinifyEnabled = false
            isDebuggable = true
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {

    // Core
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)

    // Compose
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation("androidx.compose.ui:ui-text")
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.androidx.material3.window.size)
    implementation(libs.material)
    implementation(libs.androidx.material.icons.extended)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel)
    implementation(libs.androidx.lifecycle.viewmodel.ktx)
    implementation(libs.androidx.lifecycle.service)
    implementation(libs.androidx.savedstate)
    implementation(libs.androidx.window)

    // Markdown
    implementation("io.noties.markwon:core:4.6.2")
    implementation("io.noties.markwon:html:4.6.2")
    implementation("io.noties.markwon:image:4.6.2")
    implementation("io.noties.markwon:ext-latex:4.6.2")
    implementation("io.noties.markwon:inline-parser:4.6.2")

    // SVG support - AndroidSVG library for SVG rendering
    implementation("com.caverock:androidsvg:1.4")

    // Navigation
    implementation(libs.androidx.navigation.compose)

    // ViewModel
    implementation(libs.androidx.lifecycle.viewmodel.compose)

    // Retrofit for Networking
    implementation(libs.retrofit)
    implementation(libs.retrofit.converter.gson)
    implementation(libs.retrofit.kotlinx.serialization.converter)
    implementation(libs.okhttp)
    implementation(libs.okhttp.dnsoverhttps)
    implementation(libs.kotlinx.serialization.json)

    // Room for Database
    implementation(libs.androidx.room.runtime)
    kapt(libs.androidx.room.compiler)
    implementation(libs.androidx.room.ktx)

    // ExifInterface for image orientation
    implementation("androidx.exifinterface:exifinterface:1.3.7")

    // Security
    implementation("androidx.security:security-crypto:1.0.0")

    // Test
    testImplementation(libs.junit)
    testImplementation(libs.mockk)
    testImplementation(libs.kotlinx.coroutines.test)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.ui.test.junit4)
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest)
}
