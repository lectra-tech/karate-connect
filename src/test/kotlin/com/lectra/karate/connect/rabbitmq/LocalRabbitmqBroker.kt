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
package com.lectra.karate.connect.rabbitmq

import com.lectra.karate.connect.LocalBroker
import org.apache.qpid.server.SystemLauncher

class LocalRabbitmqBroker(private val port: Int = LocalBroker.freePort()) : LocalBroker {

    private val systemLauncher: SystemLauncher = SystemLauncher()
    val info = LocalRabbitmqBrokerInfo(port = port)

    override fun start() {
        val initialConfig = Thread.currentThread().contextClassLoader.getResource("rabbitmq/qpid-config.json")?.toExternalForm()
        System.setProperty("qpid.amqp_port", port.toString())
        System.setProperty("queue.behaviourOnUnknownDeclareArgument", "IGNORE")
        systemLauncher.startup(
            mapOf(
                "type" to "Memory",
                "initialConfigurationLocation" to initialConfig,
                "startupLoggedToSystemOut" to true
            )
        )
    }

    override fun stop() {
        systemLauncher.shutdown()
    }
}

data class LocalRabbitmqBrokerInfo(
    val host: String = "localhost",
    val port: Int,
    val virtualHost: String = "default",
    val username: String = "guest",
    val password: String = "guest",
    val ssl: Boolean = false
)
