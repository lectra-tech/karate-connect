import io.karatelabs.gherkin.Feature
import java.nio.file.Files
import java.nio.file.Paths
import kotlin.io.path.nameWithoutExtension
import kotlin.io.path.pathString

group = "com.lectra"
description = "Karate enriched with extensions to connect to other systems"
version = grgitService.service.get().grgit.describe { tags = true }?.replace("^v".toRegex(), "") ?: "0.0.0"

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.grgit.service)
}

repositories {
    mavenCentral()
    maven {
        url = uri("https://packages.confluent.io/maven")
    }
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(21))
    }
}
dependencies {
    implementation(libs.amqp.client)
    implementation(libs.awaitility.kotlin)
    implementation(libs.kafka.clients)
    implementation(libs.kafka.avro.serializer)
    implementation(libs.kafka.json.schema.serializer)
    implementation(libs.kafka.protobuf.serializer)
    runtimeClasspath(libs.karate.core)
    runtimeClasspath(libs.logback.classic)
    testImplementation(libs.karate.junit6)
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.qpid.broker.core)
    testImplementation(libs.qpid.broker.plugins.amqp)
    testImplementation(libs.assertj.core)
    testRuntimeOnly(libs.qpid.broker.plugins.memory.store)
    testImplementation(libs.embedded.kafka.schema.registry)
    testRuntimeOnly(libs.junit.platform.launcher)
}

buildscript {
    dependencies {
        classpath(libs.karate.core)
    }
}

tasks {
    test {
        useJUnitPlatform()
        systemProperty("testExtensions", System.getProperties().getProperty("testExtensions", "rabbitmq,kafka,kubernetes"))
        // ensure tests are always run
        outputs.upToDateWhen { false }
    }
    register("karateVersion") {
        val version = libs.karate.core.get().version
        doLast {
            println(version)
        }
    }
    //  https://www.baeldung.com/kotlin/gradle-executable-jar
    val fatJar = register("fatJar", Jar::class) {
        dependsOn.addAll(
            listOf(
                "compileJava",
                "compileKotlin",
                "processResources"
            )
        ) // We need this for Gradle optimization to work
        archiveClassifier.set("standalone") // Naming the jar
        duplicatesStrategy = DuplicatesStrategy.EXCLUDE
        manifest {
            attributes(
                mapOf(
                    "Main-Class" to "com.intuit.karate.Main",
                    "Implementation-Title" to "karate-connect",
                    "Implementation-Version" to project.version,
                    "Implementation-Vendor" to "Lectra"
                )
            )
        }
        val runtimeContents = configurations.runtimeClasspath.get().map {
            if (it.isDirectory) {
                fileTree(it) { exclude("logback.xml") }
            } else {
                zipTree(it).matching { exclude("logback.xml") }
            }
        }
        from(runtimeContents)
        from(sourceSets.main.get().output)
        exclude("LICENSE*", "META-INF/LICENSE*", "META-INF/NOTICE*")
    }
    build {
        dependsOn(fatJar)
    }
    processResources {
        val resourcesDirPath = sourceSets.main.get().resources.srcDirs.first().path
        val outputResourcesDirPath = sourceSets.main.get().output.resourcesDir?.path!!
        val extensions = Files.walk(Paths.get(resourcesDirPath), 1)
            .filter { Files.isDirectory(it) && it.pathString != resourcesDirPath }.map { it.fileName.toString() }
            .toList()
        // Capture as plain strings for configuration cache compatibility
        val resourcesDirPathStr: String = resourcesDirPath
        val outputResourcesDirPathStr: String = outputResourcesDirPath
        val extensionsList: List<String> = extensions
        doFirst {
            Paths.get(outputResourcesDirPathStr).toFile().mkdirs()
        }
        doLast {
            extensionsList.forEach { extension ->
                val out = Files.walk(Paths.get("$resourcesDirPathStr/$extension"), 1)
                    .filter { !Files.isDirectory(it) && it.pathString.endsWith(".feature") }.toList()
                    .map { featurePath ->
                        val feature = Feature.read(featurePath.pathString)
                        if (feature.tags.any { it.name == "deprecated" }) {
                            ""
                        } else {
                            val text = feature
                                .sections.filter { !it.isOutline }.map { it.scenario }
                                .filter { it.tags?.none { tag -> tag.name == "ignore" } ?: true }
                                .joinToString(separator = ",\n\t\t") { """"${it.name}": (args) => karate.call('classpath:$extension/${featurePath.fileName}@${it.name}', args).result""" }
                            "\t\"${featurePath.fileName.nameWithoutExtension}\": {\n\t\t$text\n\t}"
                        }
                    }.filter { it.isNotBlank() }.joinToString(prefix = "return {\n", separator = ",\n", postfix = "\n};")
                Paths.get("$outputResourcesDirPathStr/$extension/$extension.js").toFile().also { it.parentFile.mkdirs() }.writeText(out)
            }
        }
    }
}
