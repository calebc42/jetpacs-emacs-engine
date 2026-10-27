// The engine AAR: pristine Emacs Java (package org.gnu.emacs, whose name the
// JNI side hardcodes), its resources, the cross-built lib/<abi>/*.so and the
// assets tree with Emacs's directory-tree index. Nothing here is Jetpacs
// behavior; the Companion's bundled flavor supplies the service that starts
// Emacs through EmacsNative.
plugins {
    alias(libs.plugins.android.library)
}

val engineDist: File = (findProperty("engineDist") as String?)?.let(::file)
    ?: rootDir.resolve("../dist/current")
require(engineDist.resolve("java/org/gnu/emacs/EmacsNative.java").isFile) {
    "engineDist=$engineDist holds no harvested engine (run tools/harvest.sh or pass -PengineDist=...)"
}

android {
    namespace = "org.gnu.emacs"
    compileSdk = 37
    defaultConfig {
        minSdk = 34
        consumerProguardFiles(engineDist.resolve("proguard.conf"))
    }
    compileOptions {
        // The sources are written for Java 7; a modern javac accepts them.
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    packaging {
        // Keep the helper programs (libexec1.so, libloader.so, ...) as
        // real files: Emacs execs them from nativeLibraryDir.
        jniLibs.useLegacyPackaging = true
    }
    lint {
        // Upstream sources are not ours to lint-fix.
        abortOnError = false
        checkReleaseBuilds = false
    }
}

// AGP 9: the harvested trees enter through the Variant API as static source
// directories (the source-set DSL no longer accepts the legacy types). The
// manifest is the conventional src/main/AndroidManifest.xml.
androidComponents {
    onVariants { variant ->
        variant.sources.java?.addStaticSourceDirectory(engineDist.resolve("java").path)
        variant.sources.res?.addStaticSourceDirectory(engineDist.resolve("res").path)
        variant.sources.jniLibs?.addStaticSourceDirectory(engineDist.resolve("lib").path)
        variant.sources.assets?.addStaticSourceDirectory(engineDist.resolve("assets").path)
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.compilerArgs.add("-Xlint:-deprecation")
    options.compilerArgs.add("-Xlint:-removal")
}
