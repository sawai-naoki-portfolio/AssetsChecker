allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// 一部の Flutter プラグインは Java と Kotlin で別々の JVM ターゲットを指定しており
// （例: charset_converter は Java 11、file_picker は Java 17）、そのままだと
// 「Inconsistent JVM-target compatibility」でビルドが落ちる。
//
// プラグイン側の設定を上書きするには、各プロジェクトの評価が終わったあとに
// 設定を追加する必要がある（先に登録すると AGP の設定に上書きされてしまう）。
// アプリ本体と同じ Java 17 に全プロジェクトを揃える。
gradle.projectsEvaluated {
    subprojects {
        tasks.withType<JavaCompile>().configureEach {
            sourceCompatibility = JavaVersion.VERSION_17.toString()
            targetCompatibility = JavaVersion.VERSION_17.toString()
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
