import com.android.build.api.dsl.LibraryExtension

plugins {
    alias(libs.plugins.agp.lib) apply false
}

fun String.execute(currentWorkingDir: File = file("./")): String =
    providers.exec {
        workingDir = currentWorkingDir
        commandLine = split("\\s".toRegex())
    }.standardOutput.asText.get().trim()

val gitCommitCount = "git rev-list HEAD --count".execute().toInt()
val gitCommitHash = "git rev-parse --verify --short HEAD".execute()

val moduleId by extra("zygisksu")
val moduleName by extra("NeoZygisk")
val verName by extra("v2.3-postboot.3.2")
// Keep fork releases monotonically newer than the hardware-tested recovery build
// (versionCode 347) and than earlier upstream-derived commit-count versions.
val verCode by extra(10000 + gitCommitCount)
val commitHash by extra(gitCommitHash)
val minAPatchVersion by extra(10762)
val minKsuVersion by extra(10940)
val minKsudVersion by extra(11425)
val maxKsuVersion by extra(30000)
val minMagiskVersion by extra(26402)
// The target temporary-KernelSU environment has no writable /debug_ramdisk.
// /dev is an existing kernel-backed tmpfs and passed the Samsung DEFEX path
// test on the hardware-validated target, so keep the live runtime there.
val workDirectory by extra("/dev/.neozygisk")
// Fork builds must not be silently replaced by the upstream update channel.
val updateJson by extra("")

val androidMinSdkVersion by extra(26)
val androidTargetSdkVersion by extra(36)
val androidCompileSdkVersion by extra(36)
val androidBuildToolsVersion by extra("36.0.0")
// Don't update NDK unless after careful and detailed tests,
// as explained in https://github.com/JingMatrix/NeoZygisk/pull/36
val androidCompileNdkVersion by extra("27.2.12479018")
val androidSourceCompatibility by extra(JavaVersion.VERSION_21)
val androidTargetCompatibility by extra(JavaVersion.VERSION_21)

tasks.register("Delete", Delete::class) {
    delete(rootProject.layout.buildDirectory)
}

fun Project.configureBaseExtension() {
    extensions.findByType(LibraryExtension::class)?.run {
        namespace = "org.matrix.zygisk"
        compileSdk = androidCompileSdkVersion
        ndkVersion = androidCompileNdkVersion
        buildToolsVersion = androidBuildToolsVersion

        defaultConfig {
            minSdk = androidMinSdkVersion
        }

        lint {
            abortOnError = true
        }
    }
}

subprojects {
    plugins.withId("com.android.library") {
        configureBaseExtension()
    }
}
