import org.gradle.api.tasks.Delete
import org.gradle.api.file.Directory

// Plugin versions are declared once, in settings.gradle.kts pluginManagement.
// Declaring google-services here as well puts two versions on the classpath and
// fails resolution ("already on the classpath with a different version").
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

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}