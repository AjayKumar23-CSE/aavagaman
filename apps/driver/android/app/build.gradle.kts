import java.util.Properties

plugins {
    id("com.android.application")
    // TODO(firebase): add id("com.google.gms.google-services") (and the
    // classpath in settings.gradle.kts) once android/app/google-services.json
    // exists. Without the JSON the plugin fails the build, so it is not applied;
    // the app then runs without push (FirebasePushTokenSource degrades).
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.rideplatform.driver"
    // permission_handler_android is built against API 37; targetSdk stays Flutter's default.
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time APIs on older Android versions.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.rideplatform.driver"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // Plugins (flutter_secure_storage, firebase_messaging) need API 23+.
        minSdk = maxOf(flutter.minSdkVersion, 24)
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Google Maps SDK key → AndroidManifest meta-data com.google.android.geo.API_KEY.
        // Read from android/local.properties (MAPS_API_KEY=...) or the MAPS_API_KEY
        // environment variable; an empty value still builds.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey()
    }

    // SPEC §17.5 flavors. `dev` installs next to `prod` (".dev" package) and
    // is meant for staging builds: --dart-define=API_BASE_URL=<staging> APP_ENV=dev.
    // pubspec.yaml sets `default-flavor: dev` so a plain `flutter run` works.
    flavorDimensions += "env"
    productFlavors {
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            manifestPlaceholders["appLabel"] = "Aavagaman Driver (dev)"
        }
        create("prod") {
            dimension = "env"
            manifestPlaceholders["appLabel"] = "Aavagaman Driver"
        }
    }

    // Upload key (SPEC §17.5): android/key.properties locally, or the
    // KEYSTORE_PATH / KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD variables in
    // CI (decoded from secrets). Never committed. Without one, release builds
    // are debug-signed so `flutter run --release` still works on a phone.
    val upload = uploadKey()
    signingConfigs {
        if (upload != null) {
            create("upload") {
                storeFile = file(upload.getValue("storeFile"))
                storePassword = upload.getValue("storePassword")
                keyAlias = upload.getValue("keyAlias")
                keyPassword = upload.getValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName(if (upload != null) "upload" else "debug")
        }
    }
}

fun uploadKey(): Map<String, String>? {
    val props = Properties()
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { props.load(it) }
    val values = mapOf(
        "storeFile" to (props.getProperty("storeFile") ?: System.getenv("KEYSTORE_PATH")),
        "storePassword" to (props.getProperty("storePassword") ?: System.getenv("KEYSTORE_PASSWORD")),
        "keyAlias" to (props.getProperty("keyAlias") ?: System.getenv("KEY_ALIAS")),
        "keyPassword" to (props.getProperty("keyPassword") ?: System.getenv("KEY_PASSWORD")),
    )
    if (values.values.all { it.isNullOrEmpty() }) return null
    val missing = values.filterValues { it.isNullOrEmpty() }.keys
    require(missing.isEmpty()) { "Upload key is incomplete; missing: $missing" }
    return values.mapValues { it.value!! }
}

fun mapsApiKey(): String {
    val props = Properties()
    val file = rootProject.file("local.properties")
    if (file.exists()) file.inputStream().use { props.load(it) }
    return props.getProperty("MAPS_API_KEY") ?: System.getenv("MAPS_API_KEY") ?: ""
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
