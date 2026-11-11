// Only the source-built ONNX AAR from the verified recipe may satisfy this module.
allprojects {
    repositories {
        exclusiveContent {
            forRepository {
                maven { url = uri(rootProject.projectDir.resolve("../.avx1-work/native/maven")) }
            }
            filter { includeModule("com.microsoft.onnxruntime", "onnxruntime-android") }
        }
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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
