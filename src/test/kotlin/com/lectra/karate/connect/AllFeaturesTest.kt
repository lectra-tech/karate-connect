/*
 * Copyright (C) 2025 Lectra
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     https://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *
 * SPDX-License-Identifier: Apache-2.0
 * License-Filename: LICENSE
 */
package com.lectra.karate.connect

import com.intuit.karate.Results
import com.intuit.karate.Runner
import com.lectra.karate.connect.rabbitmq.LocalRabbitmqBroker
import com.lectra.karate.connect.rabbitmq.Message
import com.lectra.karate.connect.rabbitmq.SimpleServer
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.Assertions.assertEquals
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test
import java.util.*

class AllFeaturesTest {

    private val localRabbitmqBroker = LocalRabbitmqBroker()
    private lateinit var server: SimpleServer
    private val testExtensions = System.getProperties().getProperty("testExtensions").split(",").toSet().mapNotNull {
        try {
            Extension.valueOf(it)
        } catch (iae: IllegalArgumentException) {
            null
        }
    }.filterNot { it == Extension.base }
    private val tags = testExtensions.plus(Extension.base).joinToString(",") { "@${it.name}" }

    @BeforeEach
    fun setup() {
        if (testExtensions.contains(Extension.rabbitmq)) {
            localRabbitmqBroker.start()
            server = SimpleServer(
                host = localRabbitmqBroker.info.host,
                port = localRabbitmqBroker.info.port,
                virtualHost = localRabbitmqBroker.info.virtualHost,
                username = localRabbitmqBroker.info.username,
                password = localRabbitmqBroker.info.password,
                ssl = localRabbitmqBroker.info.ssl
            )
            server.start(exchangeName = "myexchangerpc", exchangeType = "topic", routingKey = "my.routing.key") {
                if (it.bodyToString() == "ping") Message.from("pong", it.propertiesToMap()) else null
            }
        }
    }

    @AfterEach
    fun tearDown() {
        if (testExtensions.contains(Extension.rabbitmq)) {
            server.stop()
            localRabbitmqBroker.stop()
        }
    }

//    @Karate.Test
//    fun testAllSequential(): Karate {
//        return Karate.run().systemProperty("extensions", "snowflake").relativeTo(javaClass)
//    }


    @Test
    fun testAllParallel() {
        val props = mutableListOf<Pair<String, String>>()
        if (testExtensions.contains(Extension.snowflake)) {
            props.addAll(javaClass.classLoader.getResourceAsStream("snowflake/snowflake.properties")?.use {
                Properties().apply { load(it) }.map { "snowflake.${it.key}" to it.value.toString() }
            } ?: emptyList())
        }
        if (testExtensions.contains(Extension.rabbitmq)) {
            props.addAll(
                listOf(
                    "rabbitmq.port" to localRabbitmqBroker.info.port.toString()
                )
            )
        }
        val builder = props.fold(
            Runner.path("src/test/resources")
                .systemProperty("extensions", testExtensions.joinToString(",") { it.name })
        ) { b, (k, v) -> b.systemProperty(k, v) }

        val results: Results = builder
            .tags(tags)
            .parallel(16)

        assertEquals(0, results.failCount, results.errorMessages)
    }
}