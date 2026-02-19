plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)

    id("org.jetbrains.kotlin.plugin.serialization") version "1.9.22"
}

android {
    namespace = "com.example.dyadespace"
    compileSdk = 36

    packaging {
        resources {
            pickFirsts += "assets/PublicSuffixDatabase.list"
        }
    }

    defaultConfig {
        applicationId = "com.example.dyadespace"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0"

        val supabaseUrl: String = project.properties["SUPABASE_URL"]?.toString() ?: ""
        val supabaseKey: String = project.properties["SUPABASE_ANON_KEY"]?.toString() ?: ""

        buildConfigField("String", "SUPABASE_URL", "\"$supabaseUrl\"")
        buildConfigField("String", "SUPABASE_ANON_KEY", "\"$supabaseKey\"")


        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.espresso.core)
    implementation(libs.androidx.material3)
    testImplementation(libs.junit)
    androidTestImplementation(libs.androidx.junit)
    androidTestImplementation(libs.androidx.espresso.core)
    androidTestImplementation(platform(libs.androidx.compose.bom))
    androidTestImplementation(libs.androidx.compose.ui.test.junit4)
    debugImplementation(libs.androidx.compose.ui.tooling)
    debugImplementation(libs.androidx.compose.ui.test.manifest)

    //implementing supabase
    implementation("io.github.jan-tennert.supabase:postgrest-kt:3.2.6")
//    implementation("io.github.jan-tennert.supabase:postgrest-kt-extensions:3.2.6")

    implementation("io.github.jan-tennert.supabase:auth-kt:3.2.6")
    implementation("io.github.jan-tennert.supabase:storage-kt:3.2.6")
    implementation("io.github.jan-tennert.supabase:realtime-kt:3.2.6")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("io.ktor:ktor-client-okhttp:3.3.3")
    implementation("androidx.navigation:navigation-compose:2.7.7")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.3")
    implementation("io.coil-kt:coil-compose:2.4.0")

    implementation("androidx.compose.material:material-icons-extended")







}