allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

subprojects {
    val configureNamespace = {
        if (plugins.hasPlugin("com.android.library")) {
            val android = extensions.findByName("android")
            if (android != null) {
                try {
                    val namespaceMethod = android.javaClass.getMethod("setNamespace", String::class.java)
                    val getNamespaceMethod = android.javaClass.getMethod("getNamespace")
                    val currentNamespace = getNamespaceMethod.invoke(android) as? String
                    if (currentNamespace.isNullOrEmpty()) {
                        val fallbackNamespace = "com.example.${project.name.replace(":", "").replace("-", ".").replace("_", ".")}"
                        namespaceMethod.invoke(android, fallbackNamespace)
                    }
                } catch (e: Exception) {
                    // Method not present or unsupported
                }
            }
        }
    }

    val configureSdkVersion = {
        if (plugins.hasPlugin("com.android.library") || plugins.hasPlugin("com.android.application")) {
            val android = extensions.findByName("android")
            if (android != null) {
                try {
                    val compileSdkVersionMethod = try {
                        android.javaClass.getMethod("compileSdkVersion", Int::class.javaPrimitiveType ?: Int::class.java)
                    } catch (e: NoSuchMethodException) {
                        android.javaClass.getMethod("setCompileSdkVersion", Int::class.javaPrimitiveType ?: Int::class.java)
                    }
                    compileSdkVersionMethod.invoke(android, 36)
                } catch (e: Exception) {
                    // Method not present or unsupported
                }

                try {
                    val getDefaultConfig = android.javaClass.getMethod("getDefaultConfig")
                    val defaultConfig = getDefaultConfig.invoke(android)
                    if (defaultConfig != null) {
                        val targetSdkVersionMethod = try {
                            defaultConfig.javaClass.getMethod("targetSdkVersion", Int::class.javaPrimitiveType ?: Int::class.java)
                        } catch (e: NoSuchMethodException) {
                            defaultConfig.javaClass.getMethod("setTargetSdkVersion", Int::class.javaPrimitiveType ?: Int::class.java)
                        }
                        targetSdkVersionMethod.invoke(defaultConfig, 36)
                    }
                } catch (e: Exception) {
                    // Method not present or unsupported
                }
            }
        }
    }

    if (state.executed) {
        configureNamespace()
        configureSdkVersion()
    } else {
        afterEvaluate {
            configureNamespace()
            configureSdkVersion()
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}

subprojects {
    tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
        val javaTaskName = name.replace("Kotlin", "JavaWithJavac")
        val javaTask = project.tasks.findByName(javaTaskName) as? JavaCompile
        val javaTarget = javaTask?.targetCompatibility ?: "17"

        val jvmTargetStr = when {
            javaTarget.contains("17") -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
            javaTarget.contains("11") -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11
            javaTarget.contains("1.8") || javaTarget.contains("8") -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
            else -> org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
        }

        compilerOptions {
            jvmTarget = jvmTargetStr
        }
    }
}
