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

    // Force every plugin to compile against the same Android API level the app does.
    //
    // Plugins pin their own `compileSdk`, and they disagree: `yandex_maps_mapkit_lite` targets
    // android-35 while `flutter_plugin_android_lifecycle` - which MapKit itself depends on -
    // declares that anything using it must compile against 36 or later. The build then fails inside
    // a *dependency*, naming two packages we do not own:
    //
    //   Dependency ':flutter_plugin_android_lifecycle' requires ... version 36 or later
    //   :yandex_maps_mapkit_lite is currently compiled against android-35
    //
    // Raising compileSdk only says which APIs the code may *reference*. It does not change
    // behaviour on any device and does not touch minSdk (26) or targetSdk, which are the two that
    // decide who can install the app and how it behaves once installed.
    //
    // **Two things about the placement are load-bearing, and both were found the hard way.**
    //
    // `afterEvaluate`, not `plugins.withId`: withId fires the moment the Android plugin is applied,
    // which is the *first* line of the plugin's own build.gradle - the rest of that file then runs
    // and sets compileSdk back to 35. Only afterEvaluate lands after the plugin has finished
    // configuring itself.
    //
    // And it has to be registered *here*, inside the first subprojects block, rather than in a
    // later one. The block below forces evaluation with `evaluationDependsOn(":app")`, and an
    // afterEvaluate registered after that throws "Cannot run Project.afterEvaluate(Action) when the
    // project is already evaluated".
    afterEvaluate {
        val androidExtension = extensions.findByName("android")
        if (androidExtension is com.android.build.gradle.BaseExtension) {
            androidExtension.compileSdkVersion(36)
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
