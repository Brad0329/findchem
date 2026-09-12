import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 릴리스 서명 키. 비밀정보라 저장소에 넣지 않는다 — `android/key.properties`(gitignore)에 두고
// keystore 파일은 저장소 밖에 둔다. 만드는 법은 docs/playbooks/팩_Flutter_Android.md.
// 파일이 없으면 debug 키로 조용히 서명하지 않고 릴리스 빌드를 거부한다(fail-closed):
// debug 키는 PC마다 달라서, 그것으로 배포하면 다음 버전을 덮어 설치할 수 없다.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties().apply {
    if (hasReleaseKeystore) {
        FileInputStream(keystorePropertiesFile).use { load(it) }
    }
}

gradle.taskGraph.whenReady {
    if (!hasReleaseKeystore && allTasks.any { it.name.contains("Release") }) {
        throw GradleException(
            "릴리스 서명 키가 없습니다: ${keystorePropertiesFile.absolutePath}\n" +
                "만드는 법은 docs/playbooks/팩_Flutter_Android.md '릴리스 서명 키'를 보세요.",
        )
    }
}

android {
    namespace = "io.github.brad0329.findchem"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // 바꾸면 이미 설치된 앱과 다른 앱이 된다(CLAUDE.md '작업 트랙' ②).
        applicationId = "io.github.brad0329.findchem"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            // 키가 없으면 위 taskGraph 검사가 이미 빌드를 멈춘다.
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}
