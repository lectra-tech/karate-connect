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

import org.assertj.core.api.Assertions.assertThat
import org.junit.jupiter.api.AfterEach
import org.junit.jupiter.api.BeforeEach
import org.junit.jupiter.api.Test


class RabbitmqClientTest {

    private val localRabbitmqBroker = LocalRabbitmqBroker()

    @BeforeEach
    fun setup() {
        localRabbitmqBroker.start()
    }

    @AfterEach
    fun tearDown() {
        localRabbitmqBroker.stop()
    }

    @Test
    fun testRabbitmqClient() {
        val exchangeName = "myexchange-unittest"
        val exchangeType = "topic"
        val queueName = "myqueue"
        val routingKey = "my.routing.key"
        RabbitmqClient(
            host = localRabbitmqBroker.info.host,
            port = localRabbitmqBroker.info.port,
            virtualHost = localRabbitmqBroker.info.virtualHost,
            username = localRabbitmqBroker.info.username,
            password = localRabbitmqBroker.info.password,
            ssl = localRabbitmqBroker.info.ssl
        ).use {
            it.exchange(name = exchangeName, type = exchangeType, durable = true, autoDelete = false)
            it.queue(name = queueName, type = "classic", durable = true, autoDelete = false, exclusive = false)
            it.bind(exchangeName = exchangeName, queueName = queueName, bindingKey = routingKey)

            val props1 = mapOf("contentType" to "application/json", "headers" to mapOf("key" to "value1"))
            val input1 = Message.from(body = """{"message": "Hello World!"}""", properties = props1)
            val props2 = mapOf("contentType" to "text/plain", "headers" to mapOf("key" to "value2"))
            val input2 = Message.from(body = "Good bye 👋", properties = props2)
            it.publish(exchangeName = exchangeName, routingKey = routingKey, message = input1)
            it.publish(exchangeName = exchangeName, routingKey = routingKey, message = input2)
            val result = it.consume(queueName = queueName, timeoutSeconds = 5, minNbMessages = 2)

            assertThat(result.size).isEqualTo(2)
            assertThat(result.first().body).isEqualTo(input1.body)
            assertThat(result.first().toMap()["properties"] as Map<String, Any>).containsAllEntriesOf(props1)
            assertThat(result[1].body).isEqualTo(input2.body)
            assertThat(result[1].toMap()["properties"] as Map<String, Any>).containsAllEntriesOf(props2)
        }
    }

    @Test
    fun testRabbitmqClientRPC() {
        val server = SimpleServer(
            localRabbitmqBroker.info.host,
            localRabbitmqBroker.info.port,
            localRabbitmqBroker.info.virtualHost,
            localRabbitmqBroker.info.username,
            localRabbitmqBroker.info.password,
            localRabbitmqBroker.info.ssl
        )
        val exchangeName = "myexchange-unittest-rpc"
        val exchangeType = "topic"
        val routingKey = "my.routing.key"
        RabbitmqClient(
            host = localRabbitmqBroker.info.host,
            port = localRabbitmqBroker.info.port,
            virtualHost = localRabbitmqBroker.info.virtualHost,
            username = localRabbitmqBroker.info.username,
            password = localRabbitmqBroker.info.password,
            ssl = localRabbitmqBroker.info.ssl
        ).use {
            server.start(exchangeName = exchangeName, exchangeType = exchangeType, routingKey = routingKey) {
                if (it.bodyToString()=="ping") Message.from("pong", it.propertiesToMap()) else null
            }

            val props = mapOf("contentType" to "plain/text")
            val input = Message.from(body = "ping", properties = props)
            val result = it.publishAndConsume(exchangeName= exchangeName, routingKey = routingKey, message = input, timeoutSeconds = 5)

            server.stop()

            assertThat(String(result.body)).isEqualTo("pong")
        }
    }
}