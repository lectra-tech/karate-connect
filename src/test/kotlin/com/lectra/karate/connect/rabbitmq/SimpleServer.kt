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

import org.slf4j.LoggerFactory
import java.util.*

class SimpleServer(
    host: String,
    port: Int,
    virtualHost: String,
    username: String,
    password: String,
    ssl: Boolean
) {

    private val LOGGER = LoggerFactory.getLogger(SimpleServer::class.java)

    val rabbitmqClient = RabbitmqClient(
        host = host,
        port = port,
        virtualHost = virtualHost,
        username = username,
        password = password,
        ssl = ssl
    )

    fun start(exchangeName: String, exchangeType: String, routingKey: String, block: (Message) -> (Message?)) {
        LOGGER.info("Starting simple server")
        rabbitmqClient.exchange(exchangeName, exchangeType, durable = true, autoDelete = false)
        val queueName = "my.own.queue.${UUID.randomUUID()}"
        rabbitmqClient.queue(queueName, "classic", durable = true, autoDelete = true, exclusive = false)
        rabbitmqClient.bind(exchangeName, queueName, routingKey)
        Thread({
            try {
                rabbitmqClient.consume(queueName = queueName, timeoutSeconds = 60, minNbMessages = 1).forEach {
                    block(it)?.let { message -> rabbitmqClient.publish("", it.properties.replyTo, message) }
                }
            } catch (e: Exception) {
                e.printStackTrace()
            }
        }).start()
    }

    fun stop() {
        LOGGER.info("Stopping simple server")
        rabbitmqClient.close()
    }
}