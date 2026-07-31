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

// Diagnostic branch only: patch the native source in the Actions checkout before
// compilation. This keeps master and the hardware-validated source generation
// untouched while testing the Shamiko/KernelSU provider-flags hypothesis.
run {
    val sourceFile = file("loader/src/injector/module.cpp")
    var source = sourceFile.readText()

    val oldGetFlags =
        "uint32_t ZygiskModule::getFlags() { return g_ctx ? (g_ctx->info_flags & ~PRIVATE_MASK) : 0; }"
    val newGetFlags = """
        uint32_t ZygiskModule::getFlags() {
            if (g_ctx == nullptr) return 0;

            const uint32_t raw_flags = g_ctx->info_flags;
            if (g_ctx->flags & SERVER_FORK_AND_SPECIALIZE) {
                LOGI("system_server getFlags: raw=0x%08x manager=%d apatch=%d ksu=%d magisk=%d",
                     raw_flags, !!(raw_flags & PROCESS_IS_MANAGER),
                     !!(raw_flags & PROCESS_ROOT_IS_APATCH),
                     !!(raw_flags & PROCESS_ROOT_IS_KSU),
                     !!(raw_flags & PROCESS_ROOT_IS_MAGISK));
            }

            // Root-aware modules such as Shamiko use the provider-specific high
            // bits to distinguish Magisk, KernelSU and APatch.
            return raw_flags;
        }
    """.trimIndent()

    check(source.contains(oldGetFlags)) { "getFlags diagnostic patch baseline not found" }
    source = source.replace(oldGetFlags, newGetFlags, ignoreCase = false)

    val oldServer = """
        void ZygiskContext::server_specialize_pre() {
            run_modules_pre();
            zygiskd::SystemServerStarted();
        }
    """.trimIndent()
    val newServer = """
        void ZygiskContext::server_specialize_pre() {
            // The app path populates info_flags before loading modules, while the
            // system_server path previously left it at zero. Shamiko performs its
            // environment check from system_server.
            if (info_flags == 0) {
                info_flags = zygiskd::GetProcessFlags(args.server->uid);
            }
            LOGI("system_server provider flags: raw=0x%08x uid=%d",
                 info_flags, static_cast<int>(args.server->uid));
            run_modules_pre();
            zygiskd::SystemServerStarted();
        }
    """.trimIndent()

    check(source.contains(oldServer)) { "server_specialize_pre diagnostic patch baseline not found" }
    source = source.replace(oldServer, newServer, ignoreCase = false)
    sourceFile.writeText(source)
}

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
