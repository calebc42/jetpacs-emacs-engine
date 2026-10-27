// Gradle project that wraps a harvested engine distribution (dist/current)
// as one Android library AAR. It compiles the pristine Emacs Java sources
// unmodified, in their own package, and carries the native libraries and
// assets Emacs's build staged. See ../README.md.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "jetpacs-emacs-engine"
include(":engine")
